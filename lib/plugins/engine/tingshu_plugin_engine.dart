import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../core/log/app_logger.dart';
import '../../features/ua/ua_resolver.dart';
import '../data/source_config_repository.dart';
import '../data/source_repository.dart';
import '../data/ting_shu_bridge.dart';
import '../model/plugin_source.dart';
import 'plugin_engine.dart';

/// 「我的听书」格式 JAR 源的引擎。
///
/// 一个 JAR 里可能有很多个源（SourceEntry.getSources 返回一串），
/// 安装时已经拆成多条 [PluginSource]，每条记住 jarPath + 入口类 + 下标，
/// 调用时由原生侧反射到对应的源实例。
///
/// 两个断层在这里补上（旧版是断的）：
/// 1. content 只传 URL 是断层：现在 content 调原生 `audio` 时把
///    `lineId` / `voiceId` 一起传过去，原生侧先把 lineId 推给源
///    （源有 setLineId / setCurrentLine / setConfig 这类方法就反射调它，
///    没有就写进该源的 ExternalSourcePrefs，供源自己读），再跑提取器。
/// 2. lines / voices 写死 `[]` 是断层：现在调原生 `lines` / `voices`，
///    原生侧反射探源有没有 lines()/lineList()/getLines()/videoLines()
///   （voices 同理），有就归一化返回，没有才返回空——空是探出来的结果，
///    不是写死的占位。源本身没有线路概念时，返回空是诚实的。
class TingShuPluginEngine implements PluginEngine {
  final SourceRepository _repo;
  final UaResolver _uaResolver;
  final SourceConfigRepository? _configRepo;

  TingShuPluginEngine(this._repo, this._uaResolver, [this._configRepo]);

  PluginSource? _source;
  String? _jarPath;
  String? _entryClass;

  /// 详情页一次调用拿全（章节、简介、封面），chapters 直接复用。
  Map<String, dynamic>? _detailCache;

  /// lines / voices / config 的能力探测结果缓存（按源 id）。
  final Map<String, Map<String, bool>> _capabilityCache = {};

