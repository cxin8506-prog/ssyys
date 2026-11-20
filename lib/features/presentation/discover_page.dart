import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../plugins/data/home_feed.dart';
import '../../plugins/data/plugin_providers.dart';
import '../../plugins/engine/plugin_engine.dart';
import '../../plugins/model/plugin_source.dart';
import '../../plugins/presentation/source_detail_dialog.dart';
import '../../plugins/presentation/source_search_page.dart';
import '../../shared/widgets/common.dart';

/// 内容显示方式：列表 / 表格 / 自动（按源记住，默认自动）
String displayModeOf(SharedPreferences prefs, String sourceId) =>
    prefs.getString(AppConstants.keyDisplayModePrefix + sourceId) ?? 'auto';

/// 分类项
class DiscoverCategory {
  final String id;
  final String name;
  const DiscoverCategory(this.id, this.name);
}

/// 当前源的分类列表（源不支持分类时返回空）
final discoverCategoriesProvider =
    FutureProvider.family<List<DiscoverCategory>, String>(
        (ref, sourceId) async {
  final source = await ref.read(sourceRepositoryProvider).byId(sourceId);
  if (source == null) return const [];
  final engine = source.isTingShu

      ? ref.read(tingShuEngineProvider)

      : source.isJar

      ? ref.read(jarPluginEngineProvider)

      : ref.read(jsPluginEngineProvider);
  try {
    await engine.attach(source);
    final raw = await engine.invoke('categories', params: {});
    return parseCategories(raw);
  } catch (_) {
    return const [];
  }
});

/// 兼容几种分类返回：["电影"] / [{id,name}] / {电影: 1}
List<DiscoverCategory> parseCategories(dynamic raw) {
  var data = raw;
  if (data is String) {
    final t = data.trim();
    if (t.startsWith('[') || t.startsWith('{')) {
      try {
        data = _decode(t);
      } catch (_) {
        return const [];
      }
    } else {
      return const [];
    }
  }
  if (data is Map) {
    for (final k in const ['list', 'data', 'items', 'categories', 'category']) {
      if (data[k] is List) {
        data = data[k];
        break;
      }
    }
  }
  final out = <DiscoverCategory>[];
  if (data is List) {
    for (var i = 0; i < data.length; i++) {
      final e = data[i];
      if (e is Map) {
        final id = '${e['id'] ?? e['key'] ?? e['code'] ?? e['url'] ?? i}';
        final name = '${e['name'] ?? e['title'] ?? e['label'] ?? id}';
        if (name.isNotEmpty) out.add(DiscoverCategory(id, name));
      } else if (e != null) {
        out.add(DiscoverCategory('$e', '$e'));
      }
    }
  } else if (data is Map) {
    data.forEach((k, v) => out.add(DiscoverCategory('$v', '$k')));
  }
  return out;
}

