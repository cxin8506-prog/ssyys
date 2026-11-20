/// 随身听书（ssts）格式的 JS 运行时引导脚本。
///
/// 与旧的异步 `host` 桥不同，随身听书插件的方法是**同步**的：
/// `this.host.getJson(url)` 必须直接返回 JSON 值，不能返回 Promise。
/// flutter_js 的宿主调用是异步消息通道，JS 里没法同步等 Dart，
/// 所以这里用「挂起 + 重放」实现同步宿主调用：
/// - JS 里 `__hostSync(method, payload)` 查缓存，命中直接返回；
///   未命中就抛一个 `__SSTS_SUSPEND__` 错误，Dart 侧捕获后执行
///   真正的宿主操作（HTTP、偏好、加密等），把结果写进 `__syncCache`，
///   再从头重跑一遍源方法。每次重跑都多命中一个缓存，直到跑完。
/// - 纯计算（DOM 解析、base64、uuid 等）直接在 JS 里做，不挂起。
/// - render / sniff / AES 这三个要 WebView 或原生加密的，暂不支持，
///   抛人话错误，不静默返回空。

/// 拼出完整的引导脚本。ua 是当前源的 UA（可空），cfg 是运行配置。
String buildSstsBootstrap(String? ua, Map<String, dynamic> cfg) {
  final uaJson = ua == null ? 'null' : _jsonStr(ua);
  final cfgJson = _jsonEncode(cfg);
  return sstsBootstrapJs
      .replaceAll('__BOOT_UA__', uaJson)
      .replaceAll('__BOOT_CFG__', cfgJson);
}

String _jsonStr(String s) =>
    '"${s.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n').replaceAll('\r', '\\r')}"';

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
  if (v is Map) {
    return _jsonEncode(Map<String, dynamic>.from(v));
  }
  if (v is List) {
    return '[${v.map(_jsonValue).join(',')}]';
  }
  return _jsonStr('$v');
}

