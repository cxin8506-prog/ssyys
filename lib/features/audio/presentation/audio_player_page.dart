import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/common.dart';
import '../data/audio_handler.dart';
import '../data/repository_providers.dart';
import '../domain/media_item.dart' as domain;

/// 听书播放页
class AudioPlayerPage extends ConsumerStatefulWidget {
  final domain.MediaItem item;
  const AudioPlayerPage({super.key, required this.item});

  @override
  ConsumerState<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends ConsumerState<AudioPlayerPage> {
  List<domain.ChapterItem> _chapters = [];
  int _currentIndex = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // 离开播放页时保存断点进度
    try {
      final pos = audioHandler.playbackState.valueOrNull?.updatePosition ??
          Duration.zero;
      final idx = audioHandler.currentIndex;
      final chapter =
          (idx >= 0 && idx < _chapters.length) ? _chapters[idx] : null;
      final totalMs = widget.item.durationMs ?? 0;
      ref.read(libraryRepositoryProvider).updateProgress(
            itemId: widget.item.id,
            chapterId: chapter?.id,
            positionMs: pos.inMilliseconds,
            progress: totalMs > 0 ? pos.inMilliseconds / totalMs : null,
          );
    } catch (_) {
      // 退出时保存失败不影响体验
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(libraryRepositoryProvider);
    final chapters = await repo.chapters(widget.item.id);
    final progress = await repo.getProgress(widget.item.id);
    final handler = audioHandler;
    final paths = chapters
        .where((c) => c.path != null && !c.isCorrupted)
        .map((c) => c.path!)
        .toList();
    int startIndex = 0;
    if (paths.isNotEmpty && progress != null && progress.chapterId != null) {
      final idx = chapters.indexWhere((c) => c.id == progress.chapterId);
      if (idx >= 0 && idx < paths.length) startIndex = idx;
    }
    if (paths.isNotEmpty) {
      await handler.setUris(paths, initialIndex: startIndex);
      if (progress != null && progress.positionMs > 0 && startIndex == 0) {
        await handler.seek(Duration(milliseconds: progress.positionMs));
      }
      await handler.play();
    }
    await repo.addHistory(widget.item.id, widget.item.type);
    if (mounted)
      setState(() {
        _chapters = chapters;
        _currentIndex = startIndex;
        _ready = true;
      });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_border),
            onPressed: _addBookmark,
            tooltip: '添加书签',
          ),
          IconButton(
            icon: const Icon(Icons.timer_outlined),
            onPressed: _showSleepTimer,
            tooltip: '定时关闭',
          ),
        ],
      ),
      body: !_ready
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
              children: [
                const SizedBox(height: 20),
                CoverImage(
                    path: widget.item.coverPath,
                    title: widget.item.title,
                    size: 150),
                const SizedBox(height: 24),
                Text(widget.item.title,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('${_chapters.length} 章',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                _buildControls(),
                const SizedBox(height: 8),
                _buildSpeedRow(),
                const SizedBox(height: 16),
                Expanded(child: _buildChapterList()),
              ],
            ),
    );
  }

  Widget _buildControls() {
    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? false;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
                icon: const Icon(Icons.replay),
                iconSize: 32,
                onPressed: () => audioHandler.rewind()),
            IconButton(
                icon: const Icon(Icons.skip_previous),
                iconSize: 36,
                onPressed: () => audioHandler.skipToPrevious()),
            CircleAvatar(
              radius: 32,
              backgroundColor: AppTheme.primary,
              child: IconButton(
                icon: Icon(playing ? Icons.pause : Icons.play_arrow,
                    color: Colors.black87),
                iconSize: 32,
                onPressed: () =>
                    playing ? audioHandler.pause() : audioHandler.play(),
              ),
            ),
            IconButton(
                icon: const Icon(Icons.skip_next),
                iconSize: 36,
                onPressed: () => audioHandler.skipToNext()),
            IconButton(
                icon: const Icon(Icons.forward),
                iconSize: 32,
                onPressed: () => audioHandler.fastForward()),
          ],
        );
      },
    );
  }

  Widget _buildSpeedRow() {
    return StreamBuilder<double>(
      stream: audioHandler.speedStream,
      initialData: 1.0,
      builder: (context, snap) {
        final speed = snap.data ?? 1.0;
        return Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [0.75, 1.0, 1.25, 1.5, 2.0, 3.0].map((s) {
            return ChoiceChip(
              label: Text('${s}x'),
              selected: (speed - s).abs() < 0.01,
              onSelected: (_) => audioHandler.setSpeed(s),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildChapterList() {
    return StreamBuilder<int?>(
      stream: audioHandler.player.currentIndexStream,
      builder: (context, snap) {
        final current = snap.data ?? _currentIndex;
        return ListView.builder(
          itemCount: _chapters.length,
          itemBuilder: (context, i) {
            final c = _chapters[i];
            final selected = i == current;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    selected ? AppTheme.primary : AppTheme.darkSurfaceAlt,
                child: Text('${i + 1}',
                    style: TextStyle(
                        color:
                            selected ? Colors.black87 : AppTheme.darkTextSub)),
              ),
              title: Text(c.title,
                  style: TextStyle(color: selected ? AppTheme.primary : null)),
              subtitle: c.isCorrupted
                  ? const Text('损坏，已跳过',
                      style: TextStyle(color: Colors.redAccent))
                  : null,
              onTap: () => audioHandler.jumpToChapter(i),
            );
          },
        );
      },
    );
  }

  void _addBookmark() {
    final pos =
        audioHandler.playbackState.valueOrNull?.updatePosition ?? Duration.zero;
    final idx = audioHandler.currentIndex;
    final repo = ref.read(libraryRepositoryProvider);
    final chapterId =
        (idx >= 0 && idx < _chapters.length) ? _chapters[idx].id : null;
    repo.addBookmark(
      itemId: widget.item.id,
      chapterId: chapterId,
      positionMs: pos.inMilliseconds,
    );
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('书签已添加')));
  }

  void _showSleepTimer() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('定时关闭', style: TextStyle(fontSize: 16)),
            ),
            Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: [5, 10, 15, 30, 45, 60].map((min) {
                return ActionChip(
                  label: Text('$min 分钟'),
                  onPressed: () {
                    audioHandler.setSleepTimer(min);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('已设置 $min 分钟后关闭（结束前渐弱）')),
                    );
                  },
                );
              }).toList(),
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('取消定时'),
              onTap: () {
                audioHandler.cancelSleepTimer();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
