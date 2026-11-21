import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/database/library_repository.dart';
import '../../core/di/providers.dart';
import '../../core/log/app_logger.dart';
import '../../core/theme/app_theme.dart';
import '../../plugins/data/plugin_providers.dart';
import '../../plugins/model/plugin_source.dart';
import '../../plugins/presentation/source_book_page.dart';
import '../../shared/widgets/soft_ui.dart';

/// 聚合搜索页（听书 + 视频共用，学随身听书 / Legado / CloudStream）。
///
/// - 每源独立任务、回来一个显示一个：不用 Future.wait 等整批；单源超时 20 秒只坏自己。
/// - 进度文案：“正在搜索… 已出 X 个源的结果 / 共 Y 个源”，搜完“共 X 条，来自 Y 个源，Z 个源失败”。
/// - “停止搜索”按钮；新搜索自动取消旧搜索（代次守卫）。
/// - 0 结果也要出验证按钮；验证页直接出结果（解析到本次关键词的结果就展示，不用重搜）。
/// - 同一本书合并成一行（同名同作者 addOrigin），行上标“来自 N 个源”。
/// - 翻页按源记 totalPage，到底显示“到底了”，“加载更多”到底后不再显示。
/// - 输入停 500ms 自动搜；历史 20 条、单条可删，失败/0 结果的词不进历史。
/// - 超时单独标“这个源超时了”。
/// - 搜索框/听书视频切换/清空/搜索按钮四件全接线；切换搜框里正在打的字；
///   清空作废旧搜索代次，正在跑的搜索不许回填已清空的结果。
/// - 热门搜索：源没给就不显示，“源没给”和“给了但解析丢了”区分记日志。
/// - 失败的源有重试与“去验证”，“去验证”对所有被验证拦截的源开放。
///
/// 依赖（引擎组 E / 界面组 U 提供）：sourceListProvider、engineForSource、
/// SourceBookPage。引擎 search 返回 {books, totalPage}，totalPage 不许丢。
class SourceSearchPage extends ConsumerStatefulWidget {
  final String type; // audio | video
  final String? initialSourceId;

  const SourceSearchPage({
    super.key,
    required this.type,
    this.initialSourceId,
  });

  @override
  ConsumerState<SourceSearchPage> createState() => _SearchPageState();
}

enum _SrcStatus {
  waiting,
  loading,
  done,
  empty,
  failed,
  needsVerification,
  timeout,
}

class _SrcState {
  final PluginSource source;
  _SrcStatus status;
  String? error;
  List<Map<String, dynamic>> books;
  int page;
  int totalPage; // 0 = 源没给总页数
  String? verifyUrl;
  int verifyDelayMs;
  int verifyAttempts;
  String? loadMoreError;

  _SrcState(this.source)
      : status = _SrcStatus.waiting,
        books = <Map<String, dynamic>>[],
        page = 0,
        totalPage = 0,
        verifyDelayMs = 0,
        verifyAttempts = 0;

  bool get hasMore {
    if (books.isEmpty) return false;
    if (totalPage <= 0) return true;
    return page < totalPage;
  }
}

class _Origin {
  final PluginSource source;
  final Map<String, dynamic> book;
  _Origin(this.source, this.book);
}

class _MergedBook {
  final String title;
  final String author;
  final String cover;
  final String intro;
  final String kind;
  final List<_Origin> origins;
  _MergedBook({
    required this.title,
    required this.author,
    required this.cover,
    required this.intro,
    required this.kind,
    required this.origins,
  });
}

class _SearchPageState extends ConsumerState<SourceSearchPage> {
  static const String _historyKey = 'search_history';
  static const String _allKey = '__all__';

  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  /// 搜索建议：300ms 防抖后出的下拉（热门词 + 历史里含输入词的）。
  Timer? _suggestDebounce;
  List<String> _suggestions = <String>[];
  final _focusNode = FocusNode();

  String _type = AppConstants.typeAudio;
  String _sourceId = _allKey;
  String _keyword = '';
  bool _searched = false;
  bool _searching = false;
  bool _loadingMore = false;

  /// 代次：新搜索/清空/停止都会加 1，旧搜索回来的结果一律丢掉。
  int _gen = 0;

  List<_SrcState> _states = <_SrcState>[];
  List<_MergedBook> _merged = <_MergedBook>[];
  List<String> _history = <String>[];
  List<String> _hotWords = <String>[];
  bool _historySavedForKeyword = false;

  /// 每源“查看更多”展开状态（源 id 集合）
  final Set<String> _expanded = <String>{};

