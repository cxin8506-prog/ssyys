import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// 坚果云（WebDAV）客户端：测试连接、上传、列云端备份、下载、删、建目录、
/// 列目录（WebDAV 播放用）、进度小文件读写。
///
/// 坚果云要求使用「应用密码」，不是登录密码：
///   账号 → 安全选项 → 添加应用密码
/// 报错全部抛原始异常，调用方用 [friendlyError] 翻译成人话。
class WebDavClient {
  final String baseUrl;
  final String username;
  final String password;

  WebDavClient({
    required this.baseUrl,
    required this.username,
    required this.password,
  });

  Map<String, String> get _headers => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      };

  Uri _uri(String name) {
    var base = baseUrl.trim();
    if (!base.endsWith('/')) base = '$base/';
    return Uri.parse('$base${Uri.encodeComponent(name)}');
  }

  /// 多段路径：每段单独编码（progress/<bookId>.json 这种）。
  Uri _pathUri(String path) {
    var base = baseUrl.trim();
    if (!base.endsWith('/')) base = '$base/';
    final encoded = path
        .split('/')
        .map((s) => Uri.encodeComponent(s))
        .join('/');
    return Uri.parse('$base$encoded');
  }

  Uri _dirUri(String dir) {
    var base = baseUrl.trim();
    if (!base.endsWith('/')) base = '$base/';
    // dir 为空就是根目录本身：直接用 base，不能再拼一个 '/'，
    // 否则会变成 .../dav//（双斜杠），坚果云对它返回 404
    if (dir.isEmpty) return Uri.parse(base);
    return Uri.parse('$base${Uri.encodeComponent(dir)}/');
  }

  /// 测试连接：对用户填的地址本身发 PROPFIND（坚果云标准地址
  /// https://dav.jianguoyun.com/dav/），带正式的 PROPFIND 请求体。
  /// 207 Multi-Status 或 200 就是成功；401/403 是账号或应用密码错；
  /// 404 才是地址错；连不上（Socket/超时）由调用方按网络问题报。
  Future<void> test() async {
    final req = http.Request('PROPFIND', _dirUri(''));
    req.headers.addAll(_headers);
    req.headers['Depth'] = '0';
    req.headers['Content-Type'] = 'application/xml; charset=utf-8';
    req.body = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
  </d:prop>
</d:propfind>''';
    final streamed = await req.send().timeout(const Duration(seconds: 20));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 200 || resp.statusCode == 207) return;
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw Exception('账号或应用密码不对（${resp.statusCode}）');
    }
    if (resp.statusCode == 404) {
      throw Exception('地址错了（404）');
    }
    throw Exception('连接失败：HTTP ${resp.statusCode}');
  }

  /// 确保目录存在（MKCOL，已存在会返回 405，忽略）
  Future<void> ensureDir(String dir) async {
    if (dir.isEmpty) return;
    final req = http.Request('MKCOL', _dirUri(dir));
    req.headers.addAll(_headers);
    final streamed = await req.send().timeout(const Duration(seconds: 20));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 300 &&
        resp.statusCode != 405 &&
        resp.statusCode != 301) {
      throw Exception('创建目录失败：HTTP ${resp.statusCode}');
    }
  }

  /// 上传文件（PUT）
  Future<void> upload(String remoteName, File file) async {
    final bytes = await file.readAsBytes();
    final req = http.Request('PUT', _uri(remoteName));
    req.headers.addAll(_headers);
    req.headers['Content-Type'] = 'application/zip';
    req.bodyBytes = bytes;
    final streamed = await req.send().timeout(const Duration(minutes: 5));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 300) {
      throw Exception('上传失败：HTTP ${resp.statusCode}');
    }
  }

  /// 上传一段文本（进度小文件用）
  Future<void> putText(String remotePath, String text) async {
    final req = http.Request('PUT', _pathUri(remotePath));
    req.headers.addAll(_headers);
    req.headers['Content-Type'] = 'application/json; charset=utf-8';
    req.bodyBytes = utf8.encode(text);
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 300) {
      throw Exception('上传失败：HTTP ${resp.statusCode}');
    }
  }

  /// 下载文件
  Future<File> download(String remoteName, File dest) async {
    final req = http.Request('GET', _uri(remoteName));
    req.headers.addAll(_headers);
    final streamed = await req.send().timeout(const Duration(minutes: 5));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 300) {
      throw Exception('下载失败：HTTP ${resp.statusCode}');
    }
    await dest.parent.create(recursive: true);
    await dest.writeAsBytes(resp.bodyBytes);
    return dest;
  }

  /// 下载一段文本（进度小文件用）；404 返回 null（云端还没有）。
  Future<String?> getText(String remotePath) async {
    final req = http.Request('GET', _pathUri(remotePath));
    req.headers.addAll(_headers);
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 404) return null;
    if (resp.statusCode >= 300) {
      throw Exception('下载失败：HTTP ${resp.statusCode}');
    }
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }

  Future<void> delete(String remoteName) async {
    final req = http.Request('DELETE', _uri(remoteName));
    req.headers.addAll(_headers);
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    await http.Response.fromStream(streamed);
  }

  /// 列出根目录下的 zip 备份（按文件名倒序，即时间倒序）。
  Future<List<WebDavItem>> listBackups() async {
    final items = await _propfind('');
    final out =
        items.where((e) => e.name.toLowerCase().endsWith('.zip')).toList();
    out.sort((a, b) => b.name.compareTo(a.name));
    return out;
  }

  /// 列出 progress/ 下的进度小文件。
  Future<List<WebDavItem>> listProgress() async {
    final items = await _propfind('progress');
    return items
        .where((e) => e.name.toLowerCase().endsWith('.json'))
        .toList();
  }

  /// 列出指定目录的全部条目（文件 + 子目录，WebDAV 播放浏览用）。
  /// dir 为空表示根目录；返回不含目录本身。
  Future<List<WebDavItem>> listDirectory(String dir) async {
    final items = await _propfind(dir);
    // PROPFIND Depth 1 的第一条就是目录本身（href 与目录同名），去掉它
    final trimmed = dir.replaceAll(RegExp(r'/+$'), '');
    final out = items.where((e) {
      if (trimmed.isEmpty) return e.name.isNotEmpty;
      return e.name != trimmed && e.name != '$trimmed/';
    }).toList();
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  Future<List<WebDavItem>> _propfind(String dir) async {
    final req = http.Request('PROPFIND', _dirUri(dir));
    req.headers.addAll(_headers);
    req.headers['Depth'] = '1';
    req.headers['Content-Type'] = 'application/xml; charset=utf-8';
    req.body = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:getcontentlength/>
    <d:getlastmodified/>
    <d:resourcetype/>
  </d:prop>
</d:propfind>''';
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode >= 300) {
      throw Exception('读取目录失败：HTTP ${resp.statusCode}');
    }
    return _parseList(utf8.decode(resp.bodyBytes, allowMalformed: true));
  }

  List<WebDavItem> _parseList(String xml) {
    final out = <WebDavItem>[];
    final blocks = RegExp(r'<(?:D|d):response\b[\s\S]*?</(?:D|d):response>')
        .allMatches(xml);
    for (final b in blocks) {
      final block = b.group(0) ?? '';
      final href = _tag(block, 'href');
      if (href.isEmpty) continue;
      final isDir = block.contains('<d:collection') ||
          block.contains('<D:collection') ||
          href.endsWith('/');
      var hrefPath = href;
      try {
        hrefPath = Uri.parse(href).path;
      } catch (_) {
        // href 不是完整 URL 时直接用原串
      }
      final segs =
          hrefPath.split('/').where((s) => s.isNotEmpty).toList();
      if (segs.isEmpty) continue;
      final name = Uri.decodeComponent(segs.last);
      final len = int.tryParse(_tag(block, 'getcontentlength')) ?? 0;
      final modifiedRaw = _tag(block, 'getlastmodified');
      DateTime? modified;
      if (modifiedRaw.isNotEmpty) {
        try {
          modified = HttpDate.parse(modifiedRaw);
        } catch (_) {
          modified = null;
        }
      }
      out.add(WebDavItem(
        name: name,
        size: len,
        modified: modifiedRaw,
        lastModified: modified,
        isDir: isDir,
      ));
    }
    return out;
  }

  String _tag(String block, String tag) {
    final m = RegExp('<(?:D|d):$tag[^>]*>([\\s\\S]*?)</(?:D|d):$tag>')
        .firstMatch(block);
    return m?.group(1)?.trim() ?? '';
  }

  /// 把报错翻译成人话，不直接甩英文原文。
  static String friendlyError(Object e) {
    final msg = '$e';
    if (msg.contains('401') || msg.contains('403')) {
      return '账号或应用密码不对（密码填应用密码，不是登录密码）';
    }
    if (msg.contains('404')) return '地址错了，服务器找不到这个地址，检查服务器地址';
    if (msg.contains('SocketException') ||
        msg.contains('TimeoutException') ||
        msg.contains('timed out') ||
        msg.contains('ClientException') ||
        msg.contains('Connection closed') ||
        msg.contains('Connection refused') ||
        msg.contains('Network is unreachable') ||
        msg.contains('Failed host lookup')) {
      return '连不上服务器，检查网络后重试（也可能是地址里的域名打不开）';
    }
    if (msg.contains('证书') || msg.contains('Certificate')) {
      return '证书校验失败，如果是自签名证书，请在服务器设置里开启信任自签名证书';
    }
    final code = RegExp(r'HTTP (\d{3})').firstMatch(msg)?.group(1);
    if (code != null) return '服务器返回了 $code，检查地址、账号和密码';
    return '请检查地址、账号、密码和网络';
  }
}

class WebDavItem {
  final String name;
  final int size;

  /// 原始 lastModified 字符串（展示用）
  final String modified;

  /// 解析后的最后修改时间（比较新旧用）
  final DateTime? lastModified;

  /// 是否目录
  final bool isDir;

  WebDavItem({
    required this.name,
    required this.size,
    this.modified = '',
    this.lastModified,
    this.isDir = false,
  });

  String get displayName => p.basename(name);
}
