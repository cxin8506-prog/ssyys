import 'dart:convert';

import 'package:path/path.dart' as p;

import '../data/source_repository.dart';
import '../data/ting_shu_bridge.dart';
import '../model/plugin_source.dart';
import 'plugin_engine.dart';

/// 「我的听书」格式 JAR 源的引擎。
///
/// 一个 JAR 里可能有很多个源（SourceEntry.getSources 返回一串），
/// 安装时已经拆成多条 [PluginSource]，每条记住 jarPath + 入口类 + 下标，
/// 调用时由原生侧反射到对应的源实例。
class TingShuPluginEngine implements PluginEngine {
  final SourceRepository _repo;

  TingShuPluginEngine(this._repo);

  PluginSource? _source;
  String? _jarPath;
  String? _entryClass;

  /// 详情页一次调用拿全（章节、简介、封面），chapters 直接复用
  Map<String, dynamic>? _detailCache;

  @override
  String get format => 'tingShu';

  @override
  Future<void> attach(PluginSource source) async {
    if (_source?.id == source.id && _jarPath != null) return;
    _source = source;
    _detailCache = null;
    _jarPath = source.jarPath;
    if (_jarPath == null || _jarPath!.isEmpty) {
      final dir = await _repo.sourceDirPath(source.id);
      _jarPath = p.join(dir, 'plugin.jar');
    }
    _entryClass = source.entryClass;
    if (_entryClass == null || _entryClass!.isEmpty) {
      final list = await TingShuBridge.scanEntryClasses(_jarPath!);
      _entryClass = list.isEmpty ? null : list.first;
      if (_entryClass == null) {
        throw Exception('这个 JAR 不是「我的听书」格式的源包');
      }
    }
  }

  Future<dynamic> _call(String method, [Map<String, dynamic>? params]) async {
    final path = _jarPath;
    final entry = _entryClass;
    if (path == null || entry == null) throw Exception('源还没准备好');
    return TingShuBridge.call(
      jarPath: path,
      entryClass: entry,
      index: _source?.sourceIndex ?? 0,
      method: method,
      params: params,
    );
  }

  @override
  Future<bool?> hasMethod(String method) async {
    switch (method) {
      case 'search':
        return true;
      case 'categories':
      case 'browse':
        return true;
      case 'content':
        return true;
      case 'detail':
      case 'chapters':
        return true;
      default:
        return false;
    }
  }

  @override
  Future<dynamic> invoke(String method, {Map<String, dynamic>? params}) async {
    final p = params ?? const <String, dynamic>{};
    switch (method) {
      case 'search':
        final r = await _call('search', {
          'keyword': p['keyword'] ?? '',
          'page': p['page'] ?? 1,
        });
        return _asList(r?['books']);

      case 'categories':
        final r = await _call('categories');
        return _categories(r);

      case 'recommend':
        // 我的听书没有推荐位，用第一个分类的第一页顶上
        final menus = _categories(await _call('categories'));
        if (menus.isEmpty) return const <Map<String, dynamic>>[];
        final first = menus.first;
        final r = await _call('browse', {'category': first['url']});
        return [
          {
            'title': '${first['name']}',
            'books': _asList(r?['books']),
          }
        ];

      case 'browse':
        final r = await _call('browse', {
          'category': p['category'] ?? p['url'] ?? '',
        });
        return {
          'list': _asList(r?['books']),
          'nextUrl': r?['nextUrl'] ?? '',
          'totalPage': r?['totalPage'] ?? 0,
        };

      case 'detail':
        final d = await _detail('${p['url'] ?? ''}');
        return d;

      case 'chapters':
        final d = await _detail('${p['url'] ?? ''}');
        return d['chapters'];

      case 'content':
        final r = await _call('audio', {'url': p['url'] ?? p['chapterUrl'] ?? ''});
        final url = '${r?['url'] ?? ''}';
        if (url.isEmpty) throw Exception('这个源没有解析出播放地址');
        final headers = <String, String>{};
        final rawHeaders = r?['headers'];
        if (rawHeaders is Map) {
          for (final e in rawHeaders.entries) {
            headers['${e.key}'] = '${e.value}';
          }
        }
        return {'url': url, 'headers': headers};

      case 'lines':
      case 'voices':
        return const [];

      default:
        throw Exception('该源不支持${PluginMethods.labels[method] ?? method}');
    }
  }

  /// 登录入口（ILogin）：没有返回 null，有返回 {url, desktop}
  Future<Map<String, dynamic>?> loginInfo() async {
    final path = _jarPath;
    final entry = _entryClass;
    if (path == null || entry == null) return null;
    return TingShuBridge.loginInfo(
      jarPath: path,
      entryClass: entry,
      index: _source?.sourceIndex ?? 0,
    );
  }

  /// 搜索验证（ISearchVerification）：没有返回 null，
  /// 有返回 {url, ua, delayMs, validated}
  Future<Map<String, dynamic>?> verificationInfo(String keyword) async {
    final path = _jarPath;
    final entry = _entryClass;
    if (path == null || entry == null) return null;
    return TingShuBridge.verificationInfo(
      jarPath: path,
      entryClass: entry,
      index: _source?.sourceIndex ?? 0,
      keyword: keyword,
    );
  }

  /// 搜索验证过没有
  Future<bool> isSearchValidated() async {
    final path = _jarPath;
    final entry = _entryClass;
    if (path == null || entry == null) return false;
    return TingShuBridge.isSearchValidated(
      jarPath: path,
      entryClass: entry,
      index: _source?.sourceIndex ?? 0,
    );
  }

  Future<Map<String, dynamic>> _detail(String url) async {
    final cached = _detailCache;
    if (cached != null && cached['__url'] == url) return cached;
    final r = await _call('detail', {'url': url});
    final chapters = _asList(r?['chapters']).map((e) {
      return {
        'name': '${e['title'] ?? e['name'] ?? ''}',
        'url': '${e['url'] ?? ''}',
      };
    }).toList();
    final out = <String, dynamic>{
      '__url': url,
      'cover': r?['cover'] ?? '',
      'author': r?['author'] ?? '',
      'artist': r?['artist'] ?? '',
      'intro': r?['intro'] ?? '',
      'chapters': chapters,
    };
    _detailCache = out;
    return out;
  }

  List<Map<String, dynamic>> _asList(dynamic raw) {
    if (raw is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }

  /// menus -> [{name,url}]（两级菜单展平，用「大类·子类」当名字）
  List<Map<String, String>> _categories(dynamic raw) {
    if (raw is! Map) return const [];
    final menus = raw['menus'];
    if (menus is! List) return const [];
    final out = <Map<String, String>>[];
    for (final m in menus) {
      if (m is! Map) continue;
      final group = '${m['title'] ?? ''}';
      final tabs = m['tabs'];
      if (tabs is! List) continue;
      for (final t in tabs) {
        if (t is! Map) continue;
        final name = '${t['title'] ?? ''}';
        final url = '${t['url'] ?? ''}';
        if (url.isEmpty) continue;
        out.add({
          'name': group.isEmpty ? name : '$group · $name',
          'url': url,
        });
      }
    }
    return out;
  }

  @override
  Future<void> dispose() async {
    _source = null;
    _detailCache = null;
  }

  /// 安装时用：扫描 JAR 里的入口类
  static Future<List<String>> scan(String jarPath) =>
      TingShuBridge.scanEntryClasses(jarPath);

  /// 安装时用：列出包里每个源
  static Future<List<Map<String, dynamic>>> list(
          String jarPath, String entryClass) =>
      TingShuBridge.listSources(jarPath, entryClass);
}
