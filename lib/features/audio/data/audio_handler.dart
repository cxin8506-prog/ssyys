import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/log/app_logger.dart';

/// 音频播放处理器：桥接 just_audio 与 audio_service，提供通知栏控制、
/// 后台播放、倍速、定时关闭（渐弱）、断点续播回调。
class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  AudioPlayer get player => _player;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<double> get speedStream => _player.speedStream;

  int _currentIndex = 0;
  Timer? _sleepTimer;
  bool _fadingOut = false;

  MyAudioHandler() {
    _player.playbackEventStream.listen(_onPlaybackEvent, onError: (e, st) {
      appLogger.error('播放错误', error: e, stack: st);
    });

    // 播放完成时自动下一首
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        skipToNext();
      }
    });
  }

  void _onPlaybackEvent(PlaybackEvent event) {
    _currentIndex = _player.currentIndex ?? _currentIndex;
    final item = queue.value.isNotEmpty
        ? queue.value[_currentIndex.clamp(0, queue.value.length - 1)]
        : MediaItem(id: '', title: '');
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek, MediaAction.setSpeed},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _mapProcessingState(_player.processingState),
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: _currentIndex,
    ));
    if (item.id.isNotEmpty) mediaItem.add(item);
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  /// 设置播放队列（章节列表）
  Future<void> setQueue(List<MediaItem> items, {int initialIndex = 0}) async {
    queue.add(items);
    _currentIndex = initialIndex;
    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex]);
      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: items.map((m) => AudioSource.uri(Uri.parse(m.id))).toList(),
        ),
        initialIndex: initialIndex,
      );
    }
  }

  /// 用简单 Uri 列表设置队列（本地文件路径）
  Future<void> setUris(List<String> paths, {int initialIndex = 0}) async {
    final items = paths.map((p) {
      final name = p.split('/').last;
      return MediaItem(
        id: p,
        title: name,
        album: '本地听书',
        artUri: null,
      );
    }).toList();
    queue.add(items);
    _currentIndex = initialIndex;
    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex]);
      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: paths.map((p) => AudioSource.file(p)).toList(),
        ),
        initialIndex: initialIndex,
      );
    }
  }

  /// 跳转到指定章节
  Future<void> jumpToChapter(int i) async {
    await _player.seek(Duration.zero, index: i);
  }

  int get currentIndex => _player.currentIndex ?? 0;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> setSpeed(double speed) async => _player.setSpeed(speed);

  @override
  Future<void> rewind() async =>
      _player.seek(_player.position - const Duration(seconds: 15));

  @override
  Future<void> fastForward() async =>
      _player.seek(_player.position + const Duration(seconds: 15));

  /// 定时关闭（分钟）。结束前 30 秒音量渐弱。
  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    _fadingOut = false;
    if (minutes <= 0) return;
    final total = Duration(minutes: minutes);
    _sleepTimer = Timer(total, () => pause());
    // 结束前 30 秒开始渐弱
    final fadeAt = total - const Duration(seconds: 30);
    if (fadeAt > Duration.zero) {
      Timer(fadeAt, () async {
        _fadingOut = true;
        for (var v = 1.0; v > 0 && _fadingOut; v -= 0.1) {
          await _player.setVolume(v.clamp(0.0, 1.0));
          await Future.delayed(const Duration(seconds: 3));
        }
        await _player.setVolume(1.0);
      });
    }
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _fadingOut = false;
    _player.setVolume(1.0);
  }

  Future<void> dispose() async {
    _sleepTimer?.cancel();
    await _player.dispose();
  }
}

/// 全局音频 handler（在 main() 中通过 AudioService.init 初始化）
late final MyAudioHandler audioHandler;
