import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../plugins/data/plugin_providers.dart';
import '../../plugins/model/plugin_source.dart';
import '../../plugins/presentation/source_book_page.dart';
import '../../shared/widgets/bottom_bar_inset.dart';
import '../../shared/widgets/common.dart';

/// 发现页：按当前源显示分类（一级 Tab + 二级 Chip）。
///
/// - 顶栏标题就是当前源名，点它回书源页（源网格）去选源。
/// - 源下拉框 + 刷新按钮。白字 bug 已修：DropdownButton 的 style
///   必须写 color，dropdownColor 钉死主题表面色；源名不截断。
/// - 点书卡进详情整页（SourceBookPage），不要只弹详情弹窗。
/// - 源没有分类时不留白，显示推荐 fallback。
/// - 源切换走 activeHomeSourceProvider（直接改 state），下次打开发现页
///   默认用这个源（仅本次运行内记忆，不落盘）。
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  List<Map<String, dynamic>> _menus = const [];
  int _menuIndex = 0;
  int _tabIndex = 0;
  List<Map<String, dynamic>> _books = const [];
  bool _loadingCategories = true;
  bool _categoriesFailed = false;
  bool _loadingBooks = false;
  String? _booksError;
  int _page = 1;
  bool _hasMore = true;
  String? _sourceId;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 240) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(activeHomeSourceProvider);
    final videoEnabled = ref.watch(videoEnabledProvider);
    if (source?.id != _sourceId) {
      _sourceId = source?.id;
      _menuIndex = 0;
      _tabIndex = 0;
      _page = 1;
      _hasMore = true;
      _books = const [];
      if (source != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _loadCategories());
      }
    }
    final sourcesAsync = ref.watch(sourceListProvider);

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          // 点顶部源名回书源页（源网格）去选源。
          onTap: () => ref.read(shellTabProvider.notifier).state = 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  source?.name ?? '发现',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.arrow_drop_down, size: 20),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: source == null ? null : () => _loadCategories(),
          ),
        ],
      ),
      body: source == null
          ? EmptyState(
              icon: Icons.extension_outlined,
              title: '还没有可用的源',
              hint: '去源管理导入或启用一个源吧。',
              actionLabel: '去源管理',
              onAction: () => context.push('/sources'),
            )
          : Column(
              children: [
                _SourceBar(
                  source: source,
                  sourcesAsync: sourcesAsync,
                  videoEnabled: videoEnabled,
                  onChanged: (s) {
                    ref.read(activeHomeSourceProvider.notifier).state = s;
                  },
                ),
                if (_loadingCategories)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  )
                else if (_menus.isEmpty)
                  _NoCategories(
                    failed: _categoriesFailed,
                    onSearch: () => context.push('/search'),
                    onRetry: () => _loadCategories(),
                  )
                else ...[
                  _MenuTabs(
                    menus: _menus,
                    index: _menuIndex,
                    onChanged: (i) {
                      setState(() {
                        _menuIndex = i;
                        _tabIndex = 0;
                        _page = 1;
                        _hasMore = true;
                      });
                      _loadBooks();
                    },
                  ),
                  _TabChips(
                    tabs: _tabsOf(_menuIndex),
                    index: _tabIndex,
                    onChanged: (i) {
                      setState(() {
                        _tabIndex = i;
                        _page = 1;
                        _hasMore = true;
                      });
                      _loadBooks();
                    },
                  ),
                ],
                if (_menus.isNotEmpty)
                  Expanded(
                    child: _loadingBooks && _books.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : _books.isEmpty
                            ? EmptyState(
                                icon: Icons.menu_book_outlined,
                                title: '这个分类下没有书',
                                hint: _booksError,
                                actionLabel: '重试',
                                onAction: () => _loadBooks(),
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                itemCount:
                                    _books.length + (_hasMore ? 1 : 0) + 1,
                                itemBuilder: (_, i) {
                                  if (i == _books.length + (_hasMore ? 1 : 0)) {
                                    return bottomBarSpace(context);
                                  }
                                  if (i >= _books.length) {
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  return _BookRow(
                                    book: _books[i],
                                    source: source,
                                  );
                                },
                              ),
                  ),
              ],
            ),
    );
  }

  List<Map<String, dynamic>> _tabsOf(int menuIndex) {
    if (menuIndex < 0 || menuIndex >= _menus.length) {
      return const [];
    }
    final tabs = _menus[menuIndex]['tabs'];
    if (tabs is List) {
      return tabs
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Future<void> _loadCategories() async {
    final source = ref.read(activeHomeSourceProvider);
    if (source == null) return;
    setState(() {
      _loadingCategories = true;
      _categoriesFailed = false;
    });
    try {
      final engine = engineForSource(ref, source);
      await engine.attach(source);
      final raw = await engine.invoke('categoryMenus', params: {});
      final menus = _parseMenus(raw);
      if (!mounted) return;
      setState(() {
        _menus = menus;
        _loadingCategories = false;
        _menuIndex = 0;
        _tabIndex = 0;
        _page = 1;
        _hasMore = true;
      });
      await _loadBooks();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _menus = const [];
        _loadingCategories = false;
        _categoriesFailed = true;
      });
    }
  }

  List<Map<String, dynamic>> _parseMenus(dynamic raw) {
    final list = raw is List
        ? raw
        : (raw is Map
            ? (raw['menus'] ?? raw['categories'] ?? raw['list'])
            : null);
    if (list is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final title = '${m['title'] ?? m['name'] ?? ''}';
      if (title.isEmpty) continue;
      final tabsRaw = m['tabs'] ?? m['children'] ?? m['sub'];
      final tabs = <Map<String, dynamic>>[];
      if (tabsRaw is List) {
        for (final t in tabsRaw) {
          if (t is Map) {
            tabs.add(Map<String, dynamic>.from(t));
          } else if (t is String) {
            tabs.add(<String, dynamic>{'title': t, 'url': t});
          }
        }
      }
      if (tabs.isEmpty) {
        tabs.add(<String, dynamic>{'title': title, 'url': m['url'] ?? ''});
      }
      out.add(<String, dynamic>{'title': title, 'tabs': tabs});
    }
    return out;
  }

  Map<String, dynamic> _currentTab() {
    final tabs = _tabsOf(_menuIndex);
    if (tabs.isEmpty) return const {};
    var i = _tabIndex;
    if (i < 0) i = 0;
    if (i >= tabs.length) i = tabs.length - 1;
    return tabs[i];
  }

  Future<void> _loadBooks() async {
    final source = ref.read(activeHomeSourceProvider);
    if (source == null || _menus.isEmpty) return;
    setState(() {
      _loadingBooks = true;
      _booksError = null;
    });
    try {
      final engine = engineForSource(ref, source);
      await engine.attach(source);
      final tab = _currentTab();
      final menu = '${tab['url'] ?? tab['title'] ?? ''}';
      final raw = await engine.invoke(
        'categoryPage',
        params: {'menu': menu, 'page': 1},
      );
      final books = _parseBooks(raw);
      if (!mounted) return;
      setState(() {
        _books = books;
        _loadingBooks = false;
        _page = 1;
        _hasMore = books.length >= 8;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBooks = false;
        _booksError = '加载失败：$e';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingBooks || !_hasMore || _menus.isEmpty) return;
    final source = ref.read(activeHomeSourceProvider);
    if (source == null) return;
    setState(() => _loadingBooks = true);
    try {
      final engine = engineForSource(ref, source);
      await engine.attach(source);
      final tab = _currentTab();
      final menu = '${tab['url'] ?? tab['title'] ?? ''}';
      final raw = await engine.invoke(
        'categoryPage',
        params: {'menu': menu, 'page': _page + 1},
      );
      final books = _parseBooks(raw);
      if (!mounted) return;
      setState(() {
        _page = _page + 1;
        _books = [..._books, ...books];
        _loadingBooks = false;
        _hasMore = books.isNotEmpty && books.length >= 8;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingBooks = false);
    }
  }

  List<Map<String, dynamic>> _parseBooks(dynamic raw) {
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['books'] ?? raw['list'] ?? raw['data']) : null);
    if (list is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }
}

/// 源下拉框 + 刷新按钮（白字 bug 修法：style 写 color，
/// dropdownColor 钉死主题表面色；源名不截断到分不清）。
class _SourceBar extends StatelessWidget {
  final PluginSource source;
  final AsyncValue<List<PluginSource>> sourcesAsync;
  final bool videoEnabled;
  final ValueChanged<PluginSource> onChanged;

  const _SourceBar({
    required this.source,
    required this.sourcesAsync,
    required this.videoEnabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyMedium?.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.extension_outlined,
              size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Text('源',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: sourcesAsync.when(
              loading: () => Text(source.name,
                  style: TextStyle(fontSize: 14, color: textColor)),
              error: (_, __) => Text(source.name,
                  style: TextStyle(fontSize: 14, color: textColor)),
              data: (list) {
                final enabled = list.where((s) => s.enabled).toList();
                final shown = videoEnabled
                    ? enabled
                    : enabled.where((s) => s.isAudio).toList();
                if (shown.isEmpty) {
                  return Text(source.name,
                      style: TextStyle(fontSize: 14, color: textColor));
                }
                final value = shown.any((s) => s.id == source.id)
                    ? source.id
                    : shown.first.id;
                return DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: value,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 20),
                    // 白字 bug 修法：style 必须写 color。
                    style: TextStyle(fontSize: 14, color: textColor),
                    // 菜单底色钉死在主题表面色上，浅色主题浅底深字。
                    dropdownColor: Theme.of(context).colorScheme.surface,
                    items: [
                      for (final s in shown)
                        DropdownMenuItem<String>(
                          value: s.id,
                          // 源名不截断到分不清：允许换行，不用 ellipsis。
                          child: Text(
                            s.name,
                            style: TextStyle(fontSize: 14, color: textColor),
                          ),
                        ),
                    ],
                    onChanged: (picked) {
                      if (picked == null) return;
                      for (final s in shown) {
                        if (s.id == picked) onChanged(s);
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTabs extends StatelessWidget {
  final List<Map<String, dynamic>> menus;
  final int index;
  final ValueChanged<int> onChanged;

  const _MenuTabs({
    required this.menus,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 不用 TabBar（需要 TabController，随菜单数量变化容易失配）：
    // 一级分类用横向滚动的文字行，选中项 3px 主题色下划线。
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: menus.length,
        itemBuilder: (_, i) {
          final selected = i == index;
          return InkWell(
            onTap: () => onChanged(i),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? primary : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                '${menus[i]['title'] ?? ''}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected
                      ? primary
                      : Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TabChips extends StatelessWidget {
  final List<Map<String, dynamic>> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  const _TabChips({
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (tabs.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: tabs.length,
        itemBuilder: (_, i) {
          final selected = i == index;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('${tabs[i]['title'] ?? ''}'),
              selected: selected,
              onSelected: (_) => onChanged(i),
            ),
          );
        },
      ),
    );
  }
}

class _NoCategories extends StatelessWidget {
  final bool failed;
  final VoidCallback onSearch;
  final VoidCallback onRetry;

  const _NoCategories({
    required this.failed,
    required this.onSearch,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            failed ? '分类加载失败' : '这个源没有分类，直接看推荐',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            failed ? '换个源或重试一次。' : '用搜索找这本书，或换个有分类的源。',
            style: TextStyle(fontSize: 13, color: context.subtleColor),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(onPressed: onSearch, child: const Text('去搜索')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ],
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  final Map<String, dynamic> book;
  final PluginSource source;

  const _BookRow({required this.book, required this.source});

  @override
  Widget build(BuildContext context) {
    final title = '${book['title'] ?? book['name'] ?? ''}';
    final author = '${book['author'] ?? book['artist'] ?? ''}';
    final cover = '${book['coverUrl'] ?? book['cover'] ?? ''}';
    final url = '${book['bookUrl'] ?? book['url'] ?? ''}';
    final intro = '${book['intro'] ?? book['description'] ?? ''}';
    return InkWell(
      // 点书卡进详情整页，不要只弹详情弹窗。
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SourceBookPage(
              sourceId: source.id,
              bookUrl: url,
              title: title,
              coverUrl: cover.isEmpty ? null : cover,
              author: author.isEmpty ? null : author,
              intro: intro.isEmpty ? null : intro,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverImage(url: cover.isEmpty ? null : cover, title: title),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
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
                        fontSize: 12,
                        color: context.subtleColor,
                      ),
                    ),
                  ],
                  if (intro.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      intro,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.subtleColor,
                      ),
                    ),
                  ],
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
