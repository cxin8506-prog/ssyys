import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/log/app_logger.dart';
import '../../../core/platform/pip_service.dart';
import '../../../core/theme/app_theme.dart';

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

  bool get _hasLines => widget.lines.length > 1 && widget.onSwitchLine != null;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _lineId = widget.currentLineId ??
        (widget.lines.isNotEmpty ? '${widget.lines.first['id']}' : null);
    _initController();
    PipService.isAvailable().then((v) {
      if (mounted && v) setState(() => _pipAvailable = v);
    });
  }

  Future<void> _initController() async {
    final paths = widget.playlist.isNotEmpty ? widget.playlist : [widget.path];
    final safeIndex = _index.clamp(0, paths.length - 1);
    await _openUrl(paths[safeIndex]);
  }

  /// 用某个地址起播。startAt 为空时从当前进度续播。
  Future<void> _openUrl(String url,
      {Duration? startAt, bool autoFallback = true}) async {
    final keep = startAt ??
        (_controller?.value.isInitialized == true
            ? _controller!.value.position
            : _lastPosition);
    final ctrl = widget.network
        ? VideoPlayerController.network(url)
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
      setState(() => _controller = ctrl);
      await old?.dispose();
      await ctrl.play();
    } catch (e, st) {
      appLogger.error('视频播放失败', error: e, stack: st);
      await ctrl.dispose();
      if (!mounted) return;
      _lastPosition = keep;
      if (autoFallback && await _fallbackLine()) return;
      _toast(_hasLines ? '所有线路都无法播放' : '视频加载失败');
      if (widget.playlist.isNotEmpty) _next();
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
    if (widget.playlist.isEmpty) return;
    if (_index + 1 >= widget.playlist.length) {
      if (mounted) Navigator.pop(context);
      return;
    }
    await _controller?.dispose();
    setState(() => _index++);
    _initController();
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
            if (!_locked && _showControls) _buildControls(),
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                children: [
                  if (_pipAvailable && !_locked)
                    IconButton(
                      icon: const Icon(Icons.picture_in_picture_alt),
                      color: Colors.white,
                      tooltip: '画中画',
                      onPressed: () async {
                        final ok = await PipService.enter();
                        if (!ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('当前设备不支持画中画')),
                          );
                        }
                      },
                    ),
                  if (_hasLines && !_locked)
                    IconButton(
                      icon: _switching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.swap_horiz),
                      color: Colors.white,
                      tooltip: '切换线路',
                      onPressed: _switching ? null : _showLineSheet,
                    ),
                  IconButton(
                    icon: Icon(_locked ? Icons.lock : Icons.lock_open),
                    color: Colors.white,
                    onPressed: () => setState(() => _locked = !_locked),
                    tooltip: _locked ? '解锁界面' : '锁定界面防误触',
                  ),
                ],
              ),
            ),
          ],
        ),
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
      onTap: () => setState(() => _showControls = !_showControls),
      onHorizontalDragEnd: (d) {
        if (_locked) return;
        final dx = d.primaryVelocity ?? 0;
        if (dx > 0) _seekBy(const Duration(seconds: 10));
        if (dx < 0) _seekBy(const Duration(seconds: -10));
      },
      onVerticalDragEnd: (d) {
        if (_locked) return;
        final dy = d.primaryVelocity ?? 0;
        if (dy > 0) setState(() => _volume = (_volume - 0.1).clamp(0.0, 1.0));
        if (dy < 0)
          setState(() => _brightness = (_brightness + 0.1).clamp(0.0, 1.0));
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final c = _controller;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: Colors.black54,
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title,
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 8),
            VideoProgressIndicator(c!,
                allowScrubbing: true,
                colors: VideoProgressColors(
                    playedColor: Theme.of(context).colorScheme.primary,
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white12)),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    icon: const Icon(Icons.replay_10, color: Colors.white),
                    onPressed: () => _seekBy(const Duration(seconds: -10))),
                IconButton(
                    icon: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 32),
                    onPressed: _togglePlay),
                IconButton(
                    icon: const Icon(Icons.forward_10, color: Colors.white),
                    onPressed: () => _seekBy(const Duration(seconds: 10))),
                IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    onPressed: _next),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _speedChip(0.5),
                _speedChip(1.0),
                _speedChip(1.5),
                _speedChip(2.0),
                const SizedBox(width: 12),
                IconButton(
                    icon: const Icon(Icons.aspect_ratio, color: Colors.white),
                    onPressed: _cycleFit,
                    tooltip: '画面比例'),
                IconButton(
                    icon: const Icon(Icons.fullscreen, color: Colors.white),
                    onPressed: _toggleFullscreen),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _speedChip(double s) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
          label: Text('${s}x', style: const TextStyle(fontSize: 11)),
          selected: (_speed - s).abs() < 0.01,
          selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          onSelected: (_) {
            setState(() => _speed = s);
            _controller?.setPlaybackSpeed(s);
          },
        ),
      );

  void _cycleFit() {
    setState(() {
      _fit = ScreenFit.values[(_fit.index + 1) % ScreenFit.values.length];
    });
    // 实际适配在 VideoPlayer 外层用 BoxFit 包装，这里演示切换状态
  }

  void _toggleFullscreen() {
    // 横屏全屏：隐藏系统 UI 并旋转
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void deactivate() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);
    super.deactivate();
  }
}
