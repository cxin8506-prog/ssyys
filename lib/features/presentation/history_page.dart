import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/library_repository.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../plugins/presentation/source_book_page.dart';
import '../../shared/widgets/bottom_bar_inset.dart';
import '../../shared/widgets/common.dart';

/// 历史页（底栏「历史」）。
///
/// - 插件断点与历史按时间合并成一条统一时间线（支撑组 getHistory
///   负责合并；这里不再插件断点全排在前、本地历史全排在后）。
/// - 行里显示日期时间；三档排序（书名 / 阅读时长 / 最近阅读）；
///   可搜索、可清空、可按书删除。
/// - 垃圾桶确认写清清哪些：听书和视频按类型分别清，不许在听书 tab
///   点一下就把视频的插件断点也清掉。
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  String _type = 'audio';
  String _sort = 'recent';
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(libraryRepositoryProvider);
    final videoEnabled = ref.watch(videoEnabledProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空历史',
            onPressed: () => _confirmClear(context),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索历史里的书名、作者',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _TypeChip(
                  label: '听书',
                  selected: _type == 'audio',
                  onTap: () => setState(() => _type = 'audio'),
                ),
                const SizedBox(width: 8),
                if (videoEnabled)
                  _TypeChip(
                    label: '视频',
                    selected: _type == 'video',
                    onTap: () => setState(() => _type = 'video'),
                  ),
                const Spacer(),
                _SortMenu(
                  value: _sort,
                  onChanged: (v) => setState(() => _sort = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<MediaItem>>(
              future: _load(repo),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snapshot.data ?? const <MediaItem>[];
                final items = _sorted(_filtered(all));
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.history_outlined,
                    title: _query.isEmpty ? '暂无历史' : '没有匹配的历史',
                    hint: '听过的书和视频会按时间出现在这里。',
                    actionLabel: '去发现',
                    onAction: () =>
                        ref.read(shellTabProvider.notifier).state = 1,
                  );
                }
                final totalSeconds =
                    items.fold<int>(0, (s, e) => s + e.lastPositionMs) ~/ 1000;
                final top3 = List<MediaItem>.from(items)
                  ..sort((a, b) => b.lastPositionMs.compareTo(a.lastPositionMs));
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  itemCount: items.length + 2,
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return _SummaryCard(
                        totalText: '累计收听 ${formatListen(totalSeconds)}',
                        top3: top3.take(3).toList(),
                      );
                    }
                    if (i == items.length + 1) {
                      return bottomBarSpace(context);
                    }
                    final item = items[i - 1];
                    return _HistoryRow(
                      item: item,
                      onTap: () => _open(item),
                      onDelete: () => _deleteOne(item),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<List<MediaItem>> _load(LibraryRepository repo) async {
    try {
      return await repo.getHistory(type: _type);
    } catch (_) {
      return const <MediaItem>[];
    }
  }

  List<MediaItem> _filtered(List<MediaItem> items) {
    if (_query.isEmpty) return items;
    final q = _query.toLowerCase();
    return items.where((e) {
      final title = e.title.toLowerCase();
      final author = (e.author ?? '').toLowerCase();
      return title.contains(q) || author.contains(q);
    }).toList();
  }

  List<MediaItem> _sorted(List<MediaItem> items) {
    final list = List<MediaItem>.from(items);
    switch (_sort) {
      case 'name':
        list.sort((a, b) => a.title.compareTo(b.title));
        break;
      case 'duration':
        list.sort((a, b) => b.lastDurationMs.compareTo(a.lastDurationMs));
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

  String _bookUrlOf(MediaItem item) {
    final parts = item.id.split('|');
    if (parts.length >= 2) return parts.sublist(1).join('|');
    return '';
  }

  void _open(MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SourceBookPage(
          sourceId: item.sourceId,
          bookUrl: _bookUrlOf(item),
          title: item.title,
          coverUrl: item.coverUrl,
          author: item.author,
        ),
      ),
    );
  }

  Future<void> _deleteOne(MediaItem item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条历史？'),
        content: Text('会删除《${item.title}》的历史记录和断点，收藏不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await ref.read(libraryRepositoryProvider).deleteHistoryByBook(item.id);
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _confirmClear(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空历史记录？'),
        content: const Text(
          '请选择要清的内容，只清选中的类型，不动另一类型：\n'
          '· 清听书：只删除听书的历史和断点，视频的不动。\n'
          '· 清视频：只删除视频的历史和断点，听书的不动。\n'
          '· 全部清空：听书和视频的历史、断点都删除。\n'
          '收藏不受影响。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'audio'),
            child: const Text('清听书'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'video'),
            child: const Text('清视频'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: const Text('全部清空'),
          ),
        ],
      ),
    );
    if (choice == null) return;
    final repo = ref.read(libraryRepositoryProvider);
    try {
      if (choice == 'all') {
        await repo.clearHistory(type: 'audio');
        await repo.clearHistory(type: 'video');
      } else {
        await repo.clearHistory(type: choice);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已按选择清空历史')),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: primary.withOpacity(0.16),
      labelStyle: TextStyle(
        color: selected
            ? primary
            : Theme.of(context).textTheme.bodyMedium?.color,
      ),
      onSelected: (_) => onTap(),
    );
  }
}

class _SortMenu extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SortMenu({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const labels = <String, String>{
      'recent': '最近阅读',
      'duration': '阅读时长',
      'name': '书名',
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

class _SummaryCard extends StatelessWidget {
  final String totalText;
  final List<MediaItem> top3;

  const _SummaryCard({required this.totalText, required this.top3});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              totalText,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (top3.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('听得最多的 3 本', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 4),
              for (var i = 0; i < top3.length; i++)
                Text(
                  '${i + 1}. ${top3[i].title}（${formatListen(top3[i].lastPositionMs ~/ 1000)}）',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryRow({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final author = item.author ?? '';
    final chapter = _chapterLabel(item.lastChapterUrl);
    return InkWell(
      onTap: onTap,
      onLongPress: () async {
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('删除这条历史？'),
            content: Text('会删除《${item.title}》的历史记录和断点，收藏不受影响。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (yes == true) onDelete();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CoverImage(
              url: item.coverUrl,
              title: item.title,
              width: 48,
              height: 64,
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
                      if (chapter.isNotEmpty) chapter,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.subtleColor),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    // 行里显示日期时间，不只显示进度时间。
                    [
                      if (item.lastPlayedAt != null)
                        formatDateTime(item.lastPlayedAt),
                      if (item.lastPositionMs > 0)
                        '听到 ${formatDuration(item.lastPositionMs)}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: context.subtleColor),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: '删除这条',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  /// 章节名：lastChapterUrl 是地址时只取最后一段当提示，不编章名。
  String _chapterLabel(String? url) {
    if (url == null || url.isEmpty) return '';
    final clean = url.split('?').first;
    final parts = clean.split('/');
    final last = parts.isEmpty ? '' : parts.last;
    if (last.isEmpty) return '';
    return last.length > 24 ? '${last.substring(0, 24)}…' : last;
  }
}
