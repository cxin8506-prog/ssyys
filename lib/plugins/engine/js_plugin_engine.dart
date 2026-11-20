import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/log/app_logger.dart';
import '../data/source_config_repository.dart';
import '../data/source_repository.dart';
import '../data/web_session.dart';
import '../model/plugin_source.dart';
import 'plugin_engine.dart';
import 'ssts_runtime_js.dart';
import '../../features/ua/ua_resolver.dart';

/// JS 插件引擎（随身听书格式 + 旧式全局函数写法）。
///
/// 两种写法共用一个 QuickJS 运行时：
///
/// 1. 随身听书格式：ZIP = manifest.json + 脚本，manifest 的 scripts 数组按顺序
///    执行、共用全局作用域；脚本用 `registerSource({...})` 注册任意多个源。
///    一个插件（一个 QuickJS 会话）里多个源共用全局作用域，会话按键是插件 id。
/// 2. 旧式写法：入口脚本定义全局函数（search / bookDetail / audio …），
///    一个源一个会话。
///
/// 源方法全是同步的：`this.host.getJson(url)` 直接返回值。flutter_js 的宿主
/// 调用是异步的，所以用「挂起 + 重放」实现（见 ssts_runtime_js.dart）：
/// JS 抛 `__SSTS_SUSPEND__`，Dart 执行宿主操作、把结果写进 `__syncCache`、
/// 再从头重跑源方法，直到跑完或出错。
///
/// Cookie 是共享的：HTTP 请求先读系统 WebView 的 Cookie（登录页写进去的），
/// 响应里的 Set-Cookie 再写回 WebView——登录或通过人机验证之后，
/// 后续请求自动带上。
///
/// UA：三个引擎统一走 UaResolver。每次请求现解析（desktop 开关按请求走），
/// 换 UA 不用重建会话就生效；解析器返回 null（自动选择关了）时，
/// 手机请求用内置手机 UA、电脑请求用内置电脑 UA——
/// 绝不能像旧版那样关掉自动选择反而钉死在桌面 UA 上。
class JsPluginEngine implements PluginEngine {
  final SourceRepository _repo;
  final SourceConfigRepository _configRepo;
  final UaResolver _uaResolver;

  /// 单源超时（秒，默认 20，照随身听书 SearchTimeoutSeconds）。
  /// 设置页改了直接改这个字段，正在跑的引擎立刻生效，不用重启。
  int searchTimeoutSeconds;

  JsPluginEngine(this._repo, this._configRepo, this._uaResolver,
      {this.searchTimeoutSeconds = 20});

  final Map<String, _JsSession> _sessions = {};

  /// 每份源的偏好（getPref/setPref），内存一份，setPref 时落库。
  /// key 是源 id（随身听书规范：保存的 key 是“源ID.key”）。
  final Map<String, Map<String, String>> _prefsBySource = {};

  PluginSource? _bound;
  String? _boundKey;
  String? _boundSstsId;

  /// 源里调 host.toast() 时的回调（没接就只记日志）。
  void Function(String message)? onToast;

  /// 源里调 host.progress() 时的回调（多页章节进度，如 "3 / 20"，null 表示结束）。
  void Function(String? progress)? onProgress;

  @override
  String get format => 'js';

  // ---------------------------------------------------------- 绑定

  @override
  Future<void> attach(PluginSource source) async {
    if (source.sstsId != null && source.sstsId!.isNotEmpty) {
      await _attachSsts(source);
      return;
    }
    _bound = source;
    _boundKey = source.id;
    _boundSstsId = null;
    if (_sessions.containsKey(source.id)) return;

    final script = await _repo.readEntryScript(source);
    final uas = await _resolveUas(source);
    final cfg = await _configRepo.load(source.id, source.type);
    final cfgMap = _configRepo.buildRuntimeConfig(cfg);

    final rt = getJavascriptRuntime();
    final session = _JsSession(
      rt: rt,
      ua: uas.mobile,
      desktopUa: uas.desktop,
      cfg: cfgMap,
      uaResolver: _uaResolver,
      sourceId: source.id,
      sourceName: source.name,
      timeoutSeconds: searchTimeoutSeconds,
    );
    session.onToast = onToast;
    session.onProgress = onProgress;
    session.onGetPref = (k) async => _prefsBySource[source.id]?[k];
    session.onSetPref = (k, v) async {
      _prefsBySource.putIfAbsent(source.id, () => <String, String>{})[k] =
          v;
      try {
        final c = await _configRepo.load(source.id, source.type);
        c.extra['pref.$k'] = v;
        await _configRepo.save(c);
      } catch (_) {}
    };
    await _loadPrefs(source.id, source.type);
    session.bindBridge();
    session.eval(_bootstrapScript(uas.mobile, uas.desktop, cfgMap));
    session.eval(script, label: '${source.name}/entry');
    // 有些插件把配置挂在 config 变量上，统一暴露一次。
    session.eval(
        'if (typeof config === "undefined" && typeof source !== "undefined") { var config = source; }');
    _sessions[source.id] = session;
    appLogger.info('JS 源已加载', detail: '${source.name} entry=${source.entry}');
  }

