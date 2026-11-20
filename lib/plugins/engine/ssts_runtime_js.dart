/// 随身听书（ssts）格式的 JS 运行时引导脚本。
///
/// 随身听书插件的方法是**同步**的：`this.host.getJson(url)` 必须直接返回值，
/// 不能返回 Promise。flutter_js 的宿主调用是异步消息通道，JS 里没法同步等 Dart，
/// 所以这里用「挂起 + 重放」实现同步宿主调用：
/// - JS 里 `__hostSync(method, payload)` 查缓存，命中直接返回；
///   未命中就抛一个 `__SSTS_SUSPEND__` 错误，Dart 侧捕获后执行真正的宿主操作
///  （HTTP、偏好、加密等），把结果写进 `__syncCache`，再从头重跑一遍源方法。
///   每次重跑都多命中一个缓存，直到跑完。
/// - 纯计算（DOM 解析、base64、uuid 等）直接在 JS 里做，不挂起。
/// - render / sniff / aesEcbDecrypt 这三个要 WebView 或原生加密的，暂不支持，
///   抛人话错误，不静默返回空。
///
/// [buildSstsBootstrap] 拼出完整的引导脚本：[ua] 是当前源的手机版 UA（可空，
/// 用内置默认顶上），[desktopUa] 是电脑版 UA（可空），[cfg] 是运行配置
/// （源声明的配置值 + voiceId / lineId 等，见 SourceConfigRepository）。
String buildSstsBootstrap(String? ua, Map<String, dynamic> cfg,
    {String? desktopUa}) {
  final uaJson = ua == null ? 'null' : _jsonStr(ua);
  final desktopJson =
      desktopUa == null ? 'null' : _jsonStr(desktopUa);
  final cfgJson = _jsonEncode(cfg);
  return sstsBootstrapJs
      .replaceAll('__BOOT_UA__', uaJson)
      .replaceAll('__BOOT_DESKTOP_UA__', desktopJson)
      .replaceAll('__BOOT_CFG__', cfgJson);
}

String _jsonStr(String s) {
  return '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n').replaceAll('\r', '\\r')}"';
}

String _jsonEncode(Map<String, dynamic> m) {
  final parts = <String>[];
  m.forEach((k, v) {
    parts.add('${_jsonStr(k)}:${_jsonValue(v)}');
  });
  return '{${parts.join(',')}}';
}

String _jsonValue(dynamic v) {
  if (v == null) return 'null';
  if (v is num || v is bool) return '$v';
  if (v is String) return _jsonStr(v);
  if (v is Map) return _jsonEncode(Map<String, dynamic>.from(v));
  if (v is List) return '[${v.map(_jsonValue).join(',')}]';
  return _jsonStr('$v');
}

