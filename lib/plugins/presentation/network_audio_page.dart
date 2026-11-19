import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/path_utils.dart';

/// 网络音频播放页（插件源直接播放 URL）
class NetworkAudioPage extends StatefulWidget {
  final String url;
  final String title;
  final String subtitle;
  final List<String> playlist;
  final int startIndex;
  final void Function(int index)? onNext;

  /// 缓存归属信息
  final String sourceId;
  final String bookName;

  const NetworkAudioPage({
    super.key,
    required this.url,
    required this.title,
    this.subtitle = '',
    this.playlist = const [],
    this.startIndex = 0,
    this.onNext,
    this.sourceId = '',
    this.bookName = '',
  });

  @override
  State<NetworkAudioPage> createState() => _NetworkAudioPageState();
}

class _NetworkAudioPageState extends State<NetworkAudioPage> {
  final _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _speed = 1.0;
  bool _ready = false;
  String? _error;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _posSub = _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
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
    _load();
  }

  Future<void> _load() async {
    try {
      // 纯在线流式播放，由播放器自己缓冲
      await _player.setUrl(widget.url);
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
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final total = _duration.inMilliseconds;
    final pos = _position.inMilliseconds.clamp(0, total == 0 ? 1 : total);
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
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
                child: const Icon(Icons.graphic_eq,
                    size: 72, color: Colors.white),
              ),
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
              Slider(
                value: pos.toDouble(),
                max: total == 0 ? 1 : total.toDouble(),
                onChanged: (v) =>
                    _player.seek(Duration(milliseconds: v.toInt())),
                activeColor: primary,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(PathUtils.formatDuration(_position.inMilliseconds),
                        style: Theme.of(context).textTheme.bodySmall),
                    Text(PathUtils.formatDuration(_duration.inMilliseconds),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    iconSize: 30,
                    icon: const Icon(Icons.replay_10),
                    onPressed: () {
                      final t = _position - const Duration(seconds: 10);
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
                    onPressed: () {
                      _player.seek(_position + const Duration(seconds: 10));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [0.75, 1.0, 1.25, 1.5, 2.0].map((v) {
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
