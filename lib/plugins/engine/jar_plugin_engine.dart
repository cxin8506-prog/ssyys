import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/log/app_logger.dart';
import '../../features/ua/ua_resolver.dart';
import '../data/source_config_repository.dart';
import '../data/source_repository.dart';
import '../model/plugin_source.dart';
import 'plugin_engine.dart';

/// 通用 JAR 插件引擎（单个主类 + 静态方法，Android DexClassLoader 反射调用）。
///
/// 约定：JAR 内含 classes.dex，主类提供静态方法 search / detail / chapters /
/// content 等，参数与返回值均为 JSON 字符串。方法名不匹配时按
/// [PluginMethods.aliases] 依次尝试。
///
/// 和「我的听书」格式的区别：这里调的是主类自己的静态方法，
/// 不是 SourceEntry.getSources() 拆出来的源；两个引擎不要混用。
class JarPluginEngine extends PluginEngine {
  static const MethodChannel _channel = MethodChannel('suishou/jar');

  final SourceRepository _repo;
  final SourceConfigRepository _configRepo;
  final UaResolver _uaResolver;

  JarPluginEngine(this._repo, this._configRepo, this._uaResolver);

  PluginSource? _source;
  String? _jarPath;
  String? _mainClass;

  /// 已经成功接住配置的钩子方法名（避免每次都试三个）。
  String? _configHook;

  /// 该 JAR 是否提供登录入口：null 表示还没探过，false 表示探过、确实没有。
  bool? _loginSupported;

  /// 登录入口缺失时给 UI 看的原因（loginInfo 返回 null 时用）。
  String? loginUnsupportedReason;

  @override
  String get format => 'jar';

  @override
  Future<void> attach(PluginSource source) async {
    _source = source;
    _loginSupported = null;
    loginUnsupportedReason = null;
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

    // 主类：优先使用源上记的，其次按命名猜测。
    _mainClass = (source.entry.isNotEmpty ? source.entry : null) ??
        await _guessMainClass();
    appLogger.info('JAR 源已加载',
        detail: '${source.name} class=$_mainClass jar=$_jarPath');

    // 把源自己声明的配置推给插件（插件若有 setConfig/initConfig 就会收到）。
    await _pushConfig(source);
  }

  /// 把配置 JSON 推给 JAR 插件。约定方法名：setConfig / initConfig / applyConfig。
  /// 运行时配置里含 lineId / voiceId / loginState / userAgent，
  /// 源每次调用前都能读到最新值。
  Future<void> _pushConfig(PluginSource s) async {
    final cls = _mainClass;
    final path = _jarPath;
    if (cls == null || cls.isEmpty || path == null) return;
    try {
      final cfg = await _configRepo.load(s.id, s.type);
      final map = _configRepo.buildRuntimeConfig(cfg);
      final ua = await _uaResolver.resolve(
        sourceId: s.id,
        sourceName: s.name,
        url: s.url,
        sourceConfigUa: map['userAgent']?.toString() ?? map['ua']?.toString(),
        desktop: false,
      );
      if (ua != null && ua.isNotEmpty) map['userAgent'] = ua;
      final payload = jsonEncode(<dynamic>[jsonEncode(map)]);
      final hooks = _configHook != null
          ? <String>[_configHook!]
          : const <String>['setConfig', 'initConfig', 'applyConfig'];
      for (final name in hooks) {
        try {
          await _channel.invokeMethod<String>('invoke', <String, dynamic>{
            'path': path,
            'className': cls,
            'method': name,
            'argsJson': payload,
          });
          _configHook = name;
          return;
        } catch (_) {
          // 这个钩子不存在，试下一个。
        }
      }
    } catch (e) {
      appLogger.warning('JAR 配置注入失败', detail: '$e');
    }
  }

