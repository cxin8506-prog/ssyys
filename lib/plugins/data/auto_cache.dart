import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/path_utils.dart';
import '../model/plugin_source.dart';
import 'plugin_providers.dart';

/// 从 content 返回里取播放地址（与详情页同一套规则）
String extractMediaUrl(dynamic r) {
  if (r == null) return '';
  if (r is String) return r.startsWith('http') ? r : '';
  if (r is Map) {
    for (final k in ['url', 'audioUrl', 'playUrl', 'src', 'mp3']) {
      final v = r[k];
      if (v != null && '$v'.startsWith('http')) return '$v';
    }
    for (final k in ['data', 'result', 'content']) {
      final v = r[k];
      if (v is Map) {
        final inner = extractMediaUrl(v);
        if (inner.isNotEmpty) return inner;
      }
    }
  }
  return '';
}

/// 从 content 返回里取播放请求头（没有就是空）
Map<String, String> extractMediaHeaders(dynamic r) {
  if (r is Map) {
    final h = r['headers'];
    if (h is Map) {
      return {for (final e in h.entries) '${e.key}': '${e.value}'};
    }
  }
  return const {};
}

/// 自动缓存：播完当前一集，自动把后面几集下载到本地。
/// 只下直链 mp4/mp3/m4a，m3u8（分段流）不下。默认关，不打开不偷偷缓存。
class AutoCache {
  static Future<Map<String, String>> _loadMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppConstants.keyAutoCacheMap) ?? '{}';
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: '${e.value}'};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveMap(Map<String, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyAutoCacheMap, jsonEncode(map));
  }

  static String cacheKey(String sourceId, String bookUrl, String chapterUrl) =>
      '$sourceId|$bookUrl|$chapterUrl';

  /// 这一集有没有缓存（文件还在才算）
  static Future<String?> cachedPathFor(
      String sourceId, String bookUrl, String chapterUrl) async {
    final map = await _loadMap();
    final key = cacheKey(sourceId, bookUrl, chapterUrl);
    final p = map[key];
    if (p == null || p.isEmpty) return null;
    if (!File(p).existsSync()) {
      map.remove(key);
      await _saveMap(map);
      return null;
    }
    return p;
  }

  /// 这本书已经缓存了哪些集（章节地址集合，供选集列表标下载图标）
  static Future<Set<String>> cachedChapterUrls(
      String sourceId, String bookUrl) async {
    final map = await _loadMap();
    final prefix = '$sourceId|$bookUrl|';
    final out = <String>{};
    for (final k in map.keys) {
      if (k.startsWith(prefix)) out.add(k.substring(prefix.length));
    }
    return out;
  }

  /// 是不是 WiFi（按网卡名判断：wlan 开头的接口在线）
  static Future<bool> isWifi() async {
    try {
      final ifs = await NetworkInterface.list();
      return ifs.any((i) => i.name.startsWith('wlan'));
    } catch (_) {
      return true;
    }
  }

  static String? _extOf(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.mp4')) return '.mp4';
    if (path.endsWith('.mp3')) return '.mp3';
    if (path.endsWith('.m4a')) return '.m4a';
    return null; // m3u8 / 未知格式不下
  }

  static int _stableHash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = ((h * 31) + c) & 0x7fffffff;
    }
    return h;
  }

  static Future<String?> _download(
      String url, Map<String, String> headers, Directory dir, String name) async {
    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      headers.forEach(req.headers.set);
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final file = File('${dir.path}/$name');
      final sink = file.openWrite();
      await resp.pipe(sink);
      await sink.close();
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 播完当前一集后，后台预取后面 count 集（不阻塞播放，失败就跳过）
  static Future<void> prefetch({
    required WidgetRef ref,
    required PluginSource source,
    required String bookUrl,
    required List<Map<String, dynamic>> chapters,
    required int currentIndex,
    String? lineId,
    String? voiceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(AppConstants.keyAutoCache) ?? false)) return;
    final count = prefs.getInt(AppConstants.keyAutoCacheCount) ?? 1;
    final wifiOnly = prefs.getBool(AppConstants.keyAutoCacheWifiOnly) ?? true;
    if (wifiOnly && !await isWifi()) return;
    final limitMb = prefs.getInt(AppConstants.keyCacheLimitMb) ?? 512;
    final dir = await PathUtils.cacheDir;
    final cacheDir = Directory('${dir.path}/autocache');
    if (!cacheDir.existsSync()) cacheDir.createSync(recursive: true);
    var used = 0;
    await for (final e in cacheDir.list()) {
      if (e is File) used += await e.length();
    }
    if (used > limitMb * 1024 * 1024) return;

    final engine = engineForSource(ref, source);
    final map = await _loadMap();
    for (var i = currentIndex + 1;
        i <= currentIndex + count && i < chapters.length;
        i++) {
      final chapterUrl = '${chapters[i]['url']}';
      if (chapterUrl.isEmpty) continue;
      final key = cacheKey(source.id, bookUrl, chapterUrl);
      if (map.containsKey(key)) continue;
      try {
        await engine.attach(source);
        final raw = await engine.invoke('content', params: {
          'url': chapterUrl,
          'voiceId': voiceId,
          'lineId': lineId,
        });
        final url = extractMediaUrl(raw);
        if (url.isEmpty) continue;
        final ext = _extOf(url);
        if (ext == null) continue;
        final name = '${_stableHash(chapterUrl)}$ext';
        final path = await _download(
            url, extractMediaHeaders(raw), cacheDir, name);
        if (path != null) map[key] = path;
      } catch (_) {
        // 某一集下不下来就跳过，不影响播放
      }
    }
    await _saveMap(map);
  }
}
