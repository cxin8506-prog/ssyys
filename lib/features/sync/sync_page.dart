import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/database/app_database.dart';
import '../../core/database/library_repository.dart';
import '../../core/log/app_logger.dart';
import '../../core/utils/path_utils.dart';
import '../backup/backup_service.dart';
import 'progress_sync.dart';
import 'webdav_client.dart';

/// 启动时检查云端备份（供界面组 main.dart 调用）：
/// 同步关着、没填配置、云端没有备份 → 返回 null；
/// 云端最新备份比本地 lastBackup 新超过 1 分钟 → 返回那份备份的信息，界面弹框问。
Future<Map<String, dynamic>?> checkCloudBackup() async {
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool(AppConstants.keySyncEnabled) ?? false)) return null;
  final url = prefs.getString(AppConstants.keySyncUrl) ?? '';
  final user = prefs.getString(AppConstants.keySyncUser) ?? '';
  final pass = prefs.getString(AppConstants.keySyncPass) ?? '';
  if (url.isEmpty || user.isEmpty || pass.isEmpty) return null;

  final client = WebDavClient(baseUrl: url, username: user, password: pass);
  try {
    final list = await client.listBackups();
    if (list.isEmpty) return null;
    final latest = list.first;
    // 优先用 PROPFIND 给的最后修改时间；没有时从文件名里的时间戳取
    var lastModify = latest.lastModified?.millisecondsSinceEpoch ?? 0;
    if (lastModify == 0) {
      final m = RegExp(r'(\d{10,})').firstMatch(latest.name);
      if (m != null) {
        final n = int.tryParse(m.group(1)!) ?? 0;
        if (n > 0) lastModify = n;
      }
    }
    if (lastModify == 0) return null;
    final localLast = prefs.getInt(AppConstants.keyLastBackup) ?? 0;
    if (lastModify - localLast > 60 * 1000) {
      return {
        'name': latest.displayName,
        'lastModify': lastModify,
        'size': latest.size,
      };
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 用户在“云端有新备份”弹框上点“取消”后调用：把本地 lastBackup 置为二者较大值，
/// 下次不再问这一份。
Future<void> markCloudBackupSeen(Map<String, dynamic> info) async {
  final prefs = await SharedPreferences.getInstance();
  final cloud = (info['lastModify'] as num?)?.toInt() ?? 0;
  final local = prefs.getInt(AppConstants.keyLastBackup) ?? 0;
  await prefs.setInt(AppConstants.keyLastBackup, cloud > local ? cloud : local);
}

/// 坚果云 WebDAV 同步页：上传整包备份、列云端备份、从云端恢复、保留份数、进度同步。
///
/// 进度同步与整包备份是两条线：进度每本书一个小文件（progress/ 下的 .json），
/// 由 ProgressSync 处理；整包备份是下面的“备份到云端”与“从云端恢复”。
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;

  bool _syncEnabled = false;
  int _keepCount = 0;
  bool _progressSyncEnabled = false;
  bool _testing = false;
  bool _busy = false;
  bool _syncingProgress = false;
  String _status = '';
  DateTime? _lastSyncAt;
  List<WebDavItem> _cloudBackups = const [];
  String _cloudError = '';

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _urlCtrl.text = prefs.getString(AppConstants.keySyncUrl) ??
          AppConstants.defaultSyncUrl;
      _userCtrl.text = prefs.getString(AppConstants.keySyncUser) ?? '';
      _passCtrl.text = prefs.getString(AppConstants.keySyncPass) ?? '';
      _syncEnabled =
          prefs.getBool(AppConstants.keySyncEnabled) ?? false;
      _keepCount =
          prefs.getInt(AppConstants.keyBackupKeepCount) ??
              AppConstants.defaultKeepCount;
      _progressSyncEnabled =
          prefs.getBool(AppConstants.keySyncProgress) ??
              AppConstants.defaultSyncProgress;
      final lastSyncMs = prefs.getInt(AppConstants.keyLastSyncTime);
      if (lastSyncMs != null && lastSyncMs > 0) {
        _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(lastSyncMs);
      }
    });
    if (_syncEnabled) _refreshCloudList();
  }

  WebDavClient get _client => WebDavClient(
        baseUrl: _urlCtrl.text.trim(),
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
      );

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keySyncUrl, _urlCtrl.text.trim());
    await prefs.setString(AppConstants.keySyncUser, _userCtrl.text.trim());
    await prefs.setString(AppConstants.keySyncPass, _passCtrl.text);
    await prefs.setBool(AppConstants.keySyncEnabled, _syncEnabled);
    await prefs.setInt(AppConstants.keyBackupKeepCount, _keepCount);
    await prefs.setBool(
        AppConstants.keySyncProgress, _progressSyncEnabled);
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _status = '正在测试连接…';
    });
    try {
      await _client.test();
      setState(() => _status = '连接成功：账号密码都对，地址没问题');
    } catch (e) {
      setState(() => _status = '连接失败：${WebDavClient.friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _refreshCloudList() async {
    try {
      final list = await _client.listBackups();
      if (mounted) {
        setState(() {
          _cloudBackups = list;
          _cloudError = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cloudBackups = const [];
          _cloudError = WebDavClient.friendlyError(e);
        });
      }
    }
  }

  Future<void> _uploadBackup() async {
    setState(() {
      _busy = true;
      _status = '正在打包并上传…';
    });
    try {
      final service = BackupService(db: ref.read(databaseProvider));
      final file = await service.createBackup();
      await _client.ensureDir('');
      final name = file.uri.pathSegments.last;
      await _client.upload(name, file);
      // 本机这份备份留着（进“本机备份”列表），不删；云端那份是另外一份
      // 按保留份数清理旧备份（刚上传的不算）
      if (_keepCount > 0) {
        try {
          final list = await _client.listBackups();
          final keep = _keepCount;
          final old = list.skip(keep).toList();
          for (final item in old) {
            await _client.delete(item.name);
          }
        } catch (e) {
          appLogger.warning('云端旧备份清理失败', detail: '${WebDavClient.friendlyError(e)}');
        }
      }
      setState(() => _status = '已上传到云端');
      await _refreshCloudList();
    } catch (e) {
      setState(() => _status = '上传失败：${_friendly(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(Object e) {
    if (e is BackupException) return e.message;
    return WebDavClient.friendlyError(e);
  }

  Future<void> _restoreFromCloud(WebDavItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从云端恢复'),
        content: Text('恢复 ${item.displayName} 吗？\n'
            '恢复前会先校验备份、再自动备一份当前数据；恢复是合并式，'
            '只写回本机已有的书的进度；恢复完成后需要重启 App。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始恢复')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _status = '正在下载并恢复…';
    });
    try {
      final tmp = File(
          '${(await PathUtils.appFilesDir).path}${Platform.pathSeparator}backups'
          '${Platform.pathSeparator}cloud_restore.tmp.zip');
      await tmp.parent.create(recursive: true);
      await _client.download(item.name, tmp);
      final service = BackupService(db: ref.read(databaseProvider));
      try {
        await service.verifyBackupFile(tmp);
      } catch (e) {
        setState(() => _status = '恢复失败：${friendlyBackupError(e)}');
        await tmp.delete();
        return;
      }
      try {
        await ref.read(databaseProvider).close();
      } catch (_) {}
      final db = AppDatabase();
      final report = await service.restoreFromZip(tmp, liveDb: db);
      await db.close();
      await tmp.delete();
      setState(() => _status = '恢复完成：写回了 ${report.restoredBooks} 本书的进度'
          '${report.missingBooks > 0 ? '，有 ${report.missingBooks} 本书还没导入进来，'
              '需先重新添加对应书源并等扫描完成，再恢复一次才能合上进度' : ''}');
      if (mounted) _restartDialog();
    } catch (e) {
      setState(() => _status = '恢复失败：${_friendly(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _syncProgressNow() async {
    setState(() => _syncingProgress = true);
    try {
      await ProgressSync.syncAll(
        client: _client,
        repo: ref.read(libraryRepositoryProvider),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(AppConstants.keyLastSyncTime,
          DateTime.now().millisecondsSinceEpoch);
      setState(() => _lastSyncAt = DateTime.now());
    } catch (e) {
      setState(() =>
          _status = '进度同步失败：${WebDavClient.friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _syncingProgress = false);
    }
  }

  void _restartDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复完成'),
        content: const Text('数据已合并恢复，请退出并重新打开 App。'),
        actions: [
          TextButton(
            onPressed: () => SystemNavigator.pop(),
            child: const Text('立即退出'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('云端同步')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('云同步'),
            subtitle: const Text('默认关。打开后才会往坚果云传备份与进度'),
            value: _syncEnabled,
            onChanged: (v) async {
              await _saveConfig();
              setState(() => _syncEnabled = v);
              if (v) await _refreshCloudList();
            },
          ),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://dav.jianguoyun.com/dav/',
              helperText: '坚果云 WebDAV 地址',
            ),
            onChanged: (_) => _saveConfig(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: '账号（邮箱）'),
            onChanged: (_) => _saveConfig(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: _obscurePass,
            decoration: InputDecoration(
              labelText: '应用密码',
              helperText: '坚果云“安全选项”里的应用密码，不是登录密码',
              suffixIcon: IconButton(
                icon: Icon(_obscurePass
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
              ),
            ),
            onChanged: (_) => _saveConfig(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.wifi_tethering_outlined),
                label: const Text('测试连接'),
                onPressed: _testing ? null : _testConnection,
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: _refreshCloudList,
                child: const Text('刷新云端列表'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_status.isNotEmpty)
            Text(_status, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          const Text('备份到云端',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('保留份数'),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: _keepCount,
                items: const [0, 1, 3, 5, 10]
                    .map((n) => DropdownMenuItem<int>(
                          value: n,
                          child: Text(n == 0 ? '不清' : '$n 份'),
                        ))
                    .toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => _keepCount = v);
                  await _saveConfig();
                },
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('备份到云端'),
                onPressed: _busy ? null : _uploadBackup,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('云端备份',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (_cloudError.isNotEmpty)
            Text('加载云端列表失败：$_cloudError',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.red)),
          if (_cloudBackups.isEmpty && _cloudError.isEmpty)
            const Text('云端暂无备份'),
          ..._cloudBackups.map((item) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_zip_outlined),
                title: Text(item.displayName),
                subtitle: Text(
                    '${PathUtils.formatSize(item.size)} · ${_formatTime(item.lastModified)}'),
                trailing: TextButton(
                  onPressed: _busy ? null : () => _restoreFromCloud(item),
                  child: const Text('恢复'),
                ),
              )),
          const SizedBox(height: 24),
          const Text('进度同步',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('每本书一个小文件，换机后断点跟着走。整包备份是上面那块，别混了。',
              style: TextStyle(fontSize: 12.5)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('同步收听进度'),
            subtitle: Text(_lastSyncAt == null
                ? '还没同步过'
                : '上次同步：${_formatTime(_lastSyncAt)}'),
            value: _progressSyncEnabled,
            onChanged: (v) async {
              setState(() => _progressSyncEnabled = v);
              await _saveConfig();
            },
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.sync_outlined),
            label: const Text('立即同步进度'),
            onPressed: _syncingProgress ? null : _syncProgressNow,
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime? t) {
    if (t == null) return '';
    final m = '${t.month}'.padLeft(2, '0');
    final d = '${t.day}'.padLeft(2, '0');
    final h = '${t.hour}'.padLeft(2, '0');
    final min = '${t.minute}'.padLeft(2, '0');
    return '${t.year}-$m-$d $h:$min';
  }
}
