import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/common.dart';
import '../data/importer.dart';
import '../data/repository_providers.dart';
import '../domain/media_item.dart';
import 'audio_player_page.dart';

/// 听书书架页
class AudioLibraryPage extends ConsumerStatefulWidget {
  /// 作为「书架」Tab 内嵌时隐藏自己的 AppBar
  final bool embedded;
  const AudioLibraryPage({super.key, this.embedded = false});

  @override
  ConsumerState<AudioLibraryPage> createState() => _AudioLibraryPageState();
}

class _AudioLibraryPageState extends ConsumerState<AudioLibraryPage> {
  String _sortBy = AppConstants.sortByAddedAt;
  String _filter = AppConstants.filterAll;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(libraryRepositoryProvider);
    final future = repo.query(
      type: AppConstants.typeAudio,
      sortBy: _sortBy,
      filter: _filter,
    );

    return Scaffold(
      appBar: widget.embedded ? null : AppBar(
        title: const Text('听书'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (v) => setState(() => _sortBy = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: AppConstants.sortByName, child: Text('按名称')),
              PopupMenuItem(
                  value: AppConstants.sortByAddedAt, child: Text('按导入时间')),
              PopupMenuItem(
                  value: AppConstants.sortByProgress, child: Text('按进度')),
              PopupMenuItem(
                  value: AppConstants.sortByLastRead, child: Text('按最近阅读')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).pushNamed('/audio-search'),
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
                  icon: Icons.headphones_outlined,
                  message: '书架还是空的',
                  hint: '点右下角 + 在源里搜书，在线收听',
                  onAction: _import,
                  actionLabel: '找书',
                );
              }
              return Column(
                children: [
                  _buildFilterBar(),
                  Expanded(child: _buildGrid(items)),
                ],
              );
            },
          ),
          if (_loading) const LoadingOverlay(message: '处理中...'),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          _filterChip('全部', AppConstants.filterAll),
          _filterChip('未读', AppConstants.filterUnread),
          _filterChip('在读', AppConstants.filterReading),
          _filterChip('已读', AppConstants.filterFinished),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.25),
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _buildGrid(List<MediaItem> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: 0.68,
      ),
      itemBuilder: (context, index) => _buildCard(items[index]),
    );
  }

  Widget _buildCard(MediaItem item) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AudioPlayerPage(item: item),
      )),
      onLongPress: () => _showItemMenu(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                CoverImage(
                    path: item.coverPath,
                    title: item.title,
                    size: double.infinity),
                if (item.progress > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: item.progress > 1
                          ? item.progress / 100
                          : item.progress,
                      color: Theme.of(context).colorScheme.primary,
                      backgroundColor: Colors.black38,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium),
          Text('${item.chapterCount} 章 · ${item.statusLabel}',
              maxLines: 1, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  void _showItemMenu(MediaItem item) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('查看详情'),
              subtitle:
                  Text(item.path, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('改名'),
              onTap: () {
                Navigator.pop(context);
                _renameDialog(item);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Colors.redAccent),
              title:
                  const Text('删除', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                _deleteWithUndo(item);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _renameDialog(MediaItem item) {
    final controller = TextEditingController(text: item.title);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref
                    .read(libraryRepositoryProvider)
                    .rename(item.id, controller.text.trim());
              }
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _deleteWithUndo(MediaItem item) {
    final repo = ref.read(libraryRepositoryProvider);
    repo.delete(item.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除「${item.title}」'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => repo.saveImport(ImportResult(item: item)),
        ),
      ),
    );
  }

  Future<void> _import() async {
    // 只从插件源在线获取内容
    await Navigator.of(context).pushNamed('/source-search');
    if (mounted) setState(() {});
  }
}
