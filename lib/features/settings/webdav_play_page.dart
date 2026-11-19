import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../plugins/presentation/network_audio_page.dart';
import '../../shared/widgets/common.dart';

/// WebDAV 播放：连自己的 WebDAV 书库，直接播服务器上的音频，不用先下载
class WebDavPlayPage extends ConsumerStatefulWidget {
  const WebDavPlayPage({super.key});

  @override
  ConsumerState<WebDavPlayPage> createState() => _WebDavPlayPageState();
}

class _WebDavEntry {
  final String name;
  final String href;
  final bool isDir;
  const _WebDavEntry(
      {required this.name, required this.href, required this.isDir});
}

class _WebDavPlayPageState extends ConsumerState<WebDavPlayPage> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pathStack = <String>[];
  List<_WebDavEntry> _entries = [];
  bool _busy = false;
  String _status = '填好服务器地址、账号、密码，点“连接”浏览书库';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPrefsProvider);
    _urlCtrl.text = prefs.getString(AppConstants.keyWebDavPlayUrl) ?? '';
    _userCtrl.text = prefs.getString(AppConstants.keyWebDavPlayUser) ?? '';
    _passCtrl.text = prefs.getString(AppConstants.keyWebDavPlayPass) ?? '';
    _ready = true;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String get _base => _urlCtrl.text.trim();
  String get _authHeader {
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (user.isEmpty) return '';
    return 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
  }

  void _save() {
    final prefs = ref.read(sharedPrefsProvider);
    prefs.setString(AppConstants.keyWebDavPlayUrl, _base);
    prefs.setString(AppConstants.keyWebDavPlayUser, _userCtrl.text.trim());
    prefs.setString(AppConstants.keyWebDavPlayPass, _passCtrl.text);
  }

  Future<List<_WebDavEntry>> _propfind(String url) async {
    final client = HttpClient();
    try {
      final req = await client.openUrl('PROPFIND', Uri.parse(url));
      req.headers.set('Depth', '1');
      req.headers.set('Content-Type', 'application/xml');
      if (_authHeader.isNotEmpty) {
        req.headers.set('Authorization', _authHeader);
      }
      req.write(
          '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/></d:prop></d:propfind>');
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode != 207 && resp.statusCode != 200) {
        throw HttpException('服务器返回 ${resp.statusCode}');
      }
      return _parseEntries(body, url);
    } finally {
      client.close();
    }
  }

  List<_WebDavEntry> _parseEntries(String body, String baseUrl) {
    final out = <_WebDavEntry>[];
    final blocks = body.split('<d:response');
    for (var i = 1; i < blocks.length; i++) {
      final b = blocks[i];
      final hrefM = RegExp(r'<d:href>(.*?)</d:href>', dotAll: true)
          .firstMatch(b);
      if (hrefM == null) continue;
      final href = hrefM.group(1)!.trim();
      final nameM = RegExp(r'<d:displayname>(.*?)</d:displayname>',
              dotAll: true)
          .firstMatch(b);
      var name = nameM?.group(1)?.trim() ?? '';
      if (name.isEmpty) {
        final parts =
            href.split('/').where((e) => e.isNotEmpty).toList();
        name = parts.isEmpty ? href : parts.last;
      }
      name = Uri.decodeComponent(name);
      final isDir = b.contains('<d:collection');
      // 跳过自身这一条（Depth 1 会把当前目录也返回）
      final baseUri = Uri.tryParse(baseUrl);
      final hrefUri = Uri.tryParse(href);
      if (baseUri != null && hrefUri != null) {
        final basePath =
            baseUri.path.endsWith('/') ? baseUri.path : '${baseUri.path}/';
        final hrefPath =
            hrefUri.path.endsWith('/') ? hrefUri.path : '${hrefUri.path}/';
        if (hrefPath == basePath) continue;
      }
      out.add(_WebDavEntry(name: name, href: href, isDir: isDir));
    }
    out.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  String _resolve(String href) {
    final base = Uri.tryParse(_base);
    if (base == null) return href;
    return base.resolve(href).toString();
  }

  bool _isAudio(String name) {
    final lower = name.toLowerCase();
    return AppConstants.audioExtensions
        .any((e) => lower.endsWith('.$e'));
  }

  Future<void> _connect() async {
    if (_base.isEmpty) {
      setState(() => _status = '先填服务器地址');
      return;
    }
    _save();
    setState(() {
      _busy = true;
      _status = '正在连接...';
    });
    try {
      final entries = await _propfind(_base);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _pathStack.clear();
        _status = '已连接，共 ${entries.length} 项';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '连接失败：${_friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDir(_WebDavEntry dir) async {
    final url = _resolve(dir.href);
    setState(() => _busy = true);
    try {
      final entries = await _propfind(url);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _pathStack.add(url);
        _status = '共 ${entries.length} 项';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '打开失败：${_friendlyError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _play(_WebDavEntry f) {
    final url = _resolve(f.href);
    final headers = <String, String>{};
    if (_authHeader.isNotEmpty) headers['Authorization'] = _authHeader;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NetworkAudioPage(
        url: url,
        headers: headers,
        title: f.name,
        subtitle: 'WebDAV',
      ),
    ));
  }

  String _friendlyError(Object e) {
    final msg = '$e';
    if (msg.contains('404')) return '地址错了（服务器返回 404），检查服务器地址';
    if (msg.contains('401') || msg.contains('403')) {
      return '账号或密码不对，检查账号和密码';
    }
    if (msg.contains('SocketException') ||
        msg.contains('timed out') ||
        msg.contains('Connection')) {
      return '连不上服务器，检查网络和地址';
    }
    return '请检查地址、账号和网络';
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        appBar: AppBar(title: const Text('WebDAV 播放')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV 播放'),
        leading: _pathStack.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () async {
                  _pathStack.removeLast();
                  final url =
                      _pathStack.isEmpty ? _base : _pathStack.last;
                  setState(() => _busy = true);
                  try {
                    final entries = await _propfind(url);
                    if (mounted) {
                      setState(() {
                        _entries = entries;
                        _status = '共 ${entries.length} 项';
                      });
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(
                          () => _status = '打开失败：${_friendlyError(e)}');
                    }
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
              ),
      ),
      body: ListView(
        padding: pagePadding(context, top: 12, bottom: 24),
        children: [
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://dav.jianguoyun.com/dav/',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(labelText: '账号'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _busy ? null : _connect,
                  child: const Text('连接'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _save();
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已保存')));
                  },
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(_status, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (_busy) const LinearProgressIndicator(),
          for (final e in _entries)
            ListTile(
              leading: Icon(
                e.isDir
                    ? Icons.folder_outlined
                    : Icons.audiotrack_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(e.name,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: e.isDir
                  ? const Icon(Icons.chevron_right, size: 18)
                  : const Icon(Icons.play_arrow, size: 20),
              onTap: () {
                if (e.isDir) {
                  _openDir(e);
                } else if (_isAudio(e.name)) {
                  _play(e);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('这个文件不是音频')));
                }
              },
            ),
        ],
      ),
    );
  }
}
