import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/database/library_repository.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../plugins/data/plugin_providers.dart';
import '../../plugins/model/plugin_source.dart';
import '../../plugins/presentation/source_book_page.dart';
import '../../shared/widgets/bottom_bar_inset.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/soft_ui.dart';

/// 首页（书架 tab）：梦幻紫樱皮肤。
///
/// 顶部 My Library 标题 + 胶囊搜索 + 吉祥物气泡，
/// 下面「正在听 / 已听完 / 收藏」胶囊 tab、三列封面卡、书架一隅横幅、书源。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _scrollController = ScrollController();
  String _segment = 'listening';
  String _sort = 'recent';
  List<String> _hiddenIds = const <String>[];

  @override
  void initState() {
    super.initState();
    _loadHidden();
  }

  Future<void> _loadHidden() async {
    final prefs = ref.read(sharedPrefsProvider);
    if (!mounted) return;
    setState(() {
      _hiddenIds = prefs.getStringList('hidden_book_ids') ?? const <String>[];
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(homeScrollToTopProvider, (_, __) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
    final repo = ref.watch(libraryRepositoryProvider);
    final videoEnabled = ref.watch(videoEnabledProvider);
    final sourcesAsync = ref.watch(sourceListProvider);

    return Scaffold(
      body: GradientBackdrop(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: FutureBuilder<List<MediaItem>>(
              future: _loadAll(repo),
              builder: (context, snapshot) {
                final all = snapshot.data ?? const <MediaItem>[];
                final visible =
                    all.where((e) => !_hiddenIds.contains(e.id)).toList();
                final listening =
                    visible.where((e) => !e.isFinished).toList(growable: false);
                final finished =
                    visible.where((e) => e.isFinished).toList(growable: false);
                final shown = _segment == 'listening' ? listening : finished;
                final sorted = _sortItems(shown, _sort);
                final continueItem = visible.isEmpty ? null : visible.first;
                return ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(top: 6),
                  children: [
                    _Header(
                      onSearch: () => context.push('/search'),
                      onSettings: () => context.push('/settings'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: PillSearch(
                        hint: '搜索书名 / 作者 / 关键词',
                        onTap: () => context.push('/search'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 14, 16, 2),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: MascotBubble(
                          text: '嗨，今天也来听个好故事吧～',
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (continueItem != null)
                      _ContinueCard(
                        item: continueItem,
                        onOpen: () => _openBook(continueItem),
                        onPlay: () => _openBook(continueItem, autoPlay: true),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: Row(
                        children: [
                          PillTabs(
                            value: _segment,
                            items: [
                              PillTabItem(
                                  'listening', '正在听 ${listening.length}'),
                              PillTabItem(
                                  'finished', '已听完 ${finished.length}'),
                              const PillTabItem('favorite', '收藏'),
                            ],
                            onChanged: (v) {
                              if (v == 'favorite') {
                                ref.read(shellTabProvider.notifier).state = 2;
                                return;
                              }
                              setState(() => _segment = v);
                            },
                          ),
                          const Spacer(),
                          _SortMenu(
                            value: _sort,
                            onChanged: (v) => setState(() => _sort = v),
                          ),
                        ],
                      ),
                    ),
                    SectionHeader(
                      title: _segment == 'listening' ? '正在听' : '已听完',
                      icon: Icons.headphones_rounded,
                      actionLabel: '查看全部',
                      onAction: () =>
                          ref.read(shellTabProvider.notifier).state = 2,
                    ),
                    if (sorted.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        child: EmptyState(
                          icon: Icons.menu_book_outlined,
                          title: _segment == 'listening' ? '还没有在听的书' : '还没有听完的书',
                          hint: '去发现页找书，或点上面的搜索框。',
                          actionLabel: '去发现',
                          onAction: () =>
                              ref.read(shellTabProvider.notifier).state = 1,
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: LayoutBuilder(
                          builder: (ctx, cons) {
                            final tileW = cons.maxWidth.isFinite
                                ? (cons.maxWidth - 20) / 3
                                : 100.0;
                            return Wrap(
                              spacing: 10,
                              runSpacing: 12,
                              children: [
                                for (final e in sorted)
                                  SizedBox(
                                    width: tileW,
                                    height: 205,
                                    child: _BookTile(
                                      item: e,
                                      onTap: () => _openBook(e),
                                      onHide: () => _hide(e),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    _CornerBanner(
                      count: visible.length,
                      finished: finished.length,
                      onTap: () =>
                          ref.read(shellTabProvider.notifier).state = 2,
                    ),
                    SectionHeader(
                      title: '书源',
                      icon: Icons.extension_rounded,
                      actionLabel: '管理',
                      onAction: () => context.push('/sources'),
                    ),
                    sourcesAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('读取源失败：$e'),
                      ),
                      data: (list) {
                        final enabled = list.where((s) => s.enabled).toList();
                        final shownSources = videoEnabled
                            ? enabled
                            : enabled.where((s) => s.isAudio).toList();
                        if (shownSources.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: EmptyState(
                              icon: Icons.extension_outlined,
                              title: '还没有导入源',
                              hint: '内容只从插件来，先导入一个 JS/ZIP 或 JAR 插件。',
                              actionLabel: '导入源',
                              onAction: () => context.push('/sources'),
                            ),
                          );
                        }
                        final columns = ref.watch(sourceColumnsProvider);
                        final cols = columns < 2 ? 2 : (columns > 4 ? 4 : columns);
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: LayoutBuilder(
                            builder: (ctx, cons) {
                              final tileW = cons.maxWidth.isFinite
                                  ? (cons.maxWidth - 10 * (cols - 1)) / cols
                                  : 160.0;
                              return Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (final s in shownSources)
                                    SizedBox(
                                      width: tileW,
                                      height: 96,
                                      child: _SourceCard(source: s),
                                    ),
                                ],
                              );
                            },
                          ),
                        );
                      },
                    ),
                    bottomBarSpace(context),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<List<MediaItem>> _loadAll(LibraryRepository repo) async {
    try {
      final listening = await repo.getListening();
      final finished = await repo.getFinished();
      final merged = <MediaItem>[...listening, ...finished];
      merged.sort(_byRecent);
      return merged;
    } catch (_) {
      return const <MediaItem>[];
    }
  }

  int _byRecent(MediaItem a, MediaItem b) {
    final at = a.lastPlayedAt;
    final bt = b.lastPlayedAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  }

  List<MediaItem> _sortItems(List<MediaItem> items, String sort) {
    final list = List<MediaItem>.from(items);
    switch (sort) {
      case 'name':
        list.sort((a, b) => a.title.compareTo(b.title));
        break;
      case 'manual':
        final order =
            ref.read(sharedPrefsProvider).getStringList('home_manual_order') ??
                const <String>[];
        list.sort((a, b) {
          final ia = order.indexOf(a.id);
          final ib = order.indexOf(b.id);
          final ra = ia >= 0 ? ia : 1000000;
          final rb = ib >= 0 ? ib : 1000000;
          return ra.compareTo(rb);
        });
        break;
      default:
        list.sort(_byRecent);
    }
    return list;
  }

  /// 从 MediaItem.id 里还原 bookUrl：插件书的 id 约定为 'sourceId|bookUrl'。
  String _bookUrlOf(MediaItem item) {
    final parts = item.id.split('|');
    if (parts.length >= 2) return parts.sublist(1).join('|');
    return '';
  }

  void _openBook(MediaItem item, {bool autoPlay = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SourceBookPage(
          sourceId: item.sourceId,
          bookUrl: _bookUrlOf(item),
          title: item.title,
          coverUrl: item.coverUrl,
          author: item.author,
          autoPlay: autoPlay,
        ),
      ),
    );
  }

  Future<void> _hide(MediaItem item) async {
    final prefs = ref.read(sharedPrefsProvider);
    final hidden = List<String>.from(_hiddenIds)..add(item.id);
    await prefs.setStringList('hidden_book_ids', hidden);
    if (!mounted) return;
    setState(() => _hiddenIds = hidden);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已隐藏，可在收藏页菜单里查看已隐藏的书')),
    );
  }
}

/// 顶部标题区：My Library / 我的书架 + 搜索与设置圆钮。
class _Header extends StatelessWidget {
  final VoidCallback onSearch;
  final VoidCallback onSettings;

  const _Header({required this.onSearch, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'My Library',
                  style: TextStyle(
                    fontSize: 27,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    shadows: [
                      Shadow(
                        color: primary.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '/ 我的书架',
                  style: TextStyle(fontSize: 13, color: context.subtleColor),
                ),
              ],
            ),
          ),
          CircleIconButton(icon: Icons.search_rounded, onTap: onSearch),
          const SizedBox(width: 10),
          CircleIconButton(icon: Icons.settings_outlined, onTap: onSettings),
        ],
      ),
    );
  }
}

/// 继续收听大卡：点卡片进书，点播放键直接播。
class _ContinueCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onOpen;
  final VoidCallback onPlay;

  const _ContinueCard({
    required this.item,
    required this.onOpen,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final accent = Theme.of(context).colorScheme.secondary;
    final progress = item.lastDurationMs > 0
        ? (item.lastPositionMs / item.lastDurationMs).clamp(0.0, 1.0)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: [primary, Color.lerp(primary, accent, 0.65)!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: primary.withOpacity(0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              CoverImage(
                url: item.coverUrl,
                title: item.title,
                width: 76,
                height: 100,
                radius: 12,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '继续收听',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.lastPositionMs > 0
                          ? '已听 ${formatDuration(item.lastPositionMs)}'
                          : '还没开始听',
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: Colors.white24,
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: onPlay,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.play_arrow_rounded, size: 28, color: primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 排序菜单：最近阅读 / 最新更新 / 书名 / 手动。
class _SortMenu extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SortMenu({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = <String, String>{
      'recent': '最近阅读',
      'updated': '最新更新',
      'name': '书名',
      'manual': '手动',
      'recentOrUpdated': '最近更新',
    };
    return PopupMenuButton<String>(
      onSelected: onChanged,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sort_rounded, size: 16, color: context.subtleColor),
          const SizedBox(width: 4),
          Text(
            labels[value] ?? '最近阅读',
            style: TextStyle(fontSize: 12, color: context.subtleColor),
          ),
        ],
      ),
      itemBuilder: (_) => labels.entries
          .map((e) => PopupMenuItem<String>(
                value: e.key,
                child: Text(e.value),
              ))
          .toList(),
    );
  }
}

/// 三列书架卡：封面 3:4 + 书名 + 作者·源 + 进度 + 已听时长。
class _BookTile extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onHide;

  const _BookTile({
    required this.item,
    required this.onTap,
    required this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final author = item.author ?? '';
    final sourceName = item.sourceName;
    final meta = [if (author.isNotEmpty) author, if (sourceName.isNotEmpty) sourceName]
        .join(' · ');
    final progress = item.lastDurationMs > 0
        ? (item.lastPositionMs / item.lastDurationMs).clamp(0.0, 1.0)
        : 0.0;
    final listened = item.isFinished
        ? '已听完'
        : (item.lastPositionMs > 0
            ? '已听 ${formatDuration(item.lastPositionMs)}'
            : '未收听');
    return SoftCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      radius: 18,
      onTap: onTap,
      child: GestureDetector(
        onLongPress: () async {
          final hide = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(item.title),
              content: const Text('要隐藏这本书吗？隐藏后不在首页显示，可在收藏页菜单里查看已隐藏的书。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('隐藏'),
                ),
              ],
            ),
          );
          if (hide == true) onHide();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: LayoutBuilder(
                builder: (ctx, cons) {
                  final w = cons.maxWidth.isFinite ? cons.maxWidth : 96.0;
                  return CoverImage(
                    url: item.coverUrl,
                    title: item.title,
                    width: w,
                    height: w * 4 / 3,
                    radius: 12,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: context.subtleColor),
            ),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: context.palette.surfaceAlt,
                valueColor: AlwaysStoppedAnimation<Color>(primary),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              listened,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: context.subtleColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// 书架一隅横幅：贴纸感的统计卡。
class _CornerBanner extends StatelessWidget {
  final int count;
  final int finished;
  final VoidCallback onTap;

  const _CornerBanner({
    required this.count,
    required this.finished,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SoftCard(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: onTap,
      child: Row(
        children: [
          IconBadge(icon: Icons.auto_stories_rounded, size: 46, color: primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '书架里收藏了 $count 本好故事',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '其中已听完 $finished 本。每一本，都是心灵的一次旅行。',
                  style: TextStyle(fontSize: 11, color: context.subtleColor),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: context.subtleColor),
        ],
      ),
    );
  }
}

class _SourceCard extends ConsumerWidget {
  final PluginSource source;

  const _SourceCard({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeHomeSourceProvider);
    final selected = active?.id == source.id;
    final primary = Theme.of(context).colorScheme.primary;
    final desc = source.description;
    return InkWell(
      onTap: () {
        ref.read(activeHomeSourceProvider.notifier).state = source;
        ref.read(shellTabProvider.notifier).state = 1;
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? primary : context.palette.outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SourceAvatar(name: source.name, size: 30),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    source.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              source.isAudio ? '听书源' : '视频源',
              style: TextStyle(fontSize: 11, color: context.subtleColor),
            ),
            if (desc.isNotEmpty)
              Text(
                desc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: context.subtleColor),
              ),
          ],
        ),
      ),
    );
  }
}
