import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../features/audio/data/repository_providers.dart';
import '../../features/video/presentation/video_player_page.dart';
import '../data/auto_cache.dart';
import '../data/home_feed.dart';
import '../data/plugin_providers.dart';
import '../data/plugin_resume.dart';
import '../model/plugin_source.dart';
import 'network_audio_page.dart';

/// 点列表里的一个片名弹出来的详情卡（我的听书的样子）：
/// 左边海报，右边片名/年份/地区/状态，下面是「取消」「添加收藏」「开始播放」，
/// 不是整页跳转到详情页。点「开始播放」直接进播放页。
Future<void> showSourceDetailDialog(
  BuildContext context,
  WidgetRef ref, {
  required PluginSource source,
  required FeedBook book,
}) async {
  var busy = false;
  await showDialog<void>(
    context: context,
    // 正在拿播放地址时不让点外面误关，拿完按钮恢复
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: book.cover.startsWith('http')
                  ? Image.network(book.cover,
                      width: 72,
                      height: 96,
                      fit: BoxFit.cover,
                      cacheWidth: 144,
                      cacheHeight: 192,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_, __, ___) =>
                          _coverPlaceholder(ctx, book.title))
                  : _coverPlaceholder(ctx, book.title),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  if (book.author.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(book.author,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(ctx).textTheme.bodySmall),
                  ],
                  if (book.intro.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(book.intro,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(ctx)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 11, height: 1.4)),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    final added =
                        await _addFavorite(ctx, ref, source, book);
                    if (added) Navigator.pop(ctx);
                  },
            child: const Text('添加收藏'),
          ),
          ElevatedButton(
            onPressed: busy
                ? null
                : () async {
                    setDialog(() => busy = true);
                    final ok = await _startPlayback(context, ref, source,
                        book,
                        onClose: () => Navigator.pop(ctx));
                    if (!ok) setDialog(() => busy = false);
                  },
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('开始播放'),
          ),
        ],
      ),
    ),
  );
}

Widget _coverPlaceholder(BuildContext context, String title) {
  return Container(
    width: 72,
    height: 96,
    color: context.palette.surfaceAlt,
    alignment: Alignment.center,
    child: Text(title.isEmpty ? '?' : title.characters.first,
        style: TextStyle(color: context.subtleColor, fontSize: 22)),
  );
}

/// 添加收藏：没有自定义分组就直接加到「默认」；建了自定义分组就弹小列表让用户选。
/// 返回 true 表示已加上（外层关框），false 表示用户取消了选择（框留着）。
Future<bool> _addFavorite(BuildContext context, WidgetRef ref,
    PluginSource source, FeedBook book) async {
  final prefs = ref.read(sharedPrefsProvider);
  final custom = prefs.getStringList('favorite_custom_groups') ?? [];
  String group = '默认';
  if (custom.isNotEmpty) {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('加到哪个分组'),
        children: [
          for (final g in ['默认', ...custom])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g),
              child: Text(g, style: const TextStyle(fontSize: 15)),
            ),
        ],
      ),
    );
    if (picked == null) return false;
    group = picked;
  }
  await ref.read(libraryRepositoryProvider).savePluginFavorite(
        sourceId: source.id,
        bookUrl: book.url,
        title: book.title,
        author: book.author,
        coverUrl: book.cover,
        type: source.type,
        group: group,
      );
  ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已加到 $group 分组')));
  return true;
}

class _Media {
  final String url;
  final Map<String, String> headers;
  const _Media(this.url, this.headers);
}

String _extractUrl(dynamic r) {
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
        final inner = _extractUrl(v);
        if (inner.isNotEmpty) return inner;
      }
    }
  }
  return '';
}

Map<String, String> _extractHeaders(dynamic r) {
  if (r is Map) {
    final h = r['headers'];
    if (h is Map) {
      return {for (final e in h.entries) '${e.key}': '${e.value}'};
    }
  }
  return const {};
}

List<Map<String, dynamic>> _normalizeChapters(dynamic raw) {
  if (raw == null) return [];
  final list = raw is List ? raw : (raw is Map ? [raw] : <dynamic>[]);
  final out = <Map<String, dynamic>>[];
  for (var i = 0; i < list.length; i++) {
    final e = list[i];
    if (e is Map) {
      out.add({
        'name': '${e['name'] ?? e['title'] ?? e['chapterName'] ?? '第${i + 1}章'}',
        'url': '${e['url'] ?? e['chapterUrl'] ?? e['id'] ?? ''}',
      });
    } else if (e != null) {
      out.add({'name': '$e', 'url': '$e'});
    }
  }
  return out;
}

List<Map<String, dynamic>> _normalizeOptions(dynamic raw) {
  if (raw == null) return [];
  final out = <Map<String, dynamic>>[];
  if (raw is List) {
    for (var i = 0; i < raw.length; i++) {
      final e = raw[i];
      if (e is Map) {
        out.add({
          'id': '${e['id'] ?? e['key'] ?? i}',
          'name': '${e['name'] ?? e['title'] ?? '选项${i + 1}'}',
        });
      } else if (e != null) {
        out.add({'id': '$i', 'name': '$e'});
      }
    }
  } else if (raw is Map) {
    raw.forEach((k, v) => out.add({'id': '$k', 'name': '$v'}));
  }
  return out;
}

