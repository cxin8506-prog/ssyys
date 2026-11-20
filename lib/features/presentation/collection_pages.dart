import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/app_database.dart';
import '../../core/database/library_repository.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../plugins/presentation/source_book_page.dart';
import '../../shared/widgets/bottom_bar_inset.dart';
import '../../shared/widgets/common.dart';
import 'history_page.dart';

enum CollectionKind { favorite, history }

/// 收藏页（底栏「收藏」）。
///
/// - 默认网格 3 列，可切列表；卡片有封面 + 标题 + 作者 +
///   上次听到哪一章（位置/时间）。
/// - 空状态提示只写真实存在的入口：源书单点书卡 → 详情页 → 添加收藏。
/// - 视频收藏点进去也从断点续播（经详情页读断点，不从头播）。
/// - 排序 5 档；长按多选，可隐藏、可批量取消收藏；已隐藏的书单独一处看。
class CollectionPage extends ConsumerStatefulWidget {
  final CollectionKind kind;
  final String initialType;

  const CollectionPage({
    super.key,
    required this.kind,
    this.initialType = 'audio',
  });

  @override
  ConsumerState<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<CollectionPage> {
  String _type = 'audio';
  String _sort = 'recent';
  bool _grid = true;
  final Set<String> _selected = <String>{};
  bool _selecting = false;
  List<String> _hiddenIds = const <String>[];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
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
  Widget build(BuildContext context) {
    // 历史走独立的 HistoryPage（统一时间线、三档排序、可搜索、可清空）。
    if (widget.kind == CollectionKind.history) {
      return const HistoryPage();
    }
    final repo = ref.watch(libraryRepositoryProvider);
    final videoEnabled = ref.watch(videoEnabledProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_selecting ? '已选 ${_selected.length} 项' : '收藏'),
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selecting = false;
                  _selected.clear();
                }),
              )
            : null,
        actions: _selecting
            ? [
                IconButton(
                  icon: const Icon(Icons.visibility_off_outlined),
                  tooltip: '隐藏',
                  onPressed: _selected.isEmpty ? null : _hideSelected,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '取消收藏',
                  onPressed: _selected.isEmpty ? null : _unfavoriteSelected,
                ),
              ]
            : [
                IconButton(
                  icon: Icon(_grid ? Icons.list : Icons.grid_view),
                  tooltip: _grid ? '列表' : '网格',
                  onPressed: () => setState(() => _grid = !_grid),
                ),
                PopupMenuButton<String>(
                  tooltip: '更多',
                  onSelected: (v) {
                    if (v == 'hidden') _showHidden();
                    if (v == 'sort_recent') setState(() => _sort = 'recent');
                    if (v == 'sort_updated') setState(() => _sort = 'updated');
                    if (v == 'sort_name') setState(() => _sort = 'name');
                    if (v == 'sort_manual') setState(() => _sort = 'manual');
                    if (v == 'sort_recentOrUpdated') {
                      setState(() => _sort = 'recentOrUpdated');
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'sort_recent', child: Text('按最近阅读')),
                    PopupMenuItem(value: 'sort_updated', child: Text('按最新更新')),
                    PopupMenuItem(value: 'sort_name', child: Text('按书名拼音')),
                    PopupMenuItem(value: 'sort_manual', child: Text('手动排序')),
                    PopupMenuItem(
                        value: 'sort_recentOrUpdated',
                        child: Text('按最近阅读或更新')),
                    PopupMenuItem(
                        value: 'hidden', child: Text('查看已隐藏的书')),
                  ],
                ),
              ],
      ),
      body: Column(
        children: [
          _TypeSwitch(
            value: _type,
            videoEnabled: videoEnabled,
            onChanged: (v) => setState(() => _type = v),
          ),
          Expanded(
            child: FutureBuilder<List<MediaItem>>(
              future: _load(repo),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = _sorted(snapshot.data ?? const <MediaItem>[]);
                if (items.isEmpty) {
                  return EmptyState(
                    icon: Icons.favorite_outline,
                    title: '暂无收藏',
                    hint: '在源书单里点一本书，进详情页点“添加收藏”。',
                    actionLabel: '去发现',
                    onAction: () =>
                        ref.read(shellTabProvider.notifier).state = 1,
                  );
                }
                if (_grid) {
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.62,
                    ),
                    itemCount: items.length + 1,
                    itemBuilder: (_, i) {
                      if (i == items.length) {
                        return bottomBarSpace(context);
                      }
                      return _FavoriteGridCard(
                        item: items[i],
                        selected: _selected.contains(items[i].id),
                        selecting: _selecting,
                        onTap: () => _onTap(items[i]),
                        onLongPress: () => _onLongPress(items[i]),
                      );
                    },
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: items.length + 1,
                  itemBuilder: (_, i) {
                    if (i == items.length) {
                      return bottomBarSpace(context);
                    }
                    return _FavoriteListRow(
                      item: items[i],
                      selected: _selected.contains(items[i].id),
                      selecting: _selecting,
                      manual: _sort == 'manual',
                      onTap: () => _onTap(items[i]),
                      onLongPress: () => _onLongPress(items[i]),
                      onMoveUp: () => _move(items[i], -1),
                      onMoveDown: () => _move(items[i], 1),
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
      final items = await repo.getFavorites(type: _type);
      return items.where((e) => !_hiddenIds.contains(e.id)).toList();
    } catch (_) {
      return const <MediaItem>[];
    }
  }

  List<MediaItem> _sorted(List<MediaItem> items) {
    final list = List<MediaItem>.from(items);
    switch (_sort) {
      case 'name':
        list.sort((a, b) => a.title.compareTo(b.title));
        break;
      case 'manual':
        final order = ref
                .read(sharedPrefsProvider)
                .getStringList('favorite_manual_order') ??
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
        // recent / updated / recentOrUpdated：都按最后播放时间倒序
        //（MediaItem 未单独立更新时间字段，见汇报）。
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

  void _onTap(MediaItem item) {
    if (_selecting) {
      setState(() {
        if (_selected.contains(item.id)) {
          _selected.remove(item.id);
          if (_selected.isEmpty) _selecting = false;
        } else {
          _selected.add(item.id);
        }
      });
      return;
    }
    // 收藏点进去进详情页，详情页点章节时读断点续播；
    // 视频收藏同一条路，不从头播。
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

  void _onLongPress(MediaItem item) {
    setState(() {
      _selecting = true;
      _selected.add(item.id);
    });
  }

  Future<void> _hideSelected() async {
    final prefs = ref.read(sharedPrefsProvider);
    final hidden = List<String>.from(_hiddenIds)..addAll(_selected);
    await prefs.setStringList('hidden_book_ids', hidden);
    if (!mounted) return;
    setState(() {
      _hiddenIds = hidden;
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _unfavoriteSelected() async {
    final repo = ref.read(libraryRepositoryProvider);
    for (final id in _selected) {
      try {
        await repo.removeFavorite(id);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _move(MediaItem item, int delta) async {
    final prefs = ref.read(sharedPrefsProvider);
    final order = List<String>.from(
        prefs.getStringList('favorite_manual_order') ?? const <String>[]);
    if (!order.contains(item.id)) order.add(item.id);
    final i = order.indexOf(item.id);
    final j = i + delta;
    if (j < 0 || j >= order.length) return;
    final tmp = order[i];
    order[i] = order[j];
    order[j] = tmp;
    await prefs.setStringList('favorite_manual_order', order);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _showHidden() async {
    final prefs = ref.read(sharedPrefsProvider);
    final hidden = prefs.getStringList('hidden_book_ids') ?? const <String>[];
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('已隐藏的书'),
        content: hidden.isEmpty
            ? const Text('没有已隐藏的书。长按书架或收藏里的书可以选择隐藏。')
            : SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final id in hidden)
                      ListTile(
                        title: Text(id, maxLines: 1),
                        trailing: TextButton(
                          onPressed: () async {
                            final next = List<String>.from(hidden)..remove(id);
                            await prefs.setStringList(
                                'hidden_book_ids', next);
                            if (!mounted) return;
                            setState(() => _hiddenIds = next);
                            Navigator.pop(ctx);
                          },
                          child: const Text('取消隐藏'),
                        ),
                      ),
                  ],
                ),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _TypeSwitch extends StatelessWidget {
  final String value;
  final bool videoEnabled;
  final ValueChanged<String> onChanged;

  const _TypeSwitch({
    required this.value,
    required this.videoEnabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    Widget chip(String key, String label, {bool enabled = true}) {
      final selected = value == key;
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: primary.withOpacity(0.16),
        labelStyle: TextStyle(
          color: selected
              ? primary
              : Theme.of(context).textTheme.bodyMedium?.color,
        ),
        onSelected: enabled ? (_) => onChanged(key) : null,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          chip('audio', '听书'),
          const SizedBox(width: 8),
          // 视频功能关了就不显示视频切换（旧坑：开关只藏书架分栏）。
          if (videoEnabled) chip('video', '视频'),
        ],
      ),
    );
  }
}

class _FavoriteGridCard extends StatelessWidget {
  final MediaItem item;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FavoriteGridCard({
    required this.item,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverImage(
                url: item.coverUrl,
                title: item.title,
                width: double.infinity,
                height: 140,
                radius: 12,
              ),
              const SizedBox(height: 6),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _progressText(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: context.subtleColor),
              ),
            ],
          ),
          if (selecting)
            Positioned(
              right: 4,
              top: 4,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black54,
                child: selected
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _FavoriteListRow extends StatelessWidget {
  final MediaItem item;
  final bool selected;
  final bool selecting;
  final bool manual;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  const _FavoriteListRow({
    required this.item,
    required this.selected,
    required this.selecting,
    required this.manual,
    required this.onTap,
    required this.onLongPress,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final author = item.author ?? '';
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (selecting)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : context.subtleColor,
                ),
              ),
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
                  if (author.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: context.subtleColor),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    _progressText(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: context.subtleColor),
                  ),
                ],
              ),
            ),
            if (manual) ...[
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 18),
                tooltip: '上移',
                onPressed: onMoveUp,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 18),
                tooltip: '下移',
                onPressed: onMoveDown,
              ),
            ],
            Icon(Icons.chevron_right, size: 20, color: context.subtleColor),
          ],
        ),
      ),
    );
  }
}

/// 上次听到哪一章：位置 + 时间。章数不在契约 MediaItem 字段里，
/// 这里不编一个假章数，只写真实有的位置和时间。
String _progressText(MediaItem item) {
  final parts = <String>[];
  if (item.isFinished) {
    parts.add('已听完');
  } else if (item.lastPositionMs > 0) {
    final total = item.lastDurationMs > 0
        ? ' / ${formatDuration(item.lastDurationMs)}'
        : '';
    parts.add('上次听到 ${formatDuration(item.lastPositionMs)}$total');
  } else {
    parts.add('未收听');
  }
  if (item.lastPlayedAt != null) {
    parts.add(formatDateTime(item.lastPlayedAt));
  }
  return parts.join(' · ');
}
