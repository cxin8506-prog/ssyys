import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';

/// 应用数据目录管理：集中管理所有本地数据路径，方便备份和迁移。
class PathUtils {
  PathUtils._();

  static Future<Directory> get appFilesDir async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(dir.path, 'local_media_app'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<Directory> get databaseDir async {
    final root = await appFilesDir;
    final d = Directory(p.join(root.path, 'database'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<Directory> get booksDir async {
    final root = await appFilesDir;
    final d = Directory(p.join(root.path, 'books'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
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

  static Future<Directory> get logsDir async {
    final root = await appFilesDir;
    final d = Directory(p.join(root.path, 'logs'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<Directory> get backupsDir async {
    final root = await appFilesDir;
    final d = Directory(p.join(root.path, 'backups'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// 取文件扩展名（小写，不含点）
  static String ext(String path) {
    final e = p.extension(path);
    if (e.isEmpty) return '';
    return e.substring(1).toLowerCase();
  }

  /// 判断文件类型
  static String? mediaType(String path) {
    final e = ext(path);
    if (AppConstants.audioExtensions.contains(e)) return AppConstants.typeAudio;
    if (AppConstants.videoExtensions.contains(e)) return AppConstants.typeVideo;
    return null;
  }

  static bool isArchive(String path) =>
      AppConstants.archiveExtensions.contains(ext(path));
  static bool isImage(String path) =>
      AppConstants.imageExtensions.contains(ext(path));

  /// 取文件名（不含扩展名）作为默认标题
  static String titleFromPath(String path) {
    final name = p.basenameWithoutExtension(path);
    return name.trim().isEmpty ? p.basename(path) : name;
  }

  /// 格式化字节大小
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  /// 格式化时长（毫秒 -> mm:ss 或 hh:mm:ss）
  static String formatDuration(int ms) {
    final total = ms ~/ 1000;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0)
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:$ss';
    return '${m.toString().padLeft(2, '0')}:$ss';
  }
}
