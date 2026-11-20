import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../core/log/app_logger.dart';
import '../../core/utils/path_utils.dart';
import '../engine/ssts_runtime_js.dart';
import '../model/plugin_source.dart';
import 'source_config_repository.dart';
import 'ting_shu_bridge.dart';

/// 插件包里的一个脚本文件（安装/加载时按 manifest 顺序读）。
class PluginScriptFile {
  final String name;
  final String text;
  const PluginScriptFile(this.name, this.text);
}

/// 源安装 / 索引仓储。
///
/// 落盘：
/// - 索引：`<应用文档>/local_media_app/plugins/index.json`
///   （源列表：id、名字、类型、格式、分组、启用、排序……）
/// - 插件文件：`<应用文档>/local_media_app/plugins/<pluginId>/`
///   （JS 插件的解压目录；多源插件的多个源共用一份）
/// - JAR 文件：`<应用文档>/local_media_app/plugins/_jar_<签名>/plugin.jar`
///   （一个包一份 JAR，包里多个源共用）
///
/// 导入入口三种：JAR、ZIP、链接。ZIP 里只有一个顶层目录时去掉这一层；
/// 网址导入先按扩展名判断，不对时按魔数判断（PK 是 zip、MZ 是 dll）；
/// 导入失败报人话错，不要只报异常名；同名重导 = 升级，先清掉旧的同名条目再装。
class SourceRepository {
  static const String _indexName = 'index.json';

  /// JAR 单包大小上限（随心听书同款：超过 32MB 拒收）。
  static const int maxJarBytes = 32 * 1024 * 1024;

  /// ZIP 插件包大小上限（随身听书云同步同款：每包最多 32MB）。
  static const int maxZipBytes = 32 * 1024 * 1024;

  final SourceConfigRepository? _configRepo;

  SourceRepository({SourceConfigRepository? configRepo})
      : _configRepo = configRepo;

