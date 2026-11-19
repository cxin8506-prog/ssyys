import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/log/app_logger.dart';
import '../model/plugin_source.dart';

/// 插件源安装与索引管理。
///
/// 目录结构：
///   <app>/local_media_app/plugins/index.json     —— 源索引
///   <app>/local_media_app/plugins/<sourceId>/...  —— 解压后的源文件
class SourceRepository {
  static const _indexName = 'index.json';

  Future<Directory> pluginsRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'local_media_app', 'plugins'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _indexFile() async =>
      File(p.join((await pluginsRoot()).path, _indexName));

  Future<List<PluginSource>> loadAll() async {
    final f = await _indexFile();
    if (!await f.exists()) return [];
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return [];
      return raw
          .whereType<Map>()
          .map((e) => PluginSource.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();
    } catch (e, st) {
      appLogger.error('源索引读取失败', error: e, stack: st);
      return [];
    }
  }

  Future<void> _saveIndex(List<PluginSource> list) async {
    final f = await _indexFile();
    await f.writeAsString(
        jsonEncode(list.map((e) => e.toJson()).toList(growable: false)));
  }

  /// 整体写回索引（改名/改类型/改主类用）
  Future<void> saveAll(List<PluginSource> list) => _saveIndex(list);

  Future<PluginSource?> byId(String id) async {
    final all = await loadAll();
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  Future<String> sourceDirPath(String id) async =>
      p.join((await pluginsRoot()).path, id);

  // ---------------------------------------------------------------- 安装 ZIP

  /// 安装 JS/ZIP 插件包。
  /// 包内可含 manifest.json（根目录或单层子目录），缺失时按文件名兜底。
  Future<PluginSource> installZip(String filePath,
      {String? typeOverride}) async {
    final bytes = await File(filePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1) 先解压到临时目录，便于探测 manifest 与目录层级
    final tmp = await Directory(p.join((await pluginsRoot()).path,
        '.tmp_${const Uuid().v4()}')).create(recursive: true);
    await _extract(archive, tmp.path);

    // 2) 定位 manifest
    final manifestFile = await _findManifest(tmp);
    Map<String, dynamic> manifest = {};
    Directory root = tmp;
    if (manifestFile != null) {
      root = manifestFile.parent;
      try {
        final m = jsonDecode(await manifestFile.readAsString());
        if (m is Map) manifest = Map<String, dynamic>.from(m);
      } catch (e) {
        appLogger.warning('manifest.json 解析失败，按默认值处理', detail: '$e');
      }
    }

    // 3) 基本信息
    final baseName = p.basenameWithoutExtension(filePath);
    final name = _pickString(manifest, ['name', '名称', 'title', 'sourceName']) ??
        baseName;
    var id = _pickString(manifest, ['id', 'key', 'package']) ??
        _slug('${baseName}_${DateTime.now().millisecondsSinceEpoch % 100000}');
    id = _slug(id);

    final type = typeOverride ??
        _pickString(manifest, ['type', '类型']) ??
        _guessType(manifest, root) ??
        'audio';

    var entry = _pickString(manifest, ['entry', 'script', 'main', 'entryFile']) ?? '';
    if (entry.isEmpty) entry = await _guessEntryScript(root);

    // 4) 移动到正式目录（同 id 覆盖安装）
    final target = Directory(p.join((await pluginsRoot()).path, id));
    if (await target.exists()) await target.delete(recursive: true);
    await root.rename(target.path);
    // 清掉可能残留的临时目录
    if (await tmp.exists()) await tmp.delete(recursive: true);

    final size = await _dirSize(target);
    final source = PluginSource(
      id: id,
      name: name,
      type: type,
      format: 'jsZip',
      version: _pickString(manifest, ['version', 'ver', '版本']) ?? '1.0.0',
      author: _pickString(manifest, ['author', '作者']) ?? '',
      description: _pickString(manifest, ['description', 'desc', '简介']) ?? '',
      entry: entry,
      icon: _pickString(manifest, ['icon', 'cover']),
      installedAt: DateTime.now().millisecondsSinceEpoch,
      sizeBytes: size,
    );

    final all = await loadAll();
    all.removeWhere((e) => e.id == id);
    all.add(source);
    await _saveIndex(all);
    appLogger.info('安装 JS/ZIP 源成功',
        detail: '${source.name} ($id) entry=$entry');
    return source;
  }

  // ---------------------------------------------------------------- 安装 JAR

  /// 安装 JAR 插件。JAR 需为 dex 化包（含 classes.dex）才能被 Android 加载。
  Future<PluginSource> installJar(String filePath,
      {String? typeOverride, String? mainClass}) async {
    final baseName = p.basenameWithoutExtension(filePath);
    final id = _slug('${baseName}_${DateTime.now().millisecondsSinceEpoch % 100000}');
    final target = Directory(p.join((await pluginsRoot()).path, id));
    if (await target.exists()) await target.delete(recursive: true);
    await target.create(recursive: true);

    final jarFile = File(p.join(target.path, 'plugin.jar'));
    await File(filePath).copy(jarFile.path);

    // 读 JAR 内的 MANIFEST / dex 情况
    String entry = mainClass ?? '';
    bool hasDex = false;
    try {
      final bytes = await jarFile.readAsBytes();
      final arc = ZipDecoder().decodeBytes(bytes);
      for (final f in arc.files) {
        final n = f.name.toLowerCase();
        if (n.endsWith('classes.dex')) hasDex = true;
        if (n == 'meta-inf/manifest.mf') {
          final txt = utf8.decode(f.content as List<int>, allowMalformed: true);
          for (final line in txt.split(RegExp(r'\r?\n'))) {
            if (line.toLowerCase().startsWith('main-class:')) {
              entry = line.substring('main-class:'.length).trim();
            }
          }
        }
      }
    } catch (e) {
      appLogger.warning('JAR 内容探测失败', detail: '$e');
    }

    final size = await _dirSize(target);
    final source = PluginSource(
      id: id,
      name: baseName,
      type: typeOverride ?? 'audio',
      format: 'jar',
      version: '1.0.0',
      description: hasDex ? '' : '该 JAR 未包含 classes.dex，Android 无法直接加载，需用 d8 转换',
      entry: entry,
      installedAt: DateTime.now().millisecondsSinceEpoch,
      sizeBytes: size,
    );

    final all = await loadAll();
    all.add(source);
    await _saveIndex(all);
    appLogger.info('安装 JAR 源成功', detail: '${source.name} dex=$hasDex entry=$entry');
    return source;
  }

  // ---------------------------------------------------------------- 其他操作

  Future<void> remove(String id) async {
    final all = await loadAll();
    all.removeWhere((e) => e.id == id);
    await _saveIndex(all);
    final dir = Directory(await sourceDirPath(id));
    if (await dir.exists()) await dir.delete(recursive: true);
    appLogger.info('已移除源', detail: id);
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final all = await loadAll();
    for (var i = 0; i < all.length; i++) {
      if (all[i].id == id) all[i].enabled = enabled;
    }
    await _saveIndex(all);
  }

  Future<void> rename(String id, String name) async {
    final all = await loadAll();
    for (var i = 0; i < all.length; i++) {
      if (all[i].id == id) {
        all[i] = all[i].copyWith(name: name);
        break;
      }
    }
    await _saveIndex(all);
  }

  /// 读取 JS 入口脚本内容
  Future<String> readEntryScript(PluginSource s) async {
    final dir = await sourceDirPath(s.id);
    var rel = s.entry;
    if (rel.isEmpty) rel = await _guessEntryScript(Directory(dir));
    final f = File(p.join(dir, rel));
    if (await f.exists()) return f.readAsString();
    // 兜底：目录里第一个 .js
    final guess = await _guessEntryScript(Directory(dir));
    if (guess.isNotEmpty) {
      final f2 = File(p.join(dir, guess));
      if (await f2.exists()) return f2.readAsString();
    }
    throw Exception('未找到 JS 入口脚本（entry=${s.entry}）');
  }

  // ---------------------------------------------------------------- 内部工具

  Future<void> _extract(Archive archive, String dest) async {
    for (final f in archive.files) {
      if (!f.isFile) continue;
      var rel = f.name.replaceAll('\\', '/');
      // 防目录穿越
      while (rel.startsWith('/')) {
        rel = rel.substring(1);
      }
      final parts = rel.split('/');
      final safe = <String>[];
      for (final seg in parts) {
        if (seg.isEmpty || seg == '.') continue;
        if (seg == '..') continue;
        safe.add(seg);
      }
      if (safe.isEmpty) continue;
      final outPath = p.joinAll([dest, ...safe]);
      final file = File(outPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(f.content as List<int>);
    }
  }

  Future<File?> _findManifest(Directory dir) async {
    final candidates = <File>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final base = p.basename(e.path).toLowerCase();
      if (base == 'manifest.json' || base == 'plugin.json') candidates.add(e);
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.path.length.compareTo(b.path.length));
    return candidates.first;
  }

  String? _pickString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return null;
  }