  /// 并发调度：正在跑的任务数 + 排队的源
  int _running = 0;
  final List<_SrcState> _queue = <_SrcState>[];

  @override
  void initState() {
    super.initState();
    _type = widget.type;
    if (widget.initialSourceId != null && widget.initialSourceId!.isNotEmpty) {
      _sourceId = widget.initialSourceId!;
    }
    _loadHistory();
    _focusNode.addListener(_onFocusChanged);
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHot());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _suggestDebounce?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 输入框失焦就收起建议下拉（搜完自动失焦，下拉跟着收）。
  void _onFocusChanged() {
    if (!_focusNode.hasFocus && _suggestions.isNotEmpty) {
      setState(() => _suggestions = <String>[]);
    }
  }

  // ------------------------------------------------------------ 基础数据

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_historyKey) ?? <String>[];
    if (!mounted) return;
    setState(() {
      _history = list;
      if (_history.isNotEmpty && _ctrl.text.isEmpty) {
        _ctrl.text = _history.first;
      }
    });
  }

  Future<void> _saveHistory(String kw) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [..._history];
    list.remove(kw);
    list.insert(0, kw);
    final trimmed = list.take(20).toList();
    await prefs.setStringList(_historyKey, trimmed);
    if (mounted) setState(() => _history = trimmed);
  }

  Future<void> _deleteHistoryOne(String kw) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [..._history]..remove(kw);
    await prefs.setStringList(_historyKey, list);
    if (mounted) setState(() => _history = list);
  }

  Future<void> _clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    if (mounted) setState(() => _history = []);
  }

  List<PluginSource> _sources() {
    // sourceListProvider 是 FutureProvider，读到的是 AsyncValue，
    // 还没加载完就先按空列表算（搜索页不阻塞等源）。
    final all =
        ref.read(sourceListProvider).valueOrNull ?? const <PluginSource>[];
    return all.where((s) => s.type == _type && s.enabled).toList();
  }

  Future<int> _settingInt(String key, int def) async {
    final repo = ref.read(libraryRepositoryProvider);
    return await repo.getInt(key) ?? def;
  }

  Future<bool> _settingBool(String key, bool def) async {
    final repo = ref.read(libraryRepositoryProvider);
    return await repo.getBool(key) ?? def;
  }

  List<PluginSource> _targets(List<PluginSource> sources) {
    if (!_isAll) {
      final hit = sources.where((s) => s.id == _sourceId).toList();
      return hit.isEmpty ? sources : hit;
    }
    return sources;
  }

  bool get _isAll => _sourceId == _allKey;

  // ------------------------------------------------------------ 热门搜索

  /// 热门搜索：从当前源拿，没有就不显示（不自己编）。
  /// “源没给”和“给了但解析丢了”区分记日志，不静默吞掉。
  Future<void> _loadHot() async {
    final sources = _sources();
    if (sources.isEmpty) return;
    PluginSource? target;
    if (_isAll) {
      target = sources.first;
    } else {
      final hit = sources.where((s) => s.id == _sourceId).toList();
      target = hit.isEmpty ? sources.first : hit.first;
    }
    dynamic raw;
    var provided = false;
    try {
      final engine = engineForSource(ref, target);
      await engine.attach(target);
      try {
        raw = await engine.invoke('hot', params: <String, dynamic>{});
        provided = true;
      } catch (_) {
        raw = await engine.invoke('hotSearch', params: <String, dynamic>{});
        provided = true;
      }
    } catch (_) {
      if (!provided) {
        appLogger.info('热门搜索：源没提供热门接口', detail: target.name);
      }
      return;
    }
    final words = <String>[];
    final list = raw is List
        ? raw
        : (raw is Map
            ? (raw['list'] ?? raw['data'] ?? raw['hot'])
            : null);
    if (list is List) {
      for (final e in list) {
        final w = e is Map
            ? '${e['name'] ?? e['title'] ?? e['keyword'] ?? ''}'
            : '$e';
        if (w.trim().isNotEmpty) words.add(w.trim());
      }
    }
    if (words.isEmpty) {
      appLogger.warning('热门搜索解析失败：源给了数据但解析出 0 个词',
          detail: target.name);
      return;
    }
    if (!mounted) return;
    setState(() => _hotWords = words.take(10).toList());
  }

  // ------------------------------------------------------------ 搜索

  void _onTextChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final kw = _ctrl.text.trim();
      if (kw.isEmpty) return;
      if (kw == _keyword && _searched) return;
      _search(kw);
    });
    // 搜索建议（学 CloudStream：300ms 防抖、少于 2 个字不显示、可关默认开）：
    // 建议只来自热门词 + 搜索历史，不调第三方接口、不编词。
    _suggestDebounce?.cancel();
    final q = v.trim();
    if (!ref.read(searchSuggestionsProvider) || q.length < 2) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = <String>[]);
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _updateSuggestions(_ctrl.text.trim());
    });
  }

  /// 按当前输入筛建议：热门词在前、历史在后，含输入词的才进下拉，
  /// 去重、去空，最多 6 条；热门还没回来就只用历史。
  void _updateSuggestions(String q) {
    if (q.length < 2 || !ref.read(searchSuggestionsProvider)) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = <String>[]);
      return;
    }
    final lower = q.toLowerCase();
    final out = <String>[];
    void add(String w) {
      final t = w.trim();
      if (t.isEmpty || t.toLowerCase() == lower) return;
      if (!t.toLowerCase().contains(lower)) return;
      if (out.contains(t)) return;
      out.add(t);
    }

    for (final w in _hotWords) add(w);
    for (final h in _history) add(h);
    if (!mounted) return;
    setState(() => _suggestions = out.take(6).toList());
  }

  void _search(String rawKeyword) {
    final kw = rawKeyword.trim();
    if (kw.isEmpty) return;
    FocusScope.of(context).unfocus();
    final gen = ++_gen;
    final sources = _targets(_sources());
    setState(() {
      _keyword = kw;
      _searched = true;
      _searching = true;
      _historySavedForKeyword = false;
      _suggestions = <String>[];
      _merged = <_MergedBook>[];
      _states = sources.map((s) => _SrcState(s)).toList();
      _queue
        ..clear()
        ..addAll(_states);
      _running = 0;
    });
    if (sources.isEmpty) {
      setState(() => _searching = false);
      return;
    }
    _pump(gen);
  }

  /// 并发泵：同时最多跑 concurrency 个源任务，回来一个显示一个，不等整批。
  void _pump(int gen) async {
    final concurrency =
        await _settingInt(AppConstants.keySearchConcurrency, 6);
    final limit = concurrency.clamp(1, 32);
    while (_running < limit && _queue.isNotEmpty && gen == _gen) {
      final state = _queue.removeAt(0);
      _running++;
      _searchOne(state, gen, page: 1).whenComplete(() {
        _running--;
        if (gen == _gen && mounted) _pump(gen);
      });
    }
    if (_queue.isEmpty && _running == 0 && gen == _gen && mounted) {
      setState(() => _searching = false);
    }
  }

  /// 搜一个源的一页：超时只坏自己；失败/0 结果都试着拿验证地址。
  Future<void> _searchOne(_SrcState state, int gen,
      {required int page}) async {
    if (gen != _gen) return;
    final kw = _keyword;
    final timeoutSeconds = await _settingInt(
        AppConstants.keySearchTimeoutSeconds, 20);
    if (gen != _gen || !mounted) return;
    setState(() {
      state.status = _SrcStatus.loading;
      state.loadMoreError = null;
    });
    try {
      final engine = engineForSource(ref, state.source);
      await engine.attach(state.source);
      final raw = await engine
          .invoke('search', params: <String, dynamic>{
            'keyword': kw,
            'page': page,
          })
          .timeout(Duration(seconds: timeoutSeconds));
      if (gen != _gen || !mounted) return;
      var books = <Map<String, dynamic>>[];
      var totalPage = 0;
      if (raw is Map) {
        final list = raw['books'];
        if (list is List) {
          books = list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        totalPage = (raw['totalPage'] as num?)?.toInt() ?? 0;
      } else if (raw is List) {
        books = raw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      // 精确搜索（默认开）：只留书名或作者含关键词的
      if (await _settingBool(
          AppConstants.keyExactSearch, AppConstants.defaultExactSearch)) {
        final kwLower = kw.toLowerCase();
        books = books.where((e) {
          final name = '${e['name'] ?? e['title'] ?? ''}'.toLowerCase();
          final author = '${e['author'] ?? ''}'.toLowerCase();
          return name.contains(kwLower) || author.contains(kwLower);
        }).toList();
      }
      if (gen != _gen || !mounted) return;
      setState(() {
        if (page == 1) {
          state.books = books;
        } else {
          state.books = [...state.books, ...books];
        }
        state.page = page;
        state.totalPage = totalPage;
        state.status = books.isEmpty && page == 1
            ? _SrcStatus.empty
            : _SrcStatus.done;
        if (page > 1 && books.isEmpty) {
          // 这一页空了：到底了，不再翻
          state.totalPage = page - 1;
        }
      });
      if (books.isNotEmpty) {
        await _maybeSaveHistory();
        if (gen == _gen && mounted) {
          setState(() => _rebuildMerged());
        }
      } else if (page == 1) {
        // 0 结果也要试验证：源被验证拦截时直接标“需验证”
        await _tryAttachVerification(state, kw, gen);
      }
    } on TimeoutException {
      if (gen != _gen || !mounted) return;
      setState(() {
        state.status = _SrcStatus.timeout;
        state.error = '这个源超时了';
      });
    } catch (e) {
      if (gen != _gen || !mounted) return;
      final msg = _humanSearchError(e);
      final attached = await _tryAttachVerification(state, kw, gen);
      if (gen != _gen || !mounted) return;
      if (!attached) {
        setState(() {
          state.status = _SrcStatus.failed;
          state.error = msg;
        });
      }
    } finally {
      if (gen == _gen && mounted) {
        _refreshSearchingState(gen);
      }
    }
  }

  /// 0 结果 / 报错时都问引擎拿验证地址：拿到了就标“需验证”，对所有源开放。
  Future<bool> _tryAttachVerification(
      _SrcState state, String kw, int gen) async {
    try {
      final engine = engineForSource(ref, state.source);
      final info = await engine.verificationInfo(kw);
      final url = info == null ? null : '${info['url'] ?? ''}';
      if (url == null || url.isEmpty) return false;
      if (gen != _gen || !mounted) return false;
      setState(() {
        state.status = _SrcStatus.needsVerification;
        state.verifyUrl = url;
        state.verifyDelayMs =
            (info!['delayMs'] as num?)?.toInt() ?? 0;
        state.error = '这个源需要验证';
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  void _refreshSearchingState(int gen) {
    if (gen != _gen || !mounted) return;
    final anyLoading =
        _states.any((s) => s.status == _SrcStatus.loading);
    final queueEmpty = _queue.isEmpty && _running == 0;
    if (!anyLoading && queueEmpty && _searching) {
      setState(() => _searching = false);
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _maybeSaveHistory() async {
    if (_historySavedForKeyword) return;
    _historySavedForKeyword = true;
    // 只有搜出结果的词才进历史；失败/0 结果的词不进
    await _saveHistory(_keyword);
  }

  String _humanSearchError(Object e) {
    final msg = '$e';
    if (msg.contains('SocketException') ||
        msg.contains('TimeoutException') ||
        msg.contains('Failed host lookup')) {
      return '连不上这个源，检查网络后重试';
    }
    if (msg.contains('403') || msg.contains('429')) {
      return '这个源拒绝了请求，可能要验证';
    }
    final m = RegExp(r'Exception: (.+)').firstMatch(msg);
    if (m != null) return m.group(1) ?? '搜索失败';
    return '搜索失败';
  }

  // ------------------------------------------------------------ 合并

  void _rebuildMerged() {
    final byKey = <String, _MergedBook>{};
    for (final state in _states) {
      for (final book in state.books) {
        final title = '${book['name'] ?? book['title'] ?? ''}'.trim();
        if (title.isEmpty) continue;
        final author = '${book['author'] ?? ''}'.trim();
        final key = '${title.toLowerCase()}|$author'.toLowerCase();
        final cover = '${book['cover'] ?? book['coverUrl'] ?? ''}';
        final intro = '${book['intro'] ?? book['description'] ?? ''}';
        final kind = '${book['kind'] ?? book['category'] ?? ''}';
        final hit = byKey[key];
        if (hit == null) {
          byKey[key] = _MergedBook(
            title: title,
            author: author,
            cover: cover,
            intro: intro,
            kind: kind,
            origins: [_Origin(state.source, book)],
          );
        } else {
          if (!hit.origins.any((o) => o.source.id == state.source.id)) {
            hit.origins.add(_Origin(state.source, book));
          }
        }
      }
    }
    final list = byKey.values.toList();
    final kwLower = _keyword.toLowerCase();
    int tier(_MergedBook b) {
      if (b.title.toLowerCase() == kwLower ||
          b.author.toLowerCase() == kwLower) return 0;
      if (b.kind.toLowerCase().contains(kwLower)) return 1;
      if (b.title.toLowerCase().contains(kwLower) ||
          b.author.toLowerCase().contains(kwLower)) return 2;
      return 3;
    }

    list.sort((a, b) {
      final t = tier(a).compareTo(tier(b));
      if (t != 0) return t;
      return b.origins.length.compareTo(a.origins.length);
    });
    _merged = list;
  }

  // ------------------------------------------------------------ 停止 / 切换 / 清空

  void _stopSearch() {
    _gen++;
    _queue.clear();
    if (mounted) {
      setState(() => _searching = false);
    }
  }

  void _toggleType() {
    final currentText = _ctrl.text;
    setState(() {
      _type = _type == AppConstants.typeAudio
          ? AppConstants.typeVideo
          : AppConstants.typeAudio;
      _sourceId = _allKey;
      _hotWords = <String>[];
    });
    _loadHot();
    // 切换要搜框里正在打的字，不只认已提交过的词
    final kw = currentText.trim();
    if (kw.isNotEmpty) _search(kw);
  }

  void _clearSearch() {
    // 清空作废旧搜索代次：正在跑的搜索不许回填已清空的结果
    _gen++;
    _queue.clear();
    _suggestDebounce?.cancel();
    _ctrl.clear();
    setState(() {
      _keyword = '';
      _searched = false;
      _searching = false;
      _suggestions = <String>[];
      _states = <_SrcState>[];
      _merged = <_MergedBook>[];
    });
  }

  void _selectSource(String id) {
    setState(() {
      _sourceId = id;
      _hotWords = <String>[];
    });
    _loadHot();
    if (_keyword.isNotEmpty) _search(_keyword);
  }

  // ------------------------------------------------------------ 重试 / 验证 / 翻页

  Future<void> _retryGroup(_SrcState state) async {
    final gen = _gen;
    state.status = _SrcStatus.loading;
    state.error = null;
    setState(() {});
    await _searchOne(state, gen, page: 1);
  }

  Future<void> _verifyAndRetry(_SrcState state) async {
    if (state.verifyUrl == null || state.verifyUrl!.isEmpty) return;
    if (state.verifyAttempts >= 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已经验证过 2 次了，换个源试试')),
      );
      return;
    }
    state.verifyAttempts++;
    final engine = engineForSource(ref, state.source);
    final result = await Navigator.of(context).push<_VerifyResult>(
      MaterialPageRoute(
        builder: (_) => _VerificationPage(
          url: state.verifyUrl!,
          keyword: _keyword,
          engine: engine,
          source: state.source,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null && result.books.isNotEmpty) {
      // 验证页直接出结果：不用关掉再重搜一次
      setState(() {
        state.books = result.books;
        state.page = 1;
        state.totalPage = result.totalPage;
        state.status = _SrcStatus.done;
        state.verifyUrl = null;
        _rebuildMerged();
      });
      await _maybeSaveHistory();
      return;
    }
    // 验证页没直接出结果：按 delay 等一会儿再重搜一次
    if (state.verifyDelayMs > 0) {
      await Future<void>.delayed(
          Duration(milliseconds: state.verifyDelayMs));
    }
    await _retryGroup(state);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _searching) return;
    if (!_searched || _keyword.isEmpty) return;
    final more = _states.where((s) => s.hasMore).toList();
    if (more.isEmpty) return;
    final gen = _gen;
    setState(() => _loadingMore = true);
    try {
      for (final state in more) {
        final before = state.books.length;
        await _searchOne(state, gen, page: state.page + 1);
        if (gen != _gen || !mounted) return;
        if (state.status == _SrcStatus.failed ||
            state.status == _SrcStatus.timeout) {
          // 翻页失败要在页面上看得到提示，不要静默吃掉
          setState(() {
            state.loadMoreError = state.error ?? '翻页失败，点一下重试';
          });
        } else if (state.books.length == before) {
          setState(() => state.totalPage = state.page);
        }
      }
      if (gen == _gen && mounted) setState(() => _rebuildMerged());
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  bool get _allDone {
    if (_states.isEmpty) return false;
    return _states.every((s) => !s.hasMore);
  }

  // ------------------------------------------------------------ 界面

  @override
  Widget build(BuildContext context) {
    final sources = _sources();
    final doneCount =
        _states.where((s) => s.status != _SrcStatus.loading && s.status != _SrcStatus.waiting).length;
    final failedCount = _states
        .where((s) =>
            s.status == _SrcStatus.failed || s.status == _SrcStatus.timeout)
        .length;
    final okSources =
        _states.where((s) => s.books.isNotEmpty).map((s) => s.source.id).toSet().length;
    final primary = Theme.of(context).colorScheme.primary;
    final textColor = Theme.of(context).textTheme.bodyMedium?.color;
    return Scaffold(
      body: GradientBackdrop(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 16, 4),
                child: Row(
                  children: [
                    CircleIconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: primary.withOpacity(0.12),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            Icon(Icons.search_rounded,
                                size: 20, color: context.subtleColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _ctrl,
                                focusNode: _focusNode,
                                autofocus: _history.isEmpty,
                                textInputAction: TextInputAction.search,
                                style: TextStyle(
                                    color: textColor, fontSize: 15),
                                cursorColor: primary,
                                decoration: InputDecoration(
                                  hintText: '搜索有声书、作者或播讲员…',
                                  hintStyle:
                                      TextStyle(color: context.subtleColor, fontSize: 14),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onChanged: _onTextChanged,
                                onSubmitted: (v) => _search(v),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                  _type == AppConstants.typeAudio
                                      ? Icons.headphones_rounded
                                      : Icons.movie_rounded,
                                  size: 20,
                                  color: primary.withOpacity(0.75)),
                              tooltip: _type == AppConstants.typeAudio ? '切到视频' : '切到听书',
                              onPressed: _toggleType,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleIconButton(
                      icon: Icons.tune_rounded,
                      onTap: () => _search(_ctrl.text),
                    ),
                  ],
                ),
              ),
          _sourceBar(sources),
          if (_suggestions.isNotEmpty && _focusNode.hasFocus)
            _suggestionsView(),
          if (_searching || _searched) _progressBar(doneCount, failedCount, okSources),
          if (_searching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('停止搜索'),
                      onPressed: _stopSearch,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildBody(sources)),
          if (_searched && _merged.isNotEmpty) _loadMoreBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceBar(List<PluginSource> sources) {
    final primary = Theme.of(context).colorScheme.primary;
    final value = _isAll || sources.any((s) => s.id == _sourceId)
        ? _sourceId
        : _allKey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.extension_outlined, size: 18, color: primary),
          const SizedBox(width: 8),
          const Text('源',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: value,
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                // 审计 C 第 17 项：下拉必须写颜色，否则浅色主题下白字看不见
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
                dropdownColor: Theme.of(context).colorScheme.surface,
                items: [
                  const DropdownMenuItem<String>(
                    value: _allKey,
                    child: Text('全部'),
                  ),
                  for (final s in sources)
                    DropdownMenuItem<String>(
                      value: s.id,
                      child: Text(s.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (picked) {
                  if (picked == null) return;
                  _selectSource(picked);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressBar(int doneCount, int failedCount, int okSources) {
    final total = _states.length;
    final text = _searching
        ? '正在搜索… 已出 $doneCount 个源的结果 / 共 $total 个源'
        : '共 ${_merged.length} 条，来自 $okSources 个源'
            '${failedCount > 0 ? '，$failedCount 个源失败' : ''}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontSize: 12.5)),
    );
  }

  Widget _buildBody(List<PluginSource> sources) {
    if (!_searched) return _historyView();
    if (_merged.isEmpty && !_searching) {
      return ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SizedBox(height: 32),
          const Icon(Icons.search_off, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          const Center(child: Text('没有找到相关内容')),
          const SizedBox(height: 24),
          _sourceStatusSection(),
        ],
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _merged.length + 1,
      itemBuilder: (context, i) {
        if (i == _merged.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _sourceStatusSection(),
          );
        }
        return _mergedTile(_merged[i]);
      },
    );
  }

  Widget _mergedTile(_MergedBook book) {
    final first = book.origins.first;
    final url = '${first.book['url'] ?? first.book['bookUrl'] ?? ''}';
    return SoftCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      radius: 18,
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SourceBookPage(
            sourceId: first.source.id,
            bookUrl: url,
            title: book.title,
            coverUrl: book.cover.isEmpty ? null : book.cover,
            author: book.author,
            intro: book.intro,
          ),
        ));
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cover(book.cover, book.title),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  book.author.isEmpty
                      ? '来自 ${book.origins.length} 个源'
                      : '${book.author} · 来自 ${book.origins.length} 个源',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (book.origins.length > 1) ...[
                  const SizedBox(height: 4),
                  Text(
                    book.origins.map((o) => o.source.name).join('、'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: context.subtleColor),
        ],
      ),
    );
  }

  Widget _cover(String url, String title) {
    if (url.isEmpty) {
      return Container(
        width: 52,
        height: 70,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          title.isEmpty ? '书' : title.characters.first,
          style: TextStyle(
            fontSize: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 52,
        height: 70,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 52,
          height: 70,
          color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
          alignment: Alignment.center,
          child: Text(title.isEmpty ? '书' : title.characters.first),
        ),
      ),
    );
  }

  /// 各源状态：搜到 / 空 / 失败 / 需验证 / 超时，每源独立一行。
  Widget _sourceStatusSection() {
    if (_states.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('各源状态',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ..._states.map((s) => _sourceRow(s)),
      ],
    );
  }

  Widget _sourceRow(_SrcState state) {
    final statusText = _statusText(state);
    final statusColor = _statusColor(state);
    final expanded = _expanded.contains(state.source.id);
    final shown =
        expanded ? state.books : state.books.take(10).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              // “这个源搜索失败，点一下重试”这行字本身要点得了
              onTap: (state.status == _SrcStatus.failed ||
                      state.status == _SrcStatus.timeout)
                  ? () => _retryGroup(state)
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(state.source.name,
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(statusText,
                            style: TextStyle(
                                fontSize: 12, color: statusColor)),
                      ],
                    ),
                  ),
                  if (state.status == _SrcStatus.loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  if (state.verifyUrl != null &&
                      (state.status == _SrcStatus.needsVerification ||
                          state.status == _SrcStatus.failed ||
                          state.status == _SrcStatus.empty))
                    OutlinedButton(
                      onPressed: () => _verifyAndRetry(state),
                      child: const Text('去验证'),
                    ),
                  if (state.status == _SrcStatus.failed ||
                      state.status == _SrcStatus.timeout)
                    TextButton(
                      onPressed: () => _retryGroup(state),
                      child: const Text('重试'),
                    ),
                ],
              ),
            ),
            if (state.loadMoreError != null) ...[
              const SizedBox(height: 4),
              InkWell(
                onTap: () => _loadMore(),
                child: Text(state.loadMoreError!,
                    style: const TextStyle(fontSize: 12, color: Colors.red)),
              ),
            ],
            if (shown.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...shown.map((b) => Padding(
                    padding: const EdgeInsets.only(left: 4, top: 2),
                    child: Text(
                      '· ${b['name'] ?? b['title'] ?? ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  )),
              if (state.books.length > 10)
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (expanded) {
                        _expanded.remove(state.source.id);
                      } else {
                        _expanded.add(state.source.id);
                      }
                    });
                  },
                  child: Text(expanded
                      ? '收起'
                      : '查看更多（还有 ${state.books.length - 10} 条）'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _statusText(_SrcState state) {
    switch (state.status) {
      case _SrcStatus.waiting:
        return '等待搜索';
      case _SrcStatus.loading:
        return '正在搜索…';
      case _SrcStatus.done:
        return '搜到 ${state.books.length} 条'
            '${state.hasMore ? '（还有下一页）' : '（已到底）'}';
      case _SrcStatus.empty:
        return state.verifyUrl != null ? '这个源没有结果，需要验证' : '这个源没有结果';
      case _SrcStatus.failed:
        return '这个源搜索失败，点一下重试'
            '${state.error == null ? '' : '（${state.error}）'}';
      case _SrcStatus.timeout:
        return '这个源超时了，点一下重试';
      case _SrcStatus.needsVerification:
        return '这个源需要验证，点“去验证”';
    }
  }

  Color _statusColor(_SrcState state) {
    switch (state.status) {
      case _SrcStatus.needsVerification:
        return const Color(0xFFF59E0B);
      case _SrcStatus.failed:
      case _SrcStatus.timeout:
        return Colors.red;
      case _SrcStatus.done:
        return Colors.green;
      default:
        return Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;
    }
  }

  Widget _loadMoreBar() {
    if (_allDone) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        child: const Text('到底了', style: TextStyle(fontSize: 12)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: OutlinedButton(
        onPressed: _loadingMore ? null : _loadMore,
        child: Text(_loadingMore ? '正在加载…' : '加载更多'),
      ),
    );
  }

  /// 搜索建议下拉：点一条直接搜（填进搜索框并提交）。
  Widget _suggestionsView() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _suggestions
            .map((s) => ListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12),
                  leading: const Icon(Icons.search, size: 18),
                  title: Text(s,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    _ctrl.text = s;
                    _search(s);
                  },
                ))
            .toList(),
      ),
    );
  }

  Widget _historyView() {
    final primary = Theme.of(context).colorScheme.primary;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, size: 18, color: primary),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('最近搜索',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            if (_history.isNotEmpty)
              TextButton.icon(
                onPressed: _clearHistory,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('清空'),
              ),
          ],
        ),
        if (_history.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('输入关键词搜索',
                style: TextStyle(fontSize: 12.5, color: context.subtleColor)),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _history
                .map((h) => GestureDetector(
                      onTap: () {
                        _ctrl.text = h;
                        _search(h);
                      },
                      child: Chip(
                        backgroundColor: Theme.of(context).cardColor,
                        side: BorderSide(color: context.palette.outline),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        label: Text(h, style: const TextStyle(fontSize: 13)),
                        onDeleted: () => _deleteHistoryOne(h),
                        deleteIcon: const Icon(Icons.close, size: 15),
                      ),
                    ))
                .toList(),
          ),
        if (_hotWords.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: primary),
              const SizedBox(width: 6),
              const Text('热门搜索',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _hotWords
                .map((w) => ActionChip(
                      backgroundColor: Theme.of(context).cardColor,
                      side: BorderSide(color: context.palette.outline),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      label: Text(w, style: const TextStyle(fontSize: 13)),
                      onPressed: () {
                        _ctrl.text = w;
                        _search(w);
                      },
                    ))
                .toList(),
          ),
        ],
      ],
    );
  }
}


