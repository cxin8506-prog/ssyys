import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/database/app_database.dart';
import '../../core/utils/path_utils.dart';
import 'backup_service.dart';

/// 本地备份与恢复：数据库（书架/进度/收藏/历史/书签/设置）、封面、插件一起打包。
///
/// 恢复是合并式：只写回本机已有的书的进度，本机有、备份里没有的不动；
/// 备份里有、本机没有的单独计数并明说。恢复前先校验 SHA-256/版本，
/// 坏了报“备份文件损坏”；恢复前先自动备一份当前数据；成功后强制重启。
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;
  String _status = '';
  List<File> _localBackups = <File>[];

  bool _includeDatabase = true;
  bool _includeCovers = true;
  bool _includePlugins = true;
  bool _includeCookies = false;
  final _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;

  bool _autoBackup = true;
  int _intervalDays = 1;

  @override
  void initState() {
    super.initState();
    _loadLocal();
    _loadAutoSettings();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAutoSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoBackup = prefs.getBool(AppConstants.keyAutoBackup) ??
          AppConstants.defaultAutoBackup;
      _intervalDays = prefs.getInt(AppConstants.keyBackupIntervalDays) ??
          AppConstants.defaultBackupIntervalDays;
    });
  }

  Future<void> _loadLocal() async {
    try {
      final files = await BackupService().listLocalBackups();
      if (mounted) setState(() => _localBackups = files);
    } catch (_) {}
  }

  BackupService get _service =>
      BackupService(db: ref.read(databaseProvider));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _intro(),
          const SizedBox(height: 18),
          const Text('备份内容',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('书架、进度、收藏、历史、书签、设置'),
            subtitle: const Text('都在数据库里，一起打包'),
            value: _includeDatabase,
            onChanged: (v) => setState(() => _includeDatabase = v ?? true),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('封面'),
            value: _includeCovers,
            onChanged: (v) => setState(() => _includeCovers = v ?? true),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('插件源'),
            subtitle: const Text('JAR / ZIP 插件文件，换机后源能带过去'),
            value: _includePlugins,
            onChanged: (v) => setState(() => _includePlugins = v ?? true),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cookie 和登录态'),
            subtitle: const Text('要设本地密码才备，没有密码就不备这一项'),
            value: _includeCookies,
            onChanged: (v) => setState(() => _includeCookies = v ?? false),
          ),
          if (_includeCookies)
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '本地密码（只用于这次备份，不保存）',
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('关 App 时自动备份'),
            subtitle: const Text('只在间隔到了才备，失败只记日志'),
            value: _autoBackup,
            onChanged: (v) async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool(AppConstants.keyAutoBackup, v);
              setState(() => _autoBackup = v);
            },
          ),
          Row(
            children: [
              const Text('自动备份间隔'),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: _intervalDays,
                items: const [1, 2, 3, 7]
                    .map((d) => DropdownMenuItem<int>(
                          value: d,
                          child: Text('$d 天'),
                        ))
                    .toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt(
                      AppConstants.keyBackupIntervalDays, v);
                  setState(() => _intervalDays = v);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            icon: const Icon(Icons.backup_outlined),
            label: const Text('创建本地备份'),
            onPressed: _busy ? null : _createBackup,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.restore),
            label: const Text('从 zip 恢复'),
            onPressed: _busy ? null : _restoreFromFile,
          ),
          const SizedBox(height: 20),
          if (_busy)
            Center(
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 10),
                  Text(_status,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            )
          else if (_status.isNotEmpty)
            Text(_status, style: Theme.of(context).textTheme.bodySmall),
          if (_localBackups.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('本机备份',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ..._localBackups.take(10).map((f) => _fileTile(f)),
          ],
        ],
      ),
    );
  }

  Widget _intro() {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            primary.withOpacity(0.16),
            Theme.of(context).colorScheme.secondary.withOpacity(0.10),
          ],
        ),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, color: primary, size: 20),
              const SizedBox(width: 8),
              const Text('备份包含什么',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '书架、进度、收藏、历史、书签、设置、UA 配置、插件源与源配置。'
            '文件为 zip，可直接拷到新机恢复。恢复是合并式：只写回本机已有的书，'
            '本机没有的书会单独告诉你。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _fileTile(File f) {
    final name = f.uri.pathSegments.last;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_zip_outlined, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(PathUtils.formatSize(f.lengthSync()),
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 11)),
              ],
            ),
          ),
          TextButton(
            onPressed: _busy ? null : () => _doRestore(f),
            child: const Text('恢复'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: '删除这个备份',
            onPressed: _busy
                ? null
                : () async {
                    await BackupService().deleteLocalBackup(f);
                    await _loadLocal();
                  },
          ),
        ],
      ),
    );
  }

  Future<void> _createBackup() async {
    setState(() {
      _busy = true;
      _status = '正在打包...';
    });
    try {
      final file = await _service.createBackup(
        options: BackupOptions(
          includeDatabase: _includeDatabase,
          includeCovers: _includeCovers,
          includePlugins: _includePlugins,
          includeCookies: _includeCookies,
          localPassword:
              _includeCookies ? _passwordCtrl.text : null,
        ),
      );
      final size = await file.length();
      setState(() => _status =
          '备份完成：${file.uri.pathSegments.last}（${PathUtils.formatSize(size)}）');
      await _loadLocal();
    } catch (e) {
      setState(() => _status = '备份失败：${friendlyBackupError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreFromFile() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: false,
      );
    } catch (_) {
      setState(() => _status = '打开文件选择器失败，请重试');
      return;
    }
    final path = picked?.files.single.path;
    if (path == null) return;
    await _doRestore(File(path));
  }

  Future<void> _doRestore(File zip) async {
    // 先校验：坏了直接报，不动当前数据
    Map<String, dynamic> manifest;
    try {
      manifest = await _service.verifyBackupFile(zip);
    } catch (e) {
      setState(() => _status = '恢复失败：${friendlyBackupError(e)}');
      return;
    }
    final includes = manifest['includes'];
    final hasCookies = includes is Map && includes['cookies'] == true;
    String? password;
    if (hasCookies) {
      password = await _askPassword();
      if (password == null) return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认恢复'),
        content: const Text('恢复前会先自动备一份当前数据。\n'
            '恢复是合并式：只写回本机已有的书的进度，本机没有的书不会被删，'
            '也不会凭空多出来。\n恢复完成后需要重启 App 才生效。'),
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
      _status = '正在恢复...';
    });
    try {
      try {
        await ref.read(databaseProvider).close();
      } catch (_) {}
      // 关库后重新打开一个实例做恢复（旧实例已关，不能再用）
      final db = AppDatabase();
      final report = await _service.restoreFromZip(
        zip,
        liveDb: db,
        localPassword: password,
      );
      await db.close();
      final parts = <String>[
        '写回了 ${report.restoredBooks} 本书的进度',
        '断点 ${report.restoredProgress} 条',
        '书签 ${report.restoredBookmarks} 条',
        '收藏 ${report.restoredFavorites} 条',
      ];
      if (report.missingBooks > 0) {
        parts.add(
            '有 ${report.missingBooks} 本书还没导入进来，需先重新添加对应书源并等扫描完成，再恢复一次才能合上进度');
      }
      if (report.cookiesRestored > 0) {
        parts.add('登录态 ${report.cookiesRestored} 条');
      }
      setState(() => _status = '恢复完成：${parts.join('，')}');
      if (mounted) _restartDialog();
    } catch (e) {
      setState(() => _status = '恢复失败：${friendlyBackupError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askPassword() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('备份里有 Cookie'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: '备份时的本地密码'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('确定')),
        ],
      ),
    );
    return result;
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
}
