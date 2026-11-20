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

/// 首页（书源 tab）。
///
/// 只留：搜索、继续收听大卡、在听 / 听完、源。
/// 没有分类板块，没有推荐 feed（审计 D 第 21 项：首页的
/// 「分类·玄幻武侠」板块是错放到首页的源内分类，重写删掉；
/// 分类只在发现页按当前源展示）。
/// 点源卡片 = 切源 + 进该源页（发现页）；源卡片上没有假放大镜。
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
      appBar: AppBar(
        title: const Text('随意听书'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: FutureBuilder<List<MediaItem>>(
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
          return RefreshIndicator(
            onRefresh: () async {
              setState(() {});
            },
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.only(left: 16, right: 16, top: 12),
              children: [
                _SearchEntry(
                  onTap: () => context.push('/search'),
                ),
                const SizedBox(height: 12),
                if (continueItem != null)
                  _ContinueCard(
                    item: continueItem,
                    onOpen: () => _openBook(continueItem),
                    onPlay: () => _openBook(continueItem, autoPlay: true),
                  ),
                const SectionTitle(title: '在听 / 听完'),
                _SegmentBar(
                  value: _segment,
                  listeningCount: listening.length,
                  finishedCount: finished.length,
                  onChanged: (v) => setState(() => _segment = v),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Spacer(),
                    _SortMenu(
                      value: _sort,
                      onChanged: (v) => setState(() => _sort = v),
                    ),
                  ],
                ),
                if (sorted.isEmpty)
                  EmptyState(
                    icon: Icons.menu_book_outlined,
                    title: _segment == 'listening' ? '还没有在听的书' : '还没有听完的书',
                    hint: '去发现页找书，或点右上角搜索。',
                    actionLabel: '去发现',
                    onAction: () =>
                        ref.read(shellTabProvider.notifier).state = 1,
                  )
                else
                  ...sorted.map((e) => _BookRow(
                        item: e,
                        onTap: () => _openBook(e),
                        onHide: () => _hide(e),
                      )),
                const SectionTitle(title: '源'),
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
                      return EmptyState(
                        icon: Icons.extension_outlined,
                        title: '还没有导入源',
                        hint: '内容只从插件来，先导入一个 JS/ZIP 或 JAR 插件。',
                        actionLabel: '导入源',
                        onAction: () => context.push('/sources'),
                      );
                    }
                    final columns = ref.watch(sourceColumnsProvider);
                    final cols =
                        columns < 2 ? 2 : (columns > 4 ? 4 : columns);
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        mainAxisExtent: 96,
                      ),
                      itemCount: shownSources.length,
                      itemBuilder: (_, i) =>
                          _SourceCard(source: shownSources[i]),
                    );
                  },
                ),
                bottomBarSpace(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<List<MediaItem>> _loadAll(LibraryRepository repo) async {
    try {
      final listening = await repo.getListening();
      final finished = await repo.getFinished();
      final merged = <MediaItem>[...listening, ...finished];
      merged.sort((a, b) {
        final at = a.lastPlayedAt;
        final bt = b.lastPlayedAt;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });
      return merged;
    } catch (_) {
      return const <MediaItem>[];
    }
  }

  List<MediaItem> _sortItems(List<MediaItem> items, String sort) {
    final list = List<MediaItem>.from(items);
    switch (sort) {
      case 'name':
        list.sort((a, b) => a.title.compareTo(b.title));
        break;
      case 'updated':
        list.sort((a, b) {
          final at = a.lastPlayedAt;
          final bt = b.lastPlayedAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
        break;
      case 'recentOrUpdated':
        // 最近阅读或更新：这里按最后播放时间倒序（更新时间未单独立字段）。
        list.sort((a, b) {
          final at = a.lastPlayedAt;
          final bt = b.lastPlayedAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
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
      default: // recent
        list.sort((a, b) {
          final at = a.lastPlayedAt;
          final bt = b.lastPlayedAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
    }
    return list;
  }

  /// 从 MediaItem.id 里还原 bookUrl：插件书的 id 约定为
  /// 'sourceId|bookUrl'；解析不到就返回空字符串，详情页会退回源首页。
  /// （跨组缺口：契约的 MediaItem 字段里没有 bookUrl；见汇报。）
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

class _SearchEntry extends StatelessWidget {
  final VoidCallback onTap;

  const _SearchEntry({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 20, color: context.subtleColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '搜索书名、作者、演播…',
                style: TextStyle(fontSize: 15, color: context.subtleColor),
              ),
            ),
          ],
        ),
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
    final progress = item.lastDurationMs > 0
        ? (item.lastPositionMs / item.lastDurationMs).clamp(0.0, 1.0)
        : 0.0;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [primary, primary.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            CoverImage(
              url: item.coverUrl,
              title: item.title,
              width: 84,
              height: 112,
              radius: 10,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '继续收听',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.lastPositionMs > 0
                        ? '已听 ${formatDuration(item.lastPositionMs)}'
                        : '还没开始听',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white30,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: onPlay,
              customBorder: const CircleBorder(),
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.play_arrow_rounded,
                    size: 32, color: primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentBar extends StatelessWidget {
  final String value;
  final int listeningCount;
  final int finishedCount;
  final ValueChanged<String> onChanged;

  const _SegmentBar({
    required this.value,
    required this.listeningCount,
    required this.finishedCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _seg(context, 'listening', '在听 ($listeningCount)'),
        const SizedBox(width: 8),
        _seg(context, 'finished', '听完 ($finishedCount)'),
      ],
    );
  }

  Widget _seg(BuildContext context, String key, String label) {
    final selected = value == key;
    final primary = Theme.of(context).colorScheme.primary;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: primary.withOpacity(0.16),
      labelStyle: TextStyle(
        color: selected
            ? primary
            : Theme.of(context).textTheme.bodyMedium?.color,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      onSelected: (_) => onChanged(key),
    );
  }
}

/// 书架排序 5 档：最近阅读 / 最新更新 / 书名拼音 / 手动 / 最近阅读或更新。
class _SortMenu extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SortMenu({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = <String, String>{
      'recent': '最近阅读',
      'updated': '最新更新',
      'name': '书名拼音',
      'manual': '手动',
      'recentOrUpdated': '最近阅读或更新',
    };
    return PopupMenuButton<String>(
      onSelected: onChanged,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            labels[value] ?? '最近阅读',
            style: TextStyle(fontSize: 13, color: context.subtleColor),
          ),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 18, color: context.subtleColor),
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

class _BookRow extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onHide;

  const _BookRow({
    required this.item,
    required this.onTap,
    required this.onHide,
  });

  @override
  Widget build(BuildContext context) {
    final author = item.author ?? '';
    final sourceName = item.sourceName;
    return InkWell(
      onTap: onTap,
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CoverImage(
              url: item.coverUrl,
              title: item.title,
              width: 56,
              height: 76,
              radius: 8,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (author.isNotEmpty) author,
                      if (sourceName.isNotEmpty) sourceName,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.subtleColor),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.isFinished
                        ? '已听完'
                        : (item.lastPositionMs > 0
                            ? '听到 ${formatDuration(item.lastPositionMs)}'
                            : '未收听'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: context.subtleColor),
          ],
        ),
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
      // 点源卡片 = 切源 + 进该源页（发现页）。卡片上没有假放大镜。
      onTap: () {
        ref.read(activeHomeSourceProvider.notifier).state = source;
        ref.read(shellTabProvider.notifier).state = 1;
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
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
                SourceAvatar(name: source.name, size: 32),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    source.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              source.isAudio ? '听书源' : '视频源',
              style: TextStyle(fontSize: 12, color: context.subtleColor),
            ),
            if (desc.isNotEmpty)
              Text(
                desc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: context.subtleColor),
              ),
          ],
        ),
      ),
    );
  }
}
