import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/library_repository.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../features/audio/data/audio_handler.dart';
import '../data/plugin_providers.dart';
import '../model/plugin_source.dart';
import '../../shared/widgets/bottom_bar_inset.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/login_web_page.dart';
import '../../shared/widgets/soft_ui.dart';

/// 源书单页：详情整页进（不是详情弹窗）。
///
/// - 顶部模糊封面背景 + 大封面 + 标题 + 简介（两行可展开）+
///   “播放/继续播放”主按钮 + 加入书架/收藏 + 倒序 +
///   在其它源中搜索 + 单书跳过片头片尾。
/// - 章节列表先显示缓存章节，多页先取第一页、后台补全并报进度。
/// - 线路选择器横向一排，没线隐藏；线路按书记，不按源记。
/// - 登录入口、需要登录横条（和源中心同款逻辑：engine.loginInfo()）。
/// - 播放时把 onResolveChapter 传给播放器组：先查缓存再调引擎
///   content 解析，失败报人话错。
class SourceBookPage extends ConsumerStatefulWidget {
  final String sourceId;
  final String bookUrl;
  final String title;
  final String? coverUrl;
  final String? author;
  final String? intro;
  final bool autoPlay;

  const SourceBookPage({
    super.key,
    required this.sourceId,
    required this.bookUrl,
    required this.title,
    this.coverUrl,
    this.author,
    this.intro,
    this.autoPlay = false,
  });

  @override
  ConsumerState<SourceBookPage> createState() => _SourceBookPageState();
}

class _SourceBookPageState extends ConsumerState<SourceBookPage> {
  PluginSource? _source;
  Map<String, dynamic> _detail = {};
  List<Map<String, dynamic>> _chapters = const [];
  List<Map<String, dynamic>> _voices = const [];
  List<Map<String, dynamic>> _lines = const [];
  String? _voiceId;
  String? _lineId;
  bool _loading = true;
  String? _error;
  bool _needLogin = false;
  bool _reversed = false;
  bool _introExpanded = false;
  bool _loadingFull = false;
  String? _fullProgress;
  int _playingIndex = -1;
  bool _isFavorite = false;
  final Map<String, int> _positions = {};
  final Map<String, bool> _finished = {};
  final Map<int, String> _resolvedUrls = {};
  Map<String, String> _lastMediaHeaders = const {};
  final _chapterFilterController = TextEditingController();
  String _chapterFilter = '';

