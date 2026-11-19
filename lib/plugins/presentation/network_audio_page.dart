import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/di/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/path_utils.dart';
import '../../features/audio/data/repository_providers.dart';
import '../data/auto_cache.dart';
import '../data/plugin_resume.dart';

/// 网络音频播放页（插件源直接播放 URL）
class NetworkAudioPage extends ConsumerStatefulWidget {
  final String url;

  /// 播放这个地址要带的请求头（Referer/UA 等），没有就是空
  final Map<String, String> headers;
  final String title;
  final String subtitle;
  final List<String> playlist;
  final int startIndex;
  final void Function(int index)? onNext;

  /// 缓存归属信息
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
  final _player = AudioPlayer();

  /// 进度只刷进度条本身：positionStream 只更新这个 ValueNotifier，
  /// Slider + 时间行包在 ValueListenableBuilder 里，不整页 setState
  final _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _voiceId;
  bool _cacheFired = false;
  double _speed = 1.0;
  bool _ready = false;
  String? _error;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;
  bool _playing = false;

  // 定时关闭：还剩多久就停
  Timer? _sleepTimer;
  Duration? _sleepLeft;

  // 断点续播：每 10 秒存一次进度，退出时再存一次
  Timer? _resumeTimer;

  String get _bookmarkItemId => '${widget.sourceId}|${widget.bookName}';

