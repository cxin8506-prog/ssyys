import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/log/app_logger.dart';
import '../model/plugin_source.dart';
import 'ting_shu_bridge.dart';

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

  /// 读取源目录里的 manifest.json（JAR 源可能没有，返回空表）
  Future<Map<String, dynamic>> readManifest(PluginSource s) async {
    try {
      final dir = Directory(await sourceDirPath(s.id));
      if (!await dir.exists()) return {};
      final direct = File(p.join(dir.path, 'manifest.json'));
      final file = await direct.exists()
          ? direct
          : await _findManifest(dir) ?? direct;
      if (!await file.exists()) return {};
      final m = jsonDecode(await file.readAsString());
      if (m is Map) return Map<String, dynamic>.from(m);
    } catch (e) {
      appLogger.warning('manifest.json 读取失败', detail: '$e');
    }
    return {};
  }

  /// 读取入口脚本内容（源声明/诊断用）
  Future<String> readEntryScriptText(PluginSource s) async {
    final dir = await sourceDirPath(s.id);
    for (final name in [s.entry, 'main.js', 'index.js', 'source.js']) {
      if (name.isEmpty) continue;
      final f = File(p.join(dir, name));
      if (await f.exists()) return f.readAsString();
    }
    return '';
  }

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

    var entry = _pickString(manifest, ['entry', 'script', 'main', 'entryFile']) ?? '';
    if (entry.isEmpty) entry = await _guessEntryScript(root);

    // 类型：不用用户选，按「manifest 声明 → capabilities → 脚本内容 → 文件名」自动判断
    final String resolvedType;
    final declared = typeOverride ?? _pickString(manifest, ['type', '类型']);
    if (declared != null && declared.isNotEmpty) {
      resolvedType = declared;
    } else {
      final guessed = _guessType(manifest, root);
      if (guessed != null && guessed.isNotEmpty) {
        resolvedType = guessed;
      } else {
        final sample = await _readScriptSample(root, entry);
        resolvedType =
            _detectType('$baseName\n${jsonEncode(manifest)}\n$sample');
      }
    }

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
      type: resolvedType,
      format: 'jsZip',
      version: _pickString(manifest, ['version', 'ver', '版本']) ?? '1.0.0',
      author: _pickString(manifest, ['author', '作者']) ?? '',
      description: _pickString(manifest, ['description', 'desc', '简介']) ?? '',
      entry: entry,
      icon: _pickString(manifest, ['icon', 'cover']),
      // 分组名用包名（manifest 声明的分组，没有就用 ZIP 文件名），
      // 书源页按这个分组，不要再出现「其他」。
      group: _pickString(manifest, ['group', '分组']) ?? baseName,
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

  /// 安装 JAR 插件。
  ///
  /// 「我的听书」格式：一个 JAR 里有 SourceEntry.getSources() 返回的一串源，
  /// 这里把它们拆成多条 PluginSource，共用同一份 plugin.jar。
  /// 其余静态方法式 JAR 仍按单个源安装。
  Future<List<PluginSource>> installJar(String filePath,
      {String? typeOverride, String? mainClass}) async {
    final baseName = p.basenameWithoutExtension(filePath);
    final root = await pluginsRoot();
    // 文件名可能是中文，_slug 会把它整成空串，这里用哈希保证唯一且稳定
    final sig = baseName.hashCode.abs().toRadixString(36);

    // 同一个包共用一份 jar，放在 _jar_<签名> 下
    final groupDir = Directory(p.join(root.path, '_jar_$sig'));
    if (await groupDir.exists()) await groupDir.delete(recursive: true);
    await groupDir.create(recursive: true);
    final jarFile = File(p.join(groupDir.path, 'plugin.jar'));
    await File(filePath).copy(jarFile.path);

    // 先按「我的听书」格式解析：一个包 -> 多个源
    final entries = await TingShuBridge.scanEntryClasses(jarFile.path);
    final entryClass = entries.isEmpty ? null : entries.first;
    final found = entryClass == null
        ? <Map<String, dynamic>>[]
        : await TingShuBridge.listSources(jarFile.path, entryClass);

    if (entryClass != null && found.isNotEmpty) {
      final totalSize = await _dirSize(groupDir);
      final each = (totalSize / found.length).round();
      final all = await loadAll();
      // 重装同一个包：先清掉这个包的旧条目，以及旧版把它当成单文件 JAR 的那条。
      // 清理条件要宽一点：旧条目可能是扫描失败时落到旧格式分支的那条，
      // 名字可能是包名，也可能是残缺的名字（比如「影视_」），还可能已经是
      // 上次自愈拆出来的多源条目——按包名、残缺名、同一个共享目录三种条件清。
      final groupDirName = '_jar_$sig';
      bool samePackage(PluginSource e) {
        if (e.group == baseName) return true;
        final dirName = p.basename(p.dirname(e.jarPath ?? ''));
        if (dirName == groupDirName) return true;
        return false;
      }

      final legacyIds = <String>[];
      for (final e in all) {
        if (e.isTingShu && samePackage(e)) {
          legacyIds.add(e.id);
          continue;
        }
        if (e.isJar && (e.name == baseName || _isTruncatedName(e.name, baseName) || samePackage(e))) {
          legacyIds.add(e.id);
        }
      }
      all.removeWhere((e) => legacyIds.contains(e.id));
      for (final id in legacyIds) {
        final d = Directory(await sourceDirPath(id));
        if (await d.exists()) await d.delete(recursive: true);
      }

      final list = <PluginSource>[];
      for (final m in found) {
        final index = int.tryParse('${m['index']}') ?? 0;
        var name = '${m['name'] ?? ''}'.trim();
        if (name.isEmpty) name = '$baseName ${index + 1}';
        final desc = '${m['desc'] ?? ''}'.trim();
        final url = '${m['url'] ?? ''}';
        final type = typeOverride ?? _detectType('$name\n$desc\n$url');
        list.add(PluginSource(
          id: 'ts_${sig}_$index',
          name: name,
          type: type,
          format: 'tingShu',
          version: '1.0.0',
          description: desc,
          entry: entryClass,
          entryClass: entryClass,
          jarPath: jarFile.path,
          sourceIndex: index,
          group: baseName,
          installedAt: DateTime.now().millisecondsSinceEpoch,
          sizeBytes: each,
        ));
      }
      // 再按（入口类，下标，源名）去重：启动自愈拆出来的旧条目，
      // 包名可能不准（比如 group 是「影视」），重导时靠这个三元组认出同一批源。
      all.removeWhere((e) =>
          e.isTingShu &&
          list.any((n) =>
              n.entryClass == e.entryClass &&
              n.sourceIndex == e.sourceIndex &&
              n.name == e.name));
      all.addAll(list);
      await _saveIndex(all);
      appLogger.info('安装我的听书源包成功',
          detail: '$baseName 共 ${list.length} 个源，入口 $entryClass');
      return list;
    }

    // 旧格式：单个主类的静态方法插件
    final target = groupDir;
    String entry = mainClass ?? '';
    bool hasDex = false;
    final probe = StringBuffer(baseName);
    try {
      final bytes = await jarFile.readAsBytes();
      final arc = ZipDecoder().decodeBytes(bytes);
      for (final f in arc.files) {
        final n = f.name.toLowerCase();
        if (n.endsWith('classes.dex')) {
          hasDex = true;
          if (probe.length < 400000) {
            final content = f.content as List<int>;
            probe.write(String.fromCharCodes(
                content.length > 600000 ? content.sublist(0, 600000) : content));
          }
        }
        if (n == 'meta-inf/manifest.mf') {
          final txt = utf8.decode(f.content as List<int>, allowMalformed: true);
          probe.write('\n$txt');
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

    // 扫描不到入口类，但 dex 里有 SourceEntry / getSources 的痕迹：
    // 这就是「我的听书」格式的源包，只是原生桥没读出来。
    // 不许悄悄装成一个用不了的单源，直接报人话错误，让用户删掉重导。
    if (hasDex &&
        (probe.toString().contains('SourceEntry') ||
            probe.toString().contains('getSources'))) {
      throw Exception('这个 JAR 是「我的听书」格式的源包，但 App 没能读出里面的源。'
          '请先在源管理里删掉它，再重新导入一次；如果还是不行，可能是这个包有问题。');
    }

    String? type = typeOverride;
    if (type == null || type.isEmpty) {
      type = _detectType(probe.toString());
    }

    final id = _slug('jar_${sig}_${DateTime.now().millisecondsSinceEpoch % 100000}');
    final size = await _dirSize(target);
    final source = PluginSource(
      id: id,
      name: baseName,
      type: type,
      format: 'jar',
      version: '1.0.0',
      description: hasDex ? '' : '该 JAR 未包含 classes.dex，Android 无法直接加载，需用 d8 转换',
      entry: entry,
      // JAR 实际存在共享目录 _jar_<sig>/plugin.jar，引擎按这条路找；
      // 不写 jarPath 的话引擎去源目录下找，永远找不到。
      jarPath: jarFile.path,
      installedAt: DateTime.now().millisecondsSinceEpoch,
      sizeBytes: size,
    );

    final all = await loadAll();
    // 重装同一个包：先清掉同名旧单文件 JAR，避免索引里留重复的坏条目。
    // 同样按残缺名（比如「影视_」）和共享目录一起清，见 TingShu 分支的说明。
    final groupDirName = '_jar_$sig';
    final dup = all
        .where((e) =>
            e.isJar &&
            (e.name == baseName ||
                _isTruncatedName(e.name, baseName) ||
                p.basename(p.dirname(e.jarPath ?? '')) == groupDirName))
        .map((e) => e.id)
        .toList();
    all.removeWhere((e) => dup.contains(e.id));
    for (final dupId in dup) {
      final d = Directory(await sourceDirPath(dupId));
      if (await d.exists()) await d.delete(recursive: true);
    }
    all.add(source);
    await _saveIndex(all);
    appLogger.info('安装 JAR 源成功', detail: '${source.name} dex=$hasDex entry=$entry');
    return [source];
  }

  /// 残缺名判断：旧条目的名字去掉尾巴的下划线后，是不是包名的前半截。
  /// 比如「影视_」→「影视」，是「影视聚合」的前半截，就是同一个包的坏条目。
  bool _isTruncatedName(String name, String baseName) {
    final stripped = name.replaceAll(RegExp(r'_+$'), '');
    if (stripped.isEmpty || stripped.length < 2) return false;
    if (stripped == baseName) return false;
    return baseName.startsWith(stripped);
  }

  bool _repairAttempted = false;

  /// 启动自愈：把以前装坏的单个 JAR 条目（扫描失败时落到旧格式分支，
  /// 比如手机上那个「影视_」）重新按「我的听书」格式拆成多个源。
  /// 每个会话只跑一次；扫不到入口类的原样保留，不动用户的数据。
  /// 调用方：sourceListProvider 读到列表后调一次。
  Future<List<PluginSource>> repairLegacyJars(List<PluginSource> all) async {
    if (_repairAttempted) return all;
    _repairAttempted = true;
    final legacy =
        all.where((e) => e.isJar && (e.jarPath ?? '').isNotEmpty).toList();
    if (legacy.isEmpty) return all;
    var changed = false;
    for (final bad in legacy) {
      final jarPath = bad.jarPath!;
      if (!await File(jarPath).exists()) continue;
      List<String> entries;
      try {
        entries = await TingShuBridge.scanEntryClasses(jarPath);
      } catch (_) {
        continue;
      }
      if (entries.isEmpty) continue;
      List<Map<String, dynamic>> found;
      try {
        found = await TingShuBridge.listSources(jarPath, entries.first);
      } catch (_) {
        continue;
      }
      if (found.isEmpty) continue;
      // 旧条目的名字就是包名（文件主名），尾巴的下划线是残缺名，去掉；
      // 拆出来的源共用这份 JAR，group 用这个名字，重导时会按共享目录清掉。
      final baseName = bad.name.replaceAll(RegExp(r'_+$'), '');
      final sig = baseName.hashCode.abs().toRadixString(36);
      final totalSize = await _dirSize(Directory(p.dirname(jarPath)));
      final each = (totalSize / found.length).round();
      final list = <PluginSource>[];
      for (final m in found) {
        final index = int.tryParse('${m['index']}') ?? 0;
        var name = '${m['name'] ?? ''}'.trim();
        if (name.isEmpty) name = '$baseName ${index + 1}';
        final desc = '${m['desc'] ?? ''}'.trim();
        final url = '${m['url'] ?? ''}';
        list.add(PluginSource(
          id: 'ts_${sig}_$index',
          name: name,
          type: _detectType('$name\n$desc\n$url'),
          format: 'tingShu',
          version: '1.0.0',
          description: desc,
          entry: entries.first,
          entryClass: entries.first,
          jarPath: jarPath,
          sourceIndex: index,
          group: baseName,
          installedAt: DateTime.now().millisecondsSinceEpoch,
          sizeBytes: each,
        ));
      }
      all.removeWhere((e) => e.id == bad.id);
      all.addAll(list);
      changed = true;
      appLogger.info('自愈：坏的单源 JAR 已拆成多源',
          detail: '${bad.name} -> ${list.length} 个源');
    }
    if (changed) await _saveIndex(all);
    return all;
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

  /// 读入口脚本的前 200KB，用于自动判断源类型
  Future<String> _readScriptSample(Directory dir, String entry) async {
    try {
      final candidates = <File>[];
      if (entry.isNotEmpty) candidates.add(File(p.join(dir.path, entry)));
      if (candidates.isEmpty || !await candidates.first.exists()) {
        final guess = await _guessEntryScript(dir);
        if (guess.isNotEmpty) candidates.add(File(p.join(dir.path, guess)));
      }
      final buf = StringBuffer();
      for (final f in candidates) {
        if (!await f.exists()) continue;
        final text = await f.readAsString();
        buf.writeln(
            text.length > 200000 ? text.substring(0, 200000) : text);
      }
      return buf.toString();
    } catch (_) {
      return '';
    }
  }

  /// 从脚本内容 / 文件名 / dex 字符串里判断是听书还是视频。
  ///
  /// 判不准时返回 audio（听书类插件占多数），用户可以在源详情里手动改。
  String _detectType(String text) {
    final lower = text.toLowerCase();
    const videoWords = [
      'm3u8',
      'vod_',
      '/vod/',
      'videourl',
      'video_url',
      'playurl',
      'play_url',
      '影视',
      '电影',
      '电视剧',
      '剧集',
      'video',
      'player',
    ];
    const audioWords = [
      'mp3',
      'm4a',
      '听书',
      '有声',
      '播音',
      '音色',
      '评书',
      '相声',
      '章节',
      'chapterlist',
      '音频',
      'audio',
    ];

    int score(List<String> words) {
      var n = 0;
      for (final w in words) {
        n += RegExp(RegExp.escape(w)).allMatches(lower).length;
      }
      return n;
    }

    final v = score(videoWords);
    final a = score(audioWords);
    return (v >= 3 && v >= a * 1.5) ? 'video' : 'audio';
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
