import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../core/log/app_logger.dart';
import '../../core/utils/path_utils.dart';

/// 本地备份/恢复服务：打包 database / covers / logs / plugins 四个目录。
///
/// 插件目录也一起打包，换机后源和源的配置都能带过去。
class BackupService {
  static const List<String> dirs = ['database', 'covers', 'logs', 'plugins'];

  /// 创建一个 zip 备份，返回文件
  Future<File> createBackup() async {
    final root = await PathUtils.appFilesDir;
    final backups = await PathUtils.backupsDir;
    final name = 'backup_${DateTime.now().millisecondsSinceEpoch}.zip';
    final outPath = p.join(backups.path, name);

    final encoder = ZipFileEncoder();
    encoder.create(outPath);
    for (final sub in dirs) {
      final dir = Directory(p.join(root.path, sub));
      if (dir.existsSync()) {
        await encoder.addDirectory(dir, includeDirName: true);
      }
    }
    encoder.close();
    appLogger.info('创建本地备份', detail: outPath);
    return File(outPath);
  }

  /// 从 zip 恢复：解压到临时目录后覆盖回应用目录。
  /// 调用方需保证数据库已关闭（否则 sqlite 文件被占用）。
  Future<void> restoreFromZip(File zip) async {
    final root = await PathUtils.appFilesDir;
    final tmp = await Directory(p.join(root.path, '.restore_tmp')).create(
        recursive: true);

    // 1) 解压
    final bytes = await zip.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final f in archive.files) {
      if (!f.isFile) continue;
      var rel = f.name.replaceAll('\\', '/');
      while (rel.startsWith('/')) {
        rel = rel.substring(1);
      }
      final segs = <String>[];
      for (final s in rel.split('/')) {
        if (s.isEmpty || s == '.' || s == '..') continue;
        segs.add(s);
      }
      if (segs.isEmpty) continue;
      final out = File(p.joinAll([tmp.path, ...segs]));
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>);
    }

    // 2) 覆盖：先清空目标目录，再拷贝
    for (final sub in dirs) {
      final src = Directory(p.join(tmp.path, sub));
      if (!await src.exists()) continue;
      final dst = Directory(p.join(root.path, sub));
      if (await dst.exists()) await dst.delete(recursive: true);
      await _copyDir(src, dst);
    }

    // 3) 清理
    if (await tmp.exists()) await tmp.delete(recursive: true);
    appLogger.info('已从备份恢复', detail: zip.path);
  }

  Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final e in src.list(followLinks: false)) {
      final name = p.basename(e.path);
      if (e is Directory) {
        await _copyDir(e, Directory(p.join(dst.path, name)));
      } else if (e is File) {
        await e.copy(p.join(dst.path, name));
      }
    }
  }
}