  @override
  String get format => 'tingshu';

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
    // UA 统一走 UaResolver：解析出的两条 UA 推给原生侧，
    // 源里调 getMobileUA() / getDesktopUA() / Connection.config() 拿到的
    // 就是解析后的值；解析器返回 null 时原生侧用内置默认。
    try {
      String? configUa;
      final configRepo = _configRepo;
      if (configRepo != null) {
        final cfg = await configRepo.load(source.id, source.type);
        final raw = cfg.valueOf('ua') ?? cfg.valueOf('userAgent');
        if (raw != null && '$raw'.isNotEmpty) configUa = '$raw';
      }
      final mobile = await _uaResolver.resolve(
        sourceId: source.id,
        sourceName: source.name,
        url: source.url,
        sourceConfigUa: configUa,
        desktop: false,
      );
      final desktop = await _uaResolver.resolve(
        sourceId: source.id,
        sourceName: source.name,
        url: source.url,
        sourceConfigUa: configUa,
        desktop: true,
      );
      await TingShuBridge.setUserAgents(mobile, desktop);
    } catch (e) {
      appLogger.warning('TingShu 源 UA 下发失败', detail: '$e');
    }
  }

  Future<dynamic> _call(String method,
      [Map<String, dynamic>? params]) async {
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
      case 'categoryMenus':
      case 'categoryPage':
      case 'bookDetail':
      case 'detail':
      case 'chapters':
      case 'content':
      case 'isCacheable':
        return true;
      case 'lines':
      case 'voices':
      case 'config':
        // 探一次原生侧：源有没有对应方法。结果按源缓存，不用每次都探。
        final id = _source?.id;
        if (id == null) return null;
        final cached = _capabilityCache[id];
        if (cached != null && cached.containsKey(method)) {
          return cached[method];
        }
        try {
          final r = await invoke(method, params: const <String, dynamic>{
            'url': '',
          });
          final ok = r is List && r.isNotEmpty;
          _capabilityCache.putIfAbsent(id, () => <String, bool>{})[method] =
              ok;
          return ok;
        } catch (_) {
          _capabilityCache.putIfAbsent(id, () => <String, bool>{})[method] =
              false;
          return false;
        }
      default:
        return false;
    }
  }

  @override
  Future<dynamic> invoke(String method,
      {Map<String, dynamic> params = const <String, dynamic>{}}) async {
    final p = params;
    switch (method) {
      case 'search':
        {
          final r = await _call('search', <String, dynamic>{
            'keyword': p['keyword'] ?? '',
            'page': p['page'] ?? 1,
          });
          if (r is Map) {
            return <String, dynamic>{
              'books': _asList(r['books']),
              'totalPage': (r['totalPage'] as num?)?.toInt() ?? 0,
            };
          }
          return <String, dynamic>{
            'books': _asList(r),
            'totalPage': (p['page'] as num?)?.toInt() ?? 1,
          };
        }
      case 'categoryMenus':
        {
          final r = await _call('categories');
          return _categories(r);
        }
      case 'categoryPage':
        {
          final r = await _call('browse', <String, dynamic>{
            'category': p['menu'] ?? p['url'] ?? '',
            'url': p['menu'] ?? p['url'] ?? '',
          });
          if (r is Map) {
            return <String, dynamic>{
              'books': _asList(r['books']),
              'nextUrl': '${r['nextUrl'] ?? ''}',
              'totalPage': (r['totalPage'] as num?)?.toInt() ?? 0,
            };
          }
          return <String, dynamic>{
            'books': const <Map<String, dynamic>>[],
            'nextUrl': '',
            'totalPage': 0,
          };
        }
      case 'bookDetail':
      case 'detail':
        {
          final d = await _detail('${p['url'] ?? ''}');
          return d;
        }
      case 'chapters':
        {
          final d = await _detail('${p['url'] ?? ''}');
          return d['chapters'];
        }
      case 'content':
        {
          // lineId / voiceId 必须传进源：原生 audio 分支先推 lineId 再解析，
          // 否则切线只是重复调同一个 audio(url)。
          final r = await _call('audio', <String, dynamic>{
            'url': p['url'] ?? p['chapterUrl'] ?? '',
            'voiceId': p['voiceId'] ?? '',
            'lineId': p['lineId'] ?? '',
          });
          if (r is! Map) throw Exception('这个源没有解析出播放地址');
          final url = '${r['url'] ?? ''}';
          if (url.isEmpty) throw Exception('这个源没有解析出播放地址');
          final headers = <String, String>{};
          final rawHeaders = r['headers'];
          if (rawHeaders is Map) {
            for (final e in rawHeaders.entries) {
              headers['${e.key}'] = '${e.value}';
            }
          }
          return <String, dynamic>{'url': url, 'headers': headers};
        }
      case 'lines':
      case 'voices':
        {
          final r = await _call(method, <String, dynamic>{
            'url': p['url'] ?? '',
          });
          return _normalizeOptions(r);
        }
      case 'config':
        {
          final r = await _call('config');
          if (r is List) return r;
          if (r is Map) {
            for (final k in const <String>[
              'fields',
              'config',
              'items',
              'list',
            ]) {
              if (r[k] is List) return r[k];
            }
          }
          return const <dynamic>[];
        }
      case 'isCacheable':
        {
          final path = _jarPath;
          final entry = _entryClass;
          if (path == null || entry == null) return true;
          return TingShuBridge.isCacheable(
            jarPath: path,
            entryClass: entry,
            index: _source?.sourceIndex ?? 0,
          );
        }
      case 'recommend':
        {
          // 我的听书没有推荐位，用分类的第一页顶上。第一个分类可能没内容
          // （比如要登录、或者这个分类本来就空），顺着往后试几个分类，
          // 拿到书就返回，别因为第一个分类空就让整个推荐位空着。
          final menus = _categories(await _call('categories'));
          if (menus.isEmpty) return const <Map<String, dynamic>>[];
          for (var i = 0; i < menus.length && i < 3; i++) {
            final first = menus[i];
            try {
              final r = await _call('browse',
                  <String, dynamic>{'category': first['url']});
              final books = _asList(r is Map ? r['books'] : null);
              if (books.isNotEmpty) {
                return <Map<String, dynamic>>[
                  <String, dynamic>{
                    'title': '${first['name']}',
                    'books': books,
                  },
                ];
              }
            } catch (_) {
              // 这个分类打不开，试下一个。
            }
          }
          return const <Map<String, dynamic>>[];
        }
      default:
        throw Exception('该源不支持${PluginMethods.labels[method] ?? method}');
    }
  }

  /// 登录入口（ILogin）：没有返回 null，有返回 {url, desktop}。
  /// 通用 JAR 的 loginInfo 不要写死 null——这里走的是原生反射，
  /// 源实现了 ILogin 就一定能拿到。
  @override
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
  /// 有返回 {url, ua, delayMs, validated}。
  @override
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

  /// 搜索验证过没有（源自己读 Cookie 判断）。
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
    final r = await _call('detail', <String, dynamic>{'url': url});
    final chapters = _asList(r is Map ? r['chapters'] : null)
        .map((e) => <String, dynamic>{
              'name': '${e['title'] ?? e['name'] ?? ''}',
              'url': '${e['url'] ?? ''}',
            })
        .toList();
    final out = <String, dynamic>{
      '__url': url,
      'cover': r is Map ? '${r['cover'] ?? ''}' : '',
      'author': r is Map ? '${r['author'] ?? ''}' : '',
      'artist': r is Map ? '${r['artist'] ?? ''}' : '',
      'intro': r is Map ? '${r['intro'] ?? ''}' : '',
      'chapters': chapters,
    };
    _detailCache = out;
    return out;
  }

  List<Map<String, dynamic>> _asList(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }

  /// menus -> [{name, url}]（两级菜单展平，用「大类·子类」当名字）。
  List<Map<String, String>> _categories(dynamic raw) {
    if (raw is! Map) return const <Map<String, String>>[];
    final menus = raw['menus'];
    if (menus is! List) return const <Map<String, String>>[];
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
        out.add(<String, String>{
          'name': group.isEmpty ? name : '$group · $name',
          'url': url,
        });
      }
    }
    return out;
  }

  /// 把原生返回的线路/音色归一化成 [{id, name}]：只做归一化，不自己拼。
  List<Map<String, dynamic>> _normalizeOptions(dynamic raw) {
    var data = raw;
    for (var i = 0; i < 3; i++) {
      if (data is! String) break;
      final t = data.trim();
      if (t.isEmpty) return const <Map<String, dynamic>>[];
      if (!(t.startsWith('{') || t.startsWith('['))) {
        return <Map<String, dynamic>>[
          <String, dynamic>{'id': t, 'name': t},
        ];
      }
      try {
        data = jsonDecode(t);
      } catch (_) {
        return const <Map<String, dynamic>>[];
      }
    }
    if (data is Map) {
      for (final k in const <String>[
        'list',
        'data',
        'items',
        'voices',
        'lines',
        'options',
      ]) {
        if (data[k] is List) {
          data = data[k];
          break;
        }
      }
    }
    final out = <Map<String, dynamic>>[];
    if (data is List) {
      for (var i = 0; i < data.length; i++) {
        final e = data[i];
        if (e is Map) {
          final v = '${e['id'] ?? e['value'] ?? e['key'] ?? i}';
          final l =
              '${e['name'] ?? e['label'] ?? e['title'] ?? e['text'] ?? v}';
          out.add(<String, dynamic>{'id': v, 'name': l});
        } else if (e != null) {
          out.add(<String, dynamic>{'id': '$e', 'name': '$e'});
        }
      }
    }
    return out;
  }

  @override
  Future<void> dispose() async {
    _source = null;
    _detailCache = null;
  }

  /// 安装时用：扫描 JAR 里的入口类。
  static Future<List<String>> scan(String jarPath) =>
      TingShuBridge.scanEntryClasses(jarPath);

  /// 安装时用：列出包里每个源。
  static Future<List<Map<String, dynamic>>> list(
          String jarPath, String entryClass) =>
      TingShuBridge.listSources(jarPath, entryClass);
}
