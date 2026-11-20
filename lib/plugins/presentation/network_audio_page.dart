import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:local_media_app/core/database/library_repository.dart';
import 'package:local_media_app/features/audio/data/audio_handler.dart';
import 'package:local_media_app/plugins/data/plugin_resume.dart';

String _fmtMs(int ms) {
  final d = Duration(milliseconds: ms);
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 向源解析出来的可播地址（url + 请求头），切章/切音色时向源要。
class ResolvedChapterMedia {
  final String url;
  final Map<String, String> headers;
  const ResolvedChapterMedia(this.url, [this.headers = const {}]);
}

/// 网络音频播放页（插件源直接播放 URL）。
///
/// 播放底座是共享的 [MyAudioHandler]（audio_service 前台服务）：
/// 退出来、锁屏、切 App 都继续播，通知栏能控制，断点由 handler 每 5 秒
/// 调回调写插件断点（plugin_resume）。页面只是遥控器，
/// 退出时不停播、不销毁播放器。
/// 切章要现向源解析地址（onResolveChapter），解析失败报人话错，不静默吞掉。
/// WebDAV 单文件播放时不断点、不写到别的书上（没有书身份就清掉插件会话）。
class NetworkAudioPage extends ConsumerStatefulWidget {
  final String url;

  /// 播放这个地址要带的请求头（Referer/UA 等），没有就是空
  final Map<String, String> headers;
  final String title;
  final String subtitle;
  final List<String> playlist;
  final int startIndex;
  final void Function(int index)? onNext;

  /// 各章的源地址（下标和 playlist 对齐）：断点里要存当前章的地址，
  /// 续播时才能直接向源要地址。没有就用 chapterUrl 兜底。
  final List<String> chapterUrls;

  /// 切章时向源要地址（参数：章下标），返回可播地址+请求头；
  /// 解析失败返回 null。没有它就走老路：弹回上层，让调用方重新解析再进页。
  final Future<ResolvedChapterMedia?> Function(int index)? onResolveChapter;

  /// 断点归属信息
  final String sourceId;
  final String sourceName;
  final String bookName;
  final String bookUrl;

  /// 断点续播：从这个位置接着播（默认从头）
  final Duration startAt;

  /// 真实封面（有就显示封面，没有才显示渐变占位）
  final String coverUrl;

  /// 断点用的线路/音色信息（没有就空着）
  final String chapterUrl;
  final String lineId;
  final String lineName;
  final String voiceId;

  /// 可切换的音色：[{id, name}]，没有就不显示音色按钮
  final List<Map<String, dynamic>> voices;
  final String? currentVoiceId;

  /// 切音色时向源要新地址（参数：音色 id），返回新播放地址
  final Future<String> Function(String voiceId)? onSwitchVoice;

  /// 播到缓存频率阈值时回调一次（触发自动缓存后续章节）
  final VoidCallback? onCacheThreshold;

  const NetworkAudioPage({
    super.key,
    required this.url,
    this.headers = const {},
    required this.title,
    this.subtitle = '',
    this.playlist = const [],
    this.startIndex = 0,
    this.onNext,
    this.chapterUrls = const [],
    this.onResolveChapter,
    this.sourceId = '',
    this.sourceName = '',
    this.bookName = '',
    this.bookUrl = '',
    this.startAt = Duration.zero,
    this.coverUrl = '',
    this.chapterUrl = '',
    this.lineId = '',
    this.lineName = '',
    this.voiceId = '',
    this.voices = const [],
    this.currentVoiceId,
    this.onSwitchVoice,
    this.onCacheThreshold,
  });

  @override
  ConsumerState<NetworkAudioPage> createState() => _NetworkAudioPageState();
}

class _NetworkAudioPageState extends ConsumerState<NetworkAudioPage> {
  /// 进度只刷进度条本身：positionStream 只更新这个 ValueNotifier，
  /// Slider + 时间行包在 ValueListenableBuilder 里，不整页 setState
  final _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  Duration _duration = Duration.zero;
  String? _voiceId;
  bool _cacheFired = false;
  double _speed = 1.0;
  bool _ready = false;
  String? _error;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<double>? _speedSub;
  bool _playing = false;

  /// 当前在播的是播放列表里第几章（onNext 老路用 startIndex，这里自己记）
  int _currentIndex = 0;

  /// 正在解析切章：播完自动切和手动点下一章别重叠
  bool _switchingChapter = false;

  /// 断点续播开关（进页时读一次存下来：回调在页面退出后还可能被 handler 调到，
  /// 那时 ref 已经不能用了）
  bool _resumeEnabled = true;

  /// 断点节流：上次写断点的位置（毫秒），5 秒写一次
  int _lastResumeSavedMs = -1;

  /// 切章解析时拿到的请求头（下标 → 头）：onResolveChapter 一次解析里
  /// 同时拿到地址和头，头先存这里，handler 要播时再取。
  final Map<int, Map<String, String>> _resolvedHeaders =
      <int, Map<String, String>>{};

  // 定时关闭：还剩多久就停（显示用倒计时，实际停止由 handler 的定时器负责）
  Timer? _sleepTimer;
  Duration? _sleepLeft;

  /// 播到章末停是否开着（和倒计时二选一）
  bool _sleepEndOfEpisode = false;

  String get _resumeKey => resumeKey(widget.sourceId, widget.bookUrl);

  String get _bookmarkItemId => '${widget.sourceId}|${widget.bookName}';

  MyAudioHandler get _handler => ref.read(audioHandlerProvider);

  @override
  void initState() {
    super.initState();
    _voiceId = widget.currentVoiceId;
    _currentIndex = widget.startIndex;
    _load();
  }

  /// 插件源断点回调（handler 每 5 秒 / 暂停 / 切章 / 播完时调）：
  /// 节流 5 秒写一次（Tsacdop 的做法），force=true 的最后一次保存不节流。
  /// 位置变化 <5000ms 不写盘。
  void _onPluginProgress(
      int chapterIndex, int positionMs, int durationMs, bool force) {
    if (!force && (positionMs - _lastResumeSavedMs).abs() < 5000) return;
    _lastResumeSavedMs = positionMs;
    unawaited(_saveResumeAt(chapterIndex, positionMs, durationMs));
  }

  /// 把当前进度存成断点（“继续”区和历史页都靠它；关了断点续播就不存）。
  /// WebDAV 单文件（没有 sourceId/bookUrl）不存，免得写到别的书上。
  Future<void> _saveResumeAt(
      int index, int positionMs, int durationMs) async {
    if (widget.sourceId.isEmpty || widget.bookUrl.isEmpty) return;
    if (!_resumeEnabled) return;
    if (positionMs <= 0) return;
    final chapterName = index >= 0 && index < widget.playlist.length
        ? widget.playlist[index]
        : widget.title;
    await savePluginResume(
      _resumeKey,
      chapterIndex: index,
      positionMs: positionMs,
      durationMs: durationMs,
      type: 'audio',
      title: widget.bookName,
      chapterTitle: chapterName,
      voiceId: _voiceId,
    );
  }

  MediaItem _mediaItemFor(int index) {
    final title = index >= 0 && index < widget.playlist.length
        ? widget.playlist[index]
        : widget.title;
    final id = index >= 0 && index < widget.chapterUrls.length
        ? widget.chapterUrls[index]
        : (widget.chapterUrl.isNotEmpty ? widget.chapterUrl : widget.url);
    return MediaItem(
      id: id,
      title: title,
      album: widget.subtitle,
      artUri: widget.coverUrl.startsWith('http')
          ? Uri.tryParse(widget.coverUrl)
          : null,
    );
  }

  Future<void> _load() async {
    final handler = _handler;
    // 通知栏切章：页面退出后还留着（后台听的时候通知栏点下一章还能解析着播），
    // 下次进插件播放页会被新的回调覆盖，切回本地书时 handler.setQueue/setUris 会清掉。
    // 回调里只碰 handler 和解析器，不碰 context/ref（页面退出后它们不能用了），
    // 报错提示和 setState 都拿 mounted 守着。
    handler.onPluginSkipNext = () async => _goToChapter(_currentIndex + 1);
    handler.onPluginSkipPrevious =
        () async => _goToChapter(_currentIndex - 1);
    _posSub = handler.positionStream.listen((p) {
      _positionNotifier.value = p;
      // 缓存频率阈值：正在播、播到阈值（30%）才触发一次自动缓存
      if (!_cacheFired &&
          widget.onCacheThreshold != null &&
          _playing &&
          _duration > Duration.zero) {
        if (p.inMilliseconds / _duration.inMilliseconds >= 0.3) {
          _cacheFired = true;
          widget.onCacheThreshold!();
        }
      }
    });
    _durSub = handler.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    _stateSub = handler.playerStateStream.listen((s) {
      if (mounted) setState(() => _playing = s.playing);
      if (s.processingState == ProcessingState.completed) {
        // 播到章末停开着就停住，不自动切下一集（handler 里已经暂停了）
        if (_sleepEndOfEpisode) {
          _sleepEndOfEpisode = false;
          return;
        }
        // 播完自动切下一章：解析失败往后再试两章（auto=true）
        _goToChapter(_currentIndex + 1, auto: true);
      }
    });
    _speedSub = handler.speedStream.listen((v) {
      if (mounted) setState(() => _speed = v);
    });
    try {
      try {
        final repo = ref.read(libraryRepositoryProvider);
        _resumeEnabled = await repo.getBool('resume_enabled') ?? true;
      } catch (_) {}
      if (widget.sourceId.isNotEmpty && widget.bookUrl.isNotEmpty) {
        // 有书身份：先搭插件书（setPluginBook 里会把上一本书的断点存了，
        // 用的是旧回调），再挂新回调和解析器，最后起播。
        final chapters = List<Map<String, dynamic>>.generate(
          widget.playlist.isEmpty ? 1 : widget.playlist.length,
          (i) => <String, dynamic>{
            'title': widget.playlist.isEmpty
                ? widget.title
                : widget.playlist[i],
            'url': i < widget.chapterUrls.length
                ? widget.chapterUrls[i]
                : widget.chapterUrl,
          },
        );
        await handler.setPluginBook(
          bookKey: _resumeKey,
          sourceId: widget.sourceId,
          bookUrl: widget.bookUrl,
          title: widget.bookName.isNotEmpty ? widget.bookName : widget.title,
          coverUrl: widget.coverUrl.isEmpty ? null : widget.coverUrl,
          chapters: chapters,
          initialIndex: widget.startIndex,
        );
        handler.onPluginProgress = _onPluginProgress;
        handler.onResolveChapter = (i) async {
          final media = await widget.onResolveChapter?.call(i);
          if (media != null) {
            _resolvedHeaders[i] = media.headers;
            return media.url;
          }
          return null;
        };
        handler.onResolveHeaders = (i) =>
            _resolvedHeaders[i] ??
            (i == widget.startIndex ? widget.headers : const <String, String>{});
        // 进页时这个地址已经解析好了，先写进缓存，免得重播当前集又解析一次。
        handler.cacheChapterUrl(widget.startIndex, widget.url);
        await handler.playPluginChapter(
          widget.startIndex,
          startAt: widget.startAt,
        );
      } else {
        // 没书身份（比如 WebDAV 单文件）：清掉上一个插件会话，
        // 别让断点写到别的书上；直接播地址，不建书不断点。
        handler.clearPluginBook();
        await handler.playSingleUrl(
          item: _mediaItemFor(widget.startIndex),
          url: widget.url,
          headers: widget.headers,
          startAt: widget.startAt,
        );
      }
      _speed = handler.player.speed;
      if (mounted) setState(() => _ready = true);
      _applySleepDefault();
    } catch (e) {
      if (mounted) {
        setState(() {
          _ready = true;
          _error = '$e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_humanizeError(e))),
        );
      }
    }
  }

  String _humanizeError(Object e) {
    final s = '$e';
    if (s.contains('音频文件已失效')) return '音频文件已失效';
    if (s.contains('可能需要登录或已下架')) return '可能需要登录或已下架';
    return kPlaybackErrorToast;
  }

  /// 睡眠定时默认值：0=不设置；-1=播到章末停；大于 0=多少分钟后停
  Future<void> _applySleepDefault() async {
    int def = 0;
    try {
      final repo = ref.read(libraryRepositoryProvider);
      def = await repo.getInt('sleep_timer_default') ?? 0;
    } catch (_) {}
    if (def == -1) {
      _handler.setSleepTimer(untilChapterEnd: true);
      if (mounted) setState(() => _sleepEndOfEpisode = true);
    } else if (def > 0) {
      _handler.setSleepTimer(minutes: def);
      _startSleepCountdown(def);
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _speedSub?.cancel();
    _sleepTimer?.cancel();
    _positionNotifier.dispose();
    // 不停播、不销毁播放器：播放留在共享 handler 里继续（退出来、锁屏都接着播）。
    // 通知栏切章回调故意留着（见 _load 里的注释）。
    // 退出前最后存一次断点（不经过节流）；还没播起来（_ready=false，
    // 比如刚进页就退出）就不存，免得把别的书的位置写到这本书上。
    if (_ready) {
      unawaited(_saveResumeAt(
        _currentIndex,
        _handler.player.position.inMilliseconds,
        _duration.inMilliseconds,
      ));
    }
    super.dispose();
  }

  /// 切到第 i 章：先向源解析地址，拿到才切。
  /// auto=true 是播完自动切：解析失败报一声，往后再试两章（最多试 3 章），
  /// 都失败就停住报错；手动点的只报一次错，不自动跳章。
  Future<void> _playChapter(int index, {bool auto = false}) async {
    if (_switchingChapter) return;
    if (index < 0 || index >= widget.playlist.length) return;
    final resolver = widget.onResolveChapter;
    if (resolver == null) return;
    _switchingChapter = true;
    var i = index;
    var attempts = 0;
    String? firstError;
    try {
      while (i >= 0 && i < widget.playlist.length && attempts < 3) {
        attempts++;
        try {
          final media = await resolver(i);
          if (media == null || media.url.isEmpty) {
            throw Exception('源没有返回可播放地址');
          }
          // 这一章之前听到一半：从断点接着播
          var startAtMs = 0;
          try {
            final r = await getPluginResume(_resumeKey);
            if (r != null &&
                (r['chapterIndex'] as num?)?.toInt() == i) {
              startAtMs = (r['positionMs'] as num?)?.toInt() ?? 0;
            }
          } catch (_) {}
          _resolvedHeaders[i] = media.headers;
          _handler.cacheChapterUrl(i, media.url);
          await _handler.playPluginChapter(
            i,
            startAt: Duration(milliseconds: startAtMs),
          );
          // 切章成功：断点节流从新章重新算，缓存阈值重新算
          _lastResumeSavedMs = startAtMs;
          _cacheFired = false;
          if (mounted) {
            setState(() {
              _currentIndex = i;
              _error = null;
            });
          }
          if (firstError != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('第 ${index + 1} 集播不了，已跳到第 ${i + 1} 集')));
          }
          return;
        } catch (e) {
          firstError ??= '$e';
          if (!auto) break;
          // 自动切章：这集拿不到地址，试下一集
          i++;
        }
      }
      // 3 次都失败（或手动点的一次失败）：报人话错，留在当前章，不静默吞掉
      if (mounted) {
        setState(() => _error = '拿播放地址失败：$firstError');
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('拿播放地址失败：$firstError')));
      }
    } finally {
      _switchingChapter = false;
    }
  }

  /// 去第 i 章：有解析器就在页内切章，没有就走老路——
  /// 弹回上层，让调用方重新解析再进页。
  void _goToChapter(int i, {bool auto = false}) {
    if (i < 0 || i >= widget.playlist.length || i == _currentIndex) return;
    if (widget.onResolveChapter != null) {
      _playChapter(i, auto: auto);
    } else if (widget.onNext != null) {
      if (mounted) Navigator.of(context).pop();
      widget.onNext!(i);
    }
  }

  void _next() => _goToChapter(_currentIndex + 1);

  void _prev() => _goToChapter(_currentIndex - 1);

  /// 定时关闭：到时间自动暂停，页面上显示倒计时。
  /// 实际停止由 handler 的定时器负责，这里只管倒计时显示。
  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    if (minutes <= 0) {
      _handler.cancelSleepTimer();
      setState(() {
        _sleepEndOfEpisode = false;
        _sleepLeft = null;
      });
      return;
    }
    _handler.setSleepTimer(minutes: minutes);
    setState(() => _sleepEndOfEpisode = false);
    _startSleepCountdown(minutes);
  }

  /// 倒计时显示：每秒减一，到 0 只清显示（handler 那边已经停了）
  void _startSleepCountdown(int minutes) {
    _sleepTimer?.cancel();
    setState(() => _sleepLeft = Duration(minutes: minutes));
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      final left = (_sleepLeft ?? Duration.zero) - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        t.cancel();
        setState(() => _sleepLeft = null);
      } else {
        setState(() => _sleepLeft = left);
      }
    });
  }

  void _showSleepSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ListTile(title: Text('定时关闭')),
            for (final m in <int>[5, 15, 30, 60])
              ListTile(
                title: Text('$m 分钟后停止'),
                trailing: _sleepLeft?.inMinutes == m
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _setSleepTimer(m);
                },
              ),
            ListTile(
              title: const Text('自定义分钟数…'),
              onTap: () {
                Navigator.pop(context);
                _pickCustomSleepMinutes();
              },
            ),
            ListTile(
              title: const Text('播到本集末停'),
              trailing: _sleepEndOfEpisode ? const Icon(Icons.check) : null,
              onTap: () {
                Navigator.pop(context);
                _sleepTimer?.cancel();
                _handler.setSleepTimer(untilChapterEnd: true);
                setState(() {
                  _sleepLeft = null;
                  _sleepEndOfEpisode = true;
                });
              },
            ),
            ListTile(
              title: const Text('播完 3 集停'),
              onTap: () {
                Navigator.pop(context);
                _sleepTimer?.cancel();
                _handler.setSleepTimer(episodes: 3);
                setState(() => _sleepLeft = null);
              },
            ),
            ListTile(
              title: const Text('取消定时'),
              onTap: () {
                Navigator.pop(context);
                _setSleepTimer(0);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 自定义定时分钟数（1–240 分钟）
  Future<void> _pickCustomSleepMinutes() async {
    final controller = TextEditingController();
    final min = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义定时'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入分钟数（1–240）',
            suffixText: '分钟',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v != null && v >= 1 && v <= 240) Navigator.pop(ctx, v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (min == null || !mounted) return;
    _setSleepTimer(min);
  }

  /// 书签列表：点一行跳到那个位置，长按删
  Future<void> _showBookmarks() async {
    final repo = ref.read(libraryRepositoryProvider);
    List<dynamic> list = <dynamic>[];
    try {
      list = await repo.getBookmarks(_bookmarkItemId) as List<dynamic>;
    } catch (_) {}
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.6,
            child: Column(
              children: <Widget>[
                ListTile(
                  title: const Text('书签'),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.bookmark_add, size: 18),
                    label: const Text('加书签'),
                    onPressed: () async {
                      final pos =
                          _handler.player.position.inMilliseconds;
                      try {
                        await repo.saveBookmark(
                          bookId: _bookmarkItemId,
                          chapterUrl: _currentChapterUrl(),
                          positionMs: pos,
                          note: widget.title,
                        );
                        final fresh = await repo.getBookmarks(
                            _bookmarkItemId) as List<dynamic>;
                        setSheet(() {
                          list.clear();
                          list.addAll(fresh);
                        });
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('保存书签失败：$e')),
                          );
                        }
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: list.isEmpty
                      ? const Center(
                          child: Text('还没有书签，听到想留的地方点“加书签”'))
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final dynamic b = list[i];
                            String note = '';
                            int posMs = 0;
                            try {
                              note = '${b.note ?? ''}';
                              posMs = (b.positionMs as int?) ?? 0;
                            } catch (_) {}
                            return ListTile(
                              leading:
                                  const Icon(Icons.bookmark, size: 20),
                              title: Text(
                                  note.isEmpty ? widget.title : note,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(_fmtMs(posMs)),
                              onTap: () {
                                Navigator.pop(context);
                                _handler.seek(
                                    Duration(milliseconds: posMs));
                              },
                              onLongPress: () async {
                                try {
                                  await repo.deleteBookmark(b.id);
                                  final fresh = await repo.getBookmarks(
                                      _bookmarkItemId) as List<dynamic>;
                                  setSheet(() {
                                    list.clear();
                                    list.addAll(fresh);
                                  });
                                } catch (_) {}
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _currentChapterUrl() {
    if (_currentIndex >= 0 && _currentIndex < widget.chapterUrls.length) {
      return widget.chapterUrls[_currentIndex];
    }
    return widget.chapterUrl;
  }

  /// 音色切换：点开底部列表选音色，选完从当前进度接着播
  void _showVoiceSheet() {
    if (widget.voices.isEmpty) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ListTile(title: Text('音色')),
            for (final v in widget.voices)
              ListTile(
                title: Text('${v['name'] ?? v['id']}'),
                trailing: '${v['id']}' == _voiceId
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _switchVoice('${v['id']}');
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _switchVoice(String id) async {
    final resolver = widget.onSwitchVoice;
    if (resolver == null || id == _voiceId) return;
    final pos = _handler.player.position;
    try {
      final url = await resolver(id);
      if (url.isEmpty || !mounted) return;
      _handler.cacheChapterUrl(_currentIndex, url);
      await _handler.playPluginChapter(_currentIndex, startAt: pos);
      if (mounted) setState(() => _voiceId = id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('切换音色失败：$e')));
      }
    }
  }

  /// 选集弹窗：点哪集播哪集
  void _showChapters() {
    if (widget.playlist.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: <Widget>[
              const ListTile(title: Text('选集')),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.playlist.length,
                  itemBuilder: (_, i) {
                    final current = i == _currentIndex;
                    return ListTile(
                      title: Text(widget.playlist[i],
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: current
                          ? const Icon(Icons.play_arrow, size: 20)
                          : null,
                      selected: current,
                      onTap: () {
                        Navigator.pop(context);
                        _goToChapter(i);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, Color primary) {
    if (widget.coverUrl.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.network(
          widget.coverUrl,
          width: 220,
          height: 260,
          cacheWidth: 440,
          cacheHeight: 520,
          filterQuality: FilterQuality.low,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _coverPlaceholder(context, primary),
        ),
      );
    }
    return _coverPlaceholder(context, primary);
  }

  Widget _coverPlaceholder(BuildContext context, Color primary) {
    return Container(
      width: 220,
      height: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            primary.withOpacity(0.75),
            Theme.of(context).colorScheme.secondary.withOpacity(0.55),
          ],
        ),
      ),
      child: const Icon(Icons.graphic_eq, size: 72, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.timer_outlined),
            tooltip: '定时关闭',
            onPressed: _showSleepSheet,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_outline),
            tooltip: '书签',
            onPressed: _showBookmarks,
          ),
          if (widget.voices.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.record_voice_over_outlined),
              tooltip: '音色',
              onPressed: _showVoiceSheet,
            ),
          if (widget.playlist.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.list),
              tooltip: '选集',
              onPressed: _showChapters,
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: <Widget>[
              const Spacer(),
              _cover(context, primary),
              const SizedBox(height: 28),
              Text(
                  _currentIndex >= 0 && _currentIndex < widget.playlist.length
                      ? widget.playlist[_currentIndex]
                      : widget.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w700)),
              if (widget.subtitle.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              // 定时倒计时：还剩多久就停，点一下取消
              if (_sleepLeft != null) ...<Widget>[
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _setSleepTimer(0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '定时：还剩 ${_fmtMs(_sleepLeft!.inMilliseconds)}（点一下取消）',
                      style: TextStyle(fontSize: 13, color: primary),
                    ),
                  ),
                ),
              ],
              // 播到章末停：显示在倒计时同一位置，点一下取消
              if (_sleepEndOfEpisode) ...<Widget>[
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _setSleepTimer(0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '播到本集末停（点一下取消）',
                      style: TextStyle(fontSize: 13, color: primary),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('播放失败：$_error',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.error)),
                ),
              const Spacer(),
              ValueListenableBuilder<Duration>(
                valueListenable: _positionNotifier,
                builder: (ctx, pos, _) {
                  final totalMs = _duration.inMilliseconds;
                  final posMs = pos.inMilliseconds.clamp(
                      0, totalMs == 0 ? 1 : totalMs);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Slider(
                        value: posMs.toDouble(),
                        max: totalMs == 0 ? 1 : totalMs.toDouble(),
                        onChanged: (v) => _handler
                            .seek(Duration(milliseconds: v.toInt())),
                        activeColor: primary,
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Text(_fmtMs(posMs),
                                style: Theme.of(context).textTheme.bodySmall),
                            Text(_fmtMs(totalMs),
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  IconButton(
                    iconSize: 30,
                    icon: const Icon(Icons.replay_10),
                    tooltip: '后退 15 秒',
                    onPressed: () => _handler.seekBackward(),
                  ),
                  IconButton(
                    iconSize: 28,
                    icon: const Icon(Icons.skip_previous),
                    tooltip: '上一集',
                    onPressed: _prev,
                  ),
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primary,
                    ),
                    child: IconButton(
                      iconSize: 34,
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow,
                          color: Colors.white),
                      onPressed: _ready
                          ? () => _playing
                              ? _handler.pause()
                              : _handler.play()
                          : null,
                    ),
                  ),
                  IconButton(
                    iconSize: 28,
                    icon: const Icon(Icons.skip_next),
                    tooltip: '下一集',
                    onPressed: _next,
                  ),
                  IconButton(
                    iconSize: 30,
                    icon: const Icon(Icons.forward_10),
                    tooltip: '前进 15 秒',
                    onPressed: () => _handler.seekForward(),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((v) {
                  final selected = _speed == v;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        _handler.setSpeed(v);
                        setState(() => _speed = v);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: selected
                              ? primary.withOpacity(0.12)
                              : Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: selected
                                  ? primary
                                  : Theme.of(context).dividerColor),
                        ),
                        child: Text('${v}x',
                            style: TextStyle(
                                fontSize: 12,
                                color: selected ? primary : null,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400)),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
