import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/path_utils.dart';
import '../../../shared/widgets/common.dart';
import '../../audio/data/repository_providers.dart';
import '../../audio/domain/media_item.dart';
import 'video_player_page.dart';

/// 视频书架页
class VideoLibraryPage extends ConsumerStatefulWidget {
  /// 作为「书架」Tab 内嵌时隐藏自己的 AppBar
  final bool embedded;
  const VideoLibraryPage({super.key, this.embedded = false});

  @override
  ConsumerState<VideoLibraryPage> createState() => _VideoLibraryPageState();
}

class _VideoLibraryPageState extends ConsumerState<VideoLibraryPage> {
  String _sortBy = AppConstants.sortByAddedAt;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(libraryRepositoryProvider);
    final future = repo.query(type: AppConstants.typeVideo, sortBy: _sortBy);

    return Scaffold(
      appBar: widget.embedded ? null : AppBar(
        title: const Text('视频'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (v) => setState(() => _sortBy = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: AppConstants.sortByName, child: Text('按名称')),
              PopupMenuItem(
                  value: AppConstants.sortByAddedAt, child: Text('按导入时间')),
              PopupMenuItem(
                  value: AppConstants.sortByLastRead, child: Text('按最近播放')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _import,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.black87),
      ),
      body: Stack(
        children: [
          FutureBuilder<List<MediaItem>>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                    child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
              }
              final items = snap.data ?? [];
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.movie_outlined,
                  message: '还没有视频',
                  hint: '点右下角 + 在视频源里搜索，在线播放',
                  onAction: _import,
                  actionLabel: '找视频',
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.1,
                ),
                itemBuilder: (context, i) => _buildCard(items[i], items),
              );
            },
          ),
          if (_loading) const LoadingOverlay(message: '正在导入...'),
        ],
      ),
    );
  }

  Widget _buildCard(MediaItem item, List<MediaItem> all) {
    return GestureDetector(
      onTap: () async {
        final chapters =
            await ref.read(libraryRepositoryProvider).chapters(item.id);
        if (chapters.isEmpty) return;
        final paths = chapters.map((c) => c.path!).toList();
        {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => VideoPlayerPage(
              path: paths.first,
              playlist: paths,
              initialIndex: 0,
              title: item.title,
            ),
          ));
        }
      },
      child: Card(
        color: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
                child: CoverImage(
                    path: item.coverPath,
                    title: item.title,
                    size: double.infinity,
                    isVideo: true)),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium),
                  Text(
                      '${item.chapterCount} 个视频 · ${PathUtils.formatSize(item.sizeBytes)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _import() async {
    // 只从插件源在线获取内容
    await Navigator.of(context).pushNamed('/source-search-video');
    if (mounted) setState(() {});
  }
}