  Future<Directory> pluginsRoot() async {
    final root = await PathUtils.appFilesDir;
    final dir = Directory(p.join(root.path, 'plugins'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _indexFile() async =>
      File(p.join((await pluginsRoot()).path, _indexName));

  /// 读全部源，按 order 排（order 相同的按名字排）。
  Future<List<PluginSource>> loadAll() async {
    final f = await _indexFile();
    if (!await f.exists()) return <PluginSource>[];
    try {
      final raw = jsonDecode(await f.readAsString());
      if (raw is! List) return <PluginSource>[];
      final list = raw
          .whereType<Map>()
          .map((e) => PluginSource.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();
      list.sort((a, b) {
        final c = a.order.compareTo(b.order);
        if (c != 0) return c;
        return a.name.compareTo(b.name);
      });
      return list;
    } catch (e, st) {
      appLogger.error('源索引读取失败', error: e, stack: st);
      return <PluginSource>[];
    }
  }

  Future<void> _saveIndex(List<PluginSource> list) async {
    final f = await _indexFile();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(
        jsonEncode(list.map((e) => e.toJson()).toList(growable: false)));
    await tmp.rename(f.path);
  }

  /// 整体写回索引（改名/改类型/改主类/排序用）。
  Future<void> saveAll(List<PluginSource> list) => _saveIndex(list);

  Future<PluginSource?> byId(String id) async {
    final all = await loadAll();
    for (final s in all) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// 单个源的目录（旧写法每源一份目录；多源插件用 [pluginDirPath]）。
  Future<String> sourceDirPath(String id) async =>
      p.join((await pluginsRoot()).path, id);

  /// 插件包的解压目录：多源插件的多个源共用一份（pluginId），
  /// 单源插件就是源自己的目录。
  Future<String> pluginDirPath(PluginSource s) async =>
      p.join((await pluginsRoot()).path, s.pluginId ?? s.id);

  /// 脚本清单的根目录：manifest 所在目录（可能比插件目录深一层）。
  Future<Directory> _pluginScriptRoot(PluginSource s) async {
    final dir = Directory(await pluginDirPath(s));
    final m = await _findManifest(dir);
    return m?.parent ?? dir;
  }

  /// 读取源目录里的 manifest.json（JAR 源可能没有，返回空表）。
  Future<Map<String, dynamic>> readManifest(PluginSource s) async {
    try {
      final dir = Directory(await pluginDirPath(s));
      if (!await dir.exists()) return <String, dynamic>{};
      final direct = File(p.join(dir.path, 'manifest.json'));
      final file = await direct.exists()
          ? direct
          : await _findManifest(dir) ?? direct;
      if (!await file.exists()) return <String, dynamic>{};
      final m = jsonDecode(await file.readAsString());
      if (m is Map) return Map<String, dynamic>.from(m);
    } catch (e) {
      appLogger.warning('manifest.json 读取失败', detail: '$e');
    }
    return <String, dynamic>{};
  }

  /// 读取入口脚本内容（源声明/诊断用）。
  Future<String> readEntryScriptText(PluginSource s) async {
    final dir = await pluginDirPath(s);
    for (final name in <String>[
      s.entry,
      'main.js',
      'index.js',
      'source.js',
    ]) {
      if (name.isEmpty) continue;
      final f = File(p.join(dir, name));
      if (await f.exists()) return f.readAsString();
    }
    return '';
  }

  /// 读取 JS 入口脚本内容（旧名，引擎用）。
  Future<String> readEntryScript(PluginSource s) async {
    final dir = await pluginDirPath(s);
    var rel = s.entry;
    if (rel.isEmpty) rel = await _guessEntryScript(Directory(dir));
    final f = File(p.join(dir, rel));
    if (await f.exists()) return f.readAsString();
    // 兜底：目录里第一个 .js。
    final guess = await _guessEntryScript(Directory(dir));
    if (guess.isNotEmpty) {
      final f2 = File(p.join(dir, guess));
      if (await f2.exists()) return f2.readAsString();
    }
    throw Exception('未找到 JS 入口脚本（entry=${s.entry}）');
  }

  /// 按 manifest 的 scripts 顺序读插件脚本（引擎 attach 时用）。
  Future<List<PluginScriptFile>> readPluginScripts(PluginSource s) async {
    final root = await _pluginScriptRoot(s);
    final manifest = await readManifest(s);
    final names = await _sstsScriptNames(root, manifest);
    final out = <PluginScriptFile>[];
    for (final name in names) {
      final f = File(p.join(root.path, name));
      if (!await f.exists()) continue;
      try {
        out.add(PluginScriptFile(name, await f.readAsString()));
      } catch (_) {}
    }
    return out;
  }

  // ---------------------------------------------------------------- 安装 ZIP

  /// 安装 JS/ZIP 插件包。
  /// 包内可含 manifest.json（根目录或单层子目录），缺失时按文件名兜底。
  /// 随身听书格式（manifest 有 scripts，或脚本里有 registerSource）会拆成
  /// 多个源，一次返回多条；旧写法仍按单个源安装。
  Future<List<PluginSource>> installZip(String filePath,
      {String? typeOverride}) async {
    final srcFile = File(filePath);
    if (!await srcFile.exists()) throw Exception('找不到文件：$filePath');
    final size = await srcFile.length();
    if (size > maxZipBytes) {
      throw Exception('插件包太大了（超过 32MB），请检查文件');
    }
    final bytes = await srcFile.readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw Exception('这个文件不是 ZIP 插件包（解不开），请检查文件');
    }

    // 1) 先解压到临时目录，便于探测 manifest 与目录层级。
    final tmp = await Directory(p.join((await pluginsRoot()).path,
            '.tmp_${const Uuid().v4()}'))
        .create(recursive: true);
    try {
      await _extract(archive, tmp.path);
    } catch (e) {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }

    // ZIP 里只有一个顶层目录时去掉这一层。
    var root = _stripSingleTopDir(tmp);

    // 2) 定位 manifest，并把「manifest 所在目录」定为插件根：
    // 脚本路径都是相对 manifest 写的，多一层时会全部读错。
    final manifestFile = await _findManifest(root);
    Map<String, dynamic> manifest = <String, dynamic>{};
    if (manifestFile != null) {
      final manifestDir = manifestFile.parent;
      if (manifestDir.absolute.path != root.absolute.path) {
        root = manifestDir;
      }
      try {
        final m = jsonDecode(await manifestFile.readAsString());
        if (m is Map) manifest = Map<String, dynamic>.from(m);
      } catch (e) {
        appLogger.warning('manifest.json 解析失败，按默认值处理', detail: '$e');
      }
    }

    // 3) 基本信息。
    final baseName = p.basenameWithoutExtension(filePath);
    final name = _pickString(manifest, const <String>[
          'name',
          '名称',
          'title',
          'sourceName',
        ]) ??
        baseName;
    var id = _pickString(manifest, const <String>['id', 'key', 'package']) ??
        _slug(baseName);
    id = _slug(id);

    // 随身听书格式：先看脚本清单，再决定走哪条安装路。
    final scriptNames = await _sstsScriptNames(root, manifest);
    if (await _looksLikeSsts(root, manifest, scriptNames)) {
      return _installSstsZip(
          tmp, root, manifest, id, name, baseName, scriptNames, typeOverride);
    }
    return _installLegacyZip(
        tmp, root, manifest, id, name, baseName, typeOverride);
  }

  /// 随身听书插件的脚本清单：manifest 的 scripts 数组优先，
  /// 没有就按文件名顺序取包里所有 .js。
  Future<List<String>> _sstsScriptNames(
      Directory root, Map<String, dynamic> manifest) async {
    final out = <String>[];
    void add(String name) {
      var n = name.trim().replaceAll('\\', '/');
      while (n.startsWith('./')) {
        n = n.substring(2);
      }
      if (n.isEmpty || out.contains(n)) return;
      if (!File(p.join(root.path, n)).existsSync()) return;
      out.add(n);
    }

    final scripts = manifest['scripts'];
    if (scripts is List) {
      for (final e in scripts) {
        add('$e');
      }
    } else if (scripts is String) {
      for (final part in scripts.split(RegExp(r'[;,]'))) {
        add(part);
      }
    }
    if (out.isNotEmpty) return out;

    // scripts 没写或全写错：用 entry 顶上，再不济扫全部 .js。
    final entry = _pickString(manifest, const <String>[
      'entry',
      'script',
      'main',
      'entryFile',
    ]);
    if (entry != null && entry.toLowerCase().endsWith('.js')) add(entry);

    final files = <String>[];
    try {
      await for (final e in root.list(recursive: true, followLinks: false)) {
        if (e is File && e.path.toLowerCase().endsWith('.js')) {
          final rel = p.relative(e.path, from: root.path).replaceAll('\\', '/');
          if (rel.startsWith('__MACOSX')) continue;
          files.add(rel);
        }
      }
    } catch (_) {}
    files.sort();
    for (final f in files) {
      if (!out.contains(f)) out.add(f);
    }
    return out;
  }

  /// 是不是随身听书格式：manifest 声明了 scripts，或者脚本里有 registerSource。
  Future<bool> _looksLikeSsts(Directory root, Map<String, dynamic> manifest,
      List<String> scriptNames) async {
    final scripts = manifest['scripts'];
    if (scripts is List && scripts.isNotEmpty) return true;
    for (final name in scriptNames) {
      final f = File(p.join(root.path, name));
      if (!await f.exists()) continue;
      try {
        final text = await f.readAsString();
        if (text.contains('registerSource')) return true;
      } catch (_) {}
    }
    return false;
  }

  /// 安装随身听书插件：先在临时 JS 环境里跑脚本读注册表，
  /// 再把注册出来的每个源拆成一条记录，共用一份解压目录。
  /// 读不到注册信息的包不装空壳。
  Future<List<PluginSource>> _installSstsZip(
      Directory tmp,
      Directory root,
      Map<String, dynamic> manifest,
      String pluginId,
      String name,
      String baseName,
      List<String> scriptNames,
      String? typeOverride) async {
    final errors = <String>[];
    var meta = await _collectSstsMeta(root, scriptNames, errors: errors);
    if (meta.isEmpty) {
      meta = _metaFromManifest(manifest, name, baseName);
    }

    // 落到正式目录（同 id 覆盖安装）。
    final target = Directory(p.join((await pluginsRoot()).path, pluginId));
    if (await target.exists()) await target.delete(recursive: true);
    await root.rename(target.path);
    if (await tmp.exists()) await tmp.delete(recursive: true);

    if (meta.isEmpty) {
      try {
        await target.delete(recursive: true);
      } catch (_) {}
      final brief = errors.isEmpty
          ? ''
          : '（${errors.first}${errors.length > 1 ? '，另有 ${errors.length - 1} 个脚本出错' : ''}）';
      throw Exception('这个插件包里的脚本没有注册出任何源$brief。'
          '常见原因：包不是随身听书格式、manifest 写的脚本路径不对，'
          '或者脚本在注册前就要联网。请换一个包，或把包发开发者看日志。');
    }
    final size = await _dirSize(target);
    final each = (size / meta.length).round();
    final version = _pickString(manifest, const <String>['version', 'ver', '版本']) ??
        '1.0.0';
    final author =
        _pickString(manifest, const <String>['author', '作者']) ?? '';
    final manifestDesc = _pickString(
            manifest, const <String>['description', 'desc', '简介']) ??
        '';

    final all = await loadAll();
    // 重装同一个包：清掉这个插件的旧条目，以及旧版把它当成单源的那条。
    // 旧单源条目的目录也要清（别清到刚落盘的新目录）。
    final removedIds = <String>[];
    all.removeWhere((e) {
      final samePlugin = e.pluginId == pluginId;
      final legacySingle = e.isJs &&
          (e.pluginId == null || e.pluginId!.isEmpty) &&
          (e.group == name || e.group == baseName);
      if (samePlugin || legacySingle) {
        removedIds.add(e.id);
        return true;
      }
      return false;
    });
    for (final oldId in removedIds) {
      if (oldId == pluginId) continue;
      final d = Directory(await sourceDirPath(oldId));
      if (await d.exists()) await d.delete(recursive: true);
    }
    // 旧条目删掉后，源配置里残留的配置也清掉（登录态/音色/线路按源 id 存）。
    final configRepo = _configRepo;
    if (configRepo != null) {
      for (final oldId in removedIds) {
        try {
          await configRepo.clear(oldId);
        } catch (_) {}
      }
    }

    final orderBase = _nextOrderBase(all);
    final list = <PluginSource>[];
    for (var i = 0; i < meta.length; i++) {
      final m = meta[i];
      final sid = '${m['id'] ?? ''}'.trim();
      if (sid.isEmpty) continue;
      var sname = '${m['name'] ?? ''}'.trim();
      if (sname.isEmpty) sname = name;
      final url = '${m['url'] ?? ''}';
      final desc = '${m['description'] ?? ''}'.trim();
      final type = typeOverride ?? _detectType('$sname\n$desc\n$url');
      // 两个不同插件注册了同一个源 id 时，后装的加插件前缀，避免互相覆盖。
      var finalId = sid;
      if (all.any((e) => e.id == finalId && e.pluginId != pluginId)) {
        finalId = '${pluginId}_$sid';
      }
      list.add(PluginSource(
        id: finalId,
        name: sname,
        type: type,
        format: 'js',
        version: version,
        author: author,
        description: desc.isNotEmpty ? desc : manifestDesc,
        url: url.isEmpty ? null : url,
        entry: '',
        group: name,
        pluginId: pluginId,
        sstsId: sid,
        enabled: m['enabledByDefault'] != false,
        order: orderBase + i * 10,
        installedAt: DateTime.now().millisecondsSinceEpoch,
        sizeBytes: each,
      ));
    }
    if (list.isEmpty) {
      throw Exception('这个插件没有注册任何源');
    }
    all.addAll(list);
    await _saveIndex(all);
    appLogger.info('安装随身听书插件成功', detail: '$name 共 ${list.length} 个源');
    return list;
  }

  /// 安装时跑一遍脚本，读 registerSource 注册表（只取元数据，不联网）。
  /// 脚本在导入时不该联网，host 方法调了就抛错；注册本身不受影响。
  /// 单个脚本中途抛错只记日志，不让它拖垮整包（已注册的源照常装）。
  Future<List<Map<String, dynamic>>> _collectSstsMeta(
      Directory root, List<String> scriptNames,
      {List<String>? errors}) async {
    final rt = getJavascriptRuntime();
    try {
      rt.evaluate(buildSstsBootstrap(null, <String, dynamic>{}));
      // 安装时不该联网：日志类调用直接丢弃。
      rt.evaluate('globalThis.__hostCall = function() { return null; };');
      for (final name in scriptNames) {
        final f = File(p.join(root.path, name));
        if (!await f.exists()) continue;
        String text;
        try {
          text = await f.readAsString();
        } catch (e) {
          errors?.add('$name 读取失败');
          continue;
        }
        final err = await _evalScriptReplay(rt, text);
        if (err != null) {
          errors?.add('$name：$err');
          appLogger.warning('插件脚本安装时执行出错', detail: '$name: $err');
        }
      }
      final metaRes = rt.evaluate('globalThis.__sstsMeta()');
      if (metaRes.isError) {
        errors?.add('注册表读取失败：${metaRes.stringResult}');
        return <Map<String, dynamic>>[];
      }
      final decoded = jsonDecode(metaRes.stringResult);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      return <Map<String, dynamic>>[];
    } catch (e) {
      errors?.add('注册表读取异常：$e');
      appLogger.warning('随身听书插件注册表读取失败', detail: '$e');
      return <Map<String, dynamic>>[];
    } finally {
      try {
        rt.dispose();
      } catch (_) {}
    }
  }

  /// 在运行时装执行一段脚本，支持挂起重放。返回 null 表示跑完，
  /// 否则是错误原因。安装期的网络调用不回填真实数据，只回填错误，
  /// 让脚本继续往下跑（registerSource 不会被第一个网络调用截断）。
  Future<String?> _evalScriptReplay(JavascriptRuntime rt, String code) async {
    try {
      rt.evaluate('globalThis.__sstsScriptText = ${jsonEncode(code)};');
    } catch (e) {
      return '脚本装载失败：$e';
    }
    var guard = 0;
    while (true) {
      if (++guard > 300) return '脚本调用次数过多（可能陷入死循环）';
      final res = rt
          .evaluate('globalThis.__sstsLoadScript(globalThis.__sstsScriptText)');
      if (res.isError) {
        return res.stringResult.isEmpty ? '脚本执行失败' : res.stringResult;
      }
      dynamic decoded;
      try {
        decoded = jsonDecode(res.stringResult);
      } catch (_) {
        return null;
      }
      if (decoded is! Map) return null;
      if (decoded['__ok'] == true) return null;
      if (decoded['__error'] != null) return '${decoded['__error']}';
      final susp = decoded['__suspend'];
      if (susp is Map) {
        final method = '${susp['method'] ?? ''}';
        final key = jsonEncode(<dynamic>[method, susp['payload']]);
        final entry = <String, dynamic>{
          'ok': false,
          'error': '安装阶段不联网（$method）',
        };
        try {
          rt.evaluate(
              'globalThis.__syncCache[${jsonEncode(key)}] = ${jsonEncode(entry)};');
        } catch (_) {}
        continue;
      }
      return null;
    }
  }

  /// manifest 里直接声明 sources 时的兜底（不跑脚本也能列出源）。
  List<Map<String, dynamic>> _metaFromManifest(
      Map<String, dynamic> manifest, String name, String baseName) {
    for (final key in const <String>['sources', 'sourceList']) {
      final raw = manifest[key];
      if (raw is! List) continue;
      final out = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final id = '${e['id'] ?? e['key'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        out.add(<String, dynamic>{
          'id': id,
          'name': '${e['name'] ?? e['title'] ?? id}',
          'url': '${e['url'] ?? ''}',
          'description': '${e['description'] ?? e['desc'] ?? ''}',
          'enabledByDefault': e['enabledByDefault'] != false,
        });
      }
      if (out.isNotEmpty) return out;
    }
    return const <Map<String, dynamic>>[];
  }

  /// 安装旧式单源 ZIP（全局函数写法，没有 registerSource）。
  Future<List<PluginSource>> _installLegacyZip(
      Directory tmp,
      Directory root,
      Map<String, dynamic> manifest,
      String id,
      String name,
      String baseName,
      String? typeOverride) async {
    var entry = _pickString(manifest, const <String>[
          'entry',
          'script',
          'main',
          'entryFile',
        ]) ??
        '';
    if (entry.isEmpty) entry = await _guessEntryScript(root);

    // 类型：不用用户选，按「manifest 声明 → 脚本内容 → 文件名」自动判断。
    final String resolvedType;
    final declared = typeOverride ??
        _pickString(manifest, const <String>['type', '类型']);
    if (declared != null && declared.isNotEmpty) {
      resolvedType = _normalizeType(declared);
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

    // 移动到正式目录（同 id 覆盖安装）。
    final target = Directory(p.join((await pluginsRoot()).path, id));
    if (await target.exists()) await target.delete(recursive: true);
    await root.rename(target.path);
    if (await tmp.exists()) await tmp.delete(recursive: true);

    final size = await _dirSize(target);
    final all = await loadAll();
    all.removeWhere((e) => e.id == id);
    final source = PluginSource(
      id: id,
      name: name,
      type: resolvedType,
      format: 'js',
      version:
          _pickString(manifest, const <String>['version', 'ver', '版本']) ??
              '1.0.0',
      author:
          _pickString(manifest, const <String>['author', '作者']) ?? '',
      description: _pickString(
              manifest, const <String>['description', 'desc', '简介']) ??
          '',
      entry: entry,
      icon: _pickString(manifest, const <String>['icon', 'cover']),
      // 分组名用包名（manifest 声明的分组，没有就用 ZIP 文件名）。
      group: _pickString(manifest, const <String>['group', '分组']) ?? baseName,
      pluginId: id,
      order: _nextOrderBase(all),
      installedAt: DateTime.now().millisecondsSinceEpoch,
      sizeBytes: size,
    );
    all.add(source);
    await _saveIndex(all);
    appLogger.info('安装 JS/ZIP 源成功',
        detail: '${source.name} ($id) entry=$entry');
    return <PluginSource>[source];
  }

  // ---------------------------------------------------------------- 安装 JAR

  /// 安装 JAR 插件包。
  /// 只认含 classes.dex 的 jar，超过 32MB 拒收；导入后把文件设成只读
  /// （Android 14+ 不允许加载可写的 dex/jar），再清掉这个 JAR 的旧 odex。
  /// 先按「我的听书」格式解析（一个包 → 多个源）；扫不到入口类、
  /// 但 dex 里有 SourceEntry / getSources 痕迹时，直接报人话错，
  /// 不许悄悄装成一个用不了的单源。
  Future<List<PluginSource>> installJar(String filePath,
      {String? typeOverride, String? mainClass}) async {
    final srcFile = File(filePath);
    if (!await srcFile.exists()) throw Exception('找不到文件：$filePath');
    final fileSize = await srcFile.length();
    if (fileSize > maxJarBytes) {
      throw Exception('JAR 书源包太大了（超过 32MB），请检查文件');
    }
    if (fileSize == 0) throw Exception('JAR 书源包是空的');
    final baseName = p.basenameWithoutExtension(filePath);
    final root = await pluginsRoot();
    // 文件名可能是中文，_slug 会把它整成空串，这里用哈希保证唯一且稳定。
    final sig = baseName.hashCode.abs().toRadixString(36);

    // 同一个包共用一份 jar，放在 _jar_<签名> 下。
    final groupDir = Directory(p.join(root.path, '_jar_$sig'));
    if (await groupDir.exists()) await groupDir.delete(recursive: true);
    await groupDir.create(recursive: true);
    final jarFile = File(p.join(groupDir.path, 'plugin.jar'));
    await srcFile.copy(jarFile.path);
    // Android 14+ 拒绝加载可写的 dex：拷完立刻设只读，再清掉这个 JAR 的
    // 旧加载器/odex 缓存（重导同一个包，不清会命中旧的），然后再扫描。
    // 设只读失败也继续走（日志里记一笔，扫描失败时原因里会带上）。
    if (!await TingShuBridge.makeReadOnly(jarFile.path)) {
      appLogger.warning('JAR 设只读失败，Android 14+ 可能拒绝加载',
          detail: jarFile.path);
    }
    await TingShuBridge.clearJarCache(jarFile.path);

    // 先按「我的听书」格式解析：一个包 -> 多个源。
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
        if (e.isJar &&
            (e.name == baseName ||
                _isTruncatedName(e.name, baseName) ||
                samePackage(e))) {
          legacyIds.add(e.id);
        }
      }
      all.removeWhere((e) => legacyIds.contains(e.id));
      for (final id in legacyIds) {
        final d = Directory(await sourceDirPath(id));
        if (await d.exists()) await d.delete(recursive: true);
      }
      final configRepo = _configRepo;
      if (configRepo != null) {
        for (final id in legacyIds) {
          try {
            await configRepo.clear(id);
          } catch (_) {}
        }
      }

      final orderBase = _nextOrderBase(all);
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
          format: 'tingshu',
          version: '1.0.0',
          description: desc,
          url: url.isEmpty ? null : url,
          entry: entryClass,
          entryClass: entryClass,
          jarPath: jarFile.path,
          sourceIndex: index,
          group: baseName,
          pluginId: groupDirName,
          order: orderBase + index * 10,
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

    // 旧格式：单个主类的静态方法插件。先验 dex，没有 classes.dex 直接拒收。
    final target = groupDir;
    String entry = mainClass ?? '';
    bool hasDex = false;
    final probe = StringBuffer(baseName);
    try {
      final bytes = await jarFile.readAsBytes();
      final arc = ZipDecoder().decodeBytes(bytes);
      for (final f in arc.files) {
        final n = f.name.toLowerCase();
        if (n.endsWith('.dex') && n.contains('classes')) {
          hasDex = true;
          if (probe.length < 400000) {
            final content = f.content as List<int>;
            probe.write(String.fromCharCodes(content.length > 600000
                ? content.sublist(0, 600000)
                : content));
          }
        }
        if (n == 'meta-inf/manifest.mf') {
          final txt =
              utf8.decode(f.content as List<int>, allowMalformed: true);
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

    if (!hasDex) {
      try {
        await target.delete(recursive: true);
      } catch (_) {}
      throw Exception('这个 JAR 里没有 classes.dex，不是 Android 书源包，'
          '请用 d8 转换后再导入');
    }

    // 扫描不到入口类，但 dex 里有 SourceEntry / getSources 的痕迹：
    // 这就是「我的听书」格式的源包，只是原生桥没读出来。
    // 不许悄悄装成一个用不了的单源，直接报人话错误，让用户删掉重导。
    // 报错里带上是哪一步失败（扫描入口 / 列出源）和原生原因，下次不用再猜。
    if (probe.toString().contains('SourceEntry') ||
        probe.toString().contains('getSources')) {
      final stage = entryClass == null ? '扫描入口失败' : '列出源失败';
      final cause = entryClass == null
          ? TingShuBridge.lastScanError
          : TingShuBridge.lastListError;
      final detail = cause == null || cause.isEmpty
          ? ''
          : '（$stage：${_shortCause(cause)}）';
      try {
        await target.delete(recursive: true);
      } catch (_) {}
      throw Exception('这个 JAR 是「我的听书」格式的源包，但 App 没能读出里面的源。'
          '请先在源管理里删掉它，再重新导入一次；如果还是不行，可能是这个包有问题。$detail');
    }

    String? type = typeOverride;
    if (type == null || type.isEmpty) {
      type = _detectType(probe.toString());
    }

    final id =
        _slug('jar_${sig}_${DateTime.now().millisecondsSinceEpoch % 100000}');
    final size = await _dirSize(target);
    final source = PluginSource(
      id: id,
      name: baseName,
      type: type,
      format: 'jar',
      version: '1.0.0',
      description: '',
      entry: entry,
      // JAR 实际存在共享目录 _jar_<sig>/plugin.jar，引擎按这条路找；
      // 不写 jarPath 的话引擎去源目录下找，永远找不到。
      jarPath: jarFile.path,
      group: baseName,
      pluginId: '_jar_$sig',
      order: _nextOrderBase(await loadAll()),
      installedAt: DateTime.now().millisecondsSinceEpoch,
      sizeBytes: size,
    );

    final all = await loadAll();
    // 重装同一个包：先清掉同名旧单文件 JAR，避免索引里留重复的坏条目。
    // 同样按残缺名（比如「影视_」）和共享目录一起清。
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
    return <PluginSource>[source];
  }

  /// 链接导入：先按扩展名判断，不对时按魔数判断（PK 是 zip、MZ 是 dll）。
  /// MZ 的 dll 是桌面版插件格式，手机上装不了，直接报人话错。
  Future<List<PluginSource>> installFromUrl(String url,
      {String? typeOverride}) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) throw Exception('链接无效：$url');
    late final List<int> bytes;
    try {
      final resp = await http
          .get(uri)
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('下载失败（${resp.statusCode}）');
      }
      bytes = resp.bodyBytes;
    } on Exception catch (e) {
      throw Exception('下载插件失败：$e');
    }
    if (bytes.length > maxZipBytes) {
      throw Exception('插件包太大了（超过 32MB），请检查链接');
    }
    final lowerPath = uri.path.toLowerCase();
    String? kind;
    if (lowerPath.endsWith('.zip')) {
      kind = 'zip';
    } else if (lowerPath.endsWith('.jar')) {
      kind = 'jar';
    } else if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      // PK：zip。
      kind = 'zip';
    } else if (bytes.length >= 2 && bytes[0] == 0x4D && bytes[1] == 0x5A) {
      // MZ：dll（桌面版插件格式）。
      throw Exception('这个链接是 DLL 插件（桌面版格式），手机上装不了，'
          '请找 ZIP 或 JAR 格式的插件包');
    }
    if (kind == null) {
      throw Exception('这个链接不是 ZIP / JAR 插件包，请检查链接');
    }
    final tmpFile = File(p.join((await pluginsRoot()).path,
        '.dl_${const Uuid().v4()}.${kind == 'zip' ? 'zip' : 'jar'}'));
    try {
      await tmpFile.writeAsBytes(bytes);
      if (kind == 'zip') {
        return installZip(tmpFile.path, typeOverride: typeOverride);
      }
      return installJar(tmpFile.path, typeOverride: typeOverride);
    } finally {
      try {
        if (await tmpFile.exists()) await tmpFile.delete();
      } catch (_) {}
    }
  }

