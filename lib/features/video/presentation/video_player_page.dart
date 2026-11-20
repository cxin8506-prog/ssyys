import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'package:local_media_app/features/audio/data/audio_handler.dart';
import 'package:local_media_app/plugins/data/plugin_resume.dart';

String _fmt(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 画面模式：适应（完整显示，有黑边）/ 拉伸（拉满屏幕，不要黑边）/ 铺满（裁掉多余部分铺满，不变形）
enum ScreenFit { fit, stretch, fill }

/// 视频播放页：横屏全屏、点一下显隐控制条（3 秒自动藏）、
/// 左右滑 ±10 秒、左滑亮度右滑音量、画面三档（记住选择）、
/// 横向线路选择器、画中画、断点每 10 秒存一次 + 退出再存一次。
///
/// 线路由源暴露：App 调引擎 `lines` 拿 [{id, name}]，只做归一化；
/// `lineId` 由调用方在 `onSwitchLine` 里传进引擎 `content` 调用。
/// 视频只在线播，不做下载；视频源 isCacheable() 全部 false
/// （源侧的约定，本页不做任何缓存）。
class VideoPlayerPage extends ConsumerStatefulWidget {
  final String path;
  final List<String> playlist;
  final int initialIndex;
  final String title;

  /// true 表示 path/playlist 是网络地址（插件源在线播放）
  final bool network;

  /// 可切换的线路：[{id, name}]
  final List<Map<String, dynamic>> lines;

  /// 当前线路 id
  final String? currentLineId;

  /// 切线路时向源要新地址（参数：线路 id）
  final Future<String> Function(String lineId)? onSwitchLine;

  /// 只听声音时按章解析回调（参数：章下标，返回可播地址；解析失败返回 null）。
  /// 调用方（路由加载器）现调 content 解析，不预解析（限时签名会过期）。
  /// 没传就只保证当前集，播完即停。
  final Future<String?> Function(int index)? onResolveChapter;

  /// 只听声音时某章的请求头（和 onResolveChapter 同一次解析里拿到的）。
  final Map<String, String> Function(int index)? onResolveChapterHeaders;

  /// 播放这个地址要带的请求头（Referer/UA 等），没有就是空
  final Map<String, String> headers;

  /// 断点续播：第一次起播时从这个位置接着播（毫秒，默认 0=从头）
  final int startAtMs;

  /// 断点续播（插件源才有；本地视频不传，断点走书库）
  final String sourceId;
  final String sourceName;
  final String bookUrl;
  final String bookTitle;
  final List<String> chapterNames;
  final String lineName;
  final String voiceId;

  const VideoPlayerPage({
    super.key,
    required this.path,
    this.playlist = const [],
    this.initialIndex = 0,
    required this.title,
    this.network = false,
    this.lines = const [],
    this.currentLineId,
    this.onSwitchLine,
    this.onResolveChapter,
    this.onResolveChapterHeaders,
    this.headers = const {},
    this.startAtMs = 0,
    this.sourceId = '',
    this.sourceName = '',
    this.bookUrl = '',
    this.bookTitle = '',
    this.chapterNames = const [],
    this.lineName = '',
    this.voiceId = '',
  });

  @override
  ConsumerState<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends ConsumerState<VideoPlayerPage> {
  static const MethodChannel _pipChannel = MethodChannel('suishou/pip');

  VideoPlayerController? _controller;
  int _index = 0;
  bool _locked = false;

  /// 控制条显隐只重建控制层：ValueNotifier + ValueListenableBuilder，
  /// 不整页 setState，旧手机上点一下不卡
  final _controlsVisible = ValueNotifier<bool>(true);

  /// 默认铺满（裁掉多余部分铺满屏幕、不变形，不留大黑边），记住上次的选择
  ScreenFit _fit = ScreenFit.fill;
  bool _allLinesFailed = false;
  double _speed = 1.0;
  double _brightness = 1.0;
  double _volume = 1.0;
  bool _pipAvailable = false;

  String? _lineId;

  /// 失败过的线路（按“源+书+线路”落盘、记多条，退出播放页也不丢）。
  final Set<String> _failedLineIds = <String>{};

  Duration _lastPosition = Duration.zero;
  bool _switching = false;
  bool _startAtUsed = false;
  Timer? _hideTimer;
  Timer? _hintTimer;
  Timer? _resumeTimer;
  Timer? _finishedTimer;

  // 手势提示（亮度/音量/快进秒数）只刷提示条本身，不整页 setState
  final _gestureHint = ValueNotifier<String?>(null);
  String? _error;
  String? _failedUrl;
  String? _currentUrl;
  bool _finished = false;
  bool _handlingFinish = false;
  bool _fullscreen = true;

  /// 已切到“只听声音”：画面停掉、声音走 audioHandler，本页不再管进度。
  bool _audioOnly = false;

  bool get _hasLines => widget.lines.length > 1 && widget.onSwitchLine != null;

  String get _failedLinesPrefsKey =>
      'failed_lines_${widget.sourceId}|${widget.bookUrl}';

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _lineId = widget.currentLineId ??
        (widget.lines.isNotEmpty ? '${widget.lines.first['id']}' : null);
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() {
        _speed = (p.getDouble('playback_speed') ?? 1.0).clamp(0.5, 3.0);
        switch (p.getString('video_fit')) {
          case 'fit':
            _fit = ScreenFit.fit;
            break;
          case 'stretch':
            _fit = ScreenFit.stretch;
            break;
          case 'fill':
          default:
            _fit = ScreenFit.fill;
            break;
        }
        _failedLineIds.addAll(p.getStringList(_failedLinesPrefsKey) ?? <String>[]);
      });
    });
    // 进播放页默认横屏全屏
    _enterFullscreen();
    _initController();
    _armHideTimer();
    // 断点续播：每 10 秒存一次进度，退出时再存一次
    _resumeTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_controller?.value.isPlaying == true) {
        _saveResume();
      }
    });
    _pipChannel.invokeMethod<bool>('available').then((v) {
      if (mounted && v == true) setState(() => _pipAvailable = true);
    }).catchError((_) {});
  }

  Future<void> _persistFailedLines() async {
    if (widget.sourceId.isEmpty || widget.bookUrl.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          _failedLinesPrefsKey, _failedLineIds.toList());
    } catch (_) {}
  }

  /// 把当前进度存成断点（插件源才有 sourceId；关了断点续播就不存）。
  /// 当前线路和集地址、进度存同一行，下次打开按线名恢复。
  String _currentLineName() {
    if (_lineId == null || _lineId!.isEmpty) return '';
    for (final l in widget.lines) {
      if ('${l['id']}' == _lineId) return '${l['name'] ?? _lineId}';
    }
    return '';
  }

  Future<void> _saveResume() async {
    if (widget.sourceId.isEmpty || widget.bookUrl.isEmpty) return;
    if (_audioOnly) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position;
    if (pos <= Duration.zero) return;
    final chapterName = (_index >= 0 && _index < widget.chapterNames.length)
        ? widget.chapterNames[_index]
        : widget.title;
    try {
      await savePluginResume(
        resumeKey(widget.sourceId, widget.bookUrl),
        chapterIndex: _index,
        positionMs: pos.inMilliseconds,
        durationMs: c.value.duration.inMilliseconds,
        type: 'video',
        title: widget.bookTitle.isNotEmpty ? widget.bookTitle : widget.title,
        chapterTitle: chapterName,
        lineId: _lineId,
        lineName: _currentLineName(),
      );
    } catch (_) {}
  }

  void _enterFullscreen() {
    _fullscreen = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exitFullscreen() {
    _fullscreen = false;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  void _toggleFullscreen() {
    if (_fullscreen) {
      _exitFullscreen();
    } else {
      _enterFullscreen();
    }
    setState(() {});
  }

  /// 控制条 3 秒不动自动隐藏（只改 ValueNotifier，不重建整页）
  void _armHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_locked) _controlsVisible.value = false;
    });
  }

  void _showControlsTemporarily() {
    _controlsVisible.value = true;
    _armHideTimer();
  }

  void _showGestureHint(String text) {
    _gestureHint.value = text;
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 1), () {
      _gestureHint.value = null;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _initController({Duration? startAt}) async {
    final paths = widget.playlist.isNotEmpty ? widget.playlist : <String>[widget.path];
    final safeIndex = _index.clamp(0, paths.length - 1);
    Duration? start;
    if (startAt != null) {
      start = startAt;
    } else if (!_startAtUsed && widget.startAtMs > 0) {
      start = Duration(milliseconds: widget.startAtMs);
      _startAtUsed = true;
    }
    await _openUrl(paths[safeIndex], startAt: start);
  }

  /// 用某个地址起播。startAt 为空时从当前进度续播。
  /// 起播失败：自动按顺序试下一条线（autoFallback），都失败才报
  /// “所有线路都无法播放”，不直接退出。
  Future<void> _openUrl(String url,
      {Duration? startAt, bool autoFallback = true}) async {
    final old = _controller;
    if (old != null) {
      old.removeListener(_onControllerUpdate);
      await old.dispose();
    }
    if (mounted) {
      setState(() {
        _controller = null;
        _error = null;
        _failedUrl = null;
      });
    }
    _currentUrl = url;
    final isNetwork = url.startsWith('http');
    final ctrl = isNetwork
        ? VideoPlayerController.network(url, httpHeaders: widget.headers)
        : VideoPlayerController.file(File(url));
    _controller = ctrl;
    ctrl.addListener(_onControllerUpdate);
    try {
      await ctrl.initialize();
    } catch (e) {
      if (autoFallback && await _fallbackLine()) return;
      if (!mounted) return;
      setState(() {
        _failedUrl = url;
        _error = _allLinesFailed ? '所有线路都无法播放' : '播放失败：$e';
      });
      return;
    }
    if (!mounted) return;
    final keep = startAt ?? _lastPosition;
    await ctrl.setVolume(_volume);
    await ctrl.setPlaybackSpeed(_speed);
    if (keep > Duration.zero) {
      final dur = ctrl.value.duration;
      await ctrl.seekTo(
          keep > dur && dur > Duration.zero ? dur : keep);
    }
    await ctrl.play();
    if (mounted) {
      setState(() {
        _error = null;
        _allLinesFailed = false;
      });
    }
  }

  void _onControllerUpdate() {
    final c = _controller;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.isInitialized) _lastPosition = v.position;
    if (v.hasError && _error == null) {
      _failedUrl = _currentUrl;
      setState(() => _error = '播放失败：${v.errorDescription ?? '未知错误'}');
      return;
    }
    // 播完：按“自动播放下一集”设置进下一集，否则显示“已播完”。
    if (v.isInitialized &&
        v.duration > Duration.zero &&
        v.position >= v.duration &&
        !v.isPlaying &&
        !_handlingFinish) {
      _handlingFinish = true;
      _onFinished();
    }
  }

  Future<void> _onFinished() async {
    await _saveResume();
    bool autoNext = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      autoNext = prefs.getBool('auto_play_next') ?? true;
    } catch (_) {}
    final paths = widget.playlist.isNotEmpty ? widget.playlist : <String>[widget.path];
    if (autoNext && _index + 1 < paths.length) {
      _handlingFinish = false;
      await _nextEpisode();
      return;
    }
    if (!mounted) return;
    setState(() {
      _finished = true;
      _handlingFinish = false;
    });
    _finishedTimer?.cancel();
    _finishedTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _finished = false);
    });
  }

  /// 当前线路失败：按顺序试下一条，成功返回 true。
  /// 每步 Toast“正在切换线路至「××」”；失败过的线记下来（落盘）。
  Future<bool> _fallbackLine() async {
    final list = widget.lines;
    final resolver = widget.onSwitchLine;
    if (list.length < 2 || resolver == null) return false;
    _allLinesFailed = false;
    if (_lineId != null) {
      _failedLineIds.add(_lineId!);
      await _persistFailedLines();
    }
    final startIdx = list.indexWhere((e) => '${e['id']}' == _lineId);
    for (var i = 1; i < list.length; i++) {
      final cand = list[(startIdx + i) % list.length];
      final id = '${cand['id']}';
      if (id == _lineId) continue;
      _toast('正在切换线路至「${cand['name'] ?? id}」');
      try {
        final url = await resolver(id);
        if (url.isEmpty) continue;
        await _openUrl(url, startAt: _lastPosition, autoFallback: false);
        if (!mounted) return true;
        setState(() {
          _lineId = id;
          _failedLineIds.remove(id);
        });
        await _persistFailedLines();
        await _saveResume();
        _toast('这条线路不行，已自动切到「${cand['name'] ?? id}」');
        return true;
      } catch (_) {
        _failedLineIds.add(id);
        await _persistFailedLines();
      }
    }
    _allLinesFailed = true;
    return false;
  }

  /// 手动切线路：切线前先存当前进度，新线按集名找同一集
  /// （同一集、同一位置接着播）；解析展开过的地址换线时进度清零
  /// （线路名和原始地址都相同才保留——这里按集名 + 地址双重判断）。
  Future<void> _switchLine(String id) async {
    final resolver = widget.onSwitchLine;
    if (resolver == null || id == _lineId || _switching) return;
    setState(() => _switching = true);
    final pos = _controller?.value.position ?? _lastPosition;
    final prevUrl = _currentUrl ?? '';
    try {
      final url = await resolver(id);
      if (url.isEmpty) throw Exception('这条线路没有返回地址');
      // 解析展开过的地址（resolve:// 等）：线路名和原始地址都相同才保留进度。
      final keepPos =
          !(prevUrl.contains('resolve://') || url.contains('resolve://')) ||
              url == prevUrl;
      await _openUrl(url,
          startAt: keepPos ? pos : Duration.zero, autoFallback: false);
      if (!mounted) return;
      setState(() {
        _lineId = id;
        _failedLineIds.remove(id);
      });
      await _persistFailedLines();
      await _saveResume();
      _toast('已切换线路，从当前进度继续');
    } catch (e) {
      if (mounted) {
        setState(() {
          _failedLineIds.add(id);
        });
        await _persistFailedLines();
        _toast('切换失败：$e');
      }
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  /// 线路选择表（底部弹层）：失败的线标出来，当前线标“正在使用”。
  void _showLineSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ListTile(title: Text('线路')),
            for (final l in widget.lines)
              ListTile(
                leading: Icon(
                  '${l['id']}' == _lineId
                      ? Icons.radio_button_checked
                      : (_failedLineIds.contains('${l['id']}')
                          ? Icons.error_outline
                          : Icons.radio_button_unchecked),
                  color: _failedLineIds.contains('${l['id']}')
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                title: Text('${l['name'] ?? l['id']}'),
                subtitle: _failedLineIds.contains('${l['id']}')
                    ? const Text('上次加载失败',
                        style: TextStyle(fontSize: 11))
                    : null,
                trailing: '${l['id']}' == _lineId
                    ? const Text('正在使用', style: TextStyle(fontSize: 11))
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _switchLine('${l['id']}');
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _nextEpisode() async {
    final paths = widget.playlist.isNotEmpty ? widget.playlist : <String>[widget.path];
    if (_index + 1 >= paths.length) {
      _toast('已经是最后一集');
      return;
    }
    await _saveResume();
    await _controller?.dispose();
    if (mounted) setState(() => _controller = null);
    setState(() => _index++);
    _lastPosition = Duration.zero;
    _finished = false;
    _initController(startAt: Duration.zero);
  }

  Future<void> _prevEpisode() async {
    if (_index <= 0) {
      _toast('已经是第一集');
      return;
    }
    await _saveResume();
    await _controller?.dispose();
    if (mounted) setState(() => _controller = null);
    setState(() => _index--);
    _lastPosition = Duration.zero;
    _finished = false;
    _initController(startAt: Duration.zero);
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
  }

  void _seekBy(Duration delta) {
    final c = _controller;
    if (c == null) return;
    final target = c.value.position + delta;
    c.seekTo(target < Duration.zero
        ? Duration.zero
        : (target > c.value.duration ? c.value.duration : target));
  }

  /// “后台播放 / 只听声音”：画面停掉，声音继续走 audioHandler；
  /// 退出视频页时不断音。
  Future<void> _switchToAudioOnly() async {
    final url = _currentUrl;
    final pos = _controller?.value.position ?? _lastPosition;
    if (url == null || url.isEmpty) {
      _toast('当前没有可播地址');
      return;
    }
    await _saveResume();
    await _controller?.dispose();
    if (mounted) setState(() => _controller = null);
    _audioOnly = true;
    try {
      final handler = ref.read(audioHandlerProvider);
      final chapters = List<Map<String, dynamic>>.generate(
        widget.chapterNames.isEmpty ? 1 : widget.chapterNames.length,
        (i) => <String, dynamic>{
          'title': widget.chapterNames.isEmpty
              ? widget.title
              : widget.chapterNames[i],
          'url': i < widget.playlist.length ? widget.playlist[i] : '',
        },
      );
      final bookKey = widget.sourceId.isNotEmpty && widget.bookUrl.isNotEmpty
          ? '${widget.sourceId}|${widget.bookUrl}'
          : 'video|${widget.title}';
      await handler.setPluginBook(
        bookKey: bookKey,
        sourceId: widget.sourceId,
        bookUrl: widget.bookUrl,
        title: widget.bookTitle.isNotEmpty ? widget.bookTitle : widget.title,
        chapters: chapters,
        initialIndex: _index,
      );
      final currentIndex = _index;
      handler.cacheChapterUrl(currentIndex, url);
      final resolver = widget.onResolveChapter;
      if (resolver != null) {
        // 按需解析下一章：当前集用已解析好的地址，下一集播完时 handler
        // 自动调这里现向源解析（autoAdvancePlugin），解析失败返回 null
        // 就停住，不崩、不静默跳集；请求头走同一次解析里拿到的。
        handler.onResolveChapter = (i) async {
          if (i == currentIndex) return url;
          try {
            final next = await resolver(i);
            return (next == null || next.isEmpty) ? null : next;
          } catch (_) {
            return null;
          }
        };
        handler.onResolveHeaders = (i) {
          final h = widget.onResolveChapterHeaders?.call(i);
          if (h != null && h.isNotEmpty) return h;
          if (i == currentIndex) return widget.headers;
          return const <String, String>{};
        };
        handler.autoAdvancePlugin = true;
      } else {
        // 没传解析回调（本地视频等）：只保证当前集，播完即停。
        handler.onResolveChapter =
            (i) async => i == currentIndex ? url : null;
      }
      await handler.playPluginChapter(currentIndex, startAt: pos);
      _toast('已切换为只听声音，退出后继续播');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        _toast('切换只听声音失败：$e');
        _audioOnly = false;
        _initController(startAt: pos);
      }
    }
  }

  Future<void> _enterPip() async {
    try {
      final ok = await _pipChannel.invokeMethod<bool>(
          'enter', <String, dynamic>{'width': 16, 'height': 9});
      if (ok != true && mounted) {
        _toast('当前设备不支持画中画');
      }
    } catch (_) {
      if (mounted) _toast('当前设备不支持画中画');
    }
  }

  void _cycleFit() {
    setState(() {
      switch (_fit) {
        case ScreenFit.fit:
          _fit = ScreenFit.stretch;
          break;
        case ScreenFit.stretch:
          _fit = ScreenFit.fill;
          break;
        case ScreenFit.fill:
          _fit = ScreenFit.fit;
          break;
      }
    });
    SharedPreferences.getInstance().then((p) {
      p.setString('video_fit', _fit.name);
    });
  }

  String get _fitLabel {
    switch (_fit) {
      case ScreenFit.fit:
        return '适应';
      case ScreenFit.stretch:
        return '拉伸';
      case ScreenFit.fill:
        return '铺满';
    }
  }

  Future<void> _pickSpeed() async {
    final picked = await showMenu<double>(
      context: context,
      position: const RelativeRect.fromLTRB(100, 100, 100, 100),
      items: <double>[0.5, 1.0, 1.25, 1.5, 2.0]
          .map((v) => PopupMenuItem<double>(
                value: v,
                child: Text('${v}x'),
              ))
          .toList(),
    );
    if (picked == null) return;
    setState(() => _speed = picked);
    await _controller?.setPlaybackSpeed(picked);
  }

  @override
  void dispose() {
    _saveResume();
    _controlsVisible.dispose();
    _gestureHint.dispose();
    _resumeTimer?.cancel();
    _hideTimer?.cancel();
    _hintTimer?.cancel();
    _finishedTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _exitFullscreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _buildVideoSurface(),
            ValueListenableBuilder<String?>(
              valueListenable: _gestureHint,
              builder: (_, hint, __) => hint == null
                  ? const SizedBox.shrink()
                  : _buildGestureHint(hint),
            ),
            if (_finished) _buildFinishedHint(),
            if (_error != null) _buildErrorOverlay(),
            if (!_locked)
              ValueListenableBuilder<bool>(
                valueListenable: _controlsVisible,
                builder: (_, visible, __) =>
                    visible ? _buildControls() : const SizedBox.shrink(),
              ),
            if (_pipAvailable && !_locked)
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  icon: const Icon(Icons.picture_in_picture_alt),
                  color: Colors.white,
                  tooltip: '画中画',
                  onPressed: _enterPip,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGestureHint(String hint) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          hint,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildFinishedHint() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          '已播完',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }

  /// 播不出来：显示“所有线路都无法播放” + 换线路重试 / 重试，不直接退出。
  Widget _buildErrorOverlay() {
    final allFailed = _allLinesFailed;
    return Container(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 56, color: Colors.white70),
              const SizedBox(height: 16),
              Text(
                allFailed ? '所有线路都无法播放' : (_error ?? '播放失败'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 17),
              ),
              const SizedBox(height: 8),
              const Text(
                '可能是资源已失效或网络问题，换条线路试试',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (_hasLines)
                    ElevatedButton(
                      onPressed: () => _showLineSheet(),
                      child: const Text('换线路重试'),
                    ),
                  if (_hasLines) const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      final url = _failedUrl ?? _currentUrl;
                      if (url == null || url.isEmpty) return;
                      setState(() {
                        _error = null;
                        _allLinesFailed = false;
                      });
                      _openUrl(url,
                          startAt: _lastPosition, autoFallback: true);
                    },
                    child: const Text('重试'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoSurface() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    final video = VideoPlayer(c);
    Widget surface;
    switch (_fit) {
      case ScreenFit.fit:
        surface = Center(
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: video,
          ),
        );
        break;
      case ScreenFit.stretch:
        surface = SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: video,
            ),
          ),
        );
        break;
      case ScreenFit.fill:
        surface = SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: video,
            ),
          ),
        );
        break;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_controlsVisible.value) {
          _controlsVisible.value = false;
          _hideTimer?.cancel();
        } else {
          _showControlsTemporarily();
        }
      },
      onDoubleTap: _togglePlay,
      onHorizontalDragEnd: (details) {
        final dx = details.primaryVelocity ?? 0;
        if (dx > 0) {
          _seekBy(const Duration(seconds: 10));
          _showGestureHint('快进 10 秒');
        } else if (dx < 0) {
          _seekBy(const Duration(seconds: -10));
          _showGestureHint('快退 10 秒');
        }
        _showControlsTemporarily();
      },
      onVerticalDragUpdate: (details) {
        final width = MediaQuery.of(context).size.width;
        final left = details.globalPosition.dx < width / 2;
        final delta = -details.delta.dy / 200;
        if (left) {
          // 左边上下滑调亮度（用遮罩实现，不依赖新插件）
          setState(() {
            _brightness = (_brightness + delta).clamp(0.2, 1.0);
          });
          _showGestureHint('亮度 ${(_brightness * 100).round()}%');
        } else {
          setState(() {
            _volume = (_volume + delta).clamp(0.0, 1.0);
          });
          _controller?.setVolume(_volume);
          _showGestureHint('音量 ${(_volume * 100).round()}%');
        }
        _showControlsTemporarily();
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          surface,
          // 亮度遮罩：亮度越低遮罩越黑（0.2–1.0 对应不透明度 0.68–0）
          IgnorePointer(
            child: Container(
              color: Colors.black
                  .withOpacity((1.0 - _brightness).clamp(0.0, 1.0) * 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final c = _controller;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.black54, Colors.transparent, Colors.black54],
          stops: <double>[0.0, 0.35, 1.0],
        ),
      ),
      child: Column(
        children: <Widget>[
          // 顶栏：返回 + 标题 + 锁定
          Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                tooltip: '返回',
                onPressed: () {
                  _saveResume();
                  Navigator.of(context).pop();
                },
              ),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
              IconButton(
                icon: Icon(
                    _locked ? Icons.lock : Icons.lock_open,
                    color: Colors.white),
                tooltip: _locked ? '解锁' : '锁定（防误触）',
                onPressed: () {
                  setState(() => _locked = !_locked);
                  if (_locked) _controlsVisible.value = false;
                },
              ),
            ],
          ),
          const Spacer(),
          // 中间大播放/暂停圆钮
          if (c != null && c.value.isInitialized)
            GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black45,
                ),
                child: Icon(
                  c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          const Spacer(),
          // 横向线路选择器（没线就隐藏）
          if (_hasLines) _buildLineChips(),
          // 底部进度条 + 时间 + 按钮行
          if (c != null) _buildBottomBar(c),
        ],
      ),
    );
  }

  /// 横向线路选择器：一排横向线路名，选中态高亮；失败的线带感叹号。
  Widget _buildLineChips() {
    return Container(
      height: 40,
      alignment: Alignment.centerLeft,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: widget.lines.map((l) {
          final id = '${l['id']}';
          final selected = id == _lineId;
          final failed = _failedLineIds.contains(id);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('${l['name'] ?? id}'),
              avatar: failed
                  ? const Icon(Icons.error_outline, size: 16)
                  : null,
              selected: selected,
              selectedColor: Theme.of(context).colorScheme.primary,
              labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.white70),
              backgroundColor: Colors.black45,
              onSelected: (_) => _switchLine(id),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomBar(VideoPlayerController c) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: c,
            builder: (_, v, __) {
              final total = v.duration;
              final pos = v.position;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Slider(
                    value: total == Duration.zero
                        ? 0
                        : pos.inMilliseconds
                            .clamp(0, total.inMilliseconds)
                            .toDouble(),
                    max: total == Duration.zero
                        ? 1
                        : total.inMilliseconds.toDouble(),
                    onChanged: (val) =>
                        c.seekTo(Duration(milliseconds: val.toInt())),
                    activeColor: Colors.white,
                    inactiveColor: Colors.white38,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(_fmt(pos),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                      Text(_fmt(total),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ],
              );
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.play_arrow, color: Colors.white),
                tooltip: '播放/暂停',
                onPressed: _togglePlay,
              ),
              IconButton(
                icon: const Icon(Icons.skip_previous, color: Colors.white),
                tooltip: '上一集',
                onPressed: _prevEpisode,
              ),
              IconButton(
                icon: const Icon(Icons.skip_next, color: Colors.white),
                tooltip: '下一集',
                onPressed: _nextEpisode,
              ),
              TextButton(
                onPressed: _pickSpeed,
                child: Text('${_speed}x',
                    style:
                        const TextStyle(color: Colors.white, fontSize: 13)),
              ),
              TextButton(
                onPressed: _cycleFit,
                child: Text('画面·$_fitLabel',
                    style:
                        const TextStyle(color: Colors.white, fontSize: 13)),
              ),
              if (_hasLines)
                TextButton(
                  onPressed: _showLineSheet,
                  child: const Text('线路',
                      style: TextStyle(color: Colors.white, fontSize: 13)),
                ),
              IconButton(
                icon: const Icon(Icons.headphones, color: Colors.white),
                tooltip: '只听声音（后台播放）',
                onPressed: _switchToAudioOnly,
              ),
              IconButton(
                icon: Icon(
                    _fullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    color: Colors.white),
                tooltip: '全屏切换',
                onPressed: _toggleFullscreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