  /// 随身听书格式：一个插件（一个 QuickJS 会话）里多个源共用全局作用域，
  /// 会话按键是插件 id，不是单个源 id。
  Future<void> _attachSsts(PluginSource source) async {
    _bound = source;
    _boundSstsId = source.sstsId;
    final key = source.pluginId ?? source.id;
    _boundKey = key;
    if (_sessions.containsKey(key)) return;

    final uas = await _resolveUas(source);
    final cfg = await _configRepo.load(source.id, source.type);
    final cfgMap = _configRepo.buildRuntimeConfig(cfg);

    final rt = getJavascriptRuntime();
    final session = _JsSession(
      rt: rt,
      ua: uas.mobile,
      desktopUa: uas.desktop,
      cfg: cfgMap,
      uaResolver: _uaResolver,
      sourceId: source.id,
      sourceName: source.name,
      timeoutSeconds: searchTimeoutSeconds,
    );
    session.isSsts = true;
    session.pluginId = key;
    session.onToast = onToast;
    session.onProgress = onProgress;
    try {
      session.cacheDir = p.join(await _repo.sourceDirPath(key), 'cache');
    } catch (_) {
      session.cacheDir = '';
    }
    session.onGetPref = (k) async => _prefsBySource[source.id]?[k];
    session.onSetPref = (k, v) async {
      _prefsBySource.putIfAbsent(source.id, () => <String, String>{})[k] =
          v;
      try {
        final c = await _configRepo.load(source.id, source.type);
        c.extra['pref.$k'] = v;
        await _configRepo.save(c);
      } catch (_) {}
    };
    await _loadPrefs(source.id, source.type);
    session.bindBridge();
    session.eval(_bootstrapScript(uas.mobile, uas.desktop, cfgMap));
    session.eval(buildSstsBootstrap(uas.mobile, cfgMap,
        desktopUa: uas.desktop), label: 'ssts 引导');

    final scripts = await _repo.readPluginScripts(source);
    for (var i = 0; i < scripts.length; i++) {
      session.eval(scripts[i].text, label: '${source.group}/${scripts[i].name}');
    }
    // 确认这个源真的注册上了（脚本可能在中途抛错导致只注册了一部分）。
    final ok = session.evalBool(
        'typeof globalThis.__sstsById[${jsonEncode(source.sstsId)}] === "object"');
    if (!ok) {
      try {
        session.rt.dispose();
      } catch (_) {}
      throw Exception('这个源没有注册成功（registerSource 未执行）');
    }
    try {
      final ids = session.evalJson('Object.keys(globalThis.__sstsById)');
      if (ids is List) {
        session.sstsIds = ids.map((e) => '$e').toSet();
      }
    } catch (_) {}
    _sessions[key] = session;
    appLogger.info('JS 源已加载',
        detail:
            '${source.name} ssts=${source.sstsId} 插件=$key 共 ${session.sstsIds.length} 个源');
  }

  Future<void> _loadPrefs(String sourceId, String type) async {
    try {
      final c = await _configRepo.load(sourceId, type);
      final map = _prefsBySource.putIfAbsent(sourceId, () => <String, String>{});
      c.extra.forEach((k, v) {
        if (k.startsWith('pref.')) map[k.substring(5)] = '$v';
      });
    } catch (_) {}
  }

  String _bootstrapScript(
      String? mobileUa, String? desktopUa, Map<String, dynamic> cfg) {
    return '${buildSstsBootstrap(mobileUa, cfg, desktopUa: desktopUa)}\n'
        'globalThis.host = globalThis.__sstsHost;\n'
        'globalThis.CONFIG = globalThis.__sstsHost.config;\n';
  }

  /// 解析当前源的手机/电脑两条 UA（走 UaResolver；返回 null 时用内置默认顶上）。
  Future<_Uas> _resolveUas(PluginSource source) async {
    String? configUa;
    try {
      final cfg = await _configRepo.load(source.id, source.type);
      final raw = cfg.valueOf('ua') ?? cfg.valueOf('userAgent');
      if (raw != null && '$raw'.isNotEmpty) configUa = '$raw';
    } catch (_) {}
    final mobile = await _uaResolver.resolve(
      sourceId: source.id,
      sourceName: source.name,
      url: source.url,
      sourceConfigUa: configUa,
      desktop: false,
    );
    final desktop = await _uaResolver.resolve(
      sourceId: source.id,
      sourceName: source.name,
      url: source.url,
      sourceConfigUa: configUa,
      desktop: true,
    );
    return _Uas(
      mobile: mobile ?? _defaultMobileUa,
      desktop: desktop ?? _defaultDesktopUa,
    );
  }

  /// 绑定当前源（attach 时记录，invoke 使用）。供 UI 在切源时显式调用。
  Future<void> bind(PluginSource source) async {
    await attach(source);
  }

  void unbind() {
    _bound = null;
    _boundKey = null;
    _boundSstsId = null;
  }

  /// 丢掉一个源/插件的会话（重装、删除插件后调，下次打开按新脚本重新加载，
  /// 不然内存里的旧脚本还会继续用）。参数可以是源 id，也可以是插件 id。
  void dropSession(String sourceIdOrPluginId) {
    final session = _sessions.remove(sourceIdOrPluginId);
    if (session != null) {
      try {
        session.rt.dispose();
      } catch (_) {}
    }
    if (_boundKey == sourceIdOrPluginId) unbind();
  }

  @override
  Future<void> dispose() async {
    for (final s in _sessions.values) {
      try {
        s.rt.dispose();
      } catch (_) {}
    }
    _sessions.clear();
    unbind();
  }

  _JsSession? _sessionForBound() {
    if (_boundKey == null) return null;
    return _sessions[_boundKey];
  }

  // ---------------------------------------------------------- 能力判断

