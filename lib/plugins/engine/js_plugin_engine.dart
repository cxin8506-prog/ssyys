import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../core/log/app_logger.dart';
import '../../features/ua/data/ua_resolver.dart';
import '../data/source_config_repository.dart';
import '../data/source_repository.dart';
import '../model/plugin_source.dart';
import 'plugin_engine.dart';
import 'ssts_runtime_js.dart';

/// JS/ZIP 插件引擎（QuickJS）。
///
/// 两套写法互不兼容，各自走自己的路：
/// - 旧写法：manifest.json + 一个入口脚本，导出 async 函数
///   search / detail / chapters / content，宿主是异步 `host` 桥。
/// - 随身听书写法（ssts）：manifest.json 的 `scripts` 数组 + 多个脚本，
///   每个脚本用同步的 `registerSource({...})` 注册源，方法里调
///   `this.host.getJson / getHtml / ...` 拿值（同步返回）。
///   同步宿主调用靠「挂起 + 重放」实现，见 ssts_runtime_js.dart。
///
/// 宿主注入的 JS API（旧写法，全局）：
///   await host.httpGet(url, headers?)       -> string
///   await host.httpJson(url, headers?)      -> object
///   await host.httpPost(url, body, headers?)-> string
///   host.log(...)                           -> 写运行日志
///   host.ua                                 -> 按源解析出的 UA（可能为 null）
///   host.config                             -> { loginState, voiceId, lineId, extra }
///   java.ajax / java.get / java.post        -> 兼容随身听书写法的别名（返回 Promise）
class JsPluginEngine implements PluginEngine {
  final SourceRepository _repo;
  final SourceConfigRepository _configRepo;
  final UaResolver _uaResolver;

  JsPluginEngine(this._repo, this._configRepo, this._uaResolver);

  final Map<String, _JsSession> _sessions = {};

  /// 每份 ssts 插件的源偏好（getPref/setPref），内存里一份，setPref 时落库。
  final Map<String, Map<String, String>> _sstsPrefs = {};

  @override
  String get format => 'jsZip';

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
    final ua = await _uaResolver.resolve('${source.name} ${source.id}');
    final cfg = await _configRepo.load(source.id, source.type);
    final cfgMap = _configRepo.buildRuntimeConfig(cfg);

    final rt = getJavascriptRuntime();
    final session = _JsSession(rt, ua, cfgMap);
    session.bindBridge();
    session.eval(_bootstrapScript(ua, cfgMap));
    session.eval(script, label: '${source.name}/entry');

    // 有些插件把配置挂在 config 变量上，统一暴露一次
    session.eval('''
      if (typeof config === 'undefined' && typeof source !== 'undefined') {
        var config = source;
      }
    ''');

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

    final ua = await _uaResolver.resolve('${source.name} ${source.id}');
    final cfg = await _configRepo.load(source.id, source.type);
    final cfgMap = _configRepo.buildRuntimeConfig(cfg);

    final rt = getJavascriptRuntime();
    final session = _JsSession(rt, ua, cfgMap);
    session.isSsts = true;
    session.pluginId = key;
    try {
      session.cacheDir = p.join(await _repo.sourceDirPath(key), 'cache');
    } catch (_) {
      session.cacheDir = '';
    }
    session.onGetPref = (k) async => _prefsFor(key)[k];
    session.onSetPref = (k, v) async {
      _prefsFor(key)[k] = v;
      try {
        final c = await _configRepo.load(source.id, source.type);
        c.extra['sstsPrefs'] = Map<String, String>.from(_prefsFor(key));
        await _configRepo.save(c);
      } catch (_) {}
    };
    await _loadSstsPrefs(key, source.id, source.type);
    session.bindBridge();
    session.eval(_bootstrapScript(ua, cfgMap));
    session.eval(buildSstsBootstrap(ua, cfgMap), label: 'ssts 引导');