  Future<String?> _guessMainClass() async {
    final path = _jarPath;
    if (path == null) return null;
    try {
      final names = await _channel.invokeMethod<List<dynamic>>(
          'listClasses', <String, dynamic>{'path': path});
      final classes = (names ?? <dynamic>[])
          .map((e) => '$e')
          .where((e) => !e.contains(r'$'))
          .toList();
      String? pick(bool Function(String) test) {
        for (final c in classes) {
          if (test(c)) return c;
        }
        return null;
      }

      return pick((c) => c.endsWith('.Main')) ??
          pick((c) => c.endsWith('SourceEntry')) ??
          pick((c) => c.endsWith('Plugin')) ??
          pick((c) => c.endsWith('Source')) ??
          (classes.isEmpty ? null : classes.first);
    } catch (_) {
      return null;
    }
  }

  /// 反射看主类有没有某个方法（用于判断源声明了哪些能力）。
  @override
  Future<bool?> hasMethod(String method) async {
    final cls = _mainClass;
    final path = _jarPath;
    if (cls == null || cls.isEmpty || path == null) return null;
    try {
      final r = await _channel.invokeMethod<bool>('hasMethod',
          <String, dynamic>{
            'path': path,
            'className': cls,
            'names': PluginMethods.aliases[method] ?? <String>[method],
          });
      return r;
    } catch (_) {
      return null;
    }
  }

