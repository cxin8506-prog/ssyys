import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 应用数据目录管理：集中管理所有本地数据路径，方便备份和迁移。
///
/// 注意（修旧版审计第 14 项的路径错位）：数据库在 `<应用文档>/database/app.db`，
/// 与 `local_media_app` 是平级关系，不在它里面。`databaseDir` 必须指向真实位置，
/// 备份打包也要按这个真实路径打，绝不能再打 `local_media_app/database`。
class PathUtils {
  PathUtils._();

  /// <应用文档>/local_media_app：插件、封面、缓存、备份都在这里
  static Future<Directory> get appFilesDir async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(dir.path, 'local_media_app'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// <应用文档>/database：数据库真实位置（与 local_media_app 平级）
  static Future<Directory> get databaseDir async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(dir.path, 'database'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 数据库文件本身：<应用文档>/database/app.db
  static Future<File> get databaseFile async {
    final dir = await databaseDir;
    return File(p.join(dir.path, 'app.db'));
  }

  static Future<Directory> get coversDir async {
    final root = await appFilesDir;
    final d = Directory(p.join(root.path, 'covers'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<Directory> get cacheDir async {
    final root = await appFilesDir;
    final d = Directory(p.join(root.path, 'cache'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<Directory> get backupsDir async {
    final root = await appFilesDir;
    final d = Directory(p.join(root.path, 'backups'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<Directory> get pluginsDir async {
    final root = await appFilesDir;
    final d = Directory(p.join(root.path, 'plugins'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 取文件扩展名（小写，不含点）
  static String ext(String path) {
    final e = p.extension(path);
    if (e.isEmpty) return '';
    return e.substring(1).toLowerCase();
  }

  /// 格式化字节大小
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  /// 格式化时长（毫秒 -> mm:ss 或 hh:mm:ss）
  static String formatDuration(int ms) {
    final total = ms ~/ 1000;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:$ss';
    }
    return '${m.toString().padLeft(2, '0')}:$ss';
  }
}