  @override
  void initState() {
    super.initState();
    _voiceId = widget.currentVoiceId;
    _posSub = _player.positionStream.listen((p) {
      _position = p;
      _positionNotifier.value = p;
      // 缓存频率阈值：正在播、播到阈值（标准 30%）才触发一次自动缓存
      if (!_cacheFired &&
          widget.onCacheThreshold != null &&
          _playing &&
          _duration > Duration.zero) {
        final freq = ref.read(sharedPrefsProvider).getString(
                AppConstants.keyAutoCacheFreq) ??
            'standard';
        if (p.inMilliseconds / _duration.inMilliseconds >=
            AutoCache.thresholdFor(freq)) {
          _cacheFired = true;
          widget.onCacheThreshold!();
        }
      }
    });
    _durSub = _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    _stateSub = _player.playerStateStream.listen((s) {
      if (mounted) setState(() => _playing = s.playing);
      if (s.processingState == ProcessingState.completed) {
        _next();
      }
    });
    _resumeTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_playing) _saveResume();
    });
    _load();
  }

  /// 把当前进度存成断点（“继续”区和历史页都靠它；关了断点续播就不存）
  Future<void> _saveResume() async {
    if (widget.sourceId.isEmpty || widget.bookUrl.isEmpty) return;
    if (!ref.read(resumeEnabledProvider)) return;
    if (_position <= Duration.zero) return;
    await PluginResumeStore.save(PluginResume(
      key: resumeKey(widget.sourceId, widget.bookUrl),
      sourceId: widget.sourceId,
      sourceName: widget.sourceName,
      bookTitle: widget.bookName,
      bookUrl: widget.bookUrl,
      coverUrl: widget.coverUrl,
      chapterName: widget.title,
      chapterUrl: widget.chapterUrl,
      chapterIndex: widget.startIndex,
      positionMs: _position.inMilliseconds,
      durationMs: _duration.inMilliseconds,
      lineId: widget.lineId,
      lineName: widget.lineName,
      voiceId: widget.voiceId,
      type: AppConstants.typeAudio,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> _load() async {
    try {
      // 本地缓存文件：直接播文件，不走网络
      if (widget.url.startsWith('/')) {
        await _player.setAudioSource(
          AudioSource.uri(Uri.file(widget.url)),
        );
      } else if (widget.headers.isNotEmpty) {
        // 纯在线流式播放，由播放器自己缓冲；有请求头时带上播
        await _player.setAudioSource(
          AudioSource.uri(Uri.parse(widget.url), headers: widget.headers),
        );
      } else {
        await _player.setUrl(widget.url);
      }
      if (widget.startAt > Duration.zero) {
        await _player.seek(widget.startAt);
      }
      await _player.play();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _ready = true;
          _error = '$e';
        });
      }
    }
  }

  @override
  void dispose() {
    _saveResume();
    _positionNotifier.dispose();
    _resumeTimer?.cancel();
    _sleepTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  /// 定时关闭：到时间自动暂停，页面上显示倒计时
  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    if (minutes <= 0) {
      setState(() => _sleepLeft = null);
      return;
    }
    setState(() => _sleepLeft = Duration(minutes: minutes));
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      final left = (_sleepLeft ?? Duration.zero) - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        t.cancel();
        setState(() => _sleepLeft = null);
        _player.pause();
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
          children: [
            const ListTile(title: Text('定时关闭')),
            for (final m in [15, 30, 45, 60, 90])
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

  /// 书签列表：点一行跳到那个位置，长按删
  Future<void> _showBookmarks() async {
    final repo = ref.read(libraryRepositoryProvider);
    final list = await repo.bookmarks(_bookmarkItemId);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.6,
            child: Column(
              children: [
                ListTile(
                  title: const Text('书签'),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.bookmark_add, size: 18),
                    label: const Text('加书签'),
                    onPressed: () async {
                      await repo.addBookmark(
                        itemId: _bookmarkItemId,
                        chapterId: widget.title,
                        positionMs: _position.inMilliseconds,
                        note: widget.title,
                      );
                      final fresh = await repo.bookmarks(_bookmarkItemId);
                      setSheet(() {
                        list.clear();
                        list.addAll(fresh);
                      });
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: list.isEmpty
                      ? const Center(child: Text('还没有书签，听到想留的地方点“加书签”'))
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final b = list[i];
                            return ListTile(
                              leading: const Icon(Icons.bookmark, size: 20),
                              title: Text(b.note ?? widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  PathUtils.formatDuration(b.positionMs)),
                              onTap: () {
                                Navigator.pop(context);
                                _player.seek(
                                    Duration(milliseconds: b.positionMs));
                              },
                              onLongPress: () async {
                                await repo.deleteBookmark(b.id);
                                final fresh = await repo
                                    .bookmarks(_bookmarkItemId);
                                setSheet(() {
                                  list.clear();
                                  list.addAll(fresh);
                                });
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

  /// 音色切换：点开底部列表选音色，选完从当前进度接着播
  void _showVoiceSheet() {
    if (widget.voices.isEmpty) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
    final pos = _positionNotifier.value;
    try {
      final url = await resolver(id);
      if (url.isEmpty || !mounted) return;
      if (url.startsWith('/')) {
        await _player.setAudioSource(
          AudioSource.uri(Uri.file(url)),
        );
      } else if (widget.headers.isNotEmpty) {
        await _player.setAudioSource(
          AudioSource.uri(Uri.parse(url), headers: widget.headers),
        );
      } else {
        await _player.setUrl(url);
      }
      await _player.seek(pos);
      await _player.play();
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
            children: [
              const ListTile(title: Text('选集')),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.playlist.length,
                  itemBuilder: (_, i) {
                    final current = i == widget.startIndex;
                    return ListTile(
                      title: Text(widget.playlist[i],
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: current
                          ? const Icon(Icons.play_arrow, size: 20)
                          : null,
                      selected: current,
                      onTap: () {
                        Navigator.pop(context);
                        if (i != widget.startIndex &&
                            widget.onNext != null) {
                          widget.onNext!(i);
                        }
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

  void _next() {
    final i = widget.startIndex + 1;
    if (widget.onNext != null && widget.playlist.isNotEmpty && i < widget.playlist.length) {
      Navigator.of(context).pop();
      widget.onNext!(i);
    }
  }

  void _prev() {
    final i = widget.startIndex - 1;
    if (widget.onNext != null && i >= 0) {
      Navigator.of(context).pop();
      widget.onNext!(i);
    }
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
          errorBuilder: (_, __, ___) => _coverPlaceholder(primary),
        ),
      );
    }
    return _coverPlaceholder(primary);
  }

  Widget _coverPlaceholder(Color primary) {
    return Container(
      width: 220,
      height: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
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
    // 播放页取色偏向：开着跟主题色走，关了用中性色
    final tint = ref.watch(playerTintProvider);
    final primary = tint
        ? Theme.of(context).colorScheme.primary
        : const Color(0xFF6B7280);
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        actions: [
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
            children: [
              const Spacer(),
              _cover(context, primary),
              const SizedBox(height: 28),
              Text(widget.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w700)),
              if (widget.subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              // 定时倒计时：还剩多久就停，点一下取消
              if (_sleepLeft != null) ...[
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _setSleepTimer(0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.palette.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '定时：还剩 ${PathUtils.formatDuration(_sleepLeft!.inMilliseconds)}（点一下取消）',
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
                          ?.copyWith(color: Theme.of(context).colorScheme.error)),
                ),
              const Spacer(),
              ValueListenableBuilder<Duration>(
                valueListenable: _positionNotifier,
                builder: (ctx, pos, _) {
                  final totalMs = _duration.inMilliseconds;
                  final posMs =
                      pos.inMilliseconds.clamp(0, totalMs == 0 ? 1 : totalMs);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Slider(
                        value: posMs.toDouble(),
                        max: totalMs == 0 ? 1 : totalMs.toDouble(),
                        onChanged: (v) => _player
                            .seek(Duration(milliseconds: v.toInt())),
                        activeColor: primary,
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(PathUtils.formatDuration(posMs),
                                style: Theme.of(context).textTheme.bodySmall),
                            Text(PathUtils.formatDuration(totalMs),
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
                children: [
                  IconButton(
                    iconSize: 30,
                    icon: const Icon(Icons.replay_10),
                    tooltip: '后退 15 秒',
                    onPressed: () {
                      final t = _position - const Duration(seconds: 15);
                      _player.seek(t < Duration.zero ? Duration.zero : t);
                    },
                  ),
                  IconButton(
                    iconSize: 28,
                    icon: const Icon(Icons.skip_previous),
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
                          color: Colors.black87),
                      onPressed: _ready
                          ? () => _playing ? _player.pause() : _player.play()
                          : null,
                    ),
                  ),
                  IconButton(
                    iconSize: 28,
                    icon: const Icon(Icons.skip_next),
                    onPressed: _next,
                  ),
                  IconButton(
                    iconSize: 30,
                    icon: const Icon(Icons.forward_10),
                    tooltip: '前进 15 秒',
                    onPressed: () {
                      _player.seek(_position + const Duration(seconds: 15));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((v) {
                  final selected = _speed == v;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        _player.setSpeed(v);
                        setState(() => _speed = v);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: selected
                              ? context.palette.primarySoft
                              : context.cardColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: selected
                                  ? primary
                                  : context.palette.outline),
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
