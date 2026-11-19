import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/path_utils.dart';
import '../backup/backup_service.dart';
import 'webdav_client.dart';
import '../../shared/widgets/common.dart';

/// 坚果云同步：WebDAV 上存 zip 备份，换机后下载恢复
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _backup = BackupService();

  bool _obscure = true;
  bool _busy = false;
  String _status = '';
  List<WebDavItem> _items = [];

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPrefsProvider);
    _urlCtrl.text =
        prefs.getString(AppConstants.keySyncUrl) ?? AppConstants.defaultSyncUrl;
    _userCtrl.text = prefs.getString(AppConstants.keySyncUser) ?? '';
    _passCtrl.text = prefs.getString(AppConstants.keySyncPass) ?? '';
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  WebDavClient get _client => WebDavClient(
        baseUrl: _urlCtrl.text.trim().isEmpty
            ? AppConstants.defaultSyncUrl
            : _urlCtrl.text.trim(),
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
      );

  void _saveConfig() {
    final prefs = ref.read(sharedPrefsProvider);
    prefs.setString(AppConstants.keySyncUrl, _urlCtrl.text.trim());
    prefs.setString(AppConstants.keySyncUser, _userCtrl.text.trim());
    prefs.setString(AppConstants.keySyncPass, _passCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('坚果云同步')),
      body: ListView(
        padding: pagePadding(context, bottom: 32),
        children: [
          _introCard(),
          const SizedBox(height: 16),
          _accountCard(),
          const SizedBox(height: 16),
          _actionCard(),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Text('云端备份',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Text('${_items.length} 个',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 10),
            ..._items.map((e) => _backupTile(e)),
          ],
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.palette.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_status,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.palette.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _introCard() {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [
            primary.withOpacity(0.18),
            Theme.of(context).colorScheme.secondary.withOpacity(0.10),
          ],
        ),
        border: Border.all(color: context.palette.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_queue, color: primary, size: 20),
              const SizedBox(width: 8),
              const Text('坚果云 WebDAV',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '1. 登录坚果云网页版 → 账户信息 → 安全选项\n'
            '2. 找到「第三方应用管理」→ 添加应用 → 生成应用密码\n'
            '3. 账号填邮箱，密码填这个应用密码（不是登录密码）\n'
            '4. 服务器地址保持默认即可',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _accountCard() {
    return _card(
      children: [
        TextField(
          controller: _urlCtrl,
          decoration: const InputDecoration(
            labelText: '服务器地址',
            hintText: AppConstants.defaultSyncUrl,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _userCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: '账号（邮箱）'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passCtrl,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: '应用密码',
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                  size: 18),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _test,
                child: const Text('测试连接'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _busy ? null : _save,
                child: const Text('保存'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _actionCard() {
    return _card(
      children: [
        const Text('备份操作',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('上传会把当前书架/进度/收藏/书签/设置/插件打包成一个 zip 传到云端。',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                label: const Text('上传备份'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新列表'),
              ),
            ),
          ],
        ),
        if (_busy) ...[
          const SizedBox(height: 14),
          const Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }

  Widget _backupTile(WebDavItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.outline),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_zip_outlined,
              size: 20, color: context.subtleColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${PathUtils.formatSize(item.size)}'
                  '${item.modified.isEmpty ? '' : ' · ${item.modified}'}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _busy ? null : () => _restore(item),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 操作

  Future<void> _save() async {
    _saveConfig();
    _toast('已保存到本机');
  }

  Future<void> _test() async {
    _saveConfig();
    setState(() {
      _busy = true;
      _status = '正在连接...';
    });
    try {
      await _client.test();
      setState(() => _status = '连接成功，账号可用');
      _toast('连接成功');
    } catch (e) {
      setState(() => _status = '连接失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    _saveConfig();
    setState(() {
      _busy = true;
      _status = '正在打包本地数据...';
    });
    try {
      final file = await _backup.createBackup();
      final size = await file.length();
      setState(() => _status = '正在上传 ${PathUtils.formatSize(size)}...');
      await _client.upload(file.uri.pathSegments.last, file);
      setState(() =>
          _status = '上传成功：${file.uri.pathSegments.last}');
      await _refresh();
    } catch (e) {
      setState(() => _status = '上传失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    _saveConfig();
    setState(() => _busy = true);
    try {
      final list = await _client.listBackups();
      setState(() {
        _items = list;
        _status = '共 ${list.length} 个云端备份';
      });
    } catch (e) {
      setState(() => _status = '读取列表失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(WebDavItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从云端恢复'),
        content: Text('将用「${item.displayName}」覆盖本机的书架、进度、收藏、设置和插件。\n'
            '恢复完成后需要重启 App 才会生效。'),
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
      _status = '正在下载...';
    });
    try {
      final dir = await PathUtils.backupsDir;
      final dest = File('${dir.path}/${item.displayName}');
      await _client.download(item.name, dest);

      setState(() => _status = '正在解压覆盖...');
      // 关闭数据库，避免 sqlite 被占用
      try {
        await ref.read(databaseProvider).close();
      } catch (_) {}

      await _backup.restoreFromZip(dest);
      setState(() => _status = '恢复完成，请重启 App');
      if (mounted) _showRestartDialog();
    } catch (e) {
      setState(() => _status = '恢复失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showRestartDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复完成'),
        content: const Text('数据已覆盖。请退出并重新打开 App，'
            '新数据会在下次启动时加载。'),
        actions: [
          TextButton(
            onPressed: () {
              SystemNavigator.pop();
            },
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

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }
}
