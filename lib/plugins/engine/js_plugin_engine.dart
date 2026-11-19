import 'dart:async';
import 'dart:convert';

import 'package:flutter_js/flutter_js.dart';
import 'package:http/http.dart' as http;

import '../../../core/log/app_logger.dart';
import '../../features/ua/data/ua_resolver.dart';
import '../data/source_config_repository.dart';
import '../data/source_repository.dart';
import '../model/plugin_source.dart';
import 'plugin_engine.dart';

/// JS/ZIP 插件引擎（QuickJS）
///
/// 插件包结构：
///   manifest.json   { id, name, type, version, author, description, entry, icon }
///   main.js         导出 async 函数：search / detail / chapters / content
///
/// 宿主注入的 JS API（全局）：
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

  @override
  String get format => 'jsZip';

  @override
  Future<void> attach(PluginSource source) async {
    _bound = source;
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

  @override
  Future<bool?> hasMethod(String method) async {
    final source = _bound;
    if (source == null) return null;
    final session = _sessions[source.id];
    if (session == null) return null;
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

  @override
  Future<dynamic> invoke(String method, {Map<String, dynamic>? params}) async {
    final source = _bound;
    if (source == null) throw Exception('未绑定源');
    final session = _sessions[source.id];
    if (session == null) throw Exception('源未加载：${source.name}');

    // 每次调用前重新注入配置，用户在源详情里改了值不用重新加载脚本
    try {
      final latest = await _configRepo.load(source.id, source.type);
      session.applyConfig(_configRepo.buildRuntimeConfig(latest));
    } catch (_) {}

    final names = PluginMethods.aliases[method] ?? [method];
    final argsJson = jsonEncode(_argsFor(method, params ?? {}));

    final code = '''
      (async () => {
        var names = ${jsonEncode(names)};
        var fn = null, used = null;
        for (var i = 0; i < names.length; i++) {
          if (typeof globalThis[names[i]] === 'function') { fn = globalThis[names[i]]; used = names[i]; break; }
        }
        // 有些源把配置声明写成全局对象而不是函数，直接返回它
        if (!fn) {
          for (var i = 0; i < names.length; i++) {
            var o = globalThis[names[i]];
            if (o && typeof o === 'object') {
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
  }

  PluginSource? _bound;

  /// 绑定当前源（attach 时记录，invoke 使用）
  Future<void> bind(PluginSource source) async {
    _bound = source;
    await attach(source);
  }

  void unbind() => _bound = null;

  /// 释放某个源的会话（重装源后调用）
  void dropSession(String sourceId) {
    final s = _sessions.remove(sourceId);
    try {
      s?.rt.dispose();
    } catch (_) {}
    if (_bound?.id == sourceId) _bound = null;
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
        return [];
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

/// 单个源的 JS 运行时会话
class _JsSession {
  final JavascriptRuntime rt;
  final String? ua;
  Map<String, dynamic> cfg; // 源声明的配置值（key -> value）

  _JsSession(this.rt, this.ua, this.cfg);

  /// 重新注入配置：用户在源详情里改完立刻生效
  void applyConfig(Map<String, dynamic> next) {
    cfg = next;
    try {
      rt.evaluate('''
        (function() {
          var c = ${jsonEncode(next)};
          if (typeof host !== 'undefined') { host.config = c; }
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
