import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/di/providers.dart';
import '../../../core/log/app_logger.dart';
import '../../../core/platform/pip_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/listen_stats.dart';
import '../../../plugins/data/plugin_resume.dart';

enum ScreenFit { fit, fill, original }

/// 视频播放页：本地视频、手势、比例、全屏、界面锁定、连播、倍速
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
  VideoPlayerController? _controller;
  int _index = 0;
  bool _locked = false;
  bool _showControls = true;
  ScreenFit _fit = ScreenFit.fit;
  double _speed = 1.0;
  double _brightness = 1.0;
  double _volume = 1.0;
  bool _pipAvailable = false;

  String? _lineId;
  String? _failedLineId;
  Duration _lastPosition = Duration.zero;
  bool _switching = false;
  bool _startAtUsed = false;
  Timer? _hideTimer;
  Timer? _statsTimer;
  Timer? _hintTimer;
  Timer? _resumeTimer;
  String? _gestureHint;
  String? _error;
  String? _failedUrl;
  bool _finished = false;
  bool _handlingFinish = false;
  bool _fullscreen = true;

  bool get _hasLines => widget.lines.length > 1 && widget.onSwitchLine != null;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _speed = ref.read(defaultSpeedProvider);
    _lineId = widget.currentLineId ??
        (widget.lines.isNotEmpty ? '${widget.lines.first['id']}' : null);
    // 进播放页默认横屏全屏
    _enterFullscreen();
    _initController();
    _armHideTimer();
    // 在播的时候每 5 秒记一次收听统计
    _statsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_controller?.value.isPlaying == true) {
        ListenStats.record(5);
      }
    });
    // 断点续播：每 10 秒存一次进度，退出时再存一次
    _resumeTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_controller?.value.isPlaying == true) {
        _saveResume();
      }
    });
    PipService.isAvailable().then((v) {
      if (mounted && v) setState(() => _pipAvailable = v);
    });
  }

  /// 把当前进度存成断点（插件源才有 sourceId；关了断点续播就不存）
  Future<void> _saveResume() async {
    if (widget.sourceId.isEmpty || widget.bookUrl.isEmpty) return;
    if (!ref.read(resumeEnabledProvider)) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final pos = c.value.position;
    if (pos <= Duration.zero) return;
    final chapterName = (_index >= 0 && _index < widget.chapterNames.length)
        ? widget.chapterNames[_index]
        : widget.title;
    final chapterUrl = (_index >= 0 && _index < widget.playlist.length)
        ? widget.playlist[_index]
        : widget.path;
    String lineName = widget.lineName;
    if (lineName.isEmpty && _lineId != null) {
      for (final l in widget.lines) {
        if ('${l['id']}' == _lineId) {
          lineName = '${l['name'] ?? ''}';
          break;
        }
      }
    }
    await PluginResumeStore.save(PluginResume(
      key: resumeKey(widget.sourceId, widget.bookUrl),
      sourceId: widget.sourceId,
      sourceName: widget.sourceName,
      bookTitle: widget.bookTitle.isNotEmpty ? widget.bookTitle : widget.title,
      bookUrl: widget.bookUrl,
      chapterName: chapterName,
      chapterUrl: chapterUrl,
      chapterIndex: _index,
      positionMs: pos.inMilliseconds,
      durationMs: c.value.duration.inMilliseconds,
      lineId: _lineId ?? '',
      lineName: lineName,
      voiceId: widget.voiceId,
      type: AppConstants.typeVideo,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  void _enterFullscreen() {
    _fullscreen = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exitFullscreen() {
    _fullscreen = false;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
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

  /// 控制条 3 秒不动自动隐藏
  void _armHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_locked) setState(() => _showControls = false);
    });
  }

  void _showControlsTemporarily() {
    setState(() => _showControls = true);
    _armHideTimer();
  }

  void _showGestureHint(String text) {
    setState(() => _gestureHint = text);
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _gestureHint = null);
    });
  }

  Future<void> _initController({Duration? startAt}) async {
    final paths = widget.playlist.isNotEmpty ? widget.playlist : [widget.path];
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
  Future<void> _openUrl(String url,
      {Duration? startAt, bool autoFallback = true}) async {
    final keep = startAt ??
        (_controller?.value.isInitialized == true
            ? _controller!.value.position
            : _lastPosition);
    final ctrl = widget.network
        ? VideoPlayerController.networkUrl(Uri.parse(url),
            httpHeaders: widget.headers)
        : VideoPlayerController.file(File(url));
    try {
      await ctrl.initialize();
      await ctrl.setPlaybackSpeed(_speed);
      await ctrl.setVolume(_volume);
      if (keep > Duration.zero) await ctrl.seekTo(keep);
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      final old = _controller;
      old?.removeListener(_onControllerUpdate);
      ctrl.addListener(_onControllerUpdate);
      setState(() {
        _controller = ctrl;
        _error = null;
        _failedUrl = null;
        _finished = false;
        _handlingFinish = false;
      });
      await old?.dispose();
      await ctrl.play();
    } catch (e, st) {
      appLogger.error('视频播放失败', error: e, stack: st);
      await ctrl.dispose();
      if (!mounted) return;
      _lastPosition = keep;
      if (autoFallback && await _fallbackLine()) return;
      // 所有线路都试过还不行：显示“播放失败”，给换线路重试/重试，不直接退出
      setState(() {
        _error = '播放失败';
        _failedUrl = url;
      });
    }
  }

  /// 播完一集：按“自动播放下一集”设置决定是自动进下一集还是停住
  void _onControllerUpdate() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final dur = c.value.duration;
    if (dur <= Duration.zero) return;
    if (c.value.isPlaying) {
      _handlingFinish = false;
      return;
    }
    if (c.value.position < dur - const Duration(milliseconds: 300)) return;
    if (_handlingFinish || _switching) return;
    _handlingFinish = true;
    if (ref.read(autoNextProvider)) {
      _next();
    } else {
      setState(() => _finished = true);
      Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _finished = false);
      });
    }
  }

  /// 当前线路失败：按顺序试下一条，成功返回 true
  Future<bool> _fallbackLine() async {
    final list = widget.lines;
    final resolver = widget.onSwitchLine;
    if (list.length < 2 || resolver == null) return false;
    _failedLineId = _lineId;
    final startIdx = list.indexWhere((e) => '${e['id']}' == _lineId);
    for (var i = 1; i < list.length; i++) {
      final cand = list[(startIdx + i) % list.length];
      final id = '${cand['id']}';
      if (id == _lineId) continue;
      try {
        final url = await resolver(id);
        if (url.isEmpty) continue;
        await _openUrl(url, startAt: _lastPosition, autoFallback: false);
        if (!mounted) return true;
        setState(() {
          _lineId = id;
          _failedLineId = null;
        });
        _toast('这条线路不行，已自动切到「${cand['name']}」');
        return true;
      } catch (_) {
        _failedLineId = id;
      }
    }
    return false;
  }

  /// 手动切线路：从当前进度接着播
  Future<void> _switchLine(String id) async {
    final resolver = widget.onSwitchLine;
    if (resolver == null || id == _lineId || _switching) return;
    setState(() => _switching = true);
    final pos = _controller?.value.position ?? _lastPosition;
    try {
      final url = await resolver(id);
      if (url.isEmpty) throw Exception('这条线路没有返回地址');
      await _openUrl(url, startAt: pos, autoFallback: false);
      if (!mounted) return;
      setState(() {
        _lineId = id;
        _failedLineId = null;
      });
      _toast('已切换线路，从当前进度继续');
    } catch (e) {
      if (mounted) _toast('切换失败：$e');
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  void _showLineSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('切换线路',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              for (final l in widget.lines)
                ListTile(
                  leading: Icon(
                    '${l['id']}' == _lineId
                        ? Icons.radio_button_checked
                        : (_failedLineId == '${l['id']}'
                            ? Icons.error_outline
                            : Icons.radio_button_unchecked),
                    color: '${l['id']}' == _lineId
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    size: 20,
                  ),
                  title: Text('${l['name'] ?? l['id']}',
                      style: const TextStyle(fontSize: 14)),
                  subtitle: _failedLineId == '${l['id']}'
                      ? const Text('上次加载失败', style: TextStyle(fontSize: 11))
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
        );
      },
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _next() async {
    if (widget.playlist.isEmpty) {
      // 单个视频播完：显示“已播完”，不要卡住也不要直接退出
      if (mounted) {
        setState(() => _finished = true);
        Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _finished = false);
        });
      }
      return;
    }
    if (_index + 1 >= widget.playlist.length) {
      // 播到最后一集：显示“已播完”，不要卡住也不要直接退出
      if (mounted) {
        setState(() => _finished = true);
        Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _finished = false);
        });
      }
      return;
    }
    await _controller?.dispose();
    if (mounted) setState(() => _controller = null);
    setState(() => _index++);
    _initController(startAt: Duration.zero);
  }

  Future<void> _prev() async {
    if (widget.playlist.isEmpty) return;
    if (_index <= 0) {
      _toast('已经是第一集');
      return;
    }
    await _controller?.dispose();
    if (mounted) setState(() => _controller = null);
    setState(() => _index--);
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

  @override
  void dispose() {
    _saveResume();
    _resumeTimer?.cancel();
    _hideTimer?.cancel();
    _statsTimer?.cancel();
    _hintTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoSurface(),
            if (_gestureHint != null) _buildGestureHint(),
            if (_finished) _buildFinishedHint(),
            if (_error != null) _buildErrorOverlay(),
            if (!_locked && _showControls) _buildControls(),
            if (_pipAvailable && !_locked)
              Positioned(
                top: 12,
                right: 12,
                child: IconButton(
                  icon: const Icon(Icons.picture_in_picture_alt),
                  color: Colors.white,
                  tooltip: '画中画',
                  onPressed: () async {
                    final ok = await PipService.enter();
                    if (!ok && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('当前设备不支持画中画')),
                      );
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGestureHint() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          _gestureHint!,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildFinishedHint() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text('已播完',
            style: TextStyle(color: Colors.white, fontSize: 15)),
      ),
    );
  }

  /// 播放失败：显示“播放失败”，给换线路重试/重试，不直接退出播放页
  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 44, color: Colors.white70),
          const SizedBox(height: 14),
          const Text('播放失败',
              style: TextStyle(color: Colors.white, fontSize: 17)),
          const SizedBox(height: 6),
          const Text('地址无效或网络断了',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 20),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_hasLines)
                OutlinedButton(
                  onPressed: () {
                    setState(() => _error = null);
                    _fallbackLine();
                  },
                  style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54)),
                  child: const Text('换线路重试'),
                ),
              if (_hasLines) const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () {
                  final url = _failedUrl;
                  if (url == null) return;
                  setState(() => _error = null);
                  _openUrl(url,
                      startAt: _lastPosition, autoFallback: false);
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVideoSurface() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return Center(
          child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
    }
    return GestureDetector(
      onTap: () {
        if (_locked) return;
        if (_showControls) {
          setState(() => _showControls = false);
          _hideTimer?.cancel();
        } else {
          _showControlsTemporarily();
        }
      },
      // 左右滑快进/快退，显示秒数
      onHorizontalDragEnd: (d) {
        if (_locked) return;
        final dx = d.primaryVelocity ?? 0;
        if (dx > 0) {
          _seekBy(const Duration(seconds: 10));
          _showGestureHint('+10 秒');
        }
        if (dx < 0) {
          _seekBy(const Duration(seconds: -10));
          _showGestureHint('-10 秒');
        }
        _showControlsTemporarily();
      },
      // 左边上下滑调亮度，右边上下滑调音量，中间显示百分比
      onVerticalDragUpdate: (d) {
        if (_locked) return;
        final width = MediaQuery.of(context).size.width;
        final left = d.localPosition.dx < width / 2;
        final delta = -d.delta.dy / 200;
        if (left) {
          setState(() {
            _brightness = (_brightness + delta).clamp(0.0, 1.0);
          });
          _showGestureHint('亮度 ${(_brightness * 100).round()}%');
        } else {
          setState(() {
            _volume = (_volume + delta).clamp(0.0, 1.0);
          });
          _controller?.setVolume(_volume);
          _showGestureHint('音量 ${(_volume * 100).round()}%');
        }
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
      ),
    );
  }

  /// 控制条：上返回+标题，中间大播放/暂停，下进度条+时间，再下一行按钮
  Widget _buildControls() {
    final c = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 顶部：返回 + 标题
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 15)),
                ),
                IconButton(
                  icon: Icon(_locked ? Icons.lock : Icons.lock_open,
                      color: Colors.white),
                  onPressed: () {
                    setState(() => _locked = !_locked);
                    _armHideTimer();
                  },
                  tooltip: _locked ? '解锁界面' : '锁定界面防误触',
                ),
              ],
            ),
          ),
        ),
        // 中间大播放/暂停
        if (c != null)
          Center(
            child: GestureDetector(
              onTap: () {
                _togglePlay();
                _armHideTimer();
              },
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black45,
                  border: Border.all(color: Colors.white38),
                ),
                child: Icon(
                  c.value.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          ),
        // 底部：进度条 + 时间 + 按钮行
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c != null)
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: c,
                    builder: (context, v, _) {
                      final total = v.duration;
                      final pos = v.position;
                      return Row(
                        children: [
                          Expanded(
                            child: VideoProgressIndicator(
                              c,
                              allowScrubbing: true,
                              colors: VideoProgressColors(
                                  playedColor:
                                      Theme.of(context).colorScheme.primary,
                                  bufferedColor: Colors.white38,
                                  backgroundColor: Colors.white12),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${_fmtTime(pos)} / ${_fmtTime(total)}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                        ],
                      );
                    },
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                          c != null && c.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow,
                          color: Colors.white,
                          size: 28),
                      onPressed: () {
                        _togglePlay();
                        _armHideTimer();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous,
                          color: Colors.white),
                      tooltip: '上一集',
                      onPressed: () {
                        _prev();
                        _armHideTimer();
                      },
                    ),
                    IconButton(
                      icon:
                          const Icon(Icons.skip_next, color: Colors.white),
                      tooltip: '下一集',
                      onPressed: () {
                        _next();
                        _armHideTimer();
                      },
                    ),
                    _speedButton(),
                    if (_hasLines)
                      IconButton(
                        icon: _switching
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.swap_horiz,
                                color: Colors.white),
                        tooltip: '线路',
                        onPressed: _switching
                            ? null
                            : () {
                                _showLineSheet();
                                _armHideTimer();
                              },
                      ),
                    IconButton(
                      icon: Icon(
                          _fullscreen
                              ? Icons.fullscreen_exit
                              : Icons.fullscreen,
                          color: Colors.white),
                      tooltip: _fullscreen ? '退出全屏' : '全屏',
                      onPressed: () {
                        _toggleFullscreen();
                        _armHideTimer();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _fmtTime(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final h = d.inHours;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// 倍速按钮：点一下弹出选择（0.5/1/1.25/1.5/2），按钮上显示当前倍速
  Widget _speedButton() {
    return TextButton(
      onPressed: () async {
        final picked = await showMenu<double>(
          context: context,
          position: const RelativeRect.fromLTRB(100, 100, 100, 100),
          items: [0.5, 1.0, 1.25, 1.5, 2.0].map((v) {
            return PopupMenuItem<double>(
              value: v,
              child: Row(
                children: [
                  Text('${v}x'),
                  if ((_speed - v).abs() < 0.01) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.check, size: 16),
                  ],
                ],
              ),
            );
          }).toList(),
        );
        if (picked != null) {
          setState(() => _speed = picked);
          _controller?.setPlaybackSpeed(picked);
        }
        _armHideTimer();
      },
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 36),
      ),
      child: Text('${_speed}x', style: const TextStyle(fontSize: 13)),
    );
  }

  @override
  void deactivate() {
    // 离开播放页恢复竖屏 + 系统 UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    super.deactivate();
  }
}
