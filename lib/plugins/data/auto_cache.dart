import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/log/app_logger.dart';
import '../../core/utils/path_utils.dart';
import '../engine/plugin_engine.dart';
import '../model/plugin_source.dart';

/// 从源返回的播放结果里取出真实媒体地址（mp3/m4a/mp4 直链）。
/// 源返回的可能是纯字符串，也可能是 {url, headers, ...}。
String? extractMediaUrl(dynamic content) {
  if (content is String) {
    final u = content.trim();
    return u.isEmpty ? null : u;
  }
  if (content is Map) {
    for (final key in const <String>['url', 'audioUrl', 'playUrl', 'src']) {
      final v = content[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    // {url: {url: ...}} 这种嵌套也处理一下。
    final nested = content['url'];
    if (nested is Map) return extractMediaUrl(nested);
  }
  return null;
}

/// 从源返回的播放结果里取出请求头（有些站要带 Referer / Cookie 才给下）。
Map<String, String> extractMediaHeaders(dynamic content) {
  if (content is! Map) return <String, String>{};
  final out = <String, String>{};
  final headers = content['headers'];
  if (headers is Map) {
    headers.forEach((k, v) {
      if (v != null) out['$k'] = '$v';
    });
  }
  return out;
}

/// 自动缓存（只下直链音频，m3u8 不下；视频源与 isCacheable()==false 的源不下）。
/// 默认关，用户在设置里开；只在 WiFi 下才下（默认），下满上限删最旧的。
class AutoCache {
  final SharedPreferences _prefs;

  AutoCache(this._prefs);

  bool get enabled => _prefs.getBool(AppConstants.keyAutoCache) ?? false;

  /// 每本书最多缓存几集（默认 3）。
  int get countLimit =>
      _prefs.getInt(AppConstants.keyAutoCacheCount) ?? 3;

  /// 只在 WiFi 下缓存（默认开）。
  bool get wifiOnly =>
      _prefs.getBool(AppConstants.keyAutoCacheWifiOnly) ?? true;

  /// 缓存上限（MB，默认 500，超了删最旧的）。
  int get sizeLimitMb =>
      _prefs.getInt(AppConstants.keyAutoCleanLimit) ?? 500;

  Future<Directory> _cacheDir() async {
    final dir = Directory(
        p.join((await PathUtils.appFilesDir).path, 'audio_cache'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _fileName(String bookUrl, int chapterIndex) {
    final slug = bookUrl
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final short =
        slug.length > 40 ? slug.substring(slug.length - 40) : slug;
    return 'audio_${short}_$chapterIndex.mp3';
  }

  /// 某集的本地缓存路径（没下完返回 null）。
  Future<String?> cachedPathFor(String bookUrl, int chapterIndex) async {
    final f = File(p.join((await _cacheDir()).path,
        _fileName(bookUrl, chapterIndex)));
    return await f.exists() ? f.path : null;
  }

  /// 已缓存的章节地址（播放器播之前先问这里，有缓存直接播本地）。
  Future<List<String>> cachedChapterUrls(
      String bookUrl, List<Map<String, dynamic>> chapters) async {
    final out = <String>[];
    for (var i = 0; i < chapters.length; i++) {
      final path = await cachedPathFor(bookUrl, i);
      if (path != null) out.add(path);
    }
    return out;
  }

  /// 已缓存的集数。
  Future<int> cachedCount(String bookUrl) async {
    var n = 0;
    final dir = await _cacheDir();
    await for (final e in dir.list(followLinks: false)) {
      if (e is File && p.basename(e.path).contains('_')) n++;
    }
    return n;
  }

  /// 缓存总大小（字节）。
  Future<int> totalCacheSize() async {
    var total = 0;
    final dir = await _cacheDir();
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  /// 清掉全部音频缓存。
  Future<void> clearAllAudioCache() async {
    final dir = await _cacheDir();
    if (!await dir.exists()) return;
    await for (final e in dir.list(followLinks: false)) {
      try {
        await e.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// 超过上限删最旧的（按修改时间）。
  Future<void> enforceCountLimit() async {
    final dir = await _cacheDir();
    final files = <File>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is File) files.add(e);
    }
    files.sort((a, b) =>
        a.statSync().modified.compareTo(b.statSync().modified));
    var total = 0;
    for (final f in files) {
      total += await f.length();
    }
    final limitBytes = sizeLimitMb * 1024 * 1024;
    var i = 0;
    while ((files.length - i > countLimit || total > limitBytes) &&
        i < files.length) {
      final f = files[i];
      try {
        total -= await f.length();
        await f.delete();
      } catch (_) {}
      i++;
    }
  }

  /// 当前是不是 WiFi（用网络类型判断，拿不到就当不是）。
  Future<bool> isWifi() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final i in interfaces) {
        if (i.name.toLowerCase().contains('wlan') ||
            i.name.toLowerCase().contains('wifi')) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// 某集该不该预取：开关开着、是音频源、源允许缓存、还没下过、
  /// 不是 m3u8、WiFi 条件满足。
  Future<bool> shouldPrefetch({
    required PluginSource source,
    required String bookUrl,
    required int chapterIndex,
    required bool sourceCacheable,
  }) async {
    if (!enabled) return false;
    if (!source.isAudio) return false;
    if (!sourceCacheable) return false;
    if (await cachedPathFor(bookUrl, chapterIndex) != null) return false;
    if (wifiOnly && !await isWifi()) return false;
    return true;
  }

  /// 预取下一集（播放器在当前集播到一半时调）。
  /// [engine] 用来调源的 content 取真实地址；[lineId]/[voiceId] 传给源。
  Future<void> prefetch({
    required WidgetRef ref,
    required PluginEngine engine,
    required PluginSource source,
    required String bookUrl,
    required List<Map<String, dynamic>> chapters,
    required int currentIndex,
    String? lineId,
    String? voiceId,
  }) async {
    if (!enabled) return;
    if (!source.isAudio) return;
    try {
      final cacheable = await engine.isCacheable();
      if (!cacheable) return;
    } catch (_) {
      return;
    }
    final next = currentIndex + 1;
    if (next < 0 || next >= chapters.length) return;
    final chapter = chapters[next];
    final url = '${chapter['url'] ?? ''}';
    if (url.isEmpty) return;
    if (await cachedPathFor(bookUrl, next) != null) return;
    if (wifiOnly && !await isWifi()) return;
    try {
      final content = await engine.content(
          url: url, lineId: lineId, voiceId: voiceId);
      final mediaUrl = extractMediaUrl(content);
      if (mediaUrl == null) return;
      // m3u8 是分片流，下不了整文件，不预取。
      if (mediaUrl.toLowerCase().contains('.m3u8')) return;
      final headers = extractMediaHeaders(content);
      final resp = await http
          .get(Uri.parse(mediaUrl), headers: headers)
          .timeout(const Duration(seconds: 120));
      if (resp.statusCode != 200) return;
      final file = File(p.join((await _cacheDir()).path,
          _fileName(bookUrl, next)));
      await file.writeAsBytes(resp.bodyBytes);
      await enforceCountLimit();
      appLogger.info('自动缓存完成', detail: '${source.name} 第 ${next + 1} 集');
    } catch (e) {
      appLogger.warning('自动缓存失败', detail: '$e');
    }
  }

  /// 某本书的缓存阈值（MB）：默认按上限来，播放器组可按需改。
  int thresholdFor(String bookUrl) => sizeLimitMb;
}
