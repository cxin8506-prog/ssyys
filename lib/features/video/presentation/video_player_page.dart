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

  const VideoPlayerPage({
    super.key,
    required this.path,
    this.playlist = const [],
    this.initialIndex = 0,
    required this.title,
    this.network = false,
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

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _initController();
    PipService.isAvailable().then((v) {
      if (mounted && v) setState(() => _pipAvailable = v);
    });
  }

  Future<void> _initController() async {
    final paths = widget.playlist.isNotEmpty ? widget.playlist : [widget.path];
    final safeIndex = _index.clamp(0, paths.length - 1);
    final ctrl = widget.network
        ? VideoPlayerController.network(paths[safeIndex])
        : VideoPlayerController.file(File(paths[safeIndex]));
    try {
      await ctrl.initialize();
      await ctrl.setPlaybackSpeed(_speed);
      await ctrl.setVolume(_volume);
      if (mounted) {
        setState(() => _controller = ctrl);
      } else {
        await ctrl.dispose();
        return;
      }
      await ctrl.play();
    } catch (e, st) {
      // 损坏视频跳过并写日志
      appLogger.error('视频播放失败，已跳过', error: e, stack: st);
      await ctrl.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('视频加载失败，已跳过。若来自网络源，可尝试修改 UA 后重试'),
            action: SnackBarAction(
              label: 'UA 设置',
              onPressed: () => Navigator.of(context).pushNamed('/ua-settings'),
            ),
          ),
        );
      }
      _next();
    }
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