  /// 原生报错截短：去掉 PlatformException(XXX, ... , null, null) 的外壳，
  /// 只留中间的原因，超 160 字截断（报给用户看的，别贴整段堆栈）。
  String _shortCause(String raw) {
    var s = raw.trim();
    const head = 'PlatformException(';
    if (s.startsWith(head)) {
      final comma = s.indexOf(', ');
      if (comma > 0) s = s.substring(comma + 2);
    }
    if (s.endsWith(', null, null)')) {
      s = s.substring(0, s.length - ', null, null)'.length);
    }
    if (s.length > 160) s = '${s.substring(0, 160)}…';
    return s;
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
  /// 每个仓储实例只跑一次；扫不到入口类的原样保留，不动用户的数据。
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
      // 旧包也可能没设只读 / 有旧 odex 缓存：先设只读、清缓存，再扫描，
      // 不然自愈和重导一样扫不出来。
      await TingShuBridge.makeReadOnly(jarPath);
      await TingShuBridge.clearJarCache(jarPath);
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
      final orderBase = _nextOrderBase(all);
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
          format: 'tingshu',
          version: '1.0.0',
          description: desc,
          url: url.isEmpty ? null : url,
          entry: entries.first,
          entryClass: entries.first,
          jarPath: jarPath,
          sourceIndex: index,
          group: baseName,
          pluginId: '_jar_$sig',
          order: orderBase + index * 10,
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

  // ---------------------------------------------------------------- 源管理

  /// 按插件分组折叠：一个插件包一组，组内源按 order 排。
  /// 分组键是 pluginId（没有时用源自己的 id）。
  List<PluginGroup> pluginGroups(List<PluginSource> all) {
    final map = <String, List<PluginSource>>{};
    for (final s in all) {
      final key = s.pluginId ?? s.id;
      map.putIfAbsent(key, () => <PluginSource>[]).add(s);
    }
    final groups = <PluginGroup>[];
    map.forEach((key, sources) {
      sources.sort((a, b) {
        final c = a.order.compareTo(b.order);
        if (c != 0) return c;
        return a.name.compareTo(b.name);
      });
      final name = sources.first.group.isNotEmpty
          ? sources.first.group
          : key;
      groups.add(PluginGroup(pluginId: key, name: name, sources: sources));
    });
    groups.sort((a, b) => a.sources.first.order
        .compareTo(b.sources.first.order));
    return groups;
  }

  /// 删除一个源。如果它是所在插件包的最后一个源，插件目录、
  /// 缓存和配置一起清掉；JAR 包的 odex 缓存也清掉。
  /// 注意：删一个源即删整个插件时，调 [removePlugin]。
  Future<void> remove(String id) async {
    final all = await loadAll();
    final target = all.where((e) => e.id == id).toList();
    all.removeWhere((e) => e.id == id);
    await _saveIndex(all);
    if (target.isEmpty) return;
    await _cleanupRemoved(target, all);
    appLogger.info('已移除源', detail: id);
  }

  /// 删除整个插件包：包下所有源、目录、缓存、配置一起清掉。
  /// [pluginId] 是分组键（pluginId，没有时是单个源的 id）。
  Future<void> removePlugin(String pluginId) async {
    final all = await loadAll();
    final target =
        all.where((e) => (e.pluginId ?? e.id) == pluginId).toList();
    if (target.isEmpty) return;
    all.removeWhere((e) => (e.pluginId ?? e.id) == pluginId);
    await _saveIndex(all);
    await _cleanupRemoved(target, all);
    appLogger.info('已移除插件包', detail: '$pluginId（${target.length} 个源）');
  }

  Future<void> _cleanupRemoved(
      List<PluginSource> removed, List<PluginSource> remaining) async {
    final configRepo = _configRepo;
    for (final s in removed) {
      if (configRepo != null) {
        try {
          await configRepo.clear(s.id);
        } catch (_) {}
      }
      // JAR 的 odex 缓存：没有别的源共用这份 JAR 才清。
      final jarPath = s.jarPath;
      if (jarPath != null && jarPath.isNotEmpty) {
        final stillUsed =
            remaining.any((e) => e.jarPath == jarPath);
        if (!stillUsed) {
          try {
            await TingShuBridge.clearJarCache(jarPath);
          } catch (_) {}
          final dir = Directory(p.dirname(jarPath));
          if (await dir.exists()) {
            try {
              await dir.delete(recursive: true);
            } catch (_) {}
          }
        }
      }
    }
    // 插件目录：组里没有源在用了才删。
    final pluginIds = removed
        .map((e) => e.pluginId ?? e.id)
        .toSet();
    for (final pid in pluginIds) {
      final stillUsed =
          remaining.any((e) => (e.pluginId ?? e.id) == pid);
      if (stillUsed) continue;
      final dir = Directory(p.join((await pluginsRoot()).path, pid));
      if (await dir.exists()) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
      // 单源旧写法还可能留着按源 id 建的目录。
      for (final s in removed) {
        if ((s.pluginId ?? s.id) != pid) continue;
        final d = Directory(await sourceDirPath(s.id));
        if (await d.exists() && d.path != dir.path) {
          try {
            await d.delete(recursive: true);
          } catch (_) {}
        }
      }
    }
  }

  /// 启用 / 停用一个源（开关关掉就是停用，不删除；写回索引）。
  Future<void> setEnabled(String id, bool enabled) async {
    final all = await loadAll();
    for (var i = 0; i < all.length; i++) {
      if (all[i].id == id) all[i].enabled = enabled;
    }
    await _saveIndex(all);
  }

  /// 整包一键启用 / 停用（包内任一源启用时整包开关显示开启，见 PluginGroup）。
  Future<void> setPluginEnabled(String pluginId, bool enabled) async {
    final all = await loadAll();
    for (var i = 0; i < all.length; i++) {
      if ((all[i].pluginId ?? all[i].id) == pluginId) {
        all[i].enabled = enabled;
      }
    }
    await _saveIndex(all);
  }

  /// 上移一位：和上一个源交换 order。已经是第一个时不动。
  Future<void> moveUp(String id) async {
    final all = await loadAll();
    _normalizeOrders(all);
    final idx = all.indexWhere((e) => e.id == id);
    if (idx <= 0) return;
    final tmp = all[idx].order;
    all[idx] = all[idx].copyWith(order: all[idx - 1].order);
    all[idx - 1] = all[idx - 1].copyWith(order: tmp);
    await _saveIndex(all);
  }

  /// 下移一位：和下一个源交换 order。已经是最后一个时不动。
  Future<void> moveDown(String id) async {
    final all = await loadAll();
    _normalizeOrders(all);
    final idx = all.indexWhere((e) => e.id == id);
    if (idx < 0 || idx >= all.length - 1) return;
    final tmp = all[idx].order;
    all[idx] = all[idx].copyWith(order: all[idx + 1].order);
    all[idx + 1] = all[idx + 1].copyWith(order: tmp);
    await _saveIndex(all);
  }

  /// 把 order 理顺成 0、10、20……（旧条目 order 全是 0 时交换才有意义）。
  void _normalizeOrders(List<PluginSource> all) {
    all.sort((a, b) {
      final c = a.order.compareTo(b.order);
      if (c != 0) return c;
      return a.name.compareTo(b.name);
    });
    for (var i = 0; i < all.length; i++) {
      if (all[i].order != i * 10) {
        all[i] = all[i].copyWith(order: i * 10);
      }
    }
  }

  int _nextOrderBase(List<PluginSource> all) {
    var max = -10;
    for (final e in all) {
      if (e.order > max) max = e.order;
    }
    return max + 10;
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

  /// 改源类型（听书/视频，详情页手动改）。
  Future<void> changeType(String id, String type) async {
    final all = await loadAll();
    for (var i = 0; i < all.length; i++) {
      if (all[i].id == id) {
        all[i] = all[i].copyWith(type: _normalizeType(type));
        break;
      }
    }
    await _saveIndex(all);
  }

  /// 改 JAR 主类（详情页手动改，通用 JAR 用）。
  Future<void> setMainClass(String id, String mainClass) async {
    final all = await loadAll();
    for (var i = 0; i < all.length; i++) {
      if (all[i].id == id) {
        all[i] = all[i].copyWith(entry: mainClass);
        break;
      }
    }
    await _saveIndex(all);
  }

  String _normalizeType(String raw) {
    final t = raw.trim().toLowerCase();
    if (t == 'video' || t == '视频') return 'video';
    return 'audio';
  }

  // ---------------------------------------------------------------- 内部工具

  /// 解压 zip，带 zip-slip 防护（目标路径必须在解压目录内）。
  Future<void> _extract(Archive archive, String dest) async {
    final destAbs = Directory(dest).absolute.path;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      var rel = f.name.replaceAll('\\', '/');
      while (rel.startsWith('/')) {
        rel = rel.substring(1);
      }
      final outPath = p.normalize(p.join(destAbs, rel));
      if (!outPath.startsWith(destAbs)) {
        throw Exception('插件包里有非法路径：${f.name}');
      }
      final out = File(outPath);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(f.content as List<int>);
    }
  }

  /// ZIP 里只有一个顶层目录时去掉这一层（返回那个子目录，否则返回原目录）。
  Directory _stripSingleTopDir(Directory tmp) {
    try {
      final entries = tmp.listSync(followLinks: false);
      final visible =
          entries.where((e) => !p.basename(e.path).startsWith('.')).toList();
      if (visible.length == 1 && visible.first is Directory) {
        return visible.first as Directory;
      }
    } catch (_) {}
    return tmp;
  }

  /// 找 manifest.json：根目录优先，再逐层往下（最多 3 层）。
  /// 只找 1 层会把 `<包名>/<子目录>/manifest.json` 当成没有 manifest，
  /// 于是脚本路径全算错，最后报“没有注册任何源”。
  Future<File?> _findManifest(Directory dir) async {
    final direct = File(p.join(dir.path, 'manifest.json'));
    if (await direct.exists()) return direct;
    final queue = <MapEntry<Directory, int>>[MapEntry(dir, 0)];
    while (queue.isNotEmpty) {
      final cur = queue.removeAt(0);
      if (cur.value >= 3) continue;
      List<FileSystemEntity> entries;
      try {
        entries = cur.key.listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final e in entries) {
        if (e is! Directory) continue;
        final name = p.basename(e.path);
        if (name.startsWith('.') || name == '__MACOSX' || name == 'cache') {
          continue;
        }
        final inner = File(p.join(e.path, 'manifest.json'));
        if (await inner.exists()) return inner;
        queue.add(MapEntry(e, cur.value + 1));
      }
    }
    return null;
  }

  /// 读脚本样本（类型判断用）：入口脚本前 32KB，没有入口就取第一个 .js。
  Future<String> _readScriptSample(Directory dir, String entry) async {
    try {
      if (entry.isNotEmpty) {
        final f = File(p.join(dir.path, entry));
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          final take = bytes.length > 32768 ? bytes.sublist(0, 32768) : bytes;
          return utf8.decode(take, allowMalformed: true);
        }
      }
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File && e.path.toLowerCase().endsWith('.js')) {
          final bytes = await e.readAsBytes();
          final take = bytes.length > 32768 ? bytes.sublist(0, 32768) : bytes;
          return utf8.decode(take, allowMalformed: true);
        }
      }
    } catch (_) {}
    return '';
  }

  /// 从脚本内容 / 文件名 / dex 字符串里判断是听书还是视频。
  /// 关键词计分：视频词够多（>=3 且 >= 音频词 1.5 倍）判视频，
  /// 否则默认听书（听书类插件占多数）；判不准时用户可以在源详情里手动改。
  String _detectType(String text) {
    const videoWords = <String>[
      'm3u8',
      'video',
      '影视',
      '电影',
      '电视剧',
      '动漫',
      '综艺',
      'vod',
      'playurl',
      '视频',
    ];
    const audioWords = <String>[
      'mp3',
      '听书',
      '有声',
      '音色',
      '播客',
      'audio',
      '评书',
      '相声',
      '广播',
      '小说',
    ];
    final lower = text.toLowerCase();
    var v = 0;
    var a = 0;
    for (final w in videoWords) {
      if (lower.contains(w.toLowerCase())) v++;
    }
    for (final w in audioWords) {
      if (lower.contains(w.toLowerCase())) a++;
    }
    return (v >= 3 && v >= a * 1.5) ? 'video' : 'audio';
  }

  /// manifest 里声明的类型（capabilities 含 video 也算）。
  String? _guessType(
      Map<String, dynamic> manifest, Directory root) {
    final declared = _pickString(manifest, const <String>['type', '类型']);
    if (declared != null && declared.isNotEmpty) {
      return _normalizeType(declared);
    }
    final caps = manifest['capabilities'];
    if (caps is List) {
      final joined = caps.map((e) => '$e').join(' ').toLowerCase();
      if (joined.contains('video') || joined.contains('视频')) {
        return 'video';
      }
      if (joined.contains('audio') || joined.contains('听书')) {
        return 'audio';
      }
    }
    return null;
  }

  String? _pickString(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v != null && v is! Map && v is! List && '$v'.trim().isNotEmpty) {
        return '$v'.trim();
      }
    }
    return null;
  }

  /// 猜入口脚本：main.js / index.js / source.js 优先，否则第一个 .js。
  Future<String> _guessEntryScript(Directory dir) async {
    for (final name in const <String>[
      'main.js',
      'index.js',
      'source.js',
    ]) {
      final f = File(p.join(dir.path, name));
      if (await f.exists()) return name;
    }
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File && e.path.toLowerCase().endsWith('.js')) {
          return p.relative(e.path, from: dir.path).replaceAll('\\', '/');
        }
      }
    } catch (_) {}
    return '';
  }

  String _slug(String raw) {
    var s = raw
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    while (s.startsWith('_')) {
      s = s.substring(1);
    }
    while (s.endsWith('_')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.isEmpty) s = 'plugin';
    return s;
  }

  Future<int> _dirSize(Directory dir) async {
    var total = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
    } catch (_) {}
    return total;
  }
}
