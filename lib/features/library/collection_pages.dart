import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/path_utils.dart';
import '../../shared/widgets/common.dart';
import '../audio/data/repository_providers.dart';
import '../audio/domain/media_item.dart';
import '../audio/presentation/audio_player_page.dart';
import '../video/presentation/video_player_page.dart';

/// 收藏 / 历史 通用页面：听书与视频分栏，网格卡片
enum CollectionKind { favorite, history, bookmark }

class CollectionPage extends ConsumerStatefulWidget {
  final CollectionKind kind;
  final String initialType;

  const CollectionPage({
    super.key,
    required this.kind,
    this.initialType = AppConstants.typeAudio,
  });

  @override
  ConsumerState<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<CollectionPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late String _type;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _tabs = TabController(
        length: 2,
        vsync: this,
        initialIndex: _type == AppConstants.typeVideo ? 1 : 0);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        setState(() {
          _type = _tabs.index == 0
              ? AppConstants.typeAudio
              : AppConstants.typeVideo;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: primary,
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: primary,
          unselectedLabelColor: context.subtleColor,
          tabs: const [Tab(text: '听书'), Tab(text: '视频')],
        ),
      ),
      body: FutureBuilder<List<MediaItem>>(
        future: _load(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return EmptyState(
              icon: _icon,
              message: '还没有${widget.kind == CollectionKind.favorite ? '收藏' : '记录'}',
              hint: _type == AppConstants.typeAudio
                  ? '在听书页长按条目，或播放页点收藏'
                  : '在视频页长按条目即可加入',
            );
          }
          return GridView.builder(
            padding: pagePadding(context, top: 14, bottom: 24),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 18,
              childAspectRatio: 0.62,
            ),
            itemBuilder: (_, i) => _card(items[i]),
          );
        },
      ),
    );
  }

  Future<List<MediaItem>> _load() {
    final repo = ref.read(libraryRepositoryProvider);
    if (widget.kind == CollectionKind.favorite) {
      return repo.favorites(_type);
    }
    return repo.history(_type);
  }

  String get _title =>
      widget.kind == CollectionKind.favorite ? '收藏' : '历史';

  IconData get _icon => widget.kind == CollectionKind.favorite
      ? Icons.favorite_border
      : Icons.history;

  Widget _card(MediaItem item) {
    final p = item.progress > 1 ? item.progress / 100 : item.progress;
    return GestureDetector(
      onTap: () async {
        final chapters =
            await ref.read(libraryRepositoryProvider).chapters(item.id);
        if (chapters.isEmpty) return;
        if (item.isAudio) {
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AudioPlayerPage(item: item)));
        } else {
          final paths = chapters.map((c) => c.path!).toList();
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => VideoPlayerPage(
                  path: paths.first, playlist: paths, title: item.title)));
        }
      },
      onLongPress: () => _menu(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (ctx, c) => CoverImage(
                        path: item.coverPath,
                        title: item.title,
                        size: c.maxWidth,
                        isVideo: item.isVideo),
                  ),
                ),
                if (p > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(8)),
                      child: LinearProgressIndicator(
                        value: p,
                        minHeight: 4,
                        color: Theme.of(context).colorScheme.primary,
                        backgroundColor: Colors.black38,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            widget.kind == CollectionKind.favorite
                ? '${item.chapterCount} 章'
                : '${item.statusLabel} · ${item.chapterCount} 章',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }

  void _menu(MediaItem item) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  Text(PathUtils.formatSize(item.sizeBytes),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('查看路径'),
              subtitle: Text(item.path,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(ctx),
            ),
            ListTile(
              leading: Icon(Icons.favorite_border,
                  color: Theme.of(context).colorScheme.primary),
              title: Text(widget.kind == CollectionKind.favorite
                  ? '取消收藏'
                  : '加入收藏'),
              onTap: () async {
                Navigator.pop(ctx);
                final repo = ref.read(libraryRepositoryProvider);
                if (widget.kind == CollectionKind.favorite) {
                  await repo.removeFavorite(item.id);
                } else {
                  await repo.addFavorite(item.id, item.type);
                }
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 书签独立管理页（跨条目列出所有书签）
class BookmarkListPage extends ConsumerWidget {
  const BookmarkListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(libraryRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('书签')),
      body: FutureBuilder<List<dynamic>>(
        future: repo.bookmarks('').then((v) => v.cast<dynamic>()),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return const EmptyState(
                icon: Icons.bookmark_border,
                message: '还没有书签',
                hint: '播放时点书签按钮，会在当前位置留一个标记');
          }
          return ListView.separated(
            padding: pagePadding(context, top: 14, bottom: 24),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final b = rows[i];
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.palette.outline),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: context.palette.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.bookmark,
                          size: 17,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              PathUtils.formatDuration(
                                  (b.positionMs as int?) ?? 0),
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text((b.note as String?) ?? '书签',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
