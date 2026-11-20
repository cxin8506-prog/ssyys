import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// 坚果云（WebDAV）客户端：只实现备份同步需要的几个动作。
///
/// 坚果云要求使用「应用密码」，不是登录密码：
///   账号 → 安全选项 → 添加应用密码
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

  /// 上传文件
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

  Future<void> delete(String remoteName) async {
    final req = http.Request('DELETE', _uri(remoteName));
    req.headers.addAll(_headers);
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    await http.Response.fromStream(streamed);
  }

  /// 列出目录下的 zip 备份
  Future<List<WebDavItem>> listBackups() async {
    final req = http.Request('PROPFIND', _dirUri(''));
    req.headers.addAll(_headers);
    req.headers['Depth'] = '1';
    req.headers['Content-Type'] = 'application/xml; charset=utf-8';
    req.body = '''<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop>
    <d:displayname/>
    <d:getcontentlength/>
    <d:getlastmodified/>
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
      final name = Uri.decodeComponent(href.split('/').last);
      if (!name.toLowerCase().endsWith('.zip')) continue;
      final len = int.tryParse(_tag(block, 'getcontentlength')) ?? 0;
      final modified = _tag(block, 'getlastmodified');
      out.add(WebDavItem(name: name, size: len, modified: modified));
    }
    out.sort((a, b) => b.name.compareTo(a.name));
    return out;
  }

  String _tag(String block, String tag) {
    final m = RegExp('<(?:D|d):$tag[^>]*>([\\s\\S]*?)</(?:D|d):$tag>')
        .firstMatch(block);
    return m?.group(1)?.trim() ?? '';
  }
}

class WebDavItem {
  final String name;
  final int size;
  final String modified;

  WebDavItem({required this.name, required this.size, this.modified = ''});

  String get displayName => p.basename(name);
}