  String? _guessType(Map<String, dynamic> manifest, Directory root) {
    final caps = manifest['capabilities'];
    if (caps is List) {
      final s = caps.join(',').toLowerCase();
      if (s.contains('video') || s.contains('play')) return 'video';
      if (s.contains('audio') || s.contains('book') || s.contains('search')) {
        return 'audio';
      }
    }
    return null;
  }

  Future<String> _guessEntryScript(Directory dir) async {
    const preferred = ['index.js', 'main.js', 'source.js', 'plugin.js'];
    final jsFiles = <String>[];
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File && e.path.toLowerCase().endsWith('.js')) {
        jsFiles.add(p.relative(e.path, from: dir.path).replaceAll('\\', '/'));
      }
    }
    if (jsFiles.isEmpty) return '';
    jsFiles.sort((a, b) {
      final ai = preferred.indexOf(p.basename(a).toLowerCase());
      final bi = preferred.indexOf(p.basename(b).toLowerCase());
      final av = ai < 0 ? 99 : ai;
      final bv = bi < 0 ? 99 : bi;
      if (av != bv) return av.compareTo(bv);
      return a.length.compareTo(b.length);
    });
    return jsFiles.first;
  }

  String _slug(String raw) {
    final s = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final trimmed = s.replaceAll(RegExp(r'^_|_$'), '');
    return trimmed.isEmpty ? 'source_${DateTime.now().millisecondsSinceEpoch}' : trimmed;
  }

  Future<int> _dirSize(Directory dir) async {
    var total = 0;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) {
        try {
          total += await e.length();
        } catch (_) {}
      }
    }
    return total;
  }
}