dynamic _decode(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

/// 发现页：按当前源显示分类
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  PluginSource? _source;

  /// 当前选中的分类（空表示用第一个分类）
  DiscoverCategory? _selected;

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(activeHomeSourceProvider);
    // 换了源就回到第一个分类
    if (source?.id != _source?.id) _selected = null;
    _source = source;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          // 点顶部源名就回书源页（源网格）去选源
          onTap: source == null
              ? null
              : () => ref.read(shellTabProvider.notifier).state = 0,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Text(
              source?.name ?? '发现',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        actions: [
          if (source != null) ...[
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: '搜索',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SourceSearchPage(
                  type: source.type,
                  initialSourceId: source.id,
                ),
              )),
            ),
          ],
          const SizedBox(width: 6),
        ],
      ),
      body: source == null
          ? _noSource()
          : Column(
              children: [
                Expanded(child: _content(source)),
              ],
            ),
    );
  }

  Widget _noSource() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.explore_off_outlined, size: 46, color: context.subtleColor),
            const SizedBox(height: 14),
            const Text('还没有可用的源', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 6),
            Text('去源管理导入一个插件',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushNamed('/sources'),
              child: const Text('去源管理'),
            ),
          ],
        ),
      ),
    );
  }

  /// 我的听书的样子：顶部一排可横向滑动的分类 tabs，点一下切分类，
  /// 右边一个 ▼ 点一下展开全部分类；下面直接是当前分类的内容列表。
  Widget _content(PluginSource source) {
    final async = ref.watch(discoverCategoriesProvider(source.id));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _categoriesFailed(source),
      data: (cats) {
        if (cats.isEmpty) return _noCategories(source);
        final selected = _selected != null &&
                cats.any((c) => c.id == _selected!.id)
            ? _selected!
            : cats.first;
        return Column(
          children: [
            _categoryTabBar(source, cats, selected),
            Expanded(
              child: _CategoryList(
                key: ValueKey('${source.id}|${selected.id}'),
                sourceId: source.id,
                category: selected,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 分类 tabs 横条 + 右边的 ▼（展开全部分类）
  Widget _categoryTabBar(
      PluginSource source, List<DiscoverCategory> cats, DiscoverCategory selected) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.palette.outline),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: cats.map((c) {
                  final on = c.id == selected.id;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      if (_selected?.id != c.id) {
                        setState(() => _selected = c);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: on ? primary : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        c.name,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              on ? FontWeight.w700 : FontWeight.w400,
                          color: on ? primary : null,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
            tooltip: '全部分类',
            onPressed: () => _showAllCategories(source, cats, selected),
          ),
        ],
      ),
    );
  }

  /// ▼ 展开：底部弹出全部分类，点一个就切过去
  Future<void> _showAllCategories(PluginSource source,
      List<DiscoverCategory> cats, DiscoverCategory selected) async {
    final picked = await showModalBottomSheet<DiscoverCategory>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final primary = Theme.of(context).colorScheme.primary;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('全部分类',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: cats.map((c) {
                    final on = c.id == selected.id;
                    return ListTile(
                      title: Text(c.name,
                          style: TextStyle(
                              fontWeight: on
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: on ? primary : null)),
                      trailing: on
                          ? Icon(Icons.check,
                              size: 18, color: primary)
                          : null,
                      onTap: () => Navigator.pop(ctx, c),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked != null && picked.id != selected.id) {
      setState(() => _selected = picked);
    }
  }

  /// 分类读不出来：不甩英文错，直接给推荐和搜索入口
  Widget _categoriesFailed(PluginSource source) {
    return ListView(
      padding: pagePadding(context, top: 8, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text('「${source.name}」的分类暂时打不开，直接看推荐或者去搜索。',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        _recommendFallback(source),
      ],
    );
  }

  /// 没分类的源直接显示推荐，不留白
  Widget _noCategories(PluginSource source) {
    return ListView(
      padding: pagePadding(context, top: 8, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text('「${source.name}」没有分类，直接看推荐',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        _recommendFallback(source),
      ],
    );
  }

  Widget _recommendFallback(PluginSource source) {
    final feed = ref.watch(homeFeedProvider(source.id));
    return feed.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(30),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('这个源的推荐暂时打不开，可以直接去搜索。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(
                  onPressed: () => ref.invalidate(homeFeedProvider(source.id)),
                  child: const Text('重试'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SourceSearchPage(
                      type: source.type,
                      initialSourceId: source.id,
                    ),
                  )),
                  child: const Text('去搜索'),
                ),
              ],
            ),
          ],
        ),
      ),
      data: (sections) {
        final books = sections.expand((e) => e.books).toList();
        if (books.isEmpty) {
          // 推荐、分类都没有：只给一行紧凑的搜索入口，不摆空白卡片
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.palette.outline),
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('这个源只提供搜索',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                      builder: (_) => SourceSearchPage(
                        type: source.type,
                        initialSourceId: source.id,
                      ),
                    )),
                    child: const Text('去搜索'),
                  ),
                ],
              ),
            ),
          );
        }
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 10,
            childAspectRatio: 0.62,
          ),
          itemCount: books.length,
          itemBuilder: (ctx, i) => _FeedTile(
            book: books[i],
            onTap: () => showSourceDetailDialog(context, ref,
                source: source, book: books[i]),
          ),
        );
      },
    );
  }
}

/// 某个分类下的内容列表（内联在源页面 tabs 下方），支持翻页
class _CategoryList extends ConsumerStatefulWidget {
  final String sourceId;
  final DiscoverCategory category;

  const _CategoryList({
    super.key,
    required this.sourceId,
    required this.category,
  });