/// 验证页直接出的结果：解析到本次关键词的书就直接展示，不用重搜。
class _VerifyResult {
  final List<Map<String, dynamic>> books;
  final int totalPage;
  _VerifyResult(this.books, this.totalPage);
}

/// 搜索验证页（WebView 弹窗）：验证页 HTML 里解析到本次关键词的结果就直接返回；
/// 识别不到时由用户手动完成，页面标题不再含“验证”时自动关闭，调用方再重搜一次。
class _VerificationPage extends StatefulWidget {
  final String url;
  final String keyword;
  final dynamic engine;
  final PluginSource source;

  const _VerificationPage({
    required this.url,
    required this.keyword,
    required this.engine,
    required this.source,
  });

  @override
  State<_VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<_VerificationPage> {
  WebViewController? _controller;
  Timer? _pollTimer;
  bool _finished = false;
  String _status = '正在加载验证页…';

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkPage();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  String _decodeJsResult(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is String) return decoded;
    } catch (_) {
      // 不是 JSON 编码的字符串，直接用原串
    }
    return raw;
  }

  /// 试着从当前验证页解析出本次关键词的结果；解析到了就直接返回。
  Future<_VerifyResult?> _tryExtractResults() async {
    final controller = _controller;
    if (controller == null) return null;
    try {
      final htmlRaw = await controller
          .runJavascriptReturningResult('document.documentElement.outerHTML');
      final html = _decodeJsResult(htmlRaw);
      if (html.isEmpty) return null;
      final url = await controller.currentUrl() ?? widget.url;
      final raw = await widget.engine.invoke(
        'searchVerificationResult',
        params: <String, dynamic>{
          'html': html,
          'url': url,
          'keyword': widget.keyword,
        },
      );
      if (raw is Map && raw['verified'] == true) {
        final list = raw['books'];
        final books = <Map<String, dynamic>>[];
        if (list is List) {
          for (final e in list) {
            if (e is Map) books.add(Map<String, dynamic>.from(e));
          }
        }
        if (books.isEmpty) return null;
        final totalPage = (raw['totalPage'] as num?)?.toInt() ?? 1;
        return _VerifyResult(books, totalPage);
      }
      return null;
    } catch (_) {
      // 引擎没实现 searchVerificationResult：走重搜那条路
      return null;
    }
  }

  Future<void> _checkPage() async {
    if (_finished) return;
    final controller = _controller;
    if (controller == null) return;
    try {
      final titleRaw =
          await controller.runJavascriptReturningResult('document.title');
      final title = _decodeJsResult(titleRaw).toLowerCase();
      final result = await _tryExtractResults();
      if (!_finished && result != null) {
        _finish(result);
        return;
      }
      // 标题不再含“验证”类字样：验证过了，关掉让调用方重搜
      const markers = ['验证', 'verify', 'captcha', '机器人', '安全检查', '人机'];
      final stillVerifying =
          markers.any((m) => title.contains(m.toLowerCase()));
      if (!stillVerifying && title.isNotEmpty) {
        if (mounted) {
          setState(() => _status = '验证好像通过了，正在确认…');
        }
        await Future<void>.delayed(const Duration(seconds: 1));
        if (_finished) return;
        final again = await _tryExtractResults();
        _finish(again);
      }
    } catch (_) {
      // JS 还没就绪，等下一次轮询
    }
  }

  void _finish(_VerifyResult? result) {
    if (_finished) return;
    _finished = true;
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('验证'),
        actions: [
          TextButton(
            onPressed: () => _finish(null),
            child: const Text('验证完了，继续搜索',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_status,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: WebView(
              initialUrl: widget.url,
              javascriptMode: JavascriptMode.unrestricted,
              onWebViewCreated: (c) => _controller = c,
              onPageFinished: (_) => _checkPage(),
            ),
          ),
        ],
      ),
    );
  }
}