  /// 反射调主类的一个方法。参数按 JSON 数组传，原生侧按目标类型转换；
  /// 参数个数对不上时原生侧会退回无参调用（见 MainActivity.invokeJar）。
  /// 返回值是原生包的 `{ok, data}` 里的 data（字符串/数字/布尔原样返回）。
  Future<dynamic> _invokeRaw(String method, List<dynamic> args) async {
    final cls = _mainClass;
    final path = _jarPath;
    if (cls == null || cls.isEmpty || path == null) {
      throw Exception('源还没准备好');
    }
    final raw = await _channel.invokeMethod<String>('invoke',
        <String, dynamic>{
          'path': path,
          'className': cls,
          'method': method,
          'argsJson': jsonEncode(args),
        });
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded.containsKey('data')) {
        return decoded['data'];
      }
      return decoded;
    } catch (_) {
      return raw;
    }
  }

  /// 按别名表依次试，直到某个方法名存在。都不存在就抛“不支持”。
  Future<dynamic> _invokeAliased(String method, List<dynamic> args) async {
    final names = PluginMethods.aliases[method] ?? <String>[method];
    Exception? last;
    for (final name in names) {
      try {
        final has = await _channel.invokeMethod<bool>('hasMethod',
            <String, dynamic>{
              'path': _jarPath,
              'className': _mainClass,
              'names': <String>[name],
            });
        if (has != true) continue;
        return await _invokeRaw(name, args);
      } catch (e) {
        last = Exception('$e');
      }
    }
    throw last ?? Exception('该源不支持${PluginMethods.labels[method] ?? method}');
  }

  @override
  Future<dynamic> invoke(String method,
      {Map<String, dynamic> params = const <String, dynamic>{}}) async {
    final source = _source;
    if (source == null) throw Exception('未绑定源');
    // 用户在源详情里改过配置的话，这里同步一次（lineId/voiceId 也会推进去）。
    await _pushConfig(source);
    switch (method) {
      case 'search':
        {
          final r = await _invokeAliased('search',
              <dynamic>[params['keyword'] ?? '', params['page'] ?? 1]);
          if (r is Map) {
            return <String, dynamic>{
              'books': _asList(r['books']),
              'totalPage': (r['totalPage'] as num?)?.toInt() ?? 0,
            };
          }
          return <String, dynamic>{
            'books': _asList(r),
            'totalPage': (params['page'] as num?)?.toInt() ?? 1,
          };
        }
      case 'categoryMenus':
        return _sstsLikeCategories(
            await _invokeAliased('categoryMenus', <dynamic>[]));
      case 'categoryPage':
        {
          final r = await _invokeAliased('categoryPage',
              <dynamic>[params['menu'] ?? params['url'] ?? '']);
          if (r is Map) {
            return <String, dynamic>{
              'books': _asList(r['books'] ?? r['list']),
              'nextUrl': '${r['nextUrl'] ?? ''}',
              'totalPage': (r['totalPage'] as num?)?.toInt() ?? 0,
            };
          }
          return <String, dynamic>{
            'books': _asList(r),
            'nextUrl': '',
            'totalPage': 0,
          };
        }
      case 'bookDetail':
      case 'detail':
        {
          final r = await _invokeAliased(
              'bookDetail', <dynamic>[params['url'] ?? '']);
          if (r is! Map) throw Exception('这个源没有返回详情');
          return <String, dynamic>{
            'cover': '${r['coverUrl'] ?? r['cover'] ?? ''}',
            'author': '${r['author'] ?? ''}',
            'artist': '${r['artist'] ?? ''}',
            'intro': '${r['intro'] ?? ''}',
            'chapters': _asList(r['episodes'] ?? r['chapters'])
                .map((e) => <String, dynamic>{
                      'name': '${e['title'] ?? e['name'] ?? ''}',
                      'url': '${e['url'] ?? ''}',
                    })
                .toList(),
          };
        }
      case 'chapters':
        {
          final r = await _invokeAliased(
              'chapters', <dynamic>[params['url'] ?? '']);
          final list = r is Map ? (r['episodes'] ?? r['chapters']) : r;
          return _asList(list)
              .map((e) => <String, dynamic>{
                    'name': '${e['title'] ?? e['name'] ?? ''}',
                    'url': '${e['url'] ?? ''}',
                  })
              .toList();
        }
      case 'content':
        {
          // lineId 必须传进源：第三个参数。源如果只认 (url, voiceId)，
          // 原生侧按目标方法参数个数转换，多传的参数会被忽略，不会炸。
          final r = await _invokeAliased('content', <dynamic>[
            params['url'] ?? params['chapterUrl'] ?? '',
            params['voiceId'] ?? '',
            params['lineId'] ?? '',
          ]);
          if (r is String) {
            return <String, dynamic>{
              'url': r,
              'headers': <String, String>{},
            };
          }
          if (r is Map) {
            final u = '${r['url'] ?? ''}';
            if (u.isEmpty) throw Exception('这个源没有解析出播放地址');
            final headers = <String, String>{};
            final rawHeaders = r['headers'];
            if (rawHeaders is Map) {
              rawHeaders.forEach((k, v) {
                if (v != null) headers['$k'] = '$v';
              });
            }
            return <String, dynamic>{'url': u, 'headers': headers};
          }
          throw Exception('这个源没有解析出播放地址');
        }
      case 'lines':
      case 'voices':
        {
          final r = await _invokeAliased(
              method, <dynamic>[params['url'] ?? '']);
          return _normalizeOptions(r);
        }
      case 'config':
        {
          final r = await _invokeAliased('config', <dynamic>[]);
          return r ?? const <dynamic>[];
        }
      case 'isCacheable':
        {
          try {
            final r =
                await _invokeAliased('isCacheable', <dynamic>[]);
            if (r is bool) return r;
            if (r is String) return r.toLowerCase() != 'false';
          } catch (_) {}
          return true;
        }
      case 'recommend':
        return const <Map<String, dynamic>>[];
      default:
        throw Exception('该源不支持${PluginMethods.labels[method] ?? method}');
    }
  }

  /// 登录入口：**真的去反射探**，不是写死 null。
  /// 主类有 getLoginUrl() 就返回 {url, desktop}；
  /// 没有这个方法，返回 null，并把原因记在 [loginUnsupportedReason] 里——
  /// 这就是“明确宣布该格式不支持登录”（这个 JAR 没有登录方法，
  /// 不是引擎没接）。
  @override
  Future<Map<String, dynamic>?> loginInfo() async {
    final cls = _mainClass;
    final path = _jarPath;
    if (cls == null || cls.isEmpty || path == null) return null;
    if (_loginSupported == false) return null;
    try {
      final has = await _channel.invokeMethod<bool>('hasMethod',
          <String, dynamic>{
            'path': path,
            'className': cls,
            'names': const <String>['getLoginUrl'],
          });
      if (has != true) {
        _loginSupported = false;
        loginUnsupportedReason = '这个 JAR 源没有提供登录入口（没有 getLoginUrl 方法）';
        appLogger.info('JAR 源不支持登录', detail: '${_source?.name}：无 getLoginUrl');
        return null;
      }
      final url = await _invokeRaw('getLoginUrl', <dynamic>[]);
      final u = '$url'.trim();
      if (u.isEmpty) return null;
      var desktop = false;
      try {
        final d = await _invokeRaw('isLoginDesktop', <dynamic>[]);
        desktop = d == true || '$d'.toLowerCase() == 'true';
      } catch (_) {}
      _loginSupported = true;
      return <String, dynamic>{'url': u, 'desktop': desktop};
    } catch (e) {
      appLogger.warning('JAR 登录入口探测失败', detail: '$e');
      return null;
    }
  }

  /// 搜索验证：同样先探 getSearchVerificationUrl(keyword)，没有就返回 null。
  @override
  Future<Map<String, dynamic>?> verificationInfo(String keyword) async {
    final cls = _mainClass;
    final path = _jarPath;
    if (cls == null || cls.isEmpty || path == null) return null;
    try {
      final has = await _channel.invokeMethod<bool>('hasMethod',
          <String, dynamic>{
            'path': path,
            'className': cls,
            'names': const <String>['getSearchVerificationUrl'],
          });
      if (has != true) return null;
      final url = await _invokeRaw(
          'getSearchVerificationUrl', <dynamic>[keyword]);
      final u = '$url'.trim();
      if (u.isEmpty) return null;
      return <String, dynamic>{
        'url': u,
        'ua': '',
        'delayMs': 0,
        'validated': false,
      };
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    final path = _jarPath;
    if (path != null) {
      try {
        await _channel.invokeMethod<bool>('unload', {'path': path});
      } catch (_) {}
    }
    _source = null;
    _jarPath = null;
    _mainClass = null;
  }

  List<Map<String, dynamic>> _asList(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }

  List<Map<String, String>> _sstsLikeCategories(dynamic raw) {
    if (raw is! List) return const <Map<String, String>>[];
    final out = <Map<String, String>>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final group = '${m['title'] ?? ''}';
      final tabs = m['tabs'];
      if (tabs is List) {
        for (final t in tabs) {
          if (t is! Map) continue;
          final name = '${t['title'] ?? ''}';
          final url = '${t['url'] ?? ''}';
          if (url.isEmpty) continue;
          out.add(<String, String>{
            'name': group.isEmpty ? name : '$group · $name',
            'url': url,
          });
        }
      } else {
        final name = '${m['title'] ?? m['name'] ?? ''}';
        final url = '${m['url'] ?? ''}';
        if (name.isNotEmpty && url.isNotEmpty) {
          out.add(<String, String>{'name': name, 'url': url});
        }
      }
    }
    return out;
  }

  /// 把源返回的线路/音色归一化成 [{id, name}]：只做归一化，不自己拼。
  List<Map<String, dynamic>> _normalizeOptions(dynamic raw) {
    var data = raw;
    for (var i = 0; i < 3; i++) {
      if (data is! String) break;
      final t = data.trim();
      if (t.isEmpty) return const <Map<String, dynamic>>[];
      if (!(t.startsWith('{') || t.startsWith('['))) {
        return <Map<String, dynamic>>[
          <String, dynamic>{'id': t, 'name': t},
        ];
      }
      try {
        data = jsonDecode(t);
      } catch (_) {
        return const <Map<String, dynamic>>[];
      }
    }
    if (data is Map) {
      for (final k in const <String>[
        'list',
        'data',
        'items',
        'voices',
        'lines',
        'options',
      ]) {
        if (data[k] is List) {
          data = data[k];
          break;
        }
      }
    }
    final out = <Map<String, dynamic>>[];
    if (data is List) {
      for (var i = 0; i < data.length; i++) {
        final e = data[i];
        if (e is Map) {
          final v = '${e['id'] ?? e['value'] ?? e['key'] ?? i}';
          final l =
              '${e['name'] ?? e['label'] ?? e['title'] ?? e['text'] ?? v}';
          out.add(<String, dynamic>{'id': v, 'name': l});
        } else if (e != null) {
          out.add(<String, dynamic>{'id': '$e', 'name': '$e'});
        }
      }
    }
    return out;
  }
}
