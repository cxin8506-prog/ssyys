import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/path_utils.dart';
import 'backup_service.dart';

/// 本地 zip 备份与恢复：数据库、封面、日志、插件一起打包
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  final _service = BackupService();
  bool _busy = false;
  String _status = '';
  List<File> _localBackups = [];

  @override
  void initState() {
    super.initState();
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    try {
      final dir = await PathUtils.backupsDir;
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.zip'))
          .toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      if (mounted) setState(() => _localBackups = files);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _intro(),
          const SizedBox(height: 18),
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
                  CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 10),
                  Text(_status, style: Theme.of(context).textTheme.bodySmall),
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
        border: Border.all(color: context.palette.outline),
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
            '文件为 zip，可直接拷到新机恢复。',
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
      final file = await _service.createBackup();
      final size = await file.length();
      setState(() => _status =
          '备份完成：${file.uri.pathSegments.last}（${PathUtils.formatSize(size)}）');
      await _loadLocal();
    } catch (e) {
      setState(() => _status = '备份失败：$e');
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
    } catch (e) {
      setState(() => _status = '打开文件选择器失败：$e');
      return;
    }
    final path = picked?.files.single.path;
    if (path == null) return;
    await _doRestore(File(path));
  }

  Future<void> _doRestore(File zip) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认恢复'),
        content: const Text('会用备份覆盖当前的书架、进度、收藏、设置和插件。\n'
            '恢复完成后需要重启 App 才生效。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('覆盖恢复')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _status = '正在解压覆盖...';
    });
    try {
      try {
        await ref.read(databaseProvider).close();
      } catch (_) {}
      await _service.restoreFromZip(zip);
      setState(() => _status = '恢复完成，请重启 App');
      if (mounted) _restartDialog();
    } catch (e) {
      setState(() => _status = '恢复失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _restartDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复完成'),
        content: const Text('数据已覆盖，请退出并重新打开 App。'),
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
