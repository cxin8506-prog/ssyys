import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../../core/log/app_logger.dart';
import '../data/source_config_repository.dart';
import '../data/source_repository.dart';
import '../model/plugin_source.dart';
import 'plugin_engine.dart';

/// JAR 插件引擎（Android DexClassLoader）
///
/// 约定：JAR 内需含 classes.dex（dex 化），主类提供静态方法
/// search/detail/chapters/content，参数与返回值均为 JSON 字符串。
/// 方法名不匹配时按 [PluginMethods.aliases] 依次尝试。
class JarPluginEngine implements PluginEngine {
  static const MethodChannel _channel = MethodChannel('suishou/jar');

  final SourceRepository _repo;
  final SourceConfigRepository _configRepo;

  JarPluginEngine(this._repo, this._configRepo);

  PluginSource? _source;
  String? _jarPath;
  String? _mainClass;
  List<String> _classes = [];

  /// 已经成功接住配置的钩子方法名（避免每次都试三个）
  String? _configHook;

  @override
  String get format => 'jar';

  // 通用 JAR 源没有登录/搜索验证入口，返回空。
  @override
  Future<Map<String, dynamic>?> loginInfo() async => null;

  @override
  Future<Map<String, dynamic>?> verificationInfo(String keyword) async =>
      null;

  @override
  Future<void> attach(PluginSource source) async {
    _source = source;
    // 优先用源自己记的 jarPath（installJar 把 JAR 存在共享目录 _jar_<sig> 时
    // 就是这条路）；没有再回退到源目录下的 plugin.jar。两条路都找不到才报错。
    File? jar;
    final recorded = (source.jarPath ?? '').trim();
    if (recorded.isNotEmpty) {
      final f = File(recorded);
      if (await f.exists()) jar = f;
    }
    if (jar == null) {
      final dir = await _repo.sourceDirPath(source.id);
      final f = File('$dir/plugin.jar');
      if (await f.exists()) jar = f;
    }
    if (jar == null) throw Exception('JAR 文件不存在，请重新安装该源');
    _jarPath = jar.path;

    await _channel.invokeMethod<bool>('load', {'path': _jarPath});

    // 主类：优先使用 manifest/手动指定，其次按命名猜测
    _mainClass = (source.entry.isNotEmpty ? source.entry : null) ??
        await _guessMainClass();
    appLogger.info('JAR 源已加载',
        detail: '${source.name} class=$_mainClass jar=$_jarPath');

    // 把源自己声明的配置推给插件（插件若有 setConfig/initConfig 就会收到）
    await _pushConfig(source);
  }

  /// 把配置 JSON 推给 JAR 插件。约定方法名：setConfig / initConfig / applyConfig
  Future<void> _pushConfig(PluginSource s) async {
    final cls = _mainClass;
    final path = _jarPath;
    if (cls == null || cls.isEmpty || path == null) return;
    try {
      final cfg = await _configRepo.load(s.id, s.type);
      final map = _configRepo.buildRuntimeConfig(cfg);
      final payload = jsonEncode([jsonEncode(map)]);
      final hooks = _configHook != null
          ? [_configHook!]
          : const ['setConfig', 'initConfig', 'applyConfig'];
      for (final name in hooks) {
        try {
          await _channel.invokeMethod<String>('invoke', {
            'path': path,
            'className': cls,
            'method': name,
            'argsJson': payload,
          });
          _configHook = name;
          return;
        } catch (_) {
          // 这个钩子不存在，试下一个
        }
      }
    } catch (e) {
      appLogger.warning('JAR 配置注入失败', detail: '$e');
    }
  }

  /// 反射看主类有没有某个方法（用于判断源声明了哪些能力）
  @override
  Future<bool?> hasMethod(String method) async {
    final cls = _mainClass;
    final path = _jarPath;
    if (cls == null || cls.isEmpty || path == null) return null;
    try {
      final r = await _channel.invokeMethod<bool>('hasMethod', {
        'path': path,
        'className': cls,
        'names': PluginMethods.aliases[method] ?? [method],
      });
      return r;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<dynamic> invoke(String method, {Map<String, dynamic>? params}) async {
    final s = _source;
    if (s == null) throw Exception('未绑定源');
    final cls = _mainClass;
    if (cls == null || cls.isEmpty) {
      throw Exception('未能确定 JAR 主类，请在源详情里手动填写主类名');
    }
    final names = PluginMethods.aliases[method] ?? [method];
    final argsJson = jsonEncode(_argsFor(method, params ?? {}));

    // 用户在源详情里改过配置的话，这里同步一次
    await _pushConfig(s);

    Object? lastError;
    for (final name in names) {
      try {
        final raw = await _channel.invokeMethod<String>('invoke', {
          'path': _jarPath,
          'className': cls,
          'method': name,
          'argsJson': argsJson,
        });
        if (raw == null) continue;
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['ok'] == true) return decoded['data'];
        return decoded;
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception('JAR 调用失败：${PluginMethods.labels[method] ?? method}'
        '${lastError == null ? '' : '（$lastError）'}');
  }

  @override
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('unload');
    } catch (_) {}
    _source = null;
    _jarPath = null;
    _mainClass = null;
  }

  /// 列出 JAR 内的类（源详情页展示，便于手填主类）
  Future<List<String>> listClasses() async {
    final path = _jarPath;
    if (path == null) return [];
    try {
      final list =
          await _channel.invokeMethod<List<dynamic>>('listClasses', {'path': path});
      _classes = (list ?? []).map((e) => '$e').toList();
      return _classes;
    } catch (e) {
      appLogger.warning('JAR 类列表读取失败', detail: '$e');
      return [];
    }
  }

  Future<String?> _guessMainClass() async {
    final list = await listClasses();
    if (list.isEmpty) return null;
    const hints = ['Source', 'Plugin', 'Api', 'ApiImpl', 'BookSource', 'Main'];
    for (final h in hints) {
      for (final c in list) {
        if (c.toLowerCase().endsWith(h.toLowerCase())) return c;
      }
    }
    // 退而求其次：取第一个非内部类
    for (final c in list) {
      if (!c.contains('\$')) return c;
    }
    return list.first;
  }

  List<dynamic> _argsFor(String method, Map<String, dynamic> params) {
    switch (method) {
      case 'recommend':
        return [params['page'] ?? 1];
      case 'search':
        return [params['keyword'] ?? '', params['page'] ?? 1];
      case 'detail':
        return [params['url'] ?? ''];
      case 'chapters':
        return [params['url'] ?? params['bookUrl'] ?? ''];
      case 'content':
        return [params['url'] ?? params['chapterUrl'] ?? '', params['voiceId']];
      case 'lines':
      case 'voices':
        return [params['url'] ?? ''];
      case 'config':
      case 'categories':
        return [];
      case 'browse':
        return [params['category'] ?? '', params['page'] ?? 1];
      default:
        return [params];
    }
  }
}