  String get _bookKey => '${widget.sourceId}|${widget.bookUrl}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _chapterFilterController.dispose();
    super.dispose();
  }

  String _chapterUrl(Map<String, dynamic> c) =>
      '${c['url'] ?? c['audioUrl'] ?? c['href'] ?? ''}';

  String _chapterTitle(Map<String, dynamic> c) =>
      '${c['title'] ?? c['name'] ?? ''}';

  Future<void> _load() async {
    final list = ref.read(sourceListProvider).value ?? const <PluginSource>[];
    PluginSource? found;
    for (final s in list) {
      if (s.id == widget.sourceId) found = s;
    }
    found ??= await ref.read(sourceRepositoryProvider).byId(widget.sourceId);
    if (!mounted) return;
    setState(() => _source = found);
    if (found == null) {
      setState(() {
        _loading = false;
        _error = '找不到这个源，可能已被删除';
      });
      return;
    }
    // 先显示缓存章节（有缓存先出第一页再后台补全）。
    await _showCached();
    await _loadLogin(found);
    await _loadDetail(found, loadFullPages: false);
    if (!mounted) return;
    setState(() => _loading = false);
    _loadFavorite();
    _loadPositions();
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _playResume());
    }
  }

  Future<void> _showCached() async {
    try {
      final prefs = ref.read(sharedPrefsProvider);
      final raw = prefs.getString('cached_detail_$_bookKey');
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw);
      if (map is Map) {
        final detail = Map<String, dynamic>.from(map);
        final chapters = _parseChapters(detail);
        if (!mounted) return;
        setState(() {
          _detail = detail;
          _chapters = chapters;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadLogin(PluginSource source) async {
    try {
      final engine = engineForSource(ref, source);
      await engine.attach(source);
      final info = await engine.loginInfo();
      if (!mounted) return;
      final needs = info != null &&
          (info['needLogin'] == true || info['needsLogin'] == true);
      setState(() => _needLogin = needs);
    } catch (_) {}
  }

  Future<void> _loadDetail(PluginSource source,
      {required bool loadFullPages}) async {
    try {
      final engine = engineForSource(ref, source);
      await engine.attach(source);
      final raw = await engine.invoke(
        'bookDetail',
        params: {
          'url': widget.bookUrl,
          'loadEpisodes': true,
          'loadFullPages': loadFullPages,
        },
      );
      if (raw is! Map) return;
      final detail = Map<String, dynamic>.from(raw);
      final chapters = _parseChapters(detail);
      final voices = _parseList(detail['voices']);
      final lines = _parseList(detail['lines']);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        if (chapters.isNotEmpty) _chapters = chapters;
        if (voices.isNotEmpty) _voices = voices;
        if (lines.isNotEmpty) _lines = lines;
        _needLogin = detail['needLogin'] == true || _needLogin;
      });
      // 缓存详情（200KB 以内才存，免得 SharedPreferences 爆掉）。
      try {
        final encoded = jsonEncode(detail);
        if (encoded.length < 200 * 1024) {
          await ref
              .read(sharedPrefsProvider)
              .setString('cached_detail_$_bookKey', encoded);
        }
      } catch (_) {}
      // 多页章节：先取第一页立即显示，后台补全并报进度。
      final totalPage = _asInt(detail['totalPage'] ?? detail['totalPages']);
      if (!loadFullPages && totalPage > 1 && chapters.isNotEmpty) {
        _loadFullPages(source);
      }
      // 线路：详情里没给就问引擎 lines 方法（不自己拼，不写死 []）。
      if (lines.isEmpty) {
        _loadLines(source);
      }
      // 音色：详情里没给就问引擎 voices。
      if (voices.isEmpty) {
        _loadVoices(source);
      }
      // 恢复上次选的线路（按书记）。
      if (_lineId == null) {
        final saved = ref
            .read(sharedPrefsProvider)
            .getString('selected_line_${Uri.encodeComponent(_bookKey)}');
        if (saved != null && saved.isNotEmpty) {
          setState(() => _lineId = saved);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '详情加载失败：$e';
      });
    }
  }

  Future<void> _loadFullPages(PluginSource source) async {
    if (_loadingFull) return;
    setState(() {
      _loadingFull = true;
      _fullProgress = '正在加载全部章节…';
    });
    try {
      final engine = engineForSource(ref, source);
      await engine.attach(source);
      final raw = await engine.invoke(
        'bookDetail',
        params: {
          'url': widget.bookUrl,
          'loadEpisodes': true,
          'loadFullPages': true,
        },
      );
      if (raw is Map) {
        final chapters = _parseChapters(Map<String, dynamic>.from(raw));
        if (!mounted) return;
        if (chapters.length > _chapters.length) {
          setState(() => _chapters = chapters);
        }
      }
    } catch (_) {
      // 后台补全失败不报错，第一页照样能播。
    } finally {
      if (mounted) {
        setState(() {
          _loadingFull = false;
          _fullProgress = null;
        });
      }
    }
  }

  Future<void> _loadLines(PluginSource source) async {
    try {
      final engine = engineForSource(ref, source);
      await engine.attach(source);
      final raw = await engine.invoke('lines', params: {'url': widget.bookUrl});
      final lines = _parseList(raw);
      if (!mounted) return;
      if (lines.isNotEmpty) setState(() => _lines = lines);
    } catch (_) {}
  }

  Future<void> _loadVoices(PluginSource source) async {
    try {
      final engine = engineForSource(ref, source);
      await engine.attach(source);
      final raw = await engine.invoke('voices', params: {'url': widget.bookUrl});
      final voices = _parseList(raw);
      if (!mounted) return;
      if (voices.isNotEmpty) setState(() => _voices = voices);
    } catch (_) {}
  }

  List<Map<String, dynamic>> _parseChapters(Map<String, dynamic> detail) {
    final raw = detail['episodes'] ?? detail['chapters'] ?? detail['list'];
    return _parseList(raw);
  }

  List<Map<String, dynamic>> _parseList(dynamic raw) {
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['list'] ?? raw['data']) : null);
    if (list is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
      if (e is String) out.add(<String, dynamic>{'title': e, 'url': e});
    }
    return out;
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  Future<void> _loadFavorite() async {
    try {
      final fav = await ref
          .read(libraryRepositoryProvider)
          .isFavorite(_bookKey);
      if (!mounted) return;
      setState(() => _isFavorite = fav);
    } catch (_) {}
  }

  Future<void> _loadPositions() async {
    final repo = ref.read(libraryRepositoryProvider);
    final positions = <String, int>{};
    final finished = <String, bool>{};
    for (final c in _chapters) {
      final url = _chapterUrl(c);
      if (url.isEmpty) continue;
      try {
        final p = await repo.getProgress(_bookKey, url);
        final pos = _posOf(p, 'positionMs');
        final dur = _posOf(p, 'durationMs');
        final fin = _boolOf(p, 'isFinished') ||
            (dur > 0 && pos > 0 && pos >= dur * 0.95);
        if (pos > 0) positions[url] = pos;
        if (fin) finished[url] = true;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _positions.addAll(positions);
      _finished.addAll(finished);
    });
  }

  int _posOf(dynamic p, String field) {
    if (p == null) return 0;
    try {
      if (p is Map) return _asInt(p[field]);
      final v = (p as dynamic).positionMs;
      if (field == 'positionMs') return _asInt(v);
      final d = (p as dynamic).durationMs;
      return _asInt(d);
    } catch (_) {
      return 0;
    }
  }

  bool _boolOf(dynamic p, String field) {
    if (p == null) return false;
    try {
      if (p is Map) return p[field] == true;
      return (p as dynamic).isFinished == true;
    } catch (_) {
      return false;
    }
  }

  List<Map<String, dynamic>> get _visibleChapters {
    var list = List<Map<String, dynamic>>.from(_chapters);
    if (_chapterFilter.isNotEmpty) {
      list = list
          .where((c) => _chapterTitle(c)
              .toLowerCase()
              .contains(_chapterFilter.toLowerCase()))
          .toList();
    }
    if (_reversed) list = list.reversed.toList();
    return list;
  }

  int _resumeIndex() {
    for (var i = 0; i < _chapters.length; i++) {
      final url = _chapterUrl(_chapters[i]);
      if (_positions.containsKey(url) && !(_finished[url] ?? false)) {
        return i;
      }
    }
    return 0;
  }

  Future<void> _playResume() async {
    if (_chapters.isEmpty) return;
    await _playChapter(_resumeIndex());
  }

  /// 解析一章的播放地址：先查缓存再调引擎 content 解析。
  Future<String?> _resolveChapter(int index) async {
    if (index < 0 || index >= _chapters.length) return null;
    final cached = _resolvedUrls[index];
    if (cached != null && cached.isNotEmpty) return cached;
    final source = _source;
    if (source == null) return null;
    try {
      final engine = engineForSource(ref, source);
      await engine.attach(source);
      final raw = await engine.invoke(
        'content',
        params: {
          'url': _chapterUrl(_chapters[index]),
          'voiceId': _voiceId ?? '',
          'lineId': _lineId ?? '',
        },
      );
      final url = _mediaUrlOf(raw);
      if (url.isEmpty) return null;
      _resolvedUrls[index] = url;
      if (raw is Map) {
        final headers = raw['headers'];
        if (headers is Map) {
          _lastMediaHeaders = headers.map(
            (k, v) => MapEntry('$k', '$v'),
          );
        }
      }
      return url;
    } catch (e) {
      throw Exception('解析第 ${index + 1} 集失败：$e');
    }
  }

  String _mediaUrlOf(dynamic raw) {
    if (raw is String) return raw;
    if (raw is Map) {
      final u = raw['url'] ?? raw['audioUrl'] ?? raw['src'] ?? raw['playUrl'];
      return u == null ? '' : '$u';
    }
    return '';
  }

  Future<void> _playChapter(int index) async {
    if (_source == null || index < 0 || index >= _chapters.length) return;
    final source = _source!;
    final chapter = _chapters[index];
    final chapterUrl = _chapterUrl(chapter);
    final chapterTitle = _chapterTitle(chapter);
    if (chapterUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这一集没有播放地址')),
      );
      return;
    }
    // 视频：走视频播放页（book/chapter/lineId 参数，main.dart 的路由
    // 加载器解析成播放地址）。
    if (source.isVideo) {
      final pos = _positions[chapterUrl] ?? 0;
      try {
        await ref.read(libraryRepositoryProvider).saveProgress(
              bookId: _bookKey,
              chapterUrl: chapterUrl,
              positionMs: pos,
              durationMs: 0,
              isFinished: false,
            );
      } catch (_) {}
      if (!mounted) return;
      context.push(
        '/video-player?book=${Uri.encodeComponent(_bookKey)}'
        '&chapter=$index&lineId=${Uri.encodeComponent(_lineId ?? '')}',
      );
      setState(() => _playingIndex = index);
      return;
    }
    // 听书：经播放器组播。先把解析回调交给 handler，播完自动下一集
    // 时 handler 用它现解析，不用页面一直活着。
    final handler = ref.read(audioHandlerProvider);
    handler.onResolveChapter = (i) => _resolveChapter(i);
    handler.chapterUrls =
        List<String>.filled(_chapters.length, '');
    final urls = handler.chapterUrls;
    if (urls != null) {
      for (final entry in _resolvedUrls.entries) {
        if (entry.key < urls.length) {
          urls[entry.key] = entry.value;
        }
      }
    }
    try {
      await handler.setPluginBook(
        bookKey: _bookKey,
        sourceId: source.id,
        bookUrl: widget.bookUrl,
        title: widget.title,
        coverUrl: widget.coverUrl,
        author: widget.author,
        chapters: _chapters,
        initialIndex: index,
      );
      await handler.playPluginChapter(index);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('播放出错了：$e')),
      );
      return;
    }
    // 存断点（位置 0 起播时先记一次，播放中 handler 每 5 秒接着存）。
    try {
      final repo = ref.read(libraryRepositoryProvider);
      final pos = _positions[chapterUrl] ?? 0;
      await repo.saveProgress(
        bookId: _bookKey,
        chapterUrl: chapterUrl,
        positionMs: pos,
        durationMs: 0,
        isFinished: false,
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() => _playingIndex = index);
    // 回到正在播的播放页（已经在播放页就不重复推）。
    if (GoRouter.of(context).location != '/player') {
      context.push('/player');
    }
  }

  Future<void> _toggleFavorite() async {
    final repo = ref.read(libraryRepositoryProvider);
    try {
      if (_isFavorite) {
        await repo.removeFavorite(_bookKey);
      } else {
        await repo.addFavorite(_bookKey);
      }
      if (!mounted) return;
      setState(() => _isFavorite = !_isFavorite);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('收藏失败：$e')),
      );
    }
  }

  Future<void> _openLogin() async {
    final source = _source;
    if (source == null) return;
    try {
      final engine = engineForSource(ref, source);
      await engine.attach(source);
      final info = await engine.loginInfo();
      final url = info == null
          ? null
          : '${info['loginUrl'] ?? info['url'] ?? ''}';
      if (url == null || url.isEmpty) return;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LoginWebPage(url: url)),
      );
      await _loadLogin(source);
    } catch (_) {}
  }

  void _searchInOtherSources() {
    // 去掉标题 [...] 前缀，按 | / （ / ( 切。
    var title = widget.title;
    title = title.replaceAll(RegExp(r'^\[[^\]]*\]'), '').trim();
    for (final sep in ['|', '｜', '（', '(']) {
      if (title.contains(sep)) {
        title = title.split(sep).first.trim();
        break;
      }
    }
    context.push(
      '/search?type=audio&keyword=${Uri.encodeComponent(title)}',
    );
  }

  Future<void> _editSkip() async {
    final repo = ref.read(libraryRepositoryProvider);
    var intro = 0;
    var outro = 0;
    try {
      intro = _asInt(await repo.getInt('skip_intro:$_bookKey'));
      outro = _asInt(await repo.getInt('skip_outro:$_bookKey'));
    } catch (_) {}
    final introCtrl = TextEditingController(text: '$intro');
    final outroCtrl = TextEditingController(text: '$outro');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('单书跳过片头片尾'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: introCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '跳过片头（秒）'),
            ),
            TextField(
              controller: outroCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '跳过片尾（秒）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await repo.setInt(
          'skip_intro:$_bookKey', int.tryParse(introCtrl.text) ?? 0);
      await repo.setInt(
          'skip_outro:$_bookKey', int.tryParse(outroCtrl.text) ?? 0);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final title = '${_detail['title'] ?? widget.title}';
    final author = '${_detail['author'] ?? _detail['artist'] ?? widget.author ?? ''}';
    final intro = '${_detail['intro'] ?? _detail['description'] ?? widget.intro ?? ''}';
    final cover = '${_detail['coverUrl'] ?? _detail['cover'] ?? widget.coverUrl ?? ''}';
    final visible = _visibleChapters;
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: 200,
                  pinned: true,
                  flexibleSpace: FlexibleSpaceBar(
                    title: Text(title, maxLines: 1),
                    background: cover.isEmpty
                        ? Container(color: context.palette.surfaceAlt)
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                cover,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                    color: context.palette.surfaceAlt),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.1),
                                      Colors.black.withOpacity(0.55),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  actions: [
                    IconButton(
                      icon: Icon(
                        _isFavorite ? Icons.favorite : Icons.favorite_outline,
                      ),
                      tooltip: _isFavorite ? '取消收藏' : '加入收藏',
                      onPressed: _toggleFavorite,
                    ),
                  ],
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CoverImage(
                              url: cover.isEmpty ? null : cover,
                              title: title,
                              width: 90,
                              height: 120,
                              radius: 12,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (author.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(author,
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: context.subtleColor)),
                                  ],
                                  if (source != null) ...[
                                    const SizedBox(height: 4),
                                    Text(source.name,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary)),
                                  ],
                                  Text(
                                    '共 ${_chapters.length} 集',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: context.subtleColor),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (intro.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: () => setState(
                                () => _introExpanded = !_introExpanded),
                            child: Text(
                              intro,
                              maxLines: _introExpanded ? null : 2,
                              overflow: _introExpanded
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, height: 1.5),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (_needLogin)
                          _NeedLoginBar(onLogin: _openLogin),
                        if (_error != null) ...[
                          Text(_error!,
                              style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      Theme.of(context).colorScheme.error)),
                          const SizedBox(height: 8),
                        ],
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: ElevatedButton.icon(
                            onPressed: _chapters.isEmpty
                                ? null
                                : () => _playResume(),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(_positions.isEmpty
                                ? '播放'
                                : '继续播放'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _toggleFavorite,
                              icon: Icon(
                                _isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_outline,
                                size: 16,
                              ),
                              label:
                                  Text(_isFavorite ? '已收藏' : '加入收藏'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  setState(() => _reversed = !_reversed),
                              icon: const Icon(Icons.swap_vert, size: 16),
                              label:
                                  Text(_reversed ? '正序' : '倒序'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _searchInOtherSources,
                              icon: const Icon(Icons.search, size: 16),
                              label: const Text('在其它源中搜索'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _editSkip,
                              icon: const Icon(Icons.fast_forward, size: 16),
                              label: const Text('跳过片头片尾'),
                            ),
                          ],
                        ),
                        if (_lines.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('线路',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          _LineSelector(
                            lines: _lines,
                            selectedId: _lineId,
                            onSelected: (id) async {
                              setState(() => _lineId = id);
                              await ref.read(sharedPrefsProvider).setString(
                                  'selected_line_${Uri.encodeComponent(_bookKey)}',
                                  id);
                            },
                          ),
                        ],
                        if (_voices.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('音色',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          _VoiceSelector(
                            voices: _voices,
                            selectedId: _voiceId,
                            onSelected: (id) =>
                                setState(() => _voiceId = id),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Text('章节',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                            const Spacer(),
                            if (_loadingFull && _fullProgress != null)
                              Text(_fullProgress!,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: context.subtleColor)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _chapterFilterController,
                          decoration: const InputDecoration(
                            hintText: '筛选章节',
                            prefixIcon: Icon(Icons.search, size: 18),
                            isDense: true,
                          ),
                          onChanged: (v) =>
                              setState(() => _chapterFilter = v.trim()),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _chapters.isEmpty
                            ? '还没有章节：这个 JAR 插件没有返回目录（插件详情接口未走通，先点「重试」，仍为空请把插件发我）'
                            : '没有匹配的章节。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.subtleColor),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        if (i == visible.length) {
                          return bottomBarSpace(context);
                        }
                        final c = visible[i];
                        final realIndex = _chapters.indexOf(c);
                        final url = _chapterUrl(c);
                        final pos = _positions[url];
                        final fin = _finished[url] ?? false;
                        final playing = realIndex == _playingIndex;
                        final isFree = c['isFree'] != false;
                        return _ChapterRow(
                          title: _chapterTitle(c),
                          index: realIndex,
                          playing: playing,
                          free: isFree,
                          positionMs: pos,
                          finished: fin,
                          onTap: isFree
                              ? () => _playChapter(realIndex)
                              : null,
                        );
                      },
                      childCount: visible.length + 1,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _NeedLoginBar extends StatelessWidget {
  final VoidCallback onLogin;

  const _NeedLoginBar({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text('这个源需要登录才能看完整内容。', style: TextStyle(fontSize: 13)),
          ),
          TextButton(onPressed: onLogin, child: const Text('去登录')),
        ],
      ),
    );
  }
}

/// 线路选择器：横向一排，选中态高亮；没线就隐藏整个控件，不做弹窗。
class _LineSelector extends StatelessWidget {
  final List<Map<String, dynamic>> lines;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const _LineSelector({
    required this.lines,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: lines.length,
        itemBuilder: (_, i) {
          final line = lines[i];
          final id = '${line['id'] ?? line['name'] ?? ''}';
          var name = '${line['name'] ?? line['id'] ?? ''}'.trim();
          if (name.isEmpty || name == 'null') name = '线路 ${i + 1}';
          final selected = selectedId == id || (selectedId == null && i == 0);
          final primary = Theme.of(context).colorScheme.primary;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(name),
              selected: selected,
              selectedColor: primary.withOpacity(0.2),
              labelStyle: TextStyle(
                color: selected
                    ? primary
                    : Theme.of(context).textTheme.bodyMedium?.color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
              onSelected: (_) => onSelected(id),
            ),
          );
        },
      ),
    );
  }
}

