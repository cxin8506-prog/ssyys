import 'dart:io';

import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/log/app_logger.dart';
import '../../../core/utils/natural_sort.dart';
import '../../../core/utils/path_utils.dart';
import '../domain/media_item.dart';

/// 导入结果
class ImportResult {
  final MediaItem? item;
  final List<ChapterItem> chapters;
  final String? coverPath;
  final List<String> errors;

  const ImportResult({
    this.item,
    this.chapters = const [],
    this.coverPath,
    this.errors = const [],
  });

  bool get success => item != null;
}

/// 导入器：支持本地音频文件、文件夹、JAR/ZIP 音频包。
class MediaImporter {
  final _uuid = const Uuid();

  /// 导入一个路径（文件、文件夹或压缩包）
  Future<ImportResult> import(String path) async {
    final type = PathUtils.mediaType(path);
    final isArchive = PathUtils.isArchive(path);
    final entity =
        FileSystemEntity.isDirectorySync(path) ? Directory(path) : File(path);

    if (entity is Directory) {
      return _importFolder(path, type ?? AppConstants.typeAudio);
    }
    if (isArchive) {
      return _importArchive(path, type ?? AppConstants.typeAudio);
    }
    if (type != null) {
      return _importSingleFile(path, type);
    }
    return ImportResult(errors: ['不支持的文件类型: ${PathUtils.ext(path)}']);
  }

  /// 导入单个音频/视频文件（作为只有一章的条目）
  Future<ImportResult> _importSingleFile(String path, String type) async {
    final title = PathUtils.titleFromPath(path);
    final size = await File(path).length();
    final id = _uuid.v4();
    final chapter = ChapterItem(
      id: _uuid.v4(),
      itemId: id,
      title: title,
      path: path,
      orderIndex: 0,
    );
    final item = MediaItem(
      id: id,
      type: type,
      title: title,
      path: path,
      sourceType: 'single',
      chapterCount: 1,
      sizeBytes: size,
      addedAt: DateTime.now(),
      status: AppConstants.statusUnread,
    );
    appLogger.info('导入单文件', detail: path);
    return ImportResult(item: item, chapters: [chapter]);
  }

  /// 导入文件夹：扫描内部音频/视频文件，自然排序作为章节，找图片作封面
  Future<ImportResult> _importFolder(String folderPath, String type) async {
    final dir = Directory(folderPath);
    final files = <FileSystemEntity>[];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      files.add(entity);
    }

    final mediaFiles = <String>[];
    final errors = <String>[];
    String? coverPath;

    for (final f in files) {
      if (f is! File) continue;
      final e = PathUtils.ext(f.path);
      if (AppConstants.imageExtensions.contains(e)) {
        coverPath ??= f.path; // 用找到的第一张图片作封面
      } else if (type == AppConstants.typeAudio &&
          AppConstants.audioExtensions.contains(e)) {
        mediaFiles.add(f.path);
      } else if (type == AppConstants.typeVideo &&
          AppConstants.videoExtensions.contains(e)) {
        mediaFiles.add(f.path);
      }
    }

    if (mediaFiles.isEmpty) {
      return ImportResult(errors: [
        '文件夹内没有找到可播放的${type == AppConstants.typeAudio ? '音频' : '视频'}文件'
      ]);
    }

    // 自然排序：1、2、10 正确排列
    final sorted = NaturalSort.sort(mediaFiles);
    final id = _uuid.v4();
    final chapters = <ChapterItem>[];
    for (var i = 0; i < sorted.length; i++) {
      chapters.add(ChapterItem(
        id: _uuid.v4(),
        itemId: id,
        title: PathUtils.titleFromPath(sorted[i]),
        path: sorted[i],
        orderIndex: i,
      ));
    }

    int totalSize = 0;
    for (final f in mediaFiles) {
      try {
        totalSize += await File(f).length();
      } catch (e) {
        errors.add('读取大小失败: $f');
      }
    }

    final item = MediaItem(
      id: id,
      type: type,
      title: PathUtils.titleFromPath(folderPath),
      path: folderPath,
      coverPath: coverPath,
      sourceType: 'folder',
      chapterCount: chapters.length,
      sizeBytes: totalSize,
      addedAt: DateTime.now(),
    );
    appLogger.info('导入文件夹', detail: '$folderPath, ${chapters.length} 章');
    return ImportResult(
        item: item, chapters: chapters, coverPath: coverPath, errors: errors);
  }

  /// 导入 JAR/ZIP：当压缩包读，内部音频按文件名自然排序作为章节
  Future<ImportResult> _importArchive(String path, String type) async {
    final errors = <String>[];
    final audioEntries = <ArchiveFile>[];
    String? coverPath;

    try {
      final bytes = await File(path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        if (file.isFile) {
          final e = PathUtils.ext(file.name);
          if (AppConstants.imageExtensions.contains(e)) {
            coverPath ??= await _extractCover(file, path);
          } else if (type == AppConstants.typeAudio &&
              AppConstants.audioExtensions.contains(e)) {
            audioEntries.add(file);
          } else if (type == AppConstants.typeVideo &&
              AppConstants.videoExtensions.contains(e)) {
            audioEntries.add(file);
          }
        }
      }
    } catch (e, st) {
      appLogger.error('解压失败', error: e, stack: st);
      return ImportResult(errors: ['压缩包解析失败: $e']);
    }

    if (audioEntries.isEmpty) {
      return ImportResult(errors: ['压缩包内没有找到可播放文件']);
    }

    // 按文件名自然排序
    audioEntries.sort((a, b) => NaturalSort.compare(a.name, b.name));

    // 把内部音频解压到 books 目录，供播放器读取
    final outDir = await _archiveOutDir(path);
    final id = _uuid.v4();
    final chapters = <ChapterItem>[];
    for (var i = 0; i < audioEntries.length; i++) {
      final file = audioEntries[i];
      try {
        final outPath = '${outDir.path}/${file.name}';
        final outFile = File(outPath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
        chapters.add(ChapterItem(
          id: _uuid.v4(),
          itemId: id,
          title: PathUtils.titleFromPath(file.name),
          path: outPath,
          orderIndex: i,
        ));
      } catch (e, st) {
        // 损坏文件跳过并写日志
        errors.add('跳过损坏文件: ${file.name}');
        appLogger.error('压缩包内文件解压失败', error: e, stack: st);
      }
    }

    if (chapters.isEmpty) {
      return ImportResult(errors: ['压缩包内文件全部损坏', ...errors]);
    }

    final item = MediaItem(
      id: id,
      type: type,
      title: PathUtils.titleFromPath(path),
      path: path,
      coverPath: coverPath,
      sourceType: 'archive',
      chapterCount: chapters.length,
      sizeBytes: await File(path).length(),
      addedAt: DateTime.now(),
    );
    appLogger.info('导入压缩包', detail: '$path, ${chapters.length} 章');
    return ImportResult(
        item: item, chapters: chapters, coverPath: coverPath, errors: errors);
  }

  Future<Directory> _archiveOutDir(String archivePath) async {
    final books = await PathUtils.booksDir;
    final name = PathUtils.titleFromPath(archivePath);
    final d = Directory('${books.path}/$name');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<String> _extractCover(ArchiveFile file, String archivePath) async {
    final covers = await PathUtils.coversDir;
    final name = '${PathUtils.titleFromPath(archivePath)}_${file.name}';
    final out = File('${covers.path}/$name');
    await out.create(recursive: true);
    await out.writeAsBytes(file.content as List<int>);
    return out.path;
  }
}
