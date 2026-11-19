import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../features/audio/data/repository_providers.dart';
import '../../features/audio/domain/media_item.dart' as domain;
import '../../features/audio/presentation/audio_player_page.dart';
import '../../features/video/presentation/video_player_page.dart';
import '../presentation/network_audio_page.dart';
import '../presentation/source_search_page.dart';
import 'auto_cache.dart';
import 'plugin_providers.dart';

/// 插件源（JAR/JS）的一条断点记录：播的是哪个源的哪本书/视频、播到第几集/第几章、播到第几分第几秒。
///
/// 本地书库的断点走 LibraryRepository（数据库）；插件源不进书库，
/// 断点单独存在 SharedPreferences 里，一本书/一个视频只记一条。
class PluginResume {
  final String key; // sourceId|bookUrl
  final String sourceId;
  final String sourceName;
  final String bookTitle;
  final String bookUrl;
  final String coverUrl;
  final String chapterName;
  final String chapterUrl;
  final int chapterIndex;
  final int positionMs;
  final int durationMs;
  final String lineId;
  final String lineName;
  final String voiceId;
  final String type; // audio | video
  final int updatedAt; // epoch ms

  const PluginResume({
    required this.key,
    required this.sourceId,
    required this.sourceName,
    required this.bookTitle,
    required this.bookUrl,
    this.coverUrl = '',
    required this.chapterName,
    required this.chapterUrl,
    required this.chapterIndex,
    required this.positionMs,
    required this.durationMs,
    this.lineId = '',
    this.lineName = '',
    this.voiceId = '',
    required this.type,
    required this.updatedAt,
  });

  double get progress =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  bool get isAudio => type == AppConstants.typeAudio;

  /// 播完（进度 >= 95%）就不算断点了
  bool get finished => progress >= 0.95;

  Map<String, dynamic> toJson() => {
        'key': key,
        'sourceId': sourceId,
        'sourceName': sourceName,
        'bookTitle': bookTitle,
        'bookUrl': bookUrl,
        'coverUrl': coverUrl,
        'chapterName': chapterName,
        'chapterUrl': chapterUrl,
        'chapterIndex': chapterIndex,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'lineId': lineId,
        'lineName': lineName,
        'voiceId': voiceId,
        'type': type,
        'updatedAt': updatedAt,
      };

  static PluginResume? fromJson(Map<String, dynamic> j) {
    try {
      return PluginResume(
        key: '${j['key'] ?? ''}',
        sourceId: '${j['sourceId'] ?? ''}',
        sourceName: '${j['sourceName'] ?? ''}',
        bookTitle: '${j['bookTitle'] ?? ''}',
        bookUrl: '${j['bookUrl'] ?? ''}',
        coverUrl: '${j['coverUrl'] ?? ''}',
        chapterName: '${j['chapterName'] ?? ''}',
        chapterUrl: '${j['chapterUrl'] ?? ''}',
        chapterIndex: (j['chapterIndex'] as num?)?.toInt() ?? 0,
        positionMs: (j['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        lineId: '${j['lineId'] ?? ''}',
        lineName: '${j['lineName'] ?? ''}',
        voiceId: '${j['voiceId'] ?? ''}',
        type: '${j['type'] ?? AppConstants.typeAudio}',
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

String resumeKey(String sourceId, String bookUrl) => '$sourceId|$bookUrl';

/// 断点存储（SharedPreferences，最多记 10 条，按更新时间倒序）
class PluginResumeStore {
  static Future<List<PluginResume>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(AppConstants.keyPluginResumeList) ?? [];
    final out = <PluginResume>[];
    for (final s in raw) {
      try {
        final r = PluginResume.fromJson(
            jsonDecode(s) as Map<String, dynamic>);
        if (r != null && !r.finished) out.add(r);
      } catch (_) {}
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  static Future<PluginResume?> load(String key) async {
    final all = await loadAll();
    for (final r in all) {
      if (r.key == key) return r;
    }
    return null;
  }

  /// 保存一条断点（同 key 的旧记录被盖掉；播完的记录直接删掉）
  static Future<void> save(PluginResume r) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadAll();
    final next = <PluginResume>[];
    for (final e in all) {
      if (e.key != r.key) next.add(e);
    }
    if (!r.finished) {
      next.insert(0, r);
    }
    final trimmed = next.take(10).toList();
    await prefs.setStringList(
      AppConstants.keyPluginResumeList,
      trimmed.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  static Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadAll();
    final next = all.where((e) => e.key != key).toList();
    await prefs.setStringList(
      AppConstants.keyPluginResumeList,
      next.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  /// 清空全部断点（历史页“清空历史记录”时一起清）
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyPluginResumeList);
  }
}

// ---------------------------------------------------------------- 续播入口

/// 点“继续”卡片：直接从断点接着播（先向源要播放地址，再进播放页）
Future<void> openResume(
    BuildContext context, WidgetRef ref, PluginResume r) async {
  final source = await ref.read(sourceRepositoryProvider).byId(r.sourceId);
  if (source == null) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个源已经被删除了')));
    return;
  }
  try {
    final engine = engineForSource(ref, source);
    await engine.attach(source);
    final raw = await engine.invoke('content', params: {
      'url': r.chapterUrl,
      'voiceId': r.voiceId,
      'lineId': r.lineId,
    });
    final url = extractMediaUrl(raw);
    if (url.isEmpty) throw Exception('源没有返回可播放地址');
    final headers = extractMediaHeaders(raw);
    if (r.isAudio) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => NetworkAudioPage(
          url: url,
          headers: headers,
          title: r.chapterName,
          subtitle: r.bookTitle,
          sourceId: r.sourceId,
          bookName: r.bookTitle,
          coverUrl: r.coverUrl,
          startAt: Duration(milliseconds: r.positionMs),
          playlist: const [],
          startIndex: 0,
        ),
      ));
    } else {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
          path: url,
          network: true,
          headers: headers,
          title: '${r.bookTitle} · ${r.chapterName}',
          startAtMs: r.positionMs,
          currentLineId: r.lineId.isEmpty ? null : r.lineId,
        ),
      ));
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('续播失败：$e')));
  }
}

