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
import '../../plugins/presentation/source_book_page.dart';
import '../../plugins/presentation/source_picker_sheet.dart';
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

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(activeHomeSourceProvider);
    _source = source;

    return Scaffold(
      drawer: buildAppDrawer(context),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: '菜单',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: source == null
              ? null
              : () async {
                  final picked = await showSourcePicker(context, ref,
                      selectedId: source.id);
                  if (picked != null) {
                    setHomeSource(ref, picked);
                    ref.invalidate(discoverCategoriesProvider(picked));
                  }
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    source?.name ?? '发现',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (source != null) ...[
                  const SizedBox(width: 2),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (source != null) ...[
            IconButton(
              icon: Icon(_modeIcon(_mode)),
              tooltip: '显示方式：${_modeLabel(_mode)}',
              onPressed: () => _cycleMode(source.id),
            ),
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

  String get _mode => displayModeOf(
      ref.read(sharedPrefsProvider), _source?.id ?? '');

  static const _modeOrder = ['auto', 'list', 'table'];

  String _modeLabel(String mode) {
    switch (mode) {
      case 'list':
        return '列表';
      case 'table':
        return '表格';
      default:
        return '自动';
    }
  }

  IconData _modeIcon(String mode) {
    switch (mode) {
      case 'list':
        return Icons.view_list;
      case 'table':
        return Icons.grid_view;
      default:
        return Icons.view_module;
    }
  }

  void _cycleMode(String sourceId) {
    final prefs = ref.read(sharedPrefsProvider);
    final cur = displayModeOf(prefs, sourceId);
    final next =
        _modeOrder[(_modeOrder.indexOf(cur) + 1) % _modeOrder.length];
    prefs.setString(
        AppConstants.keyDisplayModePrefix + sourceId, next);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('显示方式：${_modeLabel(next)}'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 1),
    ));
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
            Text('去「我的 → 源管理」导入一个插件',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _content(PluginSource source) {
    final async = ref.watch(discoverCategoriesProvider(source.id));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('读取分类失败：$e')),
      data: (cats) {
        if (cats.isEmpty) return _noCategories(source);
        return ListView(
          padding: pagePadding(context, top: 8, bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text('${source.name} · 分类',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 12)),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.1,
              ),
              itemCount: cats.length,
              itemBuilder: (ctx, i) => _categoryTile(source, cats[i]),
            ),
          ],
        );
      },
    );
  }

  Widget _categoryTile(PluginSource s, DiscoverCategory c) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DiscoverListPage(
            sourceId: s.id,
            category: c,
          ),
        ));
      },
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.palette.outline),
        ),
        child: Text(
          c.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
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
        child: Text('推荐也拿不到：$e',
            style: Theme.of(context).textTheme.bodySmall),
      ),
      data: (sections) {
        final books = sections.expand((e) => e.books).toList();
        if (books.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Text('这个源暂时没有内容',
                style: Theme.of(context).textTheme.bodySmall),
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
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SourceBookPage(
                  sourceId: source.id,
                  bookUrl: books[i].url,
                  title: books[i].title,
                  coverUrl: books[i].cover,
                  author: books[i].author,
                  intro: books[i].intro,
                ),
              ));
            },
          ),
        );
      },
    );
  }
}

/// 某个分类下的内容列表，支持翻页
class DiscoverListPage extends ConsumerStatefulWidget {
  final String sourceId;
  final DiscoverCategory category;

  const DiscoverListPage({
    super.key,
    required this.sourceId,
    required this.category,
  });

  @override
  ConsumerState<DiscoverListPage> createState() => _DiscoverListPageState();
}

class _DiscoverListPageState extends ConsumerState<DiscoverListPage> {
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
    final mode = displayModeOf(
        ref.read(sharedPrefsProvider), widget.sourceId);
    return Scaffold(
      appBar: AppBar(title: Text(widget.category.name)),
      body: _items.isEmpty && _loading
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
                        Text(_error ?? '这个分类暂时没有内容',
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
              : mode == 'list'
                  ? _listView()
                  : GridView.builder(
                      controller: _scroll,
                      padding: pagePadding(context, top: 10, bottom: 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.62,
                      ),
                      itemCount: _items.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i >= _items.length) {
                          return Center(
                            child: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : Text(_hasMore ? '' : '没有更多了',
                                    style: Theme.of(ctx).textTheme.bodySmall),
                          );
                        }
                        final b = _items[i];
                        return _FeedTile(
                          book: b,
                          onTap: () => _openBook(b),
                        );
                      },
                    ),
    );
  }

  void _openBook(FeedBook b) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SourceBookPage(
        sourceId: widget.sourceId,
        bookUrl: b.url,
        title: b.title,
        coverUrl: b.cover,
        author: b.author,
        intro: b.intro,
      ),
    ));
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