    final scripts = await _repo.readPluginScripts(source);
    for (var i = 0; i < scripts.length; i++) {
      session.eval(scripts[i].text, label: '${source.group}/${scripts[i].name}');
    }
    // 确认这个源真的注册上了（脚本可能在中途抛错导致只注册了一部分）
    final ok = session.evalBool(
        'typeof globalThis.__sstsById[${jsonEncode(source.sstsId)}] === "object"');
    if (!ok) {
      session.rt.dispose();
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
        detail: '${source.name} ssts=${source.sstsId} 插件=$key 共 ${session.sstsIds.length} 个源');
  }

  Map<String, String> _prefsFor(String key) =>
      _sstsPrefs.putIfAbsent(key, () => {});

  Future<void> _loadSstsPrefs(
      String key, String sourceId, String type) async {
    try {
      final c = await _configRepo.load(sourceId, type);
      final raw = c.extra['sstsPrefs'];
      if (raw is Map) {
        raw.forEach((k, v) {
          _prefsFor(key)['$k'] = '$v';
        });
      }
    } catch (_) {}
  }

  @override
  Future<bool?> hasMethod(String method) async {
    final source = _bound;
    if (source == null) return null;
    final session = _sessionForBound();
    if (session == null) return null;
    if (_boundSstsId != null && _boundSstsId!.isNotEmpty) {
      return _hasSstsMethod(session, _boundSstsId!, method);
    }
    final names = PluginMethods.aliases[method] ?? [method];
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
      case 'lines':
      case 'voices':
        return false;
      case 'content':
        return true;
      case 'isCacheable':
        return true;
      case 'search':
        return session.evalBool(_sstsFnCheck(sstsId, 'search'));
      case 'categories':
      case 'browse':
        return session.evalBool(_sstsFnCheck(sstsId, 'categoryMenus'));
      case 'detail':
      case 'chapters':
        return session.evalBool(_sstsFnCheck(sstsId, 'bookDetail'));
      case 'config':
        return session.evalBool(
            'Array.isArray((globalThis.__sstsById[${jsonEncode(sstsId)}] || {}).config)');
      default:
        return false;
    }
  }

  String _sstsFnCheck(String sstsId, String fn) =>
      'typeof (globalThis.__sstsById[${jsonEncode(sstsId)}] || {})[${jsonEncode(fn)}] === "function"';

  @override
  Future<dynamic> invoke(String method, {Map<String, dynamic>? params}) async {
    final source = _bound;
    if (source == null) throw Exception('未绑定源');
    final session = _sessionForBound();
    if (session == null) throw Exception('源未加载：${source.name}');
    if (_boundSstsId != null && _boundSstsId!.isNotEmpty) {
      return _invokeSsts(session, _boundSstsId!, method, params ?? const {});
    }
    return _invokeLegacy(session, method, params ?? const {});
  }

  _JsSession? _sessionForBound() {
    if (_boundKey == null) return null;
    return _sessions[_boundKey];
  }

  // ---------------------------------------------------------- 随身听书调用

  Future<dynamic> _invokeSsts(_JsSession session, String sstsId,
      String method, Map<String, dynamic> params) async {
    switch (method) {
      case 'recommend':
        // 随身听书没有首页推荐位，返回空，界面会显示搜索入口。
        return const <Map<String, dynamic>>[];
      case 'search': {
        final r = await session.evalSstsMethod(sstsId, 'search',
            [params['keyword'] ?? '', params['page'] ?? 1]);
        if (r is! Map) return const [];
        return _asList(r['books']);
      }
      case 'categories': {
        final r = await session.evalSstsMethod(sstsId, 'categoryMenus', []);
        return _sstsCategories(r);
      }
      case 'browse': {
        final r = await session.evalSstsMethod(
            sstsId, 'categoryPage', [params['category'] ?? params['url'] ?? '']);
        if (r is! Map) return {'list': const [], 'nextUrl': '', 'totalPage': 0};
        return {
          'list': _asList(r['books']),
          'nextUrl': '${r['nextUrl'] ?? ''}',
          'totalPage': (r['totalPage'] as num?)?.toInt() ?? 0,
        };
      }
      case 'detail': {
        final r = await session.evalSstsMethod(sstsId, 'bookDetail',
            [params['url'] ?? '', false, false]);
        if (r is! Map) throw Exception('这个源没有返回详情');
        return {
          'cover': '${r['coverUrl'] ?? ''}',
          'author': '${r['author'] ?? ''}',
          'artist': '${r['artist'] ?? ''}',
          'intro': '${r['intro'] ?? ''}',
          'chapters': const [],
        };
      }
      case 'chapters': {
        final r = await session.evalSstsMethod(
            sstsId, 'bookDetail', [params['url'] ?? '', true, true]);
        if (r is! Map) return const [];
        return _asList(r['episodes']).map((e) {
          return {'name': '${e['title'] ?? e['name'] ?? ''}', 'url': '${e['url'] ?? ''}'};
        }).toList();
      }
      case 'content': {
        final url = params['url'] ?? params['chapterUrl'] ?? '';
        final hasAudio = session.evalBool(_sstsFnCheck(sstsId, 'audio'));
        if (!hasAudio) return {'url': '$url', 'headers': <String, String>{}};
        final r = await session.evalSstsMethod(sstsId, 'audio', ['$url']);
        if (r is String) return {'url': r, 'headers': <String, String>{}};
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
          return {'url': u, 'headers': headers};
        }
        throw Exception('这个源没有解析出播放地址');
      }
      case 'lines':
      case 'voices':
        return const [];
      case 'config': {
        final raw = session.evalJson(
            'JSON.stringify((globalThis.__sstsById[${jsonEncode(sstsId)}] || {}).config || [])');
        return raw ?? const [];
      }
      case 'isCacheable':
        return true;
      default:
        throw Exception('该源不支持${PluginMethods.labels[method] ?? method}');
    }
  }

  /// 随身听书登录入口：loginUrl / loginDesktop，直接取注册信息，不跑脚本。
  Future<Map<String, dynamic>?> loginInfo() async {
    final source = _bound;
    final session = _sessionForBound();
    if (source == null || session == null) return null;
    if (_boundSstsId == null || _boundSstsId!.isEmpty) return null;
    try {
      final raw = session.evalJson(
          'JSON.stringify({url: (globalThis.__sstsById[${jsonEncode(_boundSstsId)}] || {}).loginUrl || "", desktop: !!(globalThis.__sstsById[${jsonEncode(_boundSstsId)}] || {}).loginDesktop})');
      if (raw is Map) {
        final url = '${raw['url'] ?? ''}'.trim();
        if (url.isEmpty) return null;
        return {'url': url, 'desktop': raw['desktop'] == true};
      }
    } catch (_) {}
    return null;
  }

  /// 随身听书搜索验证：searchVerificationUrl(keywords)，只在需要时调用。
  Future<Map<String, dynamic>?> verificationInfo(String keyword) async {
    final source = _bound;
    final session = _sessionForBound();
    if (source == null || session == null) return null;
    if (_boundSstsId == null || _boundSstsId!.isEmpty) return null;
    try {
      final has = session.evalBool(_sstsFnCheck(_boundSstsId!, 'searchVerificationUrl'));
      if (!has) return null;
      final url = await session.evalSstsMethod(
          _boundSstsId!, 'searchVerificationUrl', [keyword]);
      final u = '$url'.trim();
      if (u.isEmpty) return null;
      var delayMs = 0;
      try {
        final rawDelay = session.evalJson(
            'JSON.stringify((globalThis.__sstsById[${jsonEncode(_boundSstsId)}] || {}).searchDelaySeconds || 0)');
        delayMs = ((rawDelay as num?)?.toInt() ?? 0) * 1000;
      } catch (_) {}
      return {'url': u, 'ua': '', 'delayMs': delayMs, 'validated': false};
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _sstsCategories(dynamic raw) {
    if (raw is! List) return const [];
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
        out.add({
          'name': group.isEmpty ? name : '$group · $name',
          'url': url,
        });
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _asList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }

  // ---------------------------------------------------------- 旧写法调用

  Future<dynamic> _invokeLegacy(
      _JsSession session, String method, Map<String, dynamic> params) async {
    // 每次调用前重新注入配置，用户在源详情里改了值不用重新加载脚本
    try {
      final latest = await _configRepo.load(_bound!.id, _bound!.type);
      session.applyConfig(_configRepo.buildRuntimeConfig(latest));
    } catch (_) {}

    final names = PluginMethods.aliases[method] ?? [method];
    final argsJson = jsonEncode(_argsFor(method, params));

    final code = '''
      (async () => {
        var names = ${jsonEncode(names)};
        var fn = null, used = null;
        for (var i = 0; i < names.length; i++) {
          if (typeof globalThis[names[i]] === "function") { fn = globalThis[names[i]]; used = names[i]; break; }
        }
        // 有些源把配置声明写成全局对象而不是函数，直接返回它
        if (!fn) {
          for (var i = 0; i < names.length; i++) {
            var o = globalThis[names[i]];
            if (o && typeof o === "object") {
              return JSON.stringify({ __ok: true, method: names[i], data: o });
            }
          }
          return JSON.stringify({ __error: 'METHOD_NOT_FOUND', method: ${jsonEncode(method)}, tried: names });
        }
        var args = JSON.parse(${jsonEncode(argsJson)});
        try {
          var r = await fn.apply(null, args);
          return JSON.stringify({ __ok: true, method: used, data: (r === undefined ? null : r) });
        } catch (e) {
          return JSON.stringify({ __ok: false, error: String(e && e.message ? e.message : e) });
        }
      })()
    ''';

    final res = await session.rt.evaluateAsync(code).timeout(
          const Duration(seconds: 45),
          onTimeout: () =>
              throw Exception('源响应超时（${PluginMethods.labels[method] ?? method}）'),
        );

    if (res.isError) {
      throw Exception(_readError(res));
    }
    final decoded = _unwrap(res.stringResult);
    if (decoded is Map && decoded['__ok'] == false) {
      throw Exception('${decoded['error']}');
    }
    if (decoded is Map && decoded['__error'] != null) {
      throw Exception('插件未实现「${PluginMethods.labels[method] ?? method}」方法');
    }
    if (decoded is Map && decoded['__ok'] == true) return decoded['data'];
    return decoded;
  }

  @override
  Future<void> dispose() async {
    for (final s in _sessions.values) {
      try {
        s.rt.dispose();
      } catch (_) {}
    }
    _sessions.clear();
    _sstsPrefs.clear();
  }

  PluginSource? _bound;
  String? _boundKey;
  String? _boundSstsId;

  /// 绑定当前源（attach 时记录，invoke 使用）
  Future<void> bind(PluginSource source) async {
    _bound = source;
    await attach(source);
  }

  void unbind() {
    _bound = null;
    _boundKey = null;
    _boundSstsId = null;
  }

  /// 释放某个源的会话（重装源后调用）。ssts 插件是多源共用一个会话，
  /// 删其中一个源就把整份插件的会话一起放掉。
  void dropSession(String sourceId) {
    String? dropKey;
    for (final e in _sessions.entries) {
      final s = e.value;
      if (s.isSsts) {
        if (s.sstsIds.contains(sourceId) || e.key == sourceId) dropKey = e.key;
      } else if (e.key == sourceId) {
        dropKey = e.key;
      }
    }
    if (dropKey == null) return;
    final s = _sessions.remove(dropKey);
    try {
      s?.rt.dispose();
    } catch (_) {}
    _sstsPrefs.remove(dropKey);
    if (_boundKey == dropKey) {
      _bound = null;
      _boundKey = null;
      _boundSstsId = null;
    }
  }

  // -------------------------------------------------------------- 内部实现

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

  String _readError(JsEvalResult r) {
    final raw = r.stringResult;
    try {
      final d = jsonDecode(raw);
      if (d is Map && d['message'] != null) return '${d['message']}';
    } catch (_) {}
    return raw.isEmpty ? '脚本执行失败' : raw;
  }

  String _bootstrapScript(String? ua, Map<String, dynamic> cfg) {
    final cfgJson = jsonEncode(cfg);
    return '''
      globalThis.__pending = {};
      globalThis.__seq = 0;
      globalThis.__hostCall = function(method, payload) {
        return new Promise(function(resolve, reject) {
          var id = 'c' + (++globalThis.__seq);
          globalThis.__pending[id] = { resolve: resolve, reject: reject };
          sendMessage('__host_call', JSON.stringify({ id: id, method: method, payload: payload }));
        });
      };
      globalThis.__hostResolve = function(id, ok, data) {
        var p = globalThis.__pending[id];
        if (!p) return;
        delete globalThis.__pending[id];
        if (ok) { p.resolve(data); } else { p.reject(new Error(String(data))); }
      };
      globalThis.__hostNotify = function(id, data) {
        var p = globalThis.__pending[id];
        if (!p) return;
        delete globalThis.__pending[id];
        p.resolve(data);
      };
      var host = {
        ua: ${jsonEncode(ua)},
        config: $cfgJson,
        getConfig: function(key) { return key === undefined ? host.config : host.config[key]; },
        httpGet: function(url, headers) { return __hostCall('http', { url: url, method: 'GET', headers: headers || null }); },
        httpJson: function(url, headers) { return __hostCall('httpJson', { url: url, headers: headers || null }); },
        httpPost: function(url, body, headers) { return __hostCall('http', { url: url, method: 'POST', body: body, headers: headers || null }); },
        log: function() { __hostCall('log', Array.prototype.slice.call(arguments).map(String).join(' ')); },
        toString: function(v) { return v === null || v === undefined ? '' : String(v); }
      };
      var java = {
        ajax: function(url, opts) {
          opts = opts || {};
          return __hostCall('http', { url: url, method: opts.method || 'GET', body: opts.body, headers: opts.headers });
        },
        get: function(url, headers) { return __hostCall('http', { url: url, method: 'GET', headers: headers }); },
        post: function(url, body, headers) { return __hostCall('http', { url: url, method: 'POST', body: body, headers: headers }); },
        log: host.log,
        getString: function(text, rule) { return __hostCall('rule', { text: text, rule: rule }); }
      };
      globalThis.CONFIG = host.config;
    ''';
  }
}

/// quickjs 返回的是 JSON 字符串，可能被再包一层引号
dynamic _unwrap(String raw) {
  if (raw.isEmpty) return null;
  dynamic v = raw;
  for (var i = 0; i < 2; i++) {
    if (v is! String) break;
    final t = v.trim();
    if (!(t.startsWith('{') || t.startsWith('[') || t.startsWith('"'))) break;
    try {
      v = jsonDecode(t);
    } catch (_) {
      break;
    }
  }
  return v;
}

/// 随身听书源方法调用的 JS 包装：调方法、抓挂起、包结果。
/// 返回 JSON 字符串：{__ok, data} / {__error} / {__suspend, method, payload}
String _sstsCallCode(String sstsId, String jsMethod, List<dynamic> args) {
  return '''
    (function() {
      try {
        var src = globalThis.__sstsById[${jsonEncode(sstsId)}];
        if (!src) return JSON.stringify({__error: 'SOURCE_NOT_FOUND'});
        var fn = src[${jsonEncode(jsMethod)}];
        if (typeof fn !== 'function') return JSON.stringify({__error: 'METHOD_NOT_FOUND'});
        globalThis.__sstsCurrentUrl = src.url || '';
        var r = fn.apply(src, ${jsonEncode(args)});
        if (r && typeof r.then === 'function') return JSON.stringify({__error: '源方法返回了 Promise，随身听书格式要求同步返回'});
        return JSON.stringify({__ok: true, data: (r === undefined ? null : r)});
      } catch (e) {
        var m = String(e && e.message ? e.message : e);
        if (m.indexOf('__SSTS_SUSPEND__') === 0) return JSON.stringify({__suspend: JSON.parse(m.substring(16))});
        return JSON.stringify({__error: m});
      }
    })()
  ''';
}

/// 宿主调用失败（HTTP 状态等），挂起重放时要原样抛回脚本，脚本可以读 e.status。
class _SstsHostError implements Exception {
  final String message;
  final int? status;
  _SstsHostError(this.message, {this.status});
  @override
  String toString() => message;
}

/// 单个源的 JS 运行时会话
class _JsSession {
  final JavascriptRuntime rt;
  final String? ua;
  Map<String, dynamic> cfg; // 源声明的配置值（key -> value）

  /// 随身听书插件：会话按键是插件 id，一个会话带多个源。
  bool isSsts = false;
  String? pluginId;
  Set<String> sstsIds = {};
  String cacheDir = '';

  /// 源偏好读写（引擎在 attach 时接上，落库在源配置里）。
  Future<String?> Function(String key)? onGetPref;
  Future<void> Function(String key, String value)? onSetPref;

  _JsSession(this.rt, this.ua, this.cfg);

  /// 重新注入配置：用户在源详情里改完立刻生效
  void applyConfig(Map<String, dynamic> next) {
    cfg = next;
    try {
      rt.evaluate('''
        (function() {
          var c = ${jsonEncode(next)};
          if (typeof host !== 'undefined') { host.config = c; }
          if (typeof __sstsHost !== 'undefined') { __sstsHost.config = c; }
          globalThis.CONFIG = c;
        })();
      ''');
    } catch (_) {}
  }

  void bindBridge() {
    rt.onMessage('__host_call', (dynamic args) {
      _handle(args);
    });
  }

  void eval(String code, {String? label}) {
    final r = rt.evaluate(code);
    if (r.isError) {
      appLogger.error('JS 脚本执行出错${label == null ? '' : '（$label）'}：${r.stringResult}');
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

  // -------------------------------------------------- 随身听书同步调用

  /// 调一个随身听书源方法。挂起就执行宿主操作、写缓存、从头重跑，
  /// 直到方法跑完或出错。重放次数有上限，防止不确定脚本死循环。
  Future<dynamic> evalSstsMethod(
      String sstsId, String jsMethod, List<dynamic> args) async {
    var guard = 0;
    while (true) {
      if (++guard > 300) {
        throw Exception('源调用次数过多（可能陷入循环）');
      }
      final res = rt.evaluate(_sstsCallCode(sstsId, jsMethod, args));
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
          final key = jsonEncode([method, payload]);
          final entry = errText == null
              ? {'ok': true, 'data': result}
              : {'ok': false, 'error': errText, 'status': errStatus};
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
        return _sstsHttpText(payload);
      case 'getJson': {
        final text = await _sstsHttpText(payload);
        return _sstsParseJson(text);
      }
      case 'finalUrl':
        return _sstsFinalUrl(payload);
      case 'fetch':
        return _sstsFetch(payload);
      case 'status':
        return _sstsStatus(payload);
      case 'cookies': {
        final cookie = cfg['cookie'] ?? cfg['loginState'] ?? '';
        return '$cookie';
      }
      case 'getPref': {
        final get = onGetPref;
        if (get == null) return null;
        return get('${payload['key']}');
      }
      case 'setPref': {
        final set = onSetPref;
        if (set != null) {
          await set('${payload['key']}', '${payload['value'] ?? ''}');
        }
        return null;
      }
      case 'toast':
        appLogger.info('[JS] ${payload['msg'] ?? ''}');
        return null;
      case 'sleep': {
        final ms = (payload['ms'] as num?)?.toInt() ?? 0;
        if (ms > 0) await Future.delayed(Duration(milliseconds: ms));
        return null;
      }
      case 'readCache': {
        final f = File(p.join(cacheDir, _cacheName('${payload['name']}')));
        if (!await f.exists()) return null;
        return f.readAsString();
      }
      case 'writeCache': {
        final dir = Directory(cacheDir);
        if (!await dir.exists()) await dir.create(recursive: true);
        final f = File(p.join(cacheDir, _cacheName('${payload['name']}')));
        await f.writeAsString('${payload['text'] ?? ''}');
        return null;
      }
      case 'cacheAge': {
        final f = File(p.join(cacheDir, _cacheName('${payload['name']}')));
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
        throw Exception('不支持的宿主调用：$method');
    }
  }

  String _cacheName(String name) {
    final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'cache' : safe;
  }

  Map<String, String> _sstsHeaders(Map<String, dynamic> p, bool desktop) {
    final headers = <String, String>{};
    final rawHeaders = p['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (v != null) headers['$k'] = '$v';
      });
    }
    if (!headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      headers['User-Agent'] =
          desktop ? _desktopUa : (ua ?? _desktopUa);
    }
    return headers;
  }

  static const String _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  String _resolveSstsUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    // 相对地址按当前源的网址补全（运行器在调方法前写 __sstsCurrentUrl）。
    try {
      final base = rt.evaluate('globalThis.__sstsCurrentUrl || ""');
      final b = base.isError ? '' : base.stringResult;
      if (b.isNotEmpty) {
        final baseUri = Uri.parse(b);
        return baseUri.resolve(url).toString();
      }
    } catch (_) {}
    return url;
  }

  /// 同步 host 的 HTTP 文本请求：非 2xx 按随身听书约定抛错（带 status）。
  Future<String> _sstsHttpText(Map<String, dynamic> p) async {
    final url = _resolveSstsUrl('${p['url'] ?? ''}');
    if (url.isEmpty) throw Exception('URL 为空');
    final desktop = p['desktop'] == true;
    final headers = _sstsHeaders(p, desktop);
    final method = '${p['method'] ?? 'GET'}'.toUpperCase();
    final body = p['body']?.toString();
    final uri = Uri.parse(url);
    late http.Response resp;
    if (method == 'POST') {
      resp = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 25));
    } else {
      resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 25));
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw _SstsHostError('HTTP ${resp.statusCode}', status: resp.statusCode);
    }
    return _decodeBody(resp);
  }

  dynamic _sstsParseJson(String text) {
    final t = text.trim();
    try {
      return jsonDecode(t);
    } catch (_) {}
    // 兼容 JSONP：callback({...})
    final m = RegExp(r'^[A-Za-z0-9_.$]+\((.*)\)\s*;?\s*$', dotAll: true).firstMatch(t);
    if (m != null) {
      try {
        return jsonDecode(m.group(1)!);
      } catch (_) {}
    }
    throw Exception('JSON 解析失败');
  }

  /// 手动跟跳转拿最终地址（http 包不暴露跳转后的 URL）。
  Future<String> _sstsFinalUrl(Map<String, dynamic> p) async {
    var url = _resolveSstsUrl('${p['url'] ?? ''}');
    if (url.isEmpty) throw Exception('URL 为空');
    final desktop = p['desktop'] == true;
    final headers = _sstsHeaders(p, desktop);
    final client = http.Client();
    try {
      for (var i = 0; i < 10; i++) {
        final req = http.Request('GET', Uri.parse(url));
        req.headers.addAll(headers);
        req.followRedirects = false;
        final streamed = await client.send(req).timeout(const Duration(seconds: 25));
        final loc = streamed.headers['location'];
        if (streamed.statusCode >= 300 &&
            streamed.statusCode < 400 &&
            loc != null &&
            loc.isNotEmpty) {
          await streamed.stream.drain<void>();
          url = Uri.parse(url).resolve(loc).toString();
          continue;
        }
        await streamed.stream.drain<void>();
        return url;
      }
      return url;
    } finally {
      client.close();
    }
  }

  /// fetch：返回 {status, body}，非 2xx 不抛错。
  Future<Map<String, dynamic>> _sstsFetch(Map<String, dynamic> p) async {
    final url = _resolveSstsUrl('${p['url'] ?? ''}');
    if (url.isEmpty) throw Exception('URL 为空');
    final desktop = p['desktop'] == true;
    final headers = _sstsHeaders(p, desktop);
    final method = '${p['method'] ?? 'GET'}'.toUpperCase();
    final body = p['body']?.toString();
    if (method == 'POST' && p['contentType'] != null) {
      headers['Content-Type'] = '${p['contentType']}';
    }
    final uri = Uri.parse(url);
    late http.Response resp;
    if (method == 'POST') {
      resp = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 25));
    } else {
      resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 25));
    }
    return {'status': resp.statusCode, 'body': _decodeBody(resp)};
  }

  /// 只拿状态码，不下载正文。
  Future<int> _sstsStatus(Map<String, dynamic> p) async {
    final url = _resolveSstsUrl('${p['url'] ?? ''}');
    if (url.isEmpty) throw Exception('URL 为空');
    final desktop = p['desktop'] == true;
    final headers = _sstsHeaders(p, desktop);
    try {
      final resp = await http
          .head(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 25));
      return resp.statusCode;
    } catch (_) {
      final resp = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 25));
      return resp.statusCode;
    }
  }

  // -------------------------------------------------- 旧写法宿主桥（异步）

  Future<void> _handle(dynamic args) async {
    Map<String, dynamic> req;
    try {
      final raw = args is String ? args : args.toString();
      final m = jsonDecode(raw);
      req = Map<String, dynamic>.from(m as Map);
    } catch (e) {
      appLogger.warning('宿主调用参数解析失败', detail: '$e / $args');
      return;
    }
    final id = '${req['id']}';
    final method = '${req['method']}';
    final payload = req['payload'] is Map
        ? Map<String, dynamic>.from(req['payload'] as Map)
        : <String, dynamic>{};

    try {
      dynamic result;
      switch (method) {
        case 'http':
        case 'httpJson':
          final text = await _http(payload);
          result = method == 'httpJson' ? _tryJson(text) : text;
          break;
        case 'log':
          final msg = payload is String ? payload : '${req['payload']}';
          appLogger.info('[JS] $msg');
          result = null;
          break;
        case 'progress':
          final msg = payload is String ? payload : '${req['payload']}';
          appLogger.info('[JS 进度] $msg');
          result = null;
          break;
        case 'rule':
          result = _applyRule('${payload['text'] ?? ''}', '${payload['rule'] ?? ''}');
          break;
        default:
          result = null;
      }
      _resolve(id, true, result);
    } catch (e, st) {
      appLogger.warning('宿主调用失败：$method', detail: '$e');
      _resolve(id, false, '$e');
      appLogger.error('宿主调用堆栈', stack: st);
    }
  }

  void _resolve(String id, bool ok, dynamic data) {
    final literal = jsonEncode(data);
    try {
      rt.evaluate('__hostResolve(${jsonEncode(id)}, $ok, $literal);');
    } catch (_) {}
  }

  Future<String> _http(Map<String, dynamic> p) async {
    final url = '${p['url'] ?? ''}';
    if (url.isEmpty) throw Exception('URL 为空');
    final method = '${p['method'] ?? 'GET'}'.toUpperCase();
    final headers = <String, String>{};
    final rawHeaders = p['headers'];
    if (rawHeaders is Map) {
      rawHeaders.forEach((k, v) {
        if (v != null) headers['$k'] = '$v';
      });
    }
    if (ua != null && ua!.isNotEmpty && !headers.keys.any((k) => k.toLowerCase() == 'user-agent')) {
      headers['User-Agent'] = ua!;
    }
    final body = p['body']?.toString();

    final uri = Uri.parse(url);
    late http.Response resp;
    if (method == 'POST') {
      resp = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 25));
    } else {
      resp = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 25));
    }
    return _decodeBody(resp);
  }

  String _decodeBody(http.Response resp) {
    final ct = resp.headers['content-type'] ?? '';
    final low = ct.toLowerCase();
    if (low.contains('charset=gbk') || low.contains('charset=gb2312')) {
      // 没有内置 GBK 解码器，按 latin1 兜底避免抛异常
      return String.fromCharCodes(resp.bodyBytes);
    }
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }

  dynamic _tryJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  /// 极简规则取值：支持 "regex:<pattern>" 与 "split:a|b"
  String _applyRule(String text, String rule) {
    try {
      if (rule.startsWith('regex:')) {
        final m = RegExp(rule.substring(6), multiLine: true).firstMatch(text);
        return m?.group(1) ?? m?.group(0) ?? '';
      }
      if (rule.startsWith('split:')) {
        final idx = int.tryParse(rule.substring(6)) ?? 0;
        final parts = text.split(RegExp(r'\s+'));
        return idx >= 0 && idx < parts.length ? parts[idx] : '';
      }
      return text;
    } catch (_) {
      return '';
    }
  }
}

/// 供外部读取宿主能力（诊断页用）
Future<bool> jsEngineAvailable() async {
  try {
    final rt = getJavascriptRuntime();
    final r = rt.evaluate('1+1');
    rt.dispose();
    return !r.isError && r.stringResult.contains('2');
  } catch (_) {
    return false;
  }
}