/// 中间大播放键 / 顶栏播放键：打开最近在播的那一条；什么都没播过就进空播放页
Future<void> openMostRecentResume(BuildContext context, WidgetRef ref) async {
  // 插件源断点（最新一条）
  final plugin = await PluginResumeStore.loadAll();
  // 本地书库断点（最新一条）
  domain.MediaItem? local;
  try {
    final audio = await ref
        .read(continueListProvider(AppConstants.typeAudio).future)
        .catchError((_) => <domain.MediaItem>[]);
    final video = await ref
        .read(continueListProvider(AppConstants.typeVideo).future)
        .catchError((_) => <domain.MediaItem>[]);
    final all = <domain.MediaItem>[...audio, ...video]..sort((a, b) {
        final x = a.lastReadAt ?? a.addedAt;
        final y = b.lastReadAt ?? b.addedAt;
        return y.compareTo(x);
      });
    if (all.isNotEmpty) local = all.first;
  } catch (_) {}

  final pluginAt =
      plugin.isEmpty ? 0 : plugin.first.updatedAt;
  final localAt = local == null
      ? 0
      : (local.lastReadAt ?? local.addedAt).millisecondsSinceEpoch;

  if (plugin.isEmpty && local == null) {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EmptyPlayerPage()));
    return;
  }
  if (pluginAt >= localAt) {
    await openResume(context, ref, plugin.first);
    return;
  }
  await openLocalItem(context, ref, local!);
}

/// 打开本地书库的一条（按保存的断点接着播）
Future<void> openLocalItem(
    BuildContext context, WidgetRef ref, domain.MediaItem item) async {
  final chapters =
      await ref.read(libraryRepositoryProvider).chapters(item.id);
  if (chapters.isEmpty) return;
  final progress =
      await ref.read(libraryRepositoryProvider).getProgress(item.id);
  if (item.isAudio) {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => AudioPlayerPage(
        item: item,
        initialChapterId: progress?.chapterId,
        initialPositionMs: progress?.positionMs,
      ),
    ));
  } else {
    final paths = chapters.map((c) => c.path!).toList();
    var startIndex = 0;
    if (progress?.chapterId != null) {
      final idx =
          chapters.indexWhere((c) => c.id == progress!.chapterId);
      if (idx >= 0) startIndex = idx;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoPlayerPage(
        path: paths[startIndex],
        playlist: paths,
        initialIndex: startIndex,
        title: item.title,
        startAtMs: progress?.positionMs ?? 0,
      ),
    ));
  }
}

/// 什么都没播过时打开的空播放页
class EmptyPlayerPage extends StatelessWidget {
  const EmptyPlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('播放器')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_circle_outline,
                  size: 72,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withOpacity(0.6)),
              const SizedBox(height: 18),
              const Text('还没有在播的内容',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text('搜一部喜欢的书或视频，播一半退出后会记在这里',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushReplacement(MaterialPageRoute(
                    builder: (_) => const SourceSearchPage(
                        type: AppConstants.typeAudio),
                  ));
                },
                icon: const Icon(Icons.search, size: 18),
                label: const Text('去找'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
