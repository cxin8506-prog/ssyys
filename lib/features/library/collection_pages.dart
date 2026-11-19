import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/path_utils.dart';
import '../../shared/widgets/common.dart';
import '../audio/data/repository_providers.dart';
import '../audio/domain/media_item.dart';

/// 收藏 / 历史 / 书签 页面集合。听书与视频用 type 严格分开。
enum CollectionKind { favorite, history, bookmark }

class CollectionPage extends ConsumerStatefulWidget {
  final CollectionKind kind;
  final String type; // audio | video
  const CollectionPage({super.key, required this.kind, required this.type});

  @override
  ConsumerState<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<CollectionPage> {
  @override
  Widget build(BuildContext context) {
    final repo = ref.read(libraryRepositoryProvider);
    final future = widget.kind == CollectionKind.favorite
        ? repo.favorites(widget.type)
        : repo.history(widget.type);
    final title = _title();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<List<MediaItem>>(
        future: future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.primary));
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return EmptyState(icon: _icon(), message: '暂无$title记录');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            itemBuilder: (context, i) => _buildTile(items[i]),
          );
        },
      ),
    );
  }

  String _title() {
    String base;
    switch (widget.kind) {
      case CollectionKind.favorite:
        base = '收藏';
        break;
      case CollectionKind.history:
        base = '历史';
        break;
      case CollectionKind.bookmark:
        base = '书签';
        break;
    }
    return '$base · ${widget.type == AppConstants.typeAudio ? '听书' : '视频'}';
  }

  IconData _icon() {
    switch (widget.kind) {
      case CollectionKind.favorite:
        return Icons.favorite_border;
      case CollectionKind.history:
        return Icons.history;
      case CollectionKind.bookmark:
        return Icons.bookmark_border;
    }
  }

  Widget _buildTile(MediaItem item) {
    return Card(
      color: AppTheme.darkSurface,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CoverImage(
            path: item.coverPath,
            title: item.title,
            size: 44,
            isVideo: item.isVideo),
        title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
            '${item.chapterCount} 章 · ${PathUtils.formatSize(item.sizeBytes)}'),
        trailing: widget.kind == CollectionKind.favorite
            ? IconButton(
                icon: const Icon(Icons.favorite, color: AppTheme.primary),
                onPressed: () async {
                  await ref
                      .read(libraryRepositoryProvider)
                      .removeFavorite(item.id);
                  setState(() {});
                },
              )
            : null,
      ),
    );
  }
}

/// 书签独立管理页（跨条目列出所有书签）
class BookmarkListPage extends ConsumerWidget {
  const BookmarkListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.read(libraryRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('书签')),
      body: FutureBuilder<List<dynamic>>(
        future: db.bookmarks('').then((v) => v.cast<dynamic>()),
        builder: (context, snap) {
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return const EmptyState(
                icon: Icons.bookmark_border, message: '暂无书签');
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final b = rows[i];
              return ListTile(
                leading: const Icon(Icons.bookmark, color: AppTheme.primary),
                title:
                    Text('位置 ${PathUtils.formatDuration(b.positionMs as int)}'),
                subtitle: Text(b.note as String? ?? '书签'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {},
                ),
              );
            },
          );
        },
      ),
    );
  }
}
