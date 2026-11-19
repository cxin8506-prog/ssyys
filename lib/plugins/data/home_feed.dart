import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/log/app_logger.dart';
import '../model/plugin_source.dart';
import 'plugin_providers.dart';

/// 推荐位里的一本书 / 一个视频
class FeedBook {
  final String title;
  final String author;
  final String cover;
  final String url;
  final String intro;

  const FeedBook({
    required this.title,
    this.author = '',
    this.cover = '',
    this.url = '',
    this.intro = '',
  });
}

/// 推荐板块（一个源可以给多个板块，比如「热门推荐」「新书上架」）
class FeedSection {
  final String title;
  final List<FeedBook> books;

  const FeedSection({required this.title, required this.books});

  bool get isEmpty => books.isEmpty;
}

// ---------------------------------------------------------------- 解析

const List<String> _titleKeys = [
  'name',
  'title',
  'bookName',
  'book_name',
  'videoName',
  'albumName',
  'novelName',
];
const List<String> _authorKeys = [
  'author',
  'writer',
  'upName',
  'artist',
  'narrator',
  'speaker',
];
const List<String> _coverKeys = [
  'cover',
  'img',
  'coverUrl',
  'pic',
  'image',
  'coverImg',
  'thumb',
  'poster',
];
const List<String> _urlKeys = [
  'url',
  'bookUrl',
  'detailUrl',
  'link',
  'href',
  'bookId',
  'videoId',
  'id',
];
const List<String> _introKeys = [
  'intro',
  'desc',
  'description',
  'summary',
  'brief',
  'remark',
];

/// 把插件 `recommend` / `home` 的返回值归一化成板块列表。
///
/// 兼容几种常见写法：
/// - `[{ name, author, cover, url }]`                    单板块书籍数组
/// - `{ list: [...], title: '热门' }`                    map 包一层
/// - `{ data: { list: [...] } }`                         data 再包一层
/// - `[{ title: '热门', books: [...] }, { ... }]`         多板块
/// - `{ sections: [{ title, items: [...] }] }`           显式 sections
List<FeedSection> parseHomeFeed(dynamic raw, {String fallbackTitle = '为你推荐'}) {
  final data = _decode(raw);
  if (data == null) return const [];

  if (data is Map) {
    final map = Map<String, dynamic>.from(data);

    // 显式板块字段
    for (final key in const [
      'sections',
      'groups',
      'blocks',
      'modules',
      'categories',
    ]) {
      final v = map[key];
      if (v is List && v.isNotEmpty) {
        final sections = _fromList(v, fallbackTitle);
        if (sections.isNotEmpty) return sections;
      }
    }

    // 常见的外层包装：data / result / lists
    for (final key in const [
      'data',
      'result',
      'lists',
      'list',
      'books',
      'items',
      'records',
      'videos',
    ]) {
      final v = map[key];
      if (v is Map || v is List) {
        final nested = parseHomeFeed(v, fallbackTitle: fallbackTitle);
        if (nested.isNotEmpty) {
          final named = _pick(map, const ['title', 'name', 'sectionName']);
          if (named == null || nested.length > 1) return nested;
          return [
            FeedSection(title: named, books: nested.first.books),
          ];
        }
      }
    }

    // 单本书
    final one = _book(map);
    if (one != null) {
      return [
        FeedSection(title: fallbackTitle, books: [one]),
      ];
    }
    return const [];
  }

  if (data is List) return _fromList(data, fallbackTitle);
  return const [];
}

List<FeedSection> _fromList(List list, String fallbackTitle) {
  final sections = <FeedSection>[];
  final flat = <FeedBook>[];

  for (final e in list) {
    if (e is! Map) continue;
    final m = Map<String, dynamic>.from(e);

    final inner = _innerList(m);
    if (inner != null) {
      final books = <FeedBook>[];
      for (final x in inner) {
        final b = _book(x);
        if (b != null) books.add(b);
      }
      if (books.isNotEmpty) {
        sections.add(FeedSection(
          title: _pick(m, const ['title', 'name', 'sectionName', 'category', 'label']) ??
              fallbackTitle,
          books: books,
        ));
      }
    } else {
      final b = _book(m);
      if (b != null) flat.add(b);
    }
  }

  if (flat.isNotEmpty) {
    sections.insert(0, FeedSection(title: fallbackTitle, books: flat));
  }
  return sections;
}

/// 判断一个 map 是不是「板块」，而不是「一本书」
List<dynamic>? _innerList(Map<String, dynamic> m) {
  for (final key in const [
    'books',
    'list',
    'items',
    'data',
    'records',
    'videos',
    'novels',
  ]) {
    final v = m[key];
    if (v is! List || v.isEmpty) continue;
    // 必须至少有一项能当成书，才认作板块，避免把书里的 tags 当板块
    for (final x in v) {
      if (_book(x) != null) return v;
    }
  }
  return null;
}