class _VoiceSelector extends StatelessWidget {
  final List<Map<String, dynamic>> voices;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  const _VoiceSelector({
    required this.voices,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: voices.length,
        itemBuilder: (_, i) {
          final v = voices[i];
          final id = '${v['id'] ?? v['name'] ?? ''}';
          var name = '${v['name'] ?? v['id'] ?? ''}'.trim();
          if (name.isEmpty || name == 'null') name = '音色 ${i + 1}';
          final selected = selectedId == id || (selectedId == null && i == 0);
          final primary = Theme.of(context).colorScheme.primary;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(name),
              selected: selected,
              selectedColor: primary.withOpacity(0.2),
              labelStyle: TextStyle(
                color: selected
                    ? primary
                    : Theme.of(context).textTheme.bodyMedium?.color,
              ),
              onSelected: (_) => onSelected(id),
            ),
          );
        },
      ),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  final String title;
  final int index;
  final bool playing;
  final bool free;
  final int? positionMs;
  final bool finished;
  final VoidCallback? onTap;

  const _ChapterRow({
    required this.title,
    required this.index,
    required this.playing,
    required this.free,
    required this.positionMs,
    required this.finished,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final color = playing
        ? primary
        : Theme.of(context).textTheme.bodyMedium?.color;
    return SoftCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      radius: 16,
      onTap: onTap,
      child: Row(
        children: [
          if (playing)
            Icon(Icons.play_arrow_rounded, size: 18, color: primary)
          else
            SizedBox(
              width: 18,
              child: Text(
                '${index + 1}',
                style: TextStyle(fontSize: 11, color: context.subtleColor),
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: color,
                fontWeight:
                    playing ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (!free)
            const Icon(Icons.lock_outline, size: 14)
          else if (finished)
            Text('已听完',
                style: TextStyle(fontSize: 11, color: context.subtleColor))
          else if (positionMs != null && positionMs! > 0)
            Text('听至 ${formatDuration(positionMs!)}',
                style: TextStyle(fontSize: 11, color: primary)),
        ],
      ),
    );
  }
}