  @override
  Future<bool?> hasMethod(String method) async {
    final source = _bound;
    if (source == null) return null;
    final session = _sessionForBound();
    if (session == null) return null;
    if (_boundSstsId != null && _boundSstsId!.isNotEmpty) {
      return _hasSstsMethod(session, _boundSstsId!, method);
    }
    final names = PluginMethods.aliases[method] ?? <String>[method];
    try {
      final r = session.rt.evaluate(
          '${jsonEncode(names)}.some(function(n){ return typeof globalThis[n] === "function"; })');
      if (r.isError) return null;
      return r.stringResult.trim().toLowerCase() == 'true';
    } catch (_) {
      return null;
    }
  }

  bool? _hasSstsMethod(_JsSession session, String sstsId, String method) {
    switch (method) {
      case 'recommend':
        return false;
      case 'content':
      case 'isCacheable':
        return true;
      case 'search':
        return session.evalBool(_sstsFnCheck(sstsId, 'search'));
      case 'categoryMenus':
      case 'categoryPage':
        return session.evalBool(_sstsFnCheck(sstsId, 'categoryMenus'));
      case 'bookDetail':
      case 'chapters':
        return session.evalBool(_sstsFnCheck(sstsId, 'bookDetail'));
      case 'lines':
        return session.evalBool(
            'typeof (globalThis.__sstsById[${jsonEncode(sstsId)}] || {}).lines !== "undefined" || '
            'typeof (globalThis.__sstsById[${jsonEncode(sstsId)}] || {}).lineList !== "undefined" || '
            'typeof (globalThis.__sstsById[${jsonEncode(sstsId)}] || {}).getLines !== "undefined"');
      case 'voices':
        return session.evalBool(
            'typeof (globalThis.__sstsById[${jsonEncode(sstsId)}] || {}).voices !== "undefined" || '
            'typeof (globalThis.__sstsById[${jsonEncode(sstsId)}] || {}).voiceList !== "undefined" || '
            'typeof (globalThis.__sstsById[${jsonEncode(sstsId)}] || {}).getVoices !== "undefined"');
      case 'config':
        return session.evalBool(
            'Array.isArray((globalThis.__sstsById[${jsonEncode(sstsId)}] || {}).config)');
      default:
        return false;
    }
  }

  String _sstsFnCheck(String sstsId, String fn) =>
      'typeof (globalThis.__sstsById[${jsonEncode(sstsId)}] || {})[${jsonEncode(fn)}] === "function"';

  // ---------------------------------------------------------- 调用

  @override
  Future<dynamic> invoke(String method,
      {Map<String, dynamic> params = const <String, dynamic>{}}) async {
    final source = _bound;
    if (source == null) throw Exception('未绑定源');
    final session = _sessionForBound();
    if (session == null) throw Exception('源未加载：${source.name}');
    // 每次调用前重新注入配置：用户在源详情里改了值不用重新加载脚本。
    // lineId / voiceId 也在这里推进 host.config，源读 host.config 能看到。
    try {
      final cfg = await _configRepo.load(source.id, source.type);
      if (params['lineId'] != null && '${params['lineId']}'.isNotEmpty) {
        cfg.setValue('lineId', params['lineId']);
      }
      if (params['voiceId'] != null && '${params['voiceId']}'.isNotEmpty) {
        cfg.setValue('voiceId', params['voiceId']);
      }
      session.applyConfig(_configRepo.buildRuntimeConfig(cfg));
    } catch (_) {}
    if (_boundSstsId != null && _boundSstsId!.isNotEmpty) {
      return _invokeSsts(session, _boundSstsId!, method, params);
    }
    return _invokeLegacy(session, method, params);
  }