  @override
  ConsumerState<_CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends ConsumerState<_CategoryList> {
  final _scroll = ScrollController();
  final List<FeedBook> _items = [];
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  PluginSource? _source;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 240) {
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final source = _source ?? await ref.read(sourceRepositoryProvider).byId(widget.sourceId);
      if (source == null) throw Exception('源已删除');
      _source = source;
      final engine = source.isTingShu

          ? ref.read(tingShuEngineProvider)

          : source.isJar

          ? ref.read(jarPluginEngineProvider)

          : ref.read(jsPluginEngineProvider);
      await engine.attach(source);

      dynamic raw;
      try {
        raw = await engine.invoke('browse', params: {
          'category': widget.category.id,
          'name': widget.category.name,
          'page': _page,
        });
      } catch (_) {
        // 没有 browse 就退回按分类名搜索
        raw = await engine.invoke('search', params: {
          'keyword': widget.category.name,
          'page': _page,
        });
      }

      final books = parseHomeFeed(raw).expand((e) => e.books).toList();
      if (!mounted) return;
      setState(() {
        _items.addAll(books);
        _loading = false;
        _hasMore = books.isNotEmpty && books.length >= 8;
        _page += 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
        _hasMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 内容层列表：一行一个（封面 + 片名 + 作者/简介），往下划翻页。
    // FeedBook 只有 title/author/intro/cover，没有年份/地区/完结状态字段，
    // 所以副标题显示作者和简介，不编造没有的字段。
    return _items.isEmpty && _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined,
                            size: 40, color: context.subtleColor),
                        const SizedBox(height: 12),
                        Text(
                            _error != null
                                ? '这个分类暂时打不开，可以重试或去搜索。'
                                : '这个分类暂时没有内容',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 14),
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _page = 1;
                              _hasMore = true;
                            });
                            _load();
                          },
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              : _listView();
  }

  /// 点标题弹详情卡（取消/添加收藏/开始播放），不整页跳详情页
  void _openBook(FeedBook b) {
    final s = _source;
    if (s == null) return;
    showSourceDetailDialog(context, ref, source: s, book: b);
  }

  /// 列表显示：一行一个，带封面和简介
  Widget _listView() {
    return ListView.separated(
      controller: _scroll,
      padding: pagePadding(context, top: 10, bottom: 24),
      itemCount: _items.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        if (i >= _items.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_hasMore ? '' : '没有更多了',
                      style: Theme.of(ctx).textTheme.bodySmall),
            ),
          );
        }
        final b = _items[i];
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openBook(b),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.palette.outline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: b.cover.isEmpty
                      ? Container(
                          width: 54,
                          height: 72,
                          color: context.palette.surfaceAlt,
                          alignment: Alignment.center,
                          child: Text(
                              b.title.isEmpty ? '?' : b.title.characters.first,
                              style: TextStyle(
                                  color: context.subtleColor, fontSize: 18)),
                        )
                      : Image.network(
                          b.cover,
                          width: 54,
                          height: 72,
                          cacheWidth: 108,
                          cacheHeight: 144,
                          filterQuality: FilterQuality.low,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 54,
                            height: 72,
                            color: context.palette.surfaceAlt,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      if (b.author.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(b.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontSize: 12)),
                      ],
                      if (b.intro.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(b.intro,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontSize: 11, height: 1.4)),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 18, color: context.subtleColor),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 某个分类的独立页（从别处点分类进来时用）：直接复用内联分类列表
class DiscoverListPage extends ConsumerWidget {
  final String sourceId;
  final DiscoverCategory category;

  const DiscoverListPage({
    super.key,
    required this.sourceId,
    required this.category,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(category.name)),
      body: _CategoryList(
        sourceId: sourceId,
        category: category,
      ),
    );
  }
}

/// 封面卡片：封面 + 标题 + 作者，封面失败显示首字占位
class _FeedTile extends StatelessWidget {
  final FeedBook book;
  final VoidCallback onTap;

  const _FeedTile({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _cover(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          if (book.author.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: context.subtleColor),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cover(BuildContext context) {
    if (book.cover.isEmpty) return _placeholder(context);
    return Image.network(
      book.cover,
      fit: BoxFit.cover,
      cacheWidth: 240,
      cacheHeight: 320,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, __, ___) => _placeholder(context),
      loadingBuilder: (ctx, child, progress) {
        if (progress == null) return child;
        return Container(
          color: context.palette.surfaceAlt,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: context.palette.surfaceAlt,
      alignment: Alignment.center,
      child: Text(
        book.title.isEmpty ? '?' : book.title.characters.first,
        style: TextStyle(fontSize: 20, color: context.subtleColor),
      ),
    );
  }
}
