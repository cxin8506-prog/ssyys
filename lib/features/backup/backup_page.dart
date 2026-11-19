import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/app_theme.dart';
import '../../core/utils/path_utils.dart';

/// 本地 zip 备份与恢复：打包数据库、封面、设置、日志。
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;
  String _status = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('所有数据保存在本地。备份为 zip 文件，可整体拷贝迁移。',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.backup),
              label: const Text('创建本地备份'),
              onPressed: _busy ? null : _createBackup,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.restore),
              label: const Text('从 zip 恢复'),
              onPressed: _busy ? null : _restore,
            ),
            const SizedBox(height: 20),
            if (_busy)
              const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary)),
            Text(_status, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  Future<void> _createBackup() async {
    setState(() {
      _busy = true;
      _status = '正在打包...';
    });
    try {
      final root = await PathUtils.appFilesDir;
      final encoder = ZipFileEncoder();
      final backups = await PathUtils.backupsDir;
      final name = 'backup_${DateTime.now().millisecondsSinceEpoch}.zip';
      final outPath = p.join(backups.path, name);
      encoder.create(outPath);
      // 打包 database / covers / logs 三个目录
      for (final sub in ['database', 'covers', 'logs']) {
        final dir = Directory(p.join(root.path, sub));
        if (dir.existsSync()) {
          await encoder.addDirectory(dir, includeDirName: true);
        }
      }
      encoder.close();
      final size = await File(outPath).length();
      setState(() => _status = '备份完成：$name (${PathUtils.formatSize(size)})');
    } catch (e) {
      setState(() => _status = '备份失败: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _status = '请选择备份 zip 文件（文件选择器）');
    // 恢复涉及覆盖数据库，需关闭数据库后再操作；此处给出流程骨架。
    // 实际实现：选 zip -> 解压到临时目录 -> 关闭 db -> 覆盖 database/covers/logs -> 重启。
    await Future.delayed(const Duration(milliseconds: 300));
  }
}