  Future<dynamic> _invokeSsts(_JsSession session, String sstsId,
      String method, Map<String, dynamic> params) async {
    switch (method) {
      case 'recommend':
        // 随身听书没有首页推荐位，返回空，界面会显示搜索入口。
        return const <Map<String, dynamic>>[];
      case 'search':
        {
          final r = await session.evalSstsMethod(sstsId, 'search',
              <dynamic>[params['keyword'] ?? '', params['page'] ?? 1]);
          if (r is Map) {
            return <String, dynamic>{
              'books': _asList(r['books']),
              'totalPage': (r['totalPage'] as num?)?.toInt() ?? 0,
            };
          }
          if (r is List) {
            // 有的源直接返回书列表，不带总页数：当页就是最后一页已知的页。
            return <String, dynamic>{
              'books': _asList(r),
              'totalPage': (params['page'] as num?)?.toInt() ?? 1,
            };
          }
          return <String, dynamic>{
            'books': const <Map<String, dynamic>>[],
            'totalPage': 0,
          };
        }
      case 'categoryMenus':
        {
          final r =
              await session.evalSstsMethod(sstsId, 'categoryMenus', <dynamic>[]);
          return _sstsCategories(r);
        }
      case 'categoryPage':
        {
          final r = await session.evalSstsMethod(sstsId, 'categoryPage',
              <dynamic>[params['menu'] ?? params['url'] ?? '']);
          if (r is! Map) {
            return <String, dynamic>{
              'books': const <Map<String, dynamic>>[],
              'nextUrl': '',
              'totalPage': 0,
            };
          }
          return <String, dynamic>{
            'books': _asList(r['books']),
            'nextUrl': '${r['nextUrl'] ?? ''}',
            'totalPage': (r['totalPage'] as num?)?.toInt() ?? 0,
          };
        }
      case 'bookDetail':
      case 'detail':
        {
          final r = await session.evalSstsMethod(
              sstsId, 'bookDetail', <dynamic>[params['url'] ?? '', false, false]);
          if (r is! Map) throw Exception('这个源没有返回详情');
          return <String, dynamic>{
            'cover': '${r['coverUrl'] ?? ''}',
            'author': '${r['author'] ?? ''}',
            'artist': '${r['artist'] ?? ''}',
            'intro': '${r['intro'] ?? ''}',
            'chapters': const <Map<String, dynamic>>[],
          };
        }
      case 'chapters':
        {
          final r = await session.evalSstsMethod(
              sstsId, 'bookDetail', <dynamic>[params['url'] ?? '', true, true]);
          if (r is! Map) return const <Map<String, dynamic>>[];
          return _asList(r['episodes']).map((e) {
            return <String, dynamic>{
              'name': '${e['title'] ?? e['name'] ?? ''}',
              'url': '${e['url'] ?? ''}',
            };
          }).toList();
        }
      case 'content':
        {
          final url = '${params['url'] ?? params['chapterUrl'] ?? ''}';
          final lineId = '${params['lineId'] ?? ''}';
          final voiceId = '${params['voiceId'] ?? ''}';
          final hasAudio = session.evalBool(_sstsFnCheck(sstsId, 'audio'));
          if (!hasAudio) {
            return <String, dynamic>{
              'url': url,
              'headers': <String, String>{},
            };
          }
          // lineId / voiceId 一起传进源：随身听书规范的 audio(url) 只定义了一个
          // 参数，JS 里多传的参数会被忽略；源如果要按线路解析，
          // 可以读 arguments[1]，也可以读 host.config.lineId（invoke 里已推进去）。
          final r = await session.evalSstsMethod(
              sstsId, 'audio', <dynamic>[url, lineId, voiceId]);
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
        return _sstsOptions(session, sstsId, 'lines',
            url: '${params['url'] ?? ''}');
      case 'voices':
        return _sstsOptions(session, sstsId, 'voices',
            url: '${params['url'] ?? ''}');
      case 'config':
        {
          final raw = session.evalJson(
              'JSON.stringify((globalThis.__sstsById[${jsonEncode(sstsId)}] || {}).config || [])');
          return raw ?? const <dynamic>[];
        }
      case 'isCacheable':
        return true;
      default:
        throw Exception('该源不支持${PluginMethods.labels[method] ?? method}');
    }
  }

  /// 随身听书规范里没有 lines / voices 方法，所以这里是“探”不是“写死”：
  /// 先看源对象上有没有 lines/lineList/getLines/videoLines（函数或数组），
  /// 有就调它/读它并归一化；源没提供就返回空——空是探出来的结果，
  /// 不是写死的占位。
  Future<List<Map<String, dynamic>>> _sstsOptions(
      _JsSession session, String sstsId, String kind,
      {String url = ''}) async {
    final names = kind == 'lines'
        ? const <String>['lines', 'lineList', 'getLines', 'videoLines']
        : const <String>['voices', 'voiceList', 'getVoices', 'tones'];
    for (final name in names) {
      try {
        final isFn = session.evalBool(
            'typeof (globalThis.__sstsById[${jsonEncode(sstsId)}] || {})[${jsonEncode(name)}] === "function"');
        if (isFn) {
          final r = await session.evalSstsMethod(
              sstsId, name, <dynamic>[url]);
          final out = _normalizeOptions(r);
          if (out.isNotEmpty) return out;
          continue;
        }
        final raw = session.evalJson(
            'JSON.stringify((globalThis.__sstsById[${jsonEncode(sstsId)}] || {})[${jsonEncode(name)}] || null)');
        final out = _normalizeOptions(raw);
        if (out.isNotEmpty) return out;
      } catch (_) {}
    }
    return const <Map<String, dynamic>>[];
  }

  Future<dynamic> _invokeLegacy(
      _JsSession session, String method, Map<String, dynamic> params) async {
    final names = PluginMethods.aliases[method] ?? <String>[method];
    // 逐个试别名：第一个存在的全局函数就是这个源用的名字。
    String? found;
    for (final n in names) {
      try {
        final r = session.rt.evaluate(
            'typeof globalThis[${jsonEncode(n)}] === "function"');
        if (!r.isError &&
            r.stringResult.trim().toLowerCase() == 'true') {
          found = n;
          break;
        }
      } catch (_) {}
    }
    if (found == null) {
      if (method == 'recommend') return const <Map<String, dynamic>>[];
      if (method == 'lines' || method == 'voices') {
        return const <Map<String, dynamic>>[];
      }
      if (method == 'isCacheable') return true;
      throw Exception('该源不支持${PluginMethods.labels[method] ?? method}');
    }
    final args = _argsFor(method, params);
    final data = await session.evalLegacyMethod(found, args);
    return _shapeLegacyResult(method, data, params);
  }

  /// 旧式全局函数的参数表。content 必须带 lineId（第三个参数），
  /// 否则切线只是重复调同一个地址。
  List<dynamic> _argsFor(String method, Map<String, dynamic> params) {
    switch (method) {
      case 'search':
        return <dynamic>[params['keyword'] ?? '', params['page'] ?? 1];
      case 'categoryPage':
        return <dynamic>[params['menu'] ?? params['url'] ?? ''];
      case 'bookDetail':
      case 'detail':
      case 'chapters':
        return <dynamic>[params['url'] ?? ''];
      case 'content':
        return <dynamic>[
          params['url'] ?? params['chapterUrl'] ?? '',
          params['voiceId'] ?? '',
          params['lineId'] ?? '',
        ];
      case 'lines':
      case 'voices':
        return <dynamic>[params['url'] ?? ''];
      default:
        return <dynamic>[];
    }
  }

  dynamic _shapeLegacyResult(
      String method, dynamic data, Map<String, dynamic> params) {
    switch (method) {
      case 'search':
        if (data is Map) {
          return <String, dynamic>{
            'books': _asList(data['books']),
            'totalPage': (data['totalPage'] as num?)?.toInt() ?? 0,
          };
        }
        return <String, dynamic>{
          'books': _asList(data),
          'totalPage': (params['page'] as num?)?.toInt() ?? 1,
        };
      case 'categoryPage':
        if (data is Map) {
          return <String, dynamic>{
            'books': _asList(data['books'] ?? data['list']),
            'nextUrl': '${data['nextUrl'] ?? ''}',
            'totalPage': (data['totalPage'] as num?)?.toInt() ?? 0,
          };
        }
        return <String, dynamic>{
          'books': _asList(data),
          'nextUrl': '',
          'totalPage': 0,
        };
      case 'categoryMenus':
        return _sstsCategories(data);
      case 'bookDetail':
      case 'detail':
        if (data is! Map) throw Exception('这个源没有返回详情');
        return <String, dynamic>{
          'cover': '${data['coverUrl'] ?? data['cover'] ?? ''}',
          'author': '${data['author'] ?? ''}',
          'artist': '${data['artist'] ?? ''}',
          'intro': '${data['intro'] ?? ''}',
          'chapters': _asList(data['episodes'] ?? data['chapters'])
              .map((e) => <String, dynamic>{
                    'name': '${e['title'] ?? e['name'] ?? ''}',
                    'url': '${e['url'] ?? ''}',
                  })
              .toList(),
        };
      case 'chapters':
        return _asList(data is Map
                ? (data['episodes'] ?? data['chapters'])
                : data)
            .map((e) => <String, dynamic>{
                  'name': '${e['title'] ?? e['name'] ?? ''}',
                  'url': '${e['url'] ?? ''}',
                })
            .toList();
      case 'content':
        if (data is String) {
          return <String, dynamic>{
            'url': data,
            'headers': <String, String>{},
          };
        }
        if (data is Map) {
          final u = '${data['url'] ?? ''}';
          if (u.isEmpty) throw Exception('这个源没有解析出播放地址');
          final headers = <String, String>{};
          final rawHeaders = data['headers'];
          if (rawHeaders is Map) {
            rawHeaders.forEach((k, v) {
              if (v != null) headers['$k'] = '$v';
            });
          }
          return <String, dynamic>{'url': u, 'headers': headers};
        }
        throw Exception('这个源没有解析出播放地址');
      case 'lines':
      case 'voices':
        return _normalizeOptions(data);
      case 'config':
        return data ?? const <dynamic>[];
      default:
        return data;
    }
  }

  // ---------------------------------------------------------- 登录 / 验证

  /// 随身听书登录入口：loginUrl / loginDesktop，直接取注册信息，不跑脚本。
  @override
  Future<Map<String, dynamic>?> loginInfo() async {
    final source = _bound;
    final session = _sessionForBound();
    if (source == null || session == null) return null;
    if (_boundSstsId != null && _boundSstsId!.isNotEmpty) {
      try {
        final raw = session.evalJson(
            'JSON.stringify({url: (globalThis.__sstsById[${jsonEncode(_boundSstsId)}] || {}).loginUrl || "", desktop: !!(globalThis.__sstsById[${jsonEncode(_boundSstsId)}] || {}).loginDesktop})');
        if (raw is Map) {
          final url = '${raw['url'] ?? ''}'.trim();
          if (url.isEmpty) return null;
          return <String, dynamic>{
            'url': url,
            'desktop': raw['desktop'] == true,
          };
        }
      } catch (_) {}
      return null;
    }
    // 旧式写法：全局 loginUrl 字符串。
    try {
      final raw = session.evalJson(
          'JSON.stringify(typeof globalThis.loginUrl === "string" ? globalThis.loginUrl : "")');
      final url = '$raw'.trim();
      if (url.isEmpty) return null;
      return <String, dynamic>{'url': url, 'desktop': false};
    } catch (_) {}
    return null;
  }

  /// 随身听书搜索验证：searchVerificationUrl(keywords)，只在需要时调用。
  @override
  Future<Map<String, dynamic>?> verificationInfo(String keyword) async {
    final source = _bound;
    final session = _sessionForBound();
    if (source == null || session == null) return null;
    if (_boundSstsId == null || _boundSstsId!.isEmpty) return null;
    try {
      final has =
          session.evalBool(_sstsFnCheck(_boundSstsId!, 'searchVerificationUrl'));
      if (!has) return null;
      final url = await session.evalSstsMethod(
          _boundSstsId!, 'searchVerificationUrl', <dynamic>[keyword]);
      final u = '$url'.trim();
      if (u.isEmpty) return null;
      var delayMs = 0;
      try {
        final rawDelay = session.evalJson(
            'JSON.stringify((globalThis.__sstsById[${jsonEncode(_boundSstsId)}] || {}).searchDelaySeconds || 0)');
        delayMs = ((rawDelay as num?)?.toInt() ?? 0) * 1000;
      } catch (_) {}
      return <String, dynamic>{
        'url': u,
        'ua': '',
        'delayMs': delayMs,
        'validated': false,
      };
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------- 小工具

  List<Map<String, dynamic>> _sstsCategories(dynamic raw) {
    if (raw is! List) return const <Map<String, String>>[];
    final out = <Map<String, String>>[];
    for (final m in raw) {
      if (m is! Map) continue;
      final group = '${m['title'] ?? ''}';
      final tabs = m['tabs'];
      if (tabs is! List) continue;
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
    }
    return out;
  }

  List<Map<String, dynamic>> _asList(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
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

class _Uas {
  final String mobile;
  final String desktop;
  const _Uas({required this.mobile, required this.desktop});
}

/// UaResolver 返回 null（自动选择关了）时顶上的内置默认。
/// 注意：手机请求用手机默认、电脑请求用电脑默认，不要交叉。
const String _defaultMobileUa =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
const String _defaultDesktopUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/// QuickJS 运行时可用性自检（装包失败排查用）。
Future<bool> jsEngineAvailable() async {
  try {
    final rt = getJavascriptRuntime();
    final r = rt.evaluate('1+1');
    final ok = !r.isError && r.stringResult.trim() == '2';
    try {
      rt.dispose();
    } catch (_) {}
    return ok;
  } catch (_) {
    return false;
  }
}

/// 宿主调用失败（HTTP 状态等），挂起重放时要原样抛回脚本，脚本可以读 e.status。
class _SstsHostError implements Exception {
  final String message;
  final int? status;
  _SstsHostError(this.message, {this.status});
  @override
  String toString() => message;
}

/// 单个源的 JS 运行时会话。
class _JsSession {
  final JavascriptRuntime rt;
  final String? ua;
  final String? desktopUa;
  Map<String, dynamic> cfg;
  final UaResolver uaResolver;
  final String sourceId;
  final String sourceName;
  final int timeoutSeconds;

  /// 随身听书插件：会话按键是插件 id，一个会话带多个源。
  bool isSsts = false;
  String? pluginId;
  Set<String> sstsIds = <String>{};
  String cacheDir = '';

  /// 源偏好读写（引擎在 attach 时接上，落库在源配置里）。
  Future<String?> Function(String key)? onGetPref;
  Future<void> Function(String key, String value)? onSetPref;

  void Function(String message)? onToast;
  void Function(String? progress)? onProgress;

  final WebSession _web = WebSession();

  _JsSession({
    required this.rt,
    required this.ua,
    required this.desktopUa,
    required this.cfg,
    required this.uaResolver,
    required this.sourceId,
    required this.sourceName,
    this.timeoutSeconds = 20,
  });

  /// 重新注入配置：用户在源详情里改完立刻生效。
  void applyConfig(Map<String, dynamic> next) {
    cfg = next;
    try {
      rt.evaluate(
          '(function() { var c = ${jsonEncode(next)}; '
          'if (typeof globalThis.__sstsHost !== "undefined") { globalThis.__sstsHost.config = c; } '
          'if (typeof host !== "undefined") { host.config = c; } '
          'globalThis.CONFIG = c; })();');
    } catch (_) {}
  }

  void bindBridge() {
    rt.onMessage('__host_call', (dynamic args) {
      _handle(args);
    });
  }

  /// 处理 JS 侧发来的异步消息（log / toast / progress），不用等结果。
  Future<void> _handle(dynamic args) async {
    try {
      final raw = args is String ? args : jsonEncode(args);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final method = '${decoded['method'] ?? ''}';
      final data = decoded['data'];
      switch (method) {
        case 'log':
          appLogger.info('JS: $data');
          break;
        case 'toast':
          final msg = '$data';
          if (onToast != null) {
            onToast!(msg);
          } else {
            appLogger.info('JS 提示：$msg');
          }
          break;
        case 'progress':
          if (onProgress != null) {
            onProgress!(data == null ? null : '$data');
          }
          break;
      }
    } catch (_) {}
  }

  void eval(String code, {String? label}) {
    final r = rt.evaluate(code);
    if (r.isError) {
      appLogger.warning(
          'JS 脚本执行出错${label == null ? '' : '（$label）'}', detail: r.stringResult);
    }
  }

  bool evalBool(String code) {
    try {
      final r = rt.evaluate(code);
      if (r.isError) return false;
      return r.stringResult.trim().toLowerCase() == 'true';
    } catch (_) {
      return false;
    }
  }

  dynamic evalJson(String code) {
    final r = rt.evaluate(code);
    if (r.isError) return null;
    return _unwrap(r.stringResult);
  }

  /// 调一个随身听书源方法。挂起就执行宿主操作、写缓存、从头重跑，
  /// 直到方法跑完或出错。重放次数有上限，防止不确定脚本死循环。
  Future<dynamic> evalSstsMethod(
      String sstsId, String jsMethod, List<dynamic> args) async {
    final code =
        'globalThis.__sstsCall(${jsonEncode(sstsId)}, ${jsonEncode(jsMethod)}, ${jsonEncode(args)})';
    return _runSuspendable(code);
  }

  /// 调一个旧式全局函数，同样走挂起重放（函数里也可能调 host 同步方法）。
  Future<dynamic> evalLegacyMethod(String fnName, List<dynamic> args) async {
    final code = '(function(){ '
        'try { '
        'var fn = globalThis[${jsonEncode(fnName)}]; '
        'var r = fn.apply(null, ${jsonEncode(args)}); '
        'return JSON.stringify({__ok:true, data:r}, function(k,v){ '
        'if(k==="parent") return undefined; '
        'if(typeof v==="function") return undefined; return v; }); '
        '} catch(e) { '
        'var msg = (e && e.message) ? String(e.message) : String(e); '
        'if (msg.indexOf("__SSTS_SUSPEND__") === 0) { '
        'try { return JSON.stringify({__suspend: JSON.parse(msg.substring("__SSTS_SUSPEND__".length))}); } '
        'catch(e2) { return JSON.stringify({__error: msg}); } } '
        'return JSON.stringify({__error: msg}); } })()';
    return _runSuspendable(code);
  }

  /// 挂起重放环：evaluate 一段返回 {__ok/__error/__suspend} JSON 的代码，
  /// 遇到 __suspend 就执行宿主操作、写进 __syncCache、重跑。
  Future<dynamic> _runSuspendable(String code) async {
    var guard = 0;
    while (true) {
      if (++guard > 300) {
        throw Exception('源调用次数过多（可能陷入循环）');
      }
      final res = rt.evaluate(code);
      if (res.isError) {
        throw Exception(_readErrorText(res));
      }
      final decoded = _unwrap(res.stringResult);
      if (decoded is Map) {
        if (decoded['__ok'] == true) return decoded['data'];
        if (decoded['__error'] != null) {
          throw Exception('${decoded['__error']}');
        }
        final susp = decoded['__suspend'];
        if (susp is Map) {
          final req = Map<String, dynamic>.from(susp);
          final method = '${req['method']}';
          final payload = req['payload'] is Map
              ? Map<String, dynamic>.from(req['payload'] as Map)
              : <String, dynamic>{};
          dynamic result;
          String? errText;
          int? errStatus;
          try {
            result = await _performSstsHostCall(method, payload);
          } catch (e) {
            errText = '$e';
            if (e is _SstsHostError) errStatus = e.status;
          }
          // 写进同步缓存，下次重跑直接命中；失败也写进去，脚本会收到原样错误。
          final key = jsonEncode(<dynamic>[method, payload]);
          final entry = errText == null
              ? <String, dynamic>{'ok': true, 'data': result}
              : <String, dynamic>{
                  'ok': false,
                  'error': errText,
                  'status': errStatus,
                };
          try {
            rt.evaluate(
                'globalThis.__syncCache[${jsonEncode(key)}] = ${jsonEncode(entry)};');
          } catch (_) {}
          continue;
        }
      }
      throw Exception('源返回异常');
    }
  }

  String _readErrorText(JsEvalResult r) {
    final raw = r.stringResult;
    try {
      final d = jsonDecode(raw);
      if (d is Map && d['message'] != null) return '${d['message']}';
    } catch (_) {}
    return raw.isEmpty ? '脚本执行失败' : raw;
  }

  /// 执行一次宿主操作（Dart 侧，异步）。抛错会被包进缓存、重放时抛回脚本。
  Future<dynamic> _performSstsHostCall(
      String method, Map<String, dynamic> payload) async {
    switch (method) {
      case 'getString':
        return _httpText(payload);
      case 'getJson':
        {
          final text = await _httpText(payload);
          return _decodeJsonp(text);
        }
      case 'finalUrl':
        return _finalUrl(payload);
      case 'fetch':
        {
          final url = '${payload['url'] ?? ''}';
          final headers = await _requestHeaders(
              url, payload, desktop: payload['desktop'] == true);
          final uri = Uri.tryParse(url);
          if (uri == null) throw Exception('地址无效：$url');
          final req = http.Request(
              '${payload['method'] ?? 'GET'}', uri);
          req.headers.addAll(headers);
          final body = payload['body'];
          if (body != null && '$body'.isNotEmpty) req.body = '$body';
          final contentType = payload['contentType'];
          if (contentType != null && '$contentType'.isNotEmpty) {
            req.headers['Content-Type'] = '$contentType';
          }
          final resp = await http.Client()
              .send(req)
              .timeout(Duration(seconds: timeoutSeconds));
          final bytes = await resp.stream.toBytes();
          return <String, dynamic>{
            'status': resp.statusCode,
            'body': _decodeBytes(bytes),
          };
        }
      case 'status':
        {
          final url = '${payload['url'] ?? ''}';
          final headers = await _requestHeaders(
              url, payload, desktop: payload['desktop'] == true);
          final uri = Uri.tryParse(url);
          if (uri == null) throw Exception('地址无效：$url');
          try {
            final resp = await http
                .head(uri, headers: headers)
                .timeout(Duration(seconds: timeoutSeconds));
            return resp.statusCode;
          } catch (_) {
            // 有的站不支持 HEAD，退回 Range 只取 1 字节探状态。
            final resp = await http
                .get(uri, headers: <String, String>{
                  ...headers,
                  'Range': 'bytes=0-0',
                })
                .timeout(Duration(seconds: timeoutSeconds));
            return resp.statusCode;
          }
        }
      case 'cookies':
        return _web.cookies('${payload['url'] ?? ''}');
      case 'getPref':
        {
          final key = '${payload['key'] ?? ''}';
          if (onGetPref != null) return onGetPref!(key);
          return cfg['pref.$key'];
        }
      case 'setPref':
        {
          final key = '${payload['key'] ?? ''}';
          final value = payload['value'] == null ? '' : '${payload['value']}';
          if (onSetPref != null) await onSetPref!(key, value);
          cfg['pref.$key'] = value;
          return null;
        }
      case 'sleep':
        {
          final ms = (payload['ms'] as num?)?.toInt() ?? 0;
          if (ms > 0) await Future<void>.delayed(Duration(milliseconds: ms));
          return null;
        }
      case 'readCache':
        {
          final name = _safeCacheName('${payload['name'] ?? ''}');
          if (name.isEmpty || cacheDir.isEmpty) return null;
          final f = File(p.join(cacheDir, name));
          if (!await f.exists()) return null;
          try {
            return await f.readAsString();
          } catch (_) {
            return null;
          }
        }
      case 'writeCache':
        {
          final name = _safeCacheName('${payload['name'] ?? ''}');
          if (name.isEmpty || cacheDir.isEmpty) return null;
          final dir = Directory(cacheDir);
          if (!await dir.exists()) await dir.create(recursive: true);
          await File(p.join(cacheDir, name))
              .writeAsString('${payload['text'] ?? ''}');
          return null;
        }
      case 'cacheAge':
        {
          final name = _safeCacheName('${payload['name'] ?? ''}');
          if (name.isEmpty || cacheDir.isEmpty) return -1;
          final f = File(p.join(cacheDir, name));
          if (!await f.exists()) return -1;
          final stat = await f.stat();
          return DateTime.now().millisecondsSinceEpoch -
              stat.modified.millisecondsSinceEpoch;
        }
      case 'md5':
        return md5.convert(utf8.encode('${payload['text'] ?? ''}')).toString();
      case 'sha256':
        return sha256
            .convert(utf8.encode('${payload['text'] ?? ''}'))
            .toString();
      default:
        throw Exception('宿主不支持方法：$method');
    }
  }

  /// 本次请求的请求头：UA 现解析（desktop 开关按请求走）+ 源自带 headers +
  /// WebView 共享 Cookie（登录后自动带上）。
  Future<Map<String, String>> _requestHeaders(
      String url, Map<String, dynamic> payload,
      {bool desktop = false}) async {
    final headers = <String, String>{};
    final configUa = cfg['userAgent'] ?? cfg['ua'];
    final resolved = await uaResolver.resolve(
      sourceId: sourceId,
      sourceName: sourceName,
      url: url,
      sourceConfigUa:
          configUa == null ? null : '$configUa',
      desktop: desktop,
    );
    headers['User-Agent'] = resolved ??
        (desktop
            ? (desktopUa ?? _defaultDesktopUa)
            : (ua ?? _defaultMobileUa));
    final extra = payload['headers'];
    if (extra is Map) {
      extra.forEach((k, v) {
        if (v != null) headers['$k'] = '$v';
      });
    }
    final cookie = await _web.cookies(url);
    if (cookie.isNotEmpty) {
      final prev = headers['Cookie'];
      headers['Cookie'] =
          prev == null || prev.isEmpty ? cookie : '$prev; $cookie';
    }
    return headers;
  }

  Future<String> _httpText(Map<String, dynamic> payload) async {
    final url = '${payload['url'] ?? ''}';
    final uri = Uri.tryParse(url);
    if (uri == null) throw Exception('地址无效：$url');
    final headers = await _requestHeaders(url, payload,
        desktop: payload['desktop'] == true);
    final method = '${payload['method'] ?? 'GET'}'.toUpperCase();
    http.Response resp;
    if (method == 'POST') {
      final body = payload['body'];
      resp = await http
          .post(uri,
              headers: headers,
              body: body == null ? null : '$body',
              encoding: utf8)
          .timeout(Duration(seconds: timeoutSeconds));
    } else {
      resp = await http
          .get(uri, headers: headers)
          .timeout(Duration(seconds: timeoutSeconds));
    }
    // 响应里的 Set-Cookie 写回 WebView：下次登录页/请求都能用上。
    final setCookie = resp.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      try {
        await _web.setCookie(url, setCookie);
      } catch (_) {}
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw _SstsHostError('请求失败（${resp.statusCode}）',
          status: resp.statusCode);
    }
    return _decodeBytes(resp.bodyBytes);
  }

  Future<String> _finalUrl(Map<String, dynamic> payload) async {
    final url = '${payload['url'] ?? ''}';
    final uri = Uri.tryParse(url);
    if (uri == null) throw Exception('地址无效：$url');
    final headers = await _requestHeaders(url, payload,
        desktop: payload['desktop'] == true);
    final client = HttpClient();
    try {
      final req = await client
          .getUrl(uri)
          .timeout(Duration(seconds: timeoutSeconds));
      headers.forEach(req.headers.set);
      final resp = await req
          .close()
          .timeout(Duration(seconds: timeoutSeconds));
      await resp.drain<void>();
      if (resp.redirects.isNotEmpty) {
        return resp.redirects.last.location.toString();
      }
      return url;
    } finally {
      client.close();
    }
  }

  String _safeCacheName(String name) {
    final clean = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (clean.isEmpty || clean == '.' || clean == '..') return '';
    return clean;
  }

  String _decodeBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      // 非 UTF-8 时退回 Latin-1：至少能读出结构，不至于整段变乱码。
      // GBK 编码的站这里读出来会是乱码（已知缺口，见汇报）。
      return latin1.decode(bytes);
    }
  }

  dynamic _decodeJsonp(String text) {
    final t = text.trim();
    if (t.isEmpty) throw Exception('空响应');
    try {
      return jsonDecode(t);
    } catch (_) {}
    // JSONP：callback({...})，取括号里的内容。
    final start = t.indexOf('(');
    final end = t.lastIndexOf(')');
    if (start >= 0 && end > start) {
      return jsonDecode(t.substring(start + 1, end));
    }
    throw Exception('响应不是 JSON');
  }
}

/// flutter_js 的 evaluate 返回值处理：对象是 JSON 字符串，字符串可能被
/// JSON 编码过一层（带引号），数字/布尔是原样。
dynamic _unwrap(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  if (t.startsWith('{') || t.startsWith('[')) {
    try {
      return jsonDecode(t);
    } catch (_) {
      return raw;
    }
  }
  if (t.startsWith('"')) {
    try {
      return jsonDecode(t);
    } catch (_) {
      return raw;
    }
  }
  return raw;
}