/// 引导脚本本体（不含 UA / 配置，由 buildSstsBootstrap 注入）。
const String sstsBootstrapJs = r'''
(function () {
  // ============================================================ 同步宿主调用
  // __syncCache: key 是 JSON.stringify([method, payload])，值是
  // {ok: true, data} 或 {ok: false, error, status}。
  globalThis.__syncCache = {};
  globalThis.__sstsCurrentUrl = '';

  // 异步消息（log / toast / progress 这类不用等结果的）：发给 Dart，不挂起。
  globalThis.__hostCall = function (method, data) {
    try {
      if (typeof sendMessage === 'function') {
        sendMessage('__host_call', JSON.stringify({ method: method, data: data }));
      }
    } catch (e) { /* 发不出去就算了，不影响源执行 */ }
  };

  globalThis.__hostSync = function (method, payload) {
    var key = JSON.stringify([method, payload]);
    if (Object.prototype.hasOwnProperty.call(globalThis.__syncCache, key)) {
      var hit = globalThis.__syncCache[key];
      if (hit.ok) return hit.data;
      var err = new Error(hit.error);
      if (hit.status !== undefined && hit.status !== null) err.status = hit.status;
      throw err;
    }
    throw new Error('__SSTS_SUSPEND__' + JSON.stringify({ method: method, payload: payload }));
  };

  // ============================================================ 兼容垫片
  // 插件脚本从浏览器/Node 环境搬过来，普遍直接用 console、setTimeout、
  // btoa/atob、TextEncoder、window。QuickJS 没有这些，缺一个就在加载阶段
  // ReferenceError，后面 registerSource 直接跑不到（"导入后一个源都没有"）。
  globalThis.window = globalThis;
  globalThis.self = globalThis;

  function __logLine(args) {
    var parts = [];
    for (var i = 0; i < args.length; i++) {
      var a = args[i];
      if (typeof a === 'string') {
        parts.push(a);
      } else {
        try {
          parts.push(JSON.stringify(a));
        } catch (e) {
          parts.push(String(a));
        }
      }
    }
    return parts.join(' ');
  }

  if (typeof globalThis.console === 'undefined') {
    var __consoleObj = {};
    ['log', 'info', 'warn', 'error', 'debug', 'trace'].forEach(function (k) {
      __consoleObj[k] = function () {
        try {
          __hostCall('log', k + ': ' + __logLine(arguments));
        } catch (e) {}
      };
    });
    globalThis.console = __consoleObj;
  }

  // setTimeout 只能立即执行（JS 侧没有事件循环，宿主调用靠挂起重放），
  // 限制嵌套层数，防止插件用 setTimeout 自递归把 JS 卡死。
  var __timerDepth = 0;
  globalThis.setTimeout = function (fn) {
    if (typeof fn !== 'function' || __timerDepth > 8) return 0;
    __timerDepth++;
    try {
      fn();
    } catch (e) {
    } finally {
      __timerDepth--;
    }
    return 0;
  };
  globalThis.setInterval = globalThis.setTimeout;
  globalThis.clearTimeout = function () {};
  globalThis.clearInterval = function () {};
  globalThis.requestAnimationFrame = function (fn) {
    return globalThis.setTimeout(fn);
  };

  var __B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  // btoa 按 UTF-8 走：插件常拿它编码带中文的 Cookie/参数。
  function __utf8Bytes(str) {
    var enc = encodeURIComponent(String(str));
    var bytes = [];
    for (var i = 0; i < enc.length; i++) {
      if (enc.charAt(i) === '%') {
        bytes.push(parseInt(enc.substr(i + 1, 2), 16));
        i += 2;
      } else {
        bytes.push(enc.charCodeAt(i));
      }
    }
    return bytes;
  }

  globalThis.btoa = function (s) {
    var bytes = __utf8Bytes(s), out = '', i = 0;
    for (; i + 2 < bytes.length; i += 3) {
      var n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
      out += __B64[(n >> 18) & 63] + __B64[(n >> 12) & 63] +
        __B64[(n >> 6) & 63] + __B64[n & 63];
    }
    var left = bytes.length - i;
    if (left === 1) {
      var n1 = bytes[i] << 16;
      out += __B64[(n1 >> 18) & 63] + __B64[(n1 >> 12) & 63] + '==';
    } else if (left === 2) {
      var n2 = (bytes[i] << 16) | (bytes[i + 1] << 8);
      out += __B64[(n2 >> 18) & 63] + __B64[(n2 >> 12) & 63] +
        __B64[(n2 >> 6) & 63] + '=';
    }
    return out;
  };
  globalThis.atob = function (s) {
    var str = String(s).replace(/[^A-Za-z0-9+/]/g, '');
    var buf = 0, bits = 0, bytes = [];
    for (var i = 0; i < str.length; i++) {
      buf = (buf << 6) | __B64.indexOf(str[i]);
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        bytes.push((buf >> bits) & 0xff);
      }
    }
    var esc = '';
    for (var k = 0; k < bytes.length; k++) {
      esc += '%' + (bytes[k] < 16 ? '0' : '') + bytes[k].toString(16);
    }
    try {
      return decodeURIComponent(esc);
    } catch (e) {
      return esc;
    }
  };

  if (typeof globalThis.TextDecoder === 'undefined') {
    globalThis.TextDecoder = function (label) { this.encoding = label || 'utf-8'; };
    globalThis.TextDecoder.prototype.decode = function (buf) {
      var arr = (buf && buf.byteLength !== undefined) ? buf : new Uint8Array(buf || 0);
      if (arr.buffer) arr = new Uint8Array(arr.buffer, arr.byteOffset || 0, arr.byteLength);
      var s = '';
      for (var i = 0; i < arr.length; i++) {
        s += '%' + (arr[i] < 16 ? '0' : '') + arr[i].toString(16);
      }
      try {
        return decodeURIComponent(s);
      } catch (e) {
        return s;
      }
    };
  }
  if (typeof globalThis.TextEncoder === 'undefined') {
    globalThis.TextEncoder = function () { this.encoding = 'utf-8'; };
    globalThis.TextEncoder.prototype.encode = function (str) {
      return new Uint8Array(__utf8Bytes(str));
    };
  }

  function _opt(o) { return o && typeof o === 'object' ? o : {}; }
  function _headers(o) { return _opt(o).headers || null; }

  var _defaultMobileUa = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  var _defaultDesktopUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  globalThis.__sstsHost = {
    ua: __BOOT_UA__,
    desktopUa: __BOOT_DESKTOP_UA__,
    config: __BOOT_CFG__,
    getConfig: function (key) { return key === undefined ? this.config : this.config[key]; },
    userAgent: function (desktop) {
      if (desktop) return this.desktopUa || _defaultDesktopUa;
      return this.ua || _defaultMobileUa;
    },
    getString: function (url, options) {
      var o = _opt(options);
      return __hostSync('getString', { url: url, desktop: !!o.desktop, headers: _headers(o), encoding: o.encoding || null });
    },
    getHtml: function (url, options) {
      var o = _opt(options);
      var html = __hostSync('getString', { url: url, desktop: !!o.desktop, headers: _headers(o), encoding: o.encoding || null });
      globalThis.__sstsCurrentUrl = url;
      return __parseHtml(html, url);
    },
    getJson: function (url, options) {
      var o = _opt(options);
      return __hostSync('getJson', { url: url, desktop: !!o.desktop, headers: _headers(o), encoding: o.encoding || null });
    },
    getStrings: function (urls, options, concurrency) {
      var o = _opt(options), out = [];
      for (var i = 0; i < (urls || []).length; i++) {
        try {
          out.push(__hostSync('getString', { url: urls[i], desktop: !!o.desktop, headers: _headers(o), encoding: o.encoding || null }));
        } catch (e) { out.push(null); }
      }
      return out;
    },
    finalUrl: function (url, options) {
      var o = _opt(options);
      return __hostSync('finalUrl', { url: url, desktop: !!o.desktop, headers: _headers(o) });
    },
    fetch: function (url, options) {
      var o = _opt(options);
      return __hostSync('fetch', { url: url, desktop: !!o.desktop, method: o.method || 'GET', body: o.body == null ? null : String(o.body), contentType: o.contentType || null, headers: _headers(o) });
    },
    status: function (url, options) {
      var o = _opt(options);
      return __hostSync('status', { url: url, desktop: !!o.desktop, headers: _headers(o) });
    },
    parseHtml: function (html, baseUrl) { return __parseHtml(html || '', baseUrl || globalThis.__sstsCurrentUrl || ''); },
    render: function () { throw new Error('这个源要用 WebView 渲染页面取音频，当前版本暂不支持'); },
    sniff: function () { throw new Error('这个源要用 WebView 嗅探音频，当前版本暂不支持'); },
    cookies: function (url) { return __hostSync('cookies', { url: url }); },
    getPref: function (key, def) {
      var v = __hostSync('getPref', { key: String(key) });
      return (v === null || v === undefined) ? (def === undefined ? null : def) : v;
    },
    setPref: function (key, value) { __hostSync('setPref', { key: String(key), value: value == null ? null : String(value) }); },
    toast: function (msg) { __hostCall('toast', String(msg)); },
    log: function (msg) { __hostCall('log', String(msg)); },
    progress: function (info) { __hostCall('progress', info == null ? null : String(info)); },
    sleep: function (ms) { __hostSync('sleep', { ms: Number(ms) || 0 }); },
    readCache: function (name) { return __hostSync('readCache', { name: String(name) }); },
    writeCache: function (name, text) { __hostSync('writeCache', { name: String(name), text: String(text) }); },
    cacheAge: function (name) { return __hostSync('cacheAge', { name: String(name) }); },
    base64Decode: function (s) { return __b64dec(String(s || '')); },
    base64Encode: function (s) { return __b64enc(String(s || '')); },
    md5: function (s) { return __hostSync('md5', { text: String(s || '') }); },
    sha256: function (s) { return __hostSync('sha256', { text: String(s || '') }); },
    uuid: function () {
      return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
        var r = Math.random() * 16 | 0, v = c === 'x' ? r : (r & 0x3 | 0x8);
        return v.toString(16);
      });
    },
    htmlDecode: function (s) { return __decodeEntities(String(s || '')); },
    aesEcbDecrypt: function () { throw new Error('这个源要用 AES 解密，当前版本暂不支持'); }
  };

  // 插件用裸 host / CONFIG 而不是 __sstsHost：引导里不给别名，安装期
  // 跑脚本时第一行 host.getString 就 ReferenceError，后面 registerSource
  // 永远执行不到 —— 「导入成功但一个源都没有」的首要原因。
  globalThis.host = globalThis.__sstsHost;
  globalThis.CONFIG = globalThis.__sstsHost.config;

  // ============================================================ 注册表
  globalThis.__sstsRegistry = [];
  globalThis.__sstsById = {};
  // 注册必须可重入：脚本加载期调 host 会「挂起 + 从头重放」，
  // registerSource 会被执行多次，同一 id 只能留一条，否则源翻倍。
  globalThis.registerSource = function (obj) {
    if (!obj || typeof obj !== 'object') throw new Error('registerSource 参数无效');
    var id = obj.id ? String(obj.id) : '';
    if (!id) throw new Error('registerSource 缺少 id');
    if (!obj.name) obj.name = id;
    obj.host = globalThis.__sstsHost;
    globalThis.__sstsById[id] = obj;
    for (var i = 0; i < globalThis.__sstsRegistry.length; i++) {
      if (String(globalThis.__sstsRegistry[i].id) === id) {
        globalThis.__sstsRegistry[i] = obj;
        return obj;
      }
    }
    globalThis.__sstsRegistry.push(obj);
    return obj;
  };

  // 执行插件脚本，支持「挂起 + 重放」：脚本加载期调 host 时抛
  // __SSTS_SUSPEND__，宿主请求回来后从头整段重跑，不会执行到一半中断。
  globalThis.__sstsLoadScript = function (code) {
    try {
      (0, eval)(String(code));
      return JSON.stringify({ __ok: true });
    } catch (e) {
      var msg = (e && e.message) ? String(e.message) : String(e);
      if (msg.indexOf('__SSTS_SUSPEND__') === 0) {
        try {
          return JSON.stringify({ __suspend: JSON.parse(msg.substring('__SSTS_SUSPEND__'.length)) });
        } catch (e2) {
          return JSON.stringify({ __error: msg });
        }
      }
      return JSON.stringify({ __error: msg });
    }
  };

  // 安装时读注册表元数据（不含函数，只取展示用字段）。
  globalThis.__sstsMeta = function () {
    return JSON.stringify(globalThis.__sstsRegistry.map(function (s) {
      return {
        id: String(s.id), name: String(s.name || ''),
        url: s.url ? String(s.url) : '', description: s.description ? String(s.description) : '',
        group: s.group ? String(s.group) : '',
        loginUrl: s.loginUrl ? String(s.loginUrl) : '',
        loginDesktop: !!s.loginDesktop,
        config: Array.isArray(s.config) ? s.config : [],
        multipleEpisodePages: !!s.multipleEpisodePages,
        enabledByDefault: s.enabledByDefault !== false,
        searchVerificationDesktop: s.searchVerificationDesktop !== false,
        searchDelaySeconds: Number(s.searchDelaySeconds) || 0
      };
    }));
  };

  // ============================================================ 调源方法包装
  // Dart 侧调这个函数：返回值一定是 JSON 字符串，三种形态：
  // {__ok: true, data} / {__error: '...'} / {__suspend: {method, payload}}。
  // 源方法里的 this 绑到源对象上，所以 this.host 能用。
  globalThis.__sstsCall = function (sstsId, method, argsJson) {
    var src = globalThis.__sstsById[String(sstsId)];
    if (!src) return JSON.stringify({ __error: '源不存在：' + sstsId });
    var fn = src[method];
    if (typeof fn !== 'function') return JSON.stringify({ __error: '源没有实现方法：' + method });
    var args = [];
    try { args = JSON.parse(argsJson || '[]'); } catch (e) { args = []; }
    if (!Array.isArray(args)) args = [args];
    try {
      var data = fn.apply(src, args);
      var text;
      try {
        text = JSON.stringify({ __ok: true, data: data }, function (k, v) {
          if (k === 'parent') return undefined;
          if (typeof v === 'function') return undefined;
          return v;
        });
      } catch (e) {
        text = JSON.stringify({ __ok: true, data: data == null ? null : String(data) });
      }
      return text;
    } catch (e) {
      var msg = (e && e.message) ? String(e.message) : String(e);
      if (msg.indexOf('__SSTS_SUSPEND__') === 0) {
        try {
          var req = JSON.parse(msg.substring('__SSTS_SUSPEND__'.length));
          return JSON.stringify({ __suspend: req });
        } catch (e2) {
          return JSON.stringify({ __error: msg });
        }
      }
      return JSON.stringify({ __error: msg });
    }
  };

  // ============================================================ base64 / 实体
  var __b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  function __b64enc(input) {
    var str = unescape(encodeURIComponent(input));
    var out = '', i = 0;
    while (i < str.length) {
      var a = str.charCodeAt(i++), b = i < str.length ? str.charCodeAt(i++) : NaN, c = i < str.length ? str.charCodeAt(i++) : NaN;
      var n = (a << 16) | ((isNaN(b) ? 0 : b) << 8) | (isNaN(c) ? 0 : c);
      out += __b64chars[(n >> 18) & 63] + __b64chars[(n >> 12) & 63] + (isNaN(b) ? '=' : __b64chars[(n >> 6) & 63]) + (isNaN(c) ? '=' : __b64chars[n & 63]);
    }
    return out;
  }
  function __b64dec(input) {
    var clean = String(input).replace(/[^A-Za-z0-9+/=]/g, '');
    var out = '', i = 0;
    while (i < clean.length) {
      var e1 = __b64chars.indexOf(clean.charAt(i++));
      var e2 = __b64chars.indexOf(clean.charAt(i++));
      var e3 = __b64chars.indexOf(clean.charAt(i++));
      var e4 = __b64chars.indexOf(clean.charAt(i++));
      var n = (e1 << 18) | (e2 << 12) | ((e3 & 63) << 6) | (e4 & 63);
      out += String.fromCharCode((n >> 16) & 255);
      if (e3 !== 64 && e3 !== -1) out += String.fromCharCode((n >> 8) & 255);
      if (e4 !== 64 && e4 !== -1) out += String.fromCharCode(n & 255);
    }
    try { return decodeURIComponent(escape(out)); } catch (e) { return out; }
  }
  var __entityMap = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', copy: '©', reg: '®', hellip: '…' };
  function __decodeEntities(s) {
    return s.replace(/&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);/g, function (m, body) {
      if (body.charAt(0) === '#') {
        var code = body.charAt(1) === 'x' || body.charAt(1) === 'X' ? parseInt(body.substring(2), 16) : parseInt(body.substring(1), 10);
        return isNaN(code) ? m : String.fromCharCode(code);
      }
      return __entityMap.hasOwnProperty(body) ? __entityMap[body] : m;
    });
  }

  // ============================================================ JSON 辅助
  // str(json, 'data.list.0.name') / int(...) / items(...) / at(...) /
  // regexInt(...) / parseJson(text)，照随身听书文档提供。
  function __pathGet(root, path) {
    if (path == null || path === '') return root;
    var cur = root;
    var parts = String(path).split('.');
    for (var i = 0; i < parts.length; i++) {
      if (cur == null) return undefined;
      cur = cur[parts[i]];
    }
    return cur;
  }
  globalThis.str = function (json, path) {
    var v = __pathGet(json, path);
    return v == null ? '' : String(v);
  };
  globalThis.int = function (json, path) {
    var v = __pathGet(json, path);
    var n = parseInt(v, 10);
    return isNaN(n) ? 0 : n;
  };
  globalThis.items = function (json, path) {
    var v = __pathGet(json, path);
    return Array.isArray(v) ? v : [];
  };
  globalThis.at = function (json, path) { return __pathGet(json, path); };
  globalThis.regexInt = function (text, re) {
    if (text == null) return 0;
    var m = String(text).match(re instanceof RegExp ? re : new RegExp(re));
    if (!m) return 0;
    var n = parseInt(m[1] || m[0], 10);
    return isNaN(n) ? 0 : n;
  };
  globalThis.parseJson = function (text) {
    if (text == null) return null;
    var t = String(text).trim();
    if (t === '') return null;
    try { return JSON.parse(t); } catch (e) { return null; }
  };

  // ============================================================ 纯 JS HTML 解析
  var __voidTags = { area: 1, base: 1, br: 1, col: 1, embed: 1, hr: 1, img: 1, input: 1, link: 1, meta: 1, param: 1, source: 1, track: 1, wbr: 1 };
  var __rawTags = { script: 1, style: 1 };

  function __parseAttrs(text) {
    var attrs = {};
    var re = /([^\s=\/]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g, m;
    while ((m = re.exec(text)) !== null) {
      var name = m[1].toLowerCase();
      var val = m[2] !== undefined ? m[2] : (m[3] !== undefined ? m[3] : (m[4] !== undefined ? m[4] : ''));
      attrs[name] = __decodeEntities(val);
    }
    return attrs;
  }

  function __escapeAttr(s) { return String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;'); }
  function __escapeText(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }

  function __makeEl(tag, attrs, parent, baseUrl) {
    var el = {
      __isEl: true, tag: tag, attrs: attrs || {}, children: [], parent: parent || null,
      baseUrl: baseUrl || '', _empty: false,
      exists: function () { return !this._empty; },
      text: function () {
        var out = '';
        var walk = function (node) {
          for (var i = 0; i < node.children.length; i++) {
            var c = node.children[i];
            if (typeof c === 'string') out += c;
            else walk(c);
          }
        };
        walk(this);
        return __decodeEntities(out).replace(/\s+/g, ' ').trim();
      },
      ownText: function () {
        var out = '';
        for (var i = 0; i < this.children.length; i++) {
          if (typeof this.children[i] === 'string') out += this.children[i];
        }
        return __decodeEntities(out).replace(/\s+/g, ' ').trim();
      },
      attr: function (name) {
        var v = this.attrs[String(name).toLowerCase()];
        return v === undefined ? '' : v;
      },
      absUrl: function (name) { return __resolveUrl(this.attr(name), this.baseUrl); },
      html: function () {
        var out = '';
        for (var i = 0; i < this.children.length; i++) {
          var c = this.children[i];
          out += typeof c === 'string' ? __escapeText(c) : c.outerHtml();
        }
        return out;
      },
      outerHtml: function () {
        if (this._empty) return '';
        var a = '';
        for (var k in this.attrs) a += ' ' + k + '="' + __escapeAttr(this.attrs[k]) + '"';
        if (__voidTags[this.tag]) return '<' + this.tag + a + '>';
        return '<' + this.tag + a + '>' + this.html() + '</' + this.tag + '>';
      },
      tag: function () { return this.tag; },
      hasClass: function (name) {
        var cls = (this.attrs['class'] || '').split(/\s+/);
        return cls.indexOf(name) >= 0;
      },
      children: function () {
        var out = [];
        for (var i = 0; i < this.children.length; i++) {
          if (typeof this.children[i] !== 'string') out.push(this.children[i]);
        }
        return out;
      },
      parent: function () { return this.parent || __emptyEl(this.baseUrl); },
      byId: function (id) {
        var found = this.select('#' + id);
        return found.length > 0 ? found[0] : __emptyEl(this.baseUrl);
      },
      select: function (selector) { return __selectAll(this, selector); },
      first: function (selector) {
        var found = this.select(selector);
        return found.length > 0 ? found[0] : __emptyEl(this.baseUrl);
      }
    };
    return el;
  }

  function __emptyEl(baseUrl) {
    var el = __makeEl('', {}, null, baseUrl || '');
    el._empty = true;
    el.tag = function () { return ''; };
    return el;
  }

  function __resolveUrl(href, base) {
    if (!href) return '';
    if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(href)) return href;
    if (href.indexOf('//') === 0) {
      var m = String(base || '').match(/^([a-zA-Z][a-zA-Z0-9+.-]*):/);
      return (m ? m[1] + ':' : 'https:') + href;
    }
    if (!base) return href;
    var bm = String(base).match(/^([a-zA-Z][a-zA-Z0-9+.-]*:\/\/[^/?#]*)([^?#]*)(\?[^#]*)?(#.*)?$/);
    if (!bm) return href;
    var origin = bm[1], path = bm[2] || '/';
    if (href.charAt(0) === '/') return origin + href;
    if (href.charAt(0) === '?') return origin + path + href;
    if (href.charAt(0) === '#') return origin + path + (bm[3] || '') + href;
    var dir = path.substring(0, path.lastIndexOf('/') + 1);
    var merged = dir + href;
    var parts = merged.split('/'), out = [];
    for (var i = 0; i < parts.length; i++) {
      if (parts[i] === '.') continue;
      if (parts[i] === '..') { out.pop(); continue; }
      out.push(parts[i]);
    }
    return origin + out.join('/');
  }

  // 选择器：tag / .class / #id / [attr] / [attr=v] / [attr*=v] /
  // 后代（空格）/ 子代（>）/ 逗号分组；支持 tag.class / tag#id 组合。
  function __parseSimple(sel) {
    var s = sel.trim();
    var out = { tag: '', id: '', classes: [], attrs: [] };
    var m = s.match(/^([a-zA-Z][a-zA-Z0-9-]*)?/);
    if (m && m[1]) { out.tag = m[1].toLowerCase(); s = s.substring(m[1].length); }
    else if (s.charAt(0) === '*') { s = s.substring(1); }
    var re = /([.#])([a-zA-Z0-9_-]+)|\[([^\]=\s~|^$*]+)(?:([~|^$*]?=)["']?([^\]"']*)["']?)?\]/g, mm;
    while ((mm = re.exec(s)) !== null) {
      if (mm[1] === '.') out.classes.push(mm[2]);
      else if (mm[1] === '#') out.id = mm[2];
      else if (mm[3]) out.attrs.push({ name: mm[3].toLowerCase(), op: mm[4] || '', value: mm[5] || '' });
    }
    return out;
  }
  function __matchSimple(el, simple) {
    if (!el || !el.__isEl || el._empty) return false;
    if (simple.tag && el.tag !== simple.tag) return false;
    if (simple.id && (el.attrs.id || '') !== simple.id) return false;
    for (var i = 0; i < simple.classes.length; i++) {
      if (!el.hasClass(simple.classes[i])) return false;
    }
    for (var j = 0; j < simple.attrs.length; j++) {
      var a = simple.attrs[j];
      var v = el.attrs[a.name];
      if (v === undefined) return false;
      if (a.op === '=' && v !== a.value) return false;
      if (a.op === '*=' && v.indexOf(a.value) < 0) return false;
      if (a.op === '^=' && v.indexOf(a.value) !== 0) return false;
      if (a.op === '$=' && v.slice(-a.value.length) !== a.value) return false;
      if (a.op === '~=' && (' ' + v + ' ').indexOf(' ' + a.value + ' ') < 0) return false;
    }
    return true;
  }
  function __descendants(el, out) {
    for (var i = 0; i < el.children.length; i++) {
      var c = el.children[i];
      if (typeof c === 'string') continue;
      out.push(c);
      __descendants(c, out);
    }
  }
  function __selectGroup(root, group) {
    // 先按 '>' 切子代，再按空格切后代。
    var tokens = [];
    var buf = '', i = 0;
    while (i < group.length) {
      var ch = group.charAt(i);
      if (ch === '>' ) { if (buf.trim()) tokens.push(buf.trim()); tokens.push('>'); buf = ''; i++; continue; }
      if (ch === ' ' || ch === '\t' || ch === '\n') {
        if (buf.trim()) { tokens.push(buf.trim()); buf = ''; }
        i++;
        while (i < group.length && /\s/.test(group.charAt(i))) i++;
        continue;
      }
      buf += ch; i++;
    }
    if (buf.trim()) tokens.push(buf.trim());
    var current = [root];
    var childOnly = false;
    for (var t = 0; t < tokens.length; t++) {
      var tok = tokens[t];
      if (tok === '>') { childOnly = true; continue; }
      var simple = __parseSimple(tok);
      var next = [];
      for (var c = 0; c < current.length; c++) {
        var scope = current[c];
        var pool = [];
        if (childOnly) {
          for (var k = 0; k < scope.children.length; k++) {
            if (typeof scope.children[k] !== 'string') pool.push(scope.children[k]);
          }
        } else {
          __descendants(scope, pool);
        }
        for (var p = 0; p < pool.length; p++) {
          if (__matchSimple(pool[p], simple)) next.push(pool[p]);
        }
      }
      current = next;
      childOnly = false;
      if (current.length === 0) break;
    }
    return current;
  }
  function __selectAll(root, selector) {
    var out = [], seen = [];
    if (!selector) return out;
    var groups = String(selector).split(',');
    for (var g = 0; g < groups.length; g++) {
      var found = __selectGroup(root, groups[g]);
      for (var i = 0; i < found.length; i++) {
        if (seen.indexOf(found[i]) < 0) { seen.push(found[i]); out.push(found[i]); }
      }
    }
    return out;
  }

  function __parseHtml(html, baseUrl) {
    var root = __makeEl('#document', {}, null, baseUrl || '');
    var stack = [root];
    var top = function () { return stack[stack.length - 1]; };
    var re = /<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<(\/?)([A-Za-z][A-Za-z0-9-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(\/?)>|([^<]+)/g;
    var m;
    while ((m = re.exec(html)) !== null) {
      if (m[5] !== undefined) {
        // 文本
        var text = __decodeEntities(m[5]);
        if (text) top().children.push(text);
        continue;
      }
      if (m[1] !== undefined) {
        var isClose = m[1] === '/';
        var tagName = m[2].toLowerCase();
        var attrText = m[3] || '';
        var selfClose = m[4] === '/';
        if (isClose) {
          for (var s = stack.length - 1; s > 0; s--) {
            if (stack[s].tag === tagName) { stack.length = s; break; }
          }
          continue;
        }
        var el = __makeEl(tagName, __parseAttrs(attrText), top(), baseUrl || '');
        top().children.push(el);
        if (__rawTags[tagName]) {
          var closeRe = new RegExp('</' + tagName + '\\s*>', 'i');
          var rest = html.substring(re.lastIndex);
          var cm = closeRe.exec(rest);
          if (cm) {
            var raw = rest.substring(0, cm.index);
            if (raw) el.children.push(raw);
            re.lastIndex += cm.index + cm[0].length;
          }
          continue;
        }
        if (!__voidTags[tagName] && !selfClose) stack.push(el);
      }
      // 注释 / DOCTYPE / CDATA 直接跳过
    }
    return root;
  }
  globalThis.__parseHtml = __parseHtml;
  globalThis.parseHtml = __parseHtml;
})();
''';