/// 开始播放：先拿目录（不断点续播），再拿播放地址，地址到手直接进播放页，
/// 不要在播放页里长时间转圈。失败返回 false，弹框留着给用户重试。
Future<bool> _startPlayback(
    BuildContext context, WidgetRef ref, PluginSource source, FeedBook book,
    {int startIndex = -1, VoidCallback? onClose}) async {
  try {
    final engine = engineForSource(ref, source);
    await engine.attach(source);
    final cfg =
        await ref.read(sourceConfigRepositoryProvider).load(source.id, source.type);

    dynamic detail;
    try {
      detail = await engine.invoke('detail', params: {'url': book.url});
    } catch (_) {}
    dynamic chapters;
    try {
      chapters = await engine.invoke('chapters', params: {'url': book.url});
    } catch (_) {}
    if (chapters == null && detail is Map) chapters = detail['chapters'];
    final list = _normalizeChapters(chapters);
    if (list.isEmpty) {
      _toast(context, '这个源没有返回目录');
      return false;
    }
    var index = startIndex;
    if (index < 0) {
      final resume =
          await PluginResumeStore.load(resumeKey(source.id, book.url));
      index = (resume != null && resume.chapterIndex < list.length)
          ? resume.chapterIndex
          : 0;
    }
    if (index < 0 || index >= list.length) index = 0;
    final resumeMs = await _resumeMs(source.id, book.url, index);

    var voices = cfg.voices;
    var voiceId = cfg.selectedVoiceId;
    var lines = cfg.lines;
    var lineId = cfg.selectedLineId;
    if (voices.isEmpty && source.isAudio) {
      try {
        voices = _normalizeOptions(
            await engine.invoke('voices', params: {'url': book.url}));
        voiceId ??= voices.isNotEmpty ? '${voices.first['id']}' : null;
      } catch (_) {}
    }
    if (lines.isEmpty && !source.isAudio) {
      try {
        lines = _normalizeOptions(
            await engine.invoke('lines', params: {'url': book.url}));
        lineId ??= lines.isNotEmpty ? '${lines.first['id']}' : null;
      } catch (_) {}
    }

    Future<_Media> resolve(int i, String? vId, String? lId) async {
      final r = await engine.invoke('content', params: {
        'url': '${list[i]['url']}',
        'voiceId': vId,
        'lineId': lId,
      });
      return _Media(_extractUrl(r), _extractHeaders(r));
    }

    final chapterUrl = '${list[index]['url']}';
    final cached =
        await AutoCache.cachedPathFor(source.id, book.url, chapterUrl);
    final isAudio = source.isAudio;
    final chapterNames = list.map((e) => '${e['name']}').toList();

    Future<void> openPlayer(String url, Map<String, String> headers) async {
      // 地址到手先关弹框，再进播放页（关框晚了会把播放页一起弹掉）
      onClose?.call();
      if (isAudio) {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => NetworkAudioPage(
            url: url,
            headers: headers,
            title: '${list[index]['name']}',
            subtitle: book.title,
            sourceId: source.id,
            sourceName: source.name,
            bookName: book.title,
            bookUrl: book.url,
            startAt: Duration(milliseconds: resumeMs),
            coverUrl: book.cover,
            chapterUrl: chapterUrl,
            lineId: lineId ?? '',
            voiceId: voiceId ?? '',
            playlist: chapterNames,
            startIndex: index,
            voices: voices,
            currentVoiceId: voiceId,
            onSwitchVoice: (newVoiceId) async {
              voiceId = newVoiceId;
              try {
                final cfg2 = await ref
                    .read(sourceConfigRepositoryProvider)
                    .load(source.id, source.type);
                cfg2.voices = voices;
                cfg2.selectedVoiceId = newVoiceId;
                cfg2.values['voiceId'] = newVoiceId;
                await ref
                    .read(sourceConfigRepositoryProvider)
                    .save(cfg2);
              } catch (_) {}
              final m = await resolve(index, newVoiceId, lineId);
              return m.url;
            },
            onCacheThreshold: () => AutoCache.prefetch(
              ref: ref,
              source: source,
              bookUrl: book.url,
              chapters: list,
              currentIndex: index,
              lineId: lineId,
              voiceId: voiceId,
            ),
            onNext: (i) =>
                _startPlayback(context, ref, source, book, startIndex: i),
          ),
        ));
      } else {
        String lineName = '';
        for (final l in lines) {
          if ('${l['id']}' == lineId) {
            lineName = '${l['name'] ?? ''}';
            break;
          }
        }
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VideoPlayerPage(
            path: url,
            network: true,
            headers: headers,
            title: '${book.title} · ${list[index]['name']}',
            startAtMs: resumeMs,
            sourceId: source.id,
            sourceName: source.name,
            bookUrl: book.url,
            bookTitle: book.title,
            chapterNames: chapterNames,
            lineName: lineName,
            voiceId: voiceId ?? '',
            lines: [
              for (final l in lines)
                {'id': '${l['id']}', 'name': '${l['name'] ?? l['id']}'}
            ],
            currentLineId: lineId,
            onSwitchLine: (newLineId) async {
              final m = await resolve(index, voiceId, newLineId);
              return m.url;
            },
          ),
        ));
      }
    }

    if (cached != null) {
      await openPlayer(cached, const {});
      return true;
    }
    final media = await resolve(index, voiceId, lineId);
    if (media.url.isEmpty) {
      _toast(context, '源没有返回可播放地址');
      return false;
    }
    await openPlayer(media.url, media.headers);
    return true;
  } catch (e) {
    _toast(context, '拿播放地址失败：$e');
    return false;
  }
}

Future<int> _resumeMs(String sourceId, String bookUrl, int index) async {
  try {
    final resume = await PluginResumeStore.load(resumeKey(sourceId, bookUrl));
    if (resume != null && resume.chapterIndex == index) {
      return resume.positionMs;
    }
  } catch (_) {}
  return 0;
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 3),
  ));
}