/// 引导脚本本体（不含 UA / 配置，由 buildSstsBootstrap 注入）。
const String sstsBootstrapJs = r'''
(function () {
  // ============================================================ 同步宿主调用
  globalThis.__syncCache = {};
  globalThis.__sstsCurrentUrl = '';
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

  function _opt(o) { return o && typeof o === 'object' ? o : {}; }
  function _headers(o) { return _opt(o).headers || null; }

  globalThis.__sstsHost = {
    ua: __BOOT_UA__,
    desktopUa: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    config: __BOOT_CFG__,
    getConfig: function (key) { return key === undefined ? this.config : this.config[key]; },
    userAgent: function (desktop) { return desktop ? this.desktopUa : (this.ua || this.desktopUa); },
    getString: function (url, options) {
      var o = _opt(options);
      return __hostSync('getString', { url: url, desktop: !!o.desktop, headers: _headers(o), encoding: o.encoding || null });
    },
    getHtml: function (url, options) {
      var o = _opt(options);
      var html = __hostSync('getString', { url: url, desktop: !!o.desktop, headers: _headers(o), encoding: o.encoding || null });
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
    toast: function (msg) { __hostSync('toast', { msg: String(msg) }); },
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

  // ============================================================ 注册表
  globalThis.__sstsRegistry = [];
  globalThis.__sstsById = {};
  globalThis.registerSource = function (obj) {
    if (!obj || typeof obj !== 'object') throw new Error('registerSource 参数无效');
    if (!obj.id) throw new Error('registerSource 缺少 id');
    if (!obj.name) obj.name = String(obj.id);
    obj.host = globalThis.__sstsHost;
    globalThis.__sstsRegistry.push(obj);
    globalThis.__sstsById[String(obj.id)] = obj;
    return obj;
  };
  // 安装时读注册表元数据（不含函数，只取展示用字段）
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
        hasSearch: typeof s.search === 'function',
        hasCategoryMenus: typeof s.categoryMenus === 'function',
        hasBookDetail: typeof s.bookDetail === 'function',
        hasAudio: typeof s.audio === 'function',
        hasCheckLogin: typeof s.checkLogin === 'function',
        hasSearchVerificationUrl: typeof s.searchVerificationUrl === 'function'
      };
    }));
  };

  // ============================================================ JSON 辅助
  function _atPath(obj, path) {
    var cur = obj, parts = String(path || '').split('.');
    for (var i = 0; i < parts.length; i++) {
      if (cur === null || cur === undefined) return undefined;
      cur = cur[parts[i]];
    }
    return cur;
  }
  globalThis.str = function (obj, path) {
    var v = _atPath(obj, path);
    return (v === null || v === undefined) ? '' : String(v);
  };
  globalThis.int = function (obj, path, def) {
    var v = _atPath(obj, path), n = Number(v);
    if (v === null || v === undefined || isNaN(n)) return (def === undefined ? 0 : def);
    return Math.floor(n);
  };
  globalThis.items = function (obj, path) {
    var v = _atPath(obj, path);
    return Array.isArray(v) ? v : [];
  };
  globalThis.at = function (obj, path) {
    var v = _atPath(obj, path);
    return (v === undefined) ? null : v;
  };
  globalThis.regexInt = function (text, re, def) {
    try {
      var m = re.exec(String(text || ''));
      if (m && m[1] !== undefined) { var n = parseInt(m[1], 10); if (!isNaN(n)) return n; }
    } catch (e) {}
    return (def === undefined ? 0 : def);
  };
  globalThis.parseJson = function (text) {
    try { return JSON.parse(String(text || '')); } catch (e) { return null; }
  };

  // ============================================================ base64
  var __B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  globalThis.__b64enc = function (s) {
    var out = '', i = 0;
    var bytes = [];
    for (var k = 0; k < s.length; k++) {
      var c = s.charCodeAt(k);
      if (c < 128) bytes.push(c);
      else if (c < 2048) { bytes.push(192 | (c >> 6), 128 | (c & 63)); }
      else { bytes.push(224 | (c >> 12), 128 | ((c >> 6) & 63), 128 | (c & 63)); }
    }
    for (i = 0; i < bytes.length; i += 3) {
      var b0 = bytes[i], b1 = (i + 1 < bytes.length) ? bytes[i + 1] : 0, b2 = (i + 2 < bytes.length) ? bytes[i + 2] : 0;
      out += __B64[b0 >> 2] + __B64[((b0 & 3) << 4) | (b1 >> 4)] + ((i + 1 < bytes.length) ? __B64[((b1 & 15) << 2) | (b2 >> 6)] : '=') + ((i + 2 < bytes.length) ? __B64[b2 & 63] : '=');
    }
    return out;
  };
  globalThis.__b64dec = function (s) {
    s = String(s || '').replace(/[^A-Za-z0-9+/=]/g, '');
    var out = '', i = 0;
    while (i < s.length) {
      var e0 = __B64.indexOf(s.charAt(i++)), e1 = __B64.indexOf(s.charAt(i++)),
          e2 = __B64.indexOf(s.charAt(i++)), e3 = __B64.indexOf(s.charAt(i++));
      var n = (e0 << 18) | (e1 << 12) | ((e2 & 63) << 6) | (e3 & 63);
      out += String.fromCharCode((n >> 16) & 255);
      if (e2 !== 64 && s.charAt(i - 2) !== '=') out += String.fromCharCode((n >> 8) & 255);
      if (e3 !== 64 && s.charAt(i - 1) !== '=') out += String.fromCharCode(n & 255);
    }
    try { return decodeURIComponent(escape(out)); } catch (e) { return out; }
  };

  // ============================================================ HTML 实体
  var __ENT = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };
  globalThis.__decodeEntities = function (s) {
    return String(s || '').replace(/&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);/g, function (m, body) {
      if (body.charAt(0) === '#') {
        var code = body.charAt(1) === 'x' || body.charAt(1) === 'X' ? parseInt(body.substring(2), 16) : parseInt(body.substring(1), 10);
        return isNaN(code) ? m : String.fromCharCode(code);
      }
      return (__ENT[body] !== undefined) ? __ENT[body] : m;
    });
  };

  // ============================================================ URL 解析
  globalThis.__resolveUrl = function (rel, base) {
    rel = String(rel || '');
    if (!rel) return '';
    if (/^(https?:|data:|javascript:|mailto:|tel:)/i.test(rel)) return rel;
    base = String(base || '');
    if (rel.indexOf('//') === 0) {
      var proto = /^([a-z]+:)/i.exec(base);
      return (proto ? proto[1] : 'https:') + rel;
    }
    var m = /^([a-z]+:\/\/[^\/]*)(.*)$/i.exec(base);
    var origin = m ? m[1] : '', basePath = m ? m[2] : '';
    if (rel.charAt(0) === '/') return origin + rel;
    if (rel.charAt(0) === '#') return base.split('#')[0] + rel;
    var dir = basePath.substring(0, basePath.lastIndexOf('/') + 1);
    var merged = (dir + rel).split('/');
    var out = [];
    for (var i = 0; i < merged.length; i++) {
      var seg = merged[i];
      if (seg === '.' || seg === '') continue;
      if (seg === '..') { out.pop(); continue; }
      out.push(seg);
    }
    return origin + '/' + out.join('/');
  };

  // ============================================================ HTML 解析
  var __VOID = { area: 1, base: 1, br: 1, col: 1, embed: 1, hr: 1, img: 1, input: 1, link: 1, meta: 1, param: 1, source: 1, track: 1, wbr: 1 };
  function __parseHtmlToTree(html) {
    var root = { tag: '#root', attrs: {}, children: [], parent: null };
    var stack = [root], pos = 0, len = html.length;
    function pushText(t) {
      if (!t) return;
      stack[stack.length - 1].children.push({ tag: '#text', text: __decodeEntities(t), children: [], parent: stack[stack.length - 1] });
    }
    while (pos < len) {
      var lt = html.indexOf('<', pos);
      if (lt < 0) { pushText(html.substring(pos)); break; }
      if (lt > pos) pushText(html.substring(pos, lt));
      if (html.substring(lt, lt + 4) === '<!--') {
        var end = html.indexOf('-->', lt + 4);
        pos = end < 0 ? len : end + 3;
        continue;
      }
      if (html.substring(lt, lt + 2) === '<!') {
        var gt = html.indexOf('>', lt + 2);
        pos = gt < 0 ? len : gt + 1;
        continue;
      }
      var close = html.charAt(lt + 1) === '/';
      var gt2 = html.indexOf('>', lt + (close ? 2 : 1));
      if (gt2 < 0) { pos = len; break; }
      var inside = html.substring(lt + (close ? 2 : 1), gt2);
      if (close) {
        var cname = inside.replace(/[^a-zA-Z0-9-].*$/, '').toLowerCase();
        for (var s = stack.length - 1; s > 0; s--) {
          if (stack[s].tag === cname) { stack.length = s; break; }
        }
        pos = gt2 + 1;
        continue;
      }
      var selfClose = /\/\s*$/.test(inside);
      var m = /^([a-zA-Z][a-zA-Z0-9-]*)/.exec(inside);
      if (!m) { pos = gt2 + 1; continue; }
      var tag = m[1].toLowerCase();
      var attrs = {}, rest = inside.substring(m[1].length);
      var am = /([a-zA-Z_:][a-zA-Z0-9_:\-.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g, am2;
      while ((am2 = am.exec(rest)) !== null) {
        var an = am2[1].toLowerCase();
        var av = am2[2] !== undefined ? am2[2] : (am2[3] !== undefined ? am2[3] : (am2[4] !== undefined ? am2[4] : ''));
        attrs[an] = __decodeEntities(av);
      }
      var node = { tag: tag, attrs: attrs, children: [], parent: stack[stack.length - 1] };
      stack[stack.length - 1].children.push(node);
      if (!selfClose && !__VOID[tag]) {
        stack.push(node);
        if (tag === 'script' || tag === 'style') {
          var endTag = '</' + tag;
          var endPos = html.toLowerCase().indexOf(endTag, gt2 + 1);
          if (endPos >= 0) {
            var raw = html.substring(gt2 + 1, endPos);
            if (raw) node.children.push({ tag: '#text', text: raw, children: [], parent: node });
            stack.pop();
            var gt3 = html.indexOf('>', endPos);
            pos = gt3 < 0 ? len : gt3 + 1;
            continue;
          }
        }
      }
      pos = gt2 + 1;
    }
    return root;
  }
  function __nodeText(n, own) {
    var out = '';
    for (var i = 0; i < n.children.length; i++) {
      var c = n.children[i];
      if (c.tag === '#text') out += c.text;
      else if (!own) out += __nodeText(c, false);
    }
    return out.replace(/\s+/g, ' ').replace(/^\s+|\s+$/g, '');
  }
  function __escapeHtml(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function __serialize(n) {
    if (n.tag === '#text') return __escapeHtml(n.text);
    if (n.tag === '#root') {
      var s = '';
      for (var i = 0; i < n.children.length; i++) s += __serialize(n.children[i]);
      return s;
    }
    var a = '';
    for (var k in n.attrs) a += ' ' + k + '="' + __escapeHtml(n.attrs[k]) + '"';
    if (__VOID[n.tag]) return '<' + n.tag + a + '>';
    var inner = '';
    for (var j = 0; j < n.children.length; j++) inner += __serialize(n.children[j]);
    return '<' + n.tag + a + '>' + inner + '</' + n.tag + '>';
  }
  // ---- 选择器：tag / .class / #id / [attr] / [attr=v] / 后代（空格）/ 逗号分组
  function __parseCompound(part) {
    var c = { tag: null, id: null, classes: [], attrs: [] }, rest = part;
    var tm = /^(\*|[a-zA-Z][a-zA-Z0-9-]*)/.exec(rest);
    if (tm) { c.tag = tm[1].toLowerCase(); rest = rest.substring(tm[1].length); }
    while (rest.length > 0) {
      var ch = rest.charAt(0);
      if (ch === '#') { var im = /^#([a-zA-Z0-9_-]+)/.exec(rest); if (!im) break; c.id = im[1]; rest = rest.substring(im[0].length); }
      else if (ch === '.') { var cm = /^\.([a-zA-Z0-9_-]+)/.exec(rest); if (!cm) break; c.classes.push(cm[1]); rest = rest.substring(cm[0].length); }
      else if (ch === '[') {
        var am = /^\[\s*([a-zA-Z0-9_:-]+)\s*(?:([~|^$*]?=)\s*(?:"([^"]*)"|'([^']*)'|([^\]]*?))\s*)?\]/.exec(rest);
        if (!am) break;
        c.attrs.push({ name: am[1].toLowerCase(), op: am[2] || null, value: am[3] !== undefined ? am[3] : (am[4] !== undefined ? am[4] : (am[5] !== undefined ? am[5] : null)) });
        rest = rest.substring(am[0].length);
      } else break;
    }
    return c;
  }
  function __parseSelector(sel) {
    var groups = [];
    var parts = String(sel || '').split(',');
    for (var i = 0; i < parts.length; i++) {
      var chain = [], segs = parts[i].replace(/^\s+|\s+$/g, '').split(/\s+/);
      for (var j = 0; j < segs.length; j++) { if (segs[j]) chain.push(__parseCompound(segs[j])); }
      if (chain.length > 0) groups.push(chain);
    }
    return groups;
  }
  function __matchesCompound(el, c) {
    if (el.tag === '#text' || el.tag === '#root') return false;
    if (c.tag && c.tag !== '*' && el.tag !== c.tag) return false;
    if (c.id && (el.attrs.id || '') !== c.id) return false;
    if (c.classes.length > 0) {
      var cl = (' ' + (el.attrs['class'] || '') + ' ').replace(/\s+/g, ' ');
      for (var i = 0; i < c.classes.length; i++) { if (cl.indexOf(' ' + c.classes[i] + ' ') < 0) return false; }
    }
    for (var j = 0; j < c.attrs.length; j++) {
      var a = c.attrs[j], v = el.attrs[a.name];
      if (v === undefined) return false;
      if (a.op === null) continue;
      if (a.op === '=') { if (v !== a.value) return false; }
      else if (a.op === '^=') { if (v.indexOf(a.value) !== 0) return false; }
      else if (a.op === '$=') { if (v.length < a.value.length || v.substring(v.length - a.value.length) !== a.value) return false; }
      else if (a.op === '*=') { if (v.indexOf(a.value) < 0) return false; }
      else if (a.op === '~=') { if ((' ' + v + ' ').indexOf(' ' + a.value + ' ') < 0) return false; }
    }
    return true;
  }
  function __matchesChain(el, chain) {
    var idx = chain.length - 1, cur = el;
    if (!__matchesCompound(cur, chain[idx])) return false;
    idx--;
    cur = cur.parent;
    while (idx >= 0) {
      var found = false;
      while (cur) {
        if (__matchesCompound(cur, chain[idx])) { found = true; idx--; cur = cur.parent; break; }
        cur = cur.parent;
      }
      if (!found) return false;
    }
    return true;
  }
  function __findAll(from, groups) {
    var out = [];
    function walk(n) {
      for (var i = 0; i < n.children.length; i++) {
        var c = n.children[i];
        if (c.tag !== '#text') {
          for (var g = 0; g < groups.length; g++) { if (__matchesChain(c, groups[g])) { out.push(c); break; } }
          walk(c);
        }
      }
    }
    walk(from);
    return out;
  }
  function __findById(root, id) {
    var found = null;
    function walk(n) {
      if (found) return;
      for (var i = 0; i < n.children.length; i++) {
        var c = n.children[i];
        if (c.tag !== '#text' && c.attrs.id === id) { found = c; return; }
        walk(c);
        if (found) return;
      }
    }
    walk(root);
    return found;
  }
  function __wrapEl(node, baseUrl, docRoot) {
    if (!node) return __emptyEl(baseUrl, docRoot);
    var el = {
      select: function (sel) {
        var nodes = __findAll(node, __parseSelector(sel));
        return nodes.map(function (n) { return __wrapEl(n, baseUrl, docRoot); });
      },
      first: function (sel) {
        var nodes = __findAll(node, __parseSelector(sel));
        return nodes.length > 0 ? __wrapEl(nodes[0], baseUrl, docRoot) : __emptyEl(baseUrl, docRoot);
      },
      exists: function () { return true; },
      text: function () { return __nodeText(node, false); },
      ownText: function () { return __nodeText(node, true); },
      attr: function (name) { var v = node.attrs[String(name).toLowerCase()]; return v === undefined ? '' : v; },
      absUrl: function (name) { var v = this.attr(name); return v ? __resolveUrl(v, baseUrl) : ''; },
      html: function () {
        if (node.tag === '#root') return __serialize(node);
        var s = '';
        for (var i = 0; i < node.children.length; i++) s += __serialize(node.children[i]);
        return s;
      },
      outerHtml: function () { return __serialize(node); },
      tag: function () { return node.tag === '#root' ? '' : node.tag; },
      hasClass: function (name) {
        var cl = (' ' + (node.attrs['class'] || '') + ' ').replace(/\s+/g, ' ');
        return cl.indexOf(' ' + name + ' ') >= 0;
      },
      children: function () {
        var out = [];
        for (var i = 0; i < node.children.length; i++) { if (node.children[i].tag !== '#text') out.push(__wrapEl(node.children[i], baseUrl, docRoot)); }
        return out;
      },
      parent: function () {
        if (!node.parent || node.parent.tag === '#root') return __emptyEl(baseUrl, docRoot);
        return __wrapEl(node.parent, baseUrl, docRoot);
      },
      byId: function (id) {
        var n = __findById(docRoot, String(id));
        return n ? __wrapEl(n, baseUrl, docRoot) : __emptyEl(baseUrl, docRoot);
      }
    };
    return el;
  }
  function __emptyEl(baseUrl, docRoot) {
    return {
      select: function () { return []; },
      first: function () { return __emptyEl(baseUrl, docRoot); },
      exists: function () { return false; },
      text: function () { return ''; },
      ownText: function () { return ''; },
      attr: function () { return ''; },
      absUrl: function () { return ''; },
      html: function () { return ''; },
      outerHtml: function () { return ''; },
      tag: function () { return ''; },
      hasClass: function () { return false; },
      children: function () { return []; },
      parent: function () { return __emptyEl(baseUrl, docRoot); },
      byId: function () { return __emptyEl(baseUrl, docRoot); }
    };
  }
  globalThis.__parseHtml = function (html, baseUrl) {
    var root = __parseHtmlToTree(String(html || ''));
    return __wrapEl(root, String(baseUrl || ''), root);
  };
})();
''';