FeedBook? _book(dynamic e) {
  if (e is! Map) return null;
  final m = Map<String, dynamic>.from(e);
  final title = _pick(m, _titleKeys);
  if (title == null || title.isEmpty) return null;
  if (title.length > 80) return null;

  final url = _pick(m, _urlKeys) ?? title;
  return FeedBook(
    title: title,
    author: _pick(m, _authorKeys) ?? '',
    cover: _pick(m, _coverKeys) ?? '',
    url: url,
    intro: _pick(m, _introKeys) ?? '',
  );
}

String? _pick(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v == null) continue;
    if (v is Map || v is List) continue;
    final s = '$v'.trim();
    if (s.isNotEmpty && s != 'null') return s;
  }
  return null;
}

dynamic _decode(dynamic raw) {
  var v = raw;
  for (var i = 0; i < 3; i++) {
    if (v is! String) break;
    final t = v.trim();
    if (t.isEmpty) return null;
    if (!(t.startsWith('{') || t.startsWith('[') || t.startsWith('"'))) {
      return null;
    }
    try {
      v = jsonDecode(t);
    } catch (_) {
      return null;
    }
  }
  return v;
}

// ---------------------------------------------------------------- Provider

/// 首页选中的源（跨听书/视频，独立于搜索页的「当前源」记忆）
final homeSourceIdProvider = StateProvider<String?>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getString(AppConstants.keyHomeSourceId);
});

/// 切换首页源（落 SharedPreferences）
void setHomeSource(WidgetRef ref, String sourceId) {
  ref.read(sharedPrefsProvider).setString(
        AppConstants.keyHomeSourceId,
        sourceId,
      );
  ref.read(homeSourceIdProvider.notifier).state = sourceId;
}

/// 实际生效的首页源：选中的源失效时回落到第一个启用的源
final activeHomeSourceProvider = Provider<PluginSource?>((ref) {
  final list = ref.watch(sourceListProvider).value ?? const <PluginSource>[];
  final enabled = list.where((s) => s.enabled).toList(growable: false);
  if (enabled.isEmpty) return null;
  final id = ref.watch(homeSourceIdProvider);
  for (final s in enabled) {
    if (s.id == id) return s;
  }
  return enabled.first;
});

/// 首页推荐内容（按源缓存，切换源 / 下拉刷新时 invalidate）
final homeFeedProvider =
    FutureProvider.family<List<FeedSection>, String>((ref, sourceId) async {
  final repo = ref.read(sourceRepositoryProvider);
  final source = await repo.byId(sourceId);
  if (source == null) throw Exception('源已不存在，请重新导入');

  final engine = source.isTingShu

      ? ref.read(tingShuEngineProvider)

      : source.isJar

      ? ref.read(jarPluginEngineProvider)

      : ref.read(jsPluginEngineProvider);
  await engine.attach(source);

  // 按源的实际能力依次试：推荐接口 → 分类浏览 → 空关键词搜索，
  // 哪个有内容用哪个。两个格式的源都要能出内容，别一律显示失败/空白。
  var sections = <FeedSection>[];

  // 1) 推荐接口
  try {
    final raw = await engine.invoke('recommend', params: {'page': 1});
    sections = parseHomeFeed(raw, fallbackTitle: '为你推荐');
  } catch (e) {
    final msg = '$e';
    if (!msg.contains('未实现') && !msg.contains('METHOD_NOT_FOUND')) {
      // 推荐接口本身报错（不是“没实现”）：先不抛，继续试分类/搜索
      appLogger.warning('推荐接口失败，改试分类', detail: '$e');
    }
  }

  // 2) 分类浏览：拿分类列表，顺着试前几个分类，哪个有书用哪个
  if (sections.isEmpty) {
    try {
      final cats = await engine.invoke('categories', params: {});
      final list = cats is List ? cats : const [];
      for (var i = 0; i < list.length && i < 3; i++) {
        final c = list[i];
        final id = c is Map
            ? '${c['id'] ?? c['url'] ?? c['name'] ?? ''}'
            : '$c';
        final name = c is Map ? '${c['name'] ?? c['title'] ?? id}' : '$c';
        if (id.isEmpty) continue;
        try {
          final raw = await engine.invoke('browse',
              params: {'category': id, 'page': 1});
          final got = parseHomeFeed(raw, fallbackTitle: name);
          if (got.isNotEmpty) {
            sections = got;
            break;
          }
        } catch (_) {
          // 这个分类打不开，试下一个
        }
      }
    } catch (_) {
      // 源没有分类接口，继续试搜索
    }
  }

  // 3) 空关键词搜索：不少源的空搜索就是热门推荐
  if (sections.isEmpty) {
    try {
      final again =
          await engine.invoke('search', params: {'keyword': '', 'page': 1});
      sections = parseHomeFeed(again, fallbackTitle: '为你推荐');
    } catch (_) {}
  }

  appLogger.info('首页推荐已加载',
      detail: '${source.name} 板块=${sections.length}');
  return sections;
});
