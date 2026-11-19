import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/di/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/common.dart';
import '../data/home_feed.dart';
import '../data/plugin_providers.dart';
import '../engine/plugin_engine.dart';
import '../model/plugin_source.dart';
import 'login_web_page.dart';
import 'source_book_page.dart';

/// 一个源的搜索结果
class _Group {
  final PluginSource source;
  final List<Map<String, dynamic>> items;
  final String? error;

  /// 搜索被验证拦截时，点这个地址去过验证
  final String? verificationUrl;

  /// 验证页用的 UA（决定开电脑版还是手机版 WebView）
  final String verificationUa;

  /// 验证完等多久再重搜（毫秒）
  final int verificationDelayMs;

  _Group({
    required this.source,
    required this.items,
    this.error,
    this.verificationUrl,
    this.verificationUa = '',
    this.verificationDelayMs = 0,
  });
}

/// 源搜索：可以选「全部」并发搜所有启用的源，也可以只搜某一个。
class SourceSearchPage extends ConsumerStatefulWidget {
  final String type;

  /// 从首页进来时带上的源，保证和首页选的是同一个
  final String? initialSourceId;

  const SourceSearchPage({
    super.key,
    this.type = AppConstants.typeAudio,
    this.initialSourceId,
  });

  @override
  ConsumerState<SourceSearchPage> createState() => _SourceSearchPageState();
}

class _SourceSearchPageState extends ConsumerState<SourceSearchPage> {
  static const String _allKey = '__all__';
  static const String _historyKey = 'search_history';

  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  String? _sourceId;
  String _type = AppConstants.typeAudio;
  bool _loading = false;
  bool _loadingMore = false;
  bool _searched = false;
  int _page = 1;
  int _pending = 0;
  int _searchGen = 0;
  String? _error;
  String _keyword = '';
  List<_Group> _groups = [];
  final Set<String> _expanded = {};
  List<String> _history = [];
  List<String> _hotWords = [];

  @override
  void initState() {
    super.initState();
    _type = widget.type;
    _sourceId = widget.initialSourceId ?? _allKey;
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
    final prefs = ref.read(sharedPrefsProvider);
    _history = prefs.getStringList(_historyKey) ?? [];
    // 搜索框里显示上次搜过的词
    if (_history.isNotEmpty) _ctrl.text = _history.first;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadHot());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _isAll => _sourceId == null || _sourceId == _allKey;

  List<PluginSource> _sources() {
    final all = ref.watch(sourceListProvider).value ?? const <PluginSource>[];
    return all
        .where((s) => s.type == _type && s.enabled)
        .toList(growable: false);
  }

  List<PluginSource> _targets(List<PluginSource> sources) {
    if (_isAll) {
      // 聚合搜索关了：只搜当前源，不合并所有源
      if (!ref.read(aggregateSearchProvider)) {
        final home = ref.read(activeHomeSourceProvider);
        final hit = home == null
            ? <PluginSource>[]
            : sources.where((s) => s.id == home.id).toList();
        return hit.isEmpty ? sources.take(1).toList() : hit;
      }
      return sources;
    }
    final hit = sources.where((s) => s.id == _sourceId).toList();
    return hit.isEmpty ? sources : hit;
  }

  /// 热门搜索：从当前源拿，没有就不显示（不自己编）
  Future<void> _loadHot() async {
    final sources = _sources();
    if (sources.isEmpty) return;
    PluginSource? target;
    if (_isAll) {
      target = ref.read(activeHomeSourceProvider);
      if (target != null && target.type != _type) target = null;
      target ??= sources.first;
    } else {
      final hit = sources.where((s) => s.id == _sourceId).toList();
      target = hit.isEmpty ? sources.first : hit.first;
    }
    try {
      final engine = engineForSource(ref, target);
      await engine.attach(target);
      dynamic raw;
      try {
        raw = await engine.invoke('hot', params: {});
      } catch (_) {
        raw = await engine.invoke('hotSearch', params: {});
      }
      final words = <String>[];
      final list = raw is List
          ? raw
          : (raw is Map ? (raw['list'] ?? raw['data'] ?? raw['hot']) : null);
      if (list is List) {
        for (final e in list) {
          final w = e is Map
              ? '${e['name'] ?? e['title'] ?? e['keyword'] ?? ''}'
              : '$e';
          if (w.trim().isNotEmpty) words.add(w.trim());
        }
      }
      if (mounted) setState(() => _hotWords = words.take(10).toList());
    } catch (_) {
      // 源没有热门接口就不显示
    }
  }

  /// 切换听书 / 视频：用同一个关键词立刻重搜
  void _toggleType() {
    setState(() {
      _type = _type == AppConstants.typeAudio
          ? AppConstants.typeVideo
          : AppConstants.typeAudio;
      _sourceId = _allKey;
      _hotWords = [];
    });
    _loadHot();
    if (_keyword.isNotEmpty) _search(_keyword);
  }

  void _clearSearch() {
    _ctrl.clear();
    setState(() {
      _keyword = '';
      _searched = false;
      _groups = [];
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: _history.isEmpty,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          cursorColor: Colors.white,
          decoration: const InputDecoration(
            hintText: '搜索书名 / 作者 / 视频名',
            hintStyle: TextStyle(color: Colors.white70, fontSize: 15),
            border: InputBorder.none,
            filled: false,
          ),
          onSubmitted: (v) => _search(v),
        ),
        actions: [
          TextButton(
            onPressed: _toggleType,
            style: TextButton.styleFrom(
              primary: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 36),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_type == AppConstants.typeAudio ? '听书' : '视频',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const Icon(Icons.swap_horiz, size: 16),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: '清空',
            onPressed: _clearSearch,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _search(_ctrl.text),
          ),
        ],
      ),
      body: sources.isEmpty
          ? _noSourceHint()
          : Column(
              children: [
                _sourceBar(sources),
                Divider(height: 1, color: context.palette.outline),
                Expanded(child: _buildBody(sources)),
              ],
            ),
    );
  }

  Widget _noSourceHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_outlined, size: 48, color: context.subtleColor),
            const SizedBox(height: 14),
            Text('还没有可用的${_type == 'audio' ? '听书' : '视频'}源',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('先导入一个插件源，再来搜索',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () async {
                await Navigator.of(context).pushNamed('/sources');
                ref.invalidate(sourceListProvider);
              },
              child: const Text('去导入源'),
            ),
          ],
        ),
      ),
    );
  }

  /// 点一下拉开的源选择条：默认「全部」，点开底部列表选源，选完收起并重搜
  Widget _sourceBar(List<PluginSource> sources) {
    final primary = Theme.of(context).colorScheme.primary;
    final current = _isAll
        ? '全部'
        : sources
            .where((s) => s.id == _sourceId)
            .map((s) => s.name)
            .firstWhere((_) => true, orElse: () => '全部');
    return InkWell(
      onTap: () => _pickSource(sources),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.extension_outlined, size: 18, color: primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('源：$current',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 20, color: context.subtleColor),
          ],
        ),
      ),
    );
  }

  /// 底部弹出源列表，点一个就选上、收起、用同一关键词重搜
  Future<void> _pickSource(List<PluginSource> sources) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('选择源',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    _sourceOption(ctx, _allKey, '全部', _isAll),
                    for (final s in sources)
                      _sourceOption(
                          ctx, s.id, s.name, !_isAll && _sourceId == s.id),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    if (picked == _allKey) {
      setState(() => _sourceId = _allKey);
    } else {
      setState(() => _sourceId = picked);
      setCurrentSource(ref, _type, picked);
    }
    _loadHot();
    if (_keyword.isNotEmpty) _search(_keyword);
  }

  Widget _sourceOption(
      BuildContext ctx, String id, String name, bool selected) {
    final primary = Theme.of(ctx).colorScheme.primary;
    return ListTile(
      leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: 20,
          color: selected ? primary : null),
      title: Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? primary : null)),
      trailing: selected ? const Text('正在使用', style: TextStyle(fontSize: 11)) : null,
      onTap: () => Navigator.pop(ctx, id),
    );
  }

  Widget _buildBody(List<PluginSource> sources) {
    if (!_searched) {
      return _historyView();
    }
    // 正在搜、一个结果都还没回来
    if (_loading && _groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('正在搜索…'),
          ],
        ),
      );
    }
    // 都搜完了、都没有结果也没有报错
    if (_pending <= 0 &&
        _groups.every((g) => g.items.isEmpty && g.error == null)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 44, color: context.subtleColor),
              const SizedBox(height: 12),
              const Text('没有找到相关内容'),
              const SizedBox(height: 6),
              Text(_error ?? '换个关键词，或换一个源试试',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
    }

    final rows = <Widget>[];
    // 还在搜别的源：顶部显示“正在搜索”，每个源搜完就先显示
    if (_pending > 0) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text('正在搜索…（已出 ${_groups.length} 个源的结果）',
                style: TextStyle(fontSize: 12, color: context.subtleColor)),
          ],
        ),
      ));
    }
    for (final g in _groups) {
      rows.add(_groupHeader(g));
      if (g.error != null) {
        rows.add(_groupError(g));
      } else if (g.items.isEmpty) {
        // 这个源搜不到：写清楚，不要整个分组直接消失
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text('这个源没有结果',
              style: TextStyle(fontSize: 12.5, color: context.subtleColor)),
        ));
      }
      final expanded = _expanded.contains(g.source.id);
      final shown = expanded ? g.items : g.items.take(10).toList();
      for (final r in shown) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _resultTile(r, g.source),
        ));
      }
      if (g.items.length > 10) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Center(
            child: TextButton(
              onPressed: () => setState(() {
                if (expanded) {
                  _expanded.remove(g.source.id);
                } else {
                  _expanded.add(g.source.id);
                }
              }),
              child: Text(expanded
                  ? '收起'
                  : '查看更多（还有 ${g.items.length - 10} 条）'),
            ),
          ),
        ));
      }
      rows.add(const SizedBox(height: 6));
    }
    rows.add(Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: _loadingMore
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton(
                onPressed: _loadMore,
                child: const Text('加载更多'),
              ),
      ),
    ));

    return ListView(
      controller: _scroll,
      padding: pagePadding(context, top: 12, bottom: 24),
      children: rows,
    );
  }

  Widget _groupHeader(_Group g) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Row(
        children: [
          Icon((g.source.isJar || g.source.isTingShu) ? Icons.archive_outlined : Icons.code,
              size: 14, color: context.subtleColor),
          const SizedBox(width: 6),
          Text(g.source.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text('${g.items.length} 条',
              style: TextStyle(fontSize: 11, color: context.subtleColor)),
        ],
      ),
    );
  }

  Widget _groupError(_Group g) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text('这个源搜索失败，点一下重试',
                style: TextStyle(fontSize: 11.5)),
          ),
          if (g.verificationUrl != null) ...[
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _verifyAndRetry(g),
              child: const Text('去验证'),
            ),
          ],
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _retryGroup(g),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// 只重搜这一个源
  Future<void> _retryGroup(_Group g) async {
    if (_keyword.isEmpty) return;
    final gen = _searchGen;
    setState(() => _pending++);
    final fresh = await _searchOne(g.source, _keyword, 1);
    if (!mounted || gen != _searchGen) return;
    setState(() {
      _groups = [
        for (final o in _groups)
          o.source.id == g.source.id ? fresh : o,
      ];
      _pending--;
    });
  }

  /// 打开验证页（WebView），用户过掉验证后等一会儿再重搜这个源
  Future<void> _verifyAndRetry(_Group g) async {
    final url = g.verificationUrl;
    if (url == null || url.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LoginWebPage(
        title: '${g.source.name} · 验证',
        url: url,
        desktop: g.verificationUa.contains('Windows'),
      ),
    ));
    if (!mounted) return;
    if (g.verificationDelayMs > 0) {
      await Future.delayed(
          Duration(milliseconds: g.verificationDelayMs));
    }
    if (!mounted) return;
    setState(() => _loading = true);
    final group = await _searchOne(g.source, _keyword, 1);
    if (!mounted) return;
    setState(() {
      _groups = [
        for (final old in _groups)
          old.source.id == g.source.id ? group : old,
      ];
      _loading = false;
    });
  }

  /// 搜索历史：一行一个，点直接搜；下面是热门搜索（源给的才显示）
  Widget _historyView() {
    return ListView(
      padding: pagePadding(context, top: 16, bottom: 24),
      children: [
        Row(
          children: [
            const Text('搜索历史',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(
              onPressed: _clearHistory,
              child: const Text('清空'),
            ),
          ],
        ),
        if (_history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('输入关键词搜索',
                style: Theme.of(context).textTheme.bodySmall),
          )
        else
          for (final h in _history)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                _ctrl.text = h;
                _search(h);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: context.palette.outline, width: 0.6),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.history,
                        size: 16, color: context.subtleColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(h,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5)),
                    ),
                    Icon(Icons.north_west,
                        size: 14, color: context.subtleColor),
                  ],
                ),
              ),
            ),
        if (_hotWords.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('热门搜索',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          for (final w in _hotWords)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                _ctrl.text = w;
                _search(w);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                        color: context.palette.outline, width: 0.6),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.trending_up,
                        size: 16, color: context.subtleColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(w,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _resultTile(Map<String, dynamic> r, PluginSource source) {
    final name = _pick(r, ['name', 'title', 'bookName', 'videoName']) ?? '未命名';
    final author = _pick(r, ['author', 'writer', 'upName']) ?? '';
    final intro = _pick(r, ['intro', 'desc', 'description', 'summary']) ?? '';
    final cover = _pick(r, ['cover', 'img', 'coverUrl', 'pic']);
    final url = _pick(r, ['url', 'bookUrl', 'detailUrl', 'id']) ?? '';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SourceBookPage(
            sourceId: source.id,
            bookUrl: url,
            title: name,
            coverUrl: cover,
            author: author,
            intro: intro,
          ),
        ));
      },
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
            _cover(cover, name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                  if (author.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 12)),
                  ],
                  if (intro.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(intro,
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
            Icon(Icons.chevron_right, size: 18, color: context.subtleColor),
          ],
        ),
      ),
    );
  }

  Widget _cover(String? url, String title) {
    if (url != null && url.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: 54,
          height: 72,
          cacheWidth: 108,
          cacheHeight: 144,
          filterQuality: FilterQuality.low,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _coverPlaceholder(title),
        ),
      );
    }
    return _coverPlaceholder(title);
  }

  Widget _coverPlaceholder(String title) => Container(
        width: 54,
        height: 72,
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(title.isEmpty ? '?' : title.substring(0, 1),
            style: TextStyle(color: context.subtleColor, fontSize: 18)),
      );

  String? _pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && '$v'.trim().isNotEmpty) return '$v';
    }
    return null;
  }

  // ---------------------------------------------------------------- 搜索

  Future<void> _search(String rawKeyword) async {
    final kw = rawKeyword.trim();
    if (kw.isEmpty) return;
    final sources = _sources();
    if (sources.isEmpty) {
      setState(() => _error = '没有可用的源');
      return;
    }
    FocusScope.of(context).unfocus();
    _keyword = kw;
    _page = 1;
    final gen = ++_searchGen;
    final targets = _targets(sources);
    setState(() {
      _error = null;
      _searched = true;
      _groups = [];
      _expanded.clear();
      _pending = targets.length;
      _loading = true;
    });
    _saveHistory(kw);

    // 每个源搜完就先显示，不等全部搜完
    for (final s in targets) {
      _searchOne(s, kw, 1).then((g) {
        if (!mounted || gen != _searchGen) return;
        setState(() {
          _groups = [..._groups, g];
          _pending--;
          if (_pending <= 0) _loading = false;
        });
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore) return;
    if (!_searched || _keyword.isEmpty) return;
    final sources = _targets(_sources());
    if (sources.isEmpty) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    final more = await Future.wait(
      sources.map((s) => _searchOne(s, _keyword, next)),
    );
    if (!mounted) return;
    setState(() {
      _page = next;
      // 增量返回后分组顺序不等于源顺序，按源 id 合并
      final byId = {for (final m in more) m.source.id: m};
      _groups = [
        for (final g in _groups)
          _Group(
            source: g.source,
            items: [
              ...g.items,
              ...(byId[g.source.id]?.items ?? const []),
            ],
            error: g.error,
            verificationUrl: g.verificationUrl,
            verificationUa: g.verificationUa,
            verificationDelayMs: g.verificationDelayMs,
          ),
      ];
      _loadingMore = false;
    });
  }

  Future<_Group> _searchOne(PluginSource source, String kw, int page) async {
    try {
      final engine = source.isTingShu

          ? ref.read(tingShuEngineProvider)

          : source.isJar

          ? ref.read(jarPluginEngineProvider)

          : ref.read(jsPluginEngineProvider);
      await engine.attach(source);
      final raw = await engine
          .invoke('search', params: {'keyword': kw, 'page': page});
      var items = _normalize(raw);
      // 精确搜索（默认开）：过滤掉和关键词不相关的结果
      if (ref.read(exactSearchProvider)) {
        final kwLower = kw.toLowerCase();
        items = items.where((e) {
          final name =
              '${e['name'] ?? e['title'] ?? ''}'.toLowerCase();
          final author = '${e['author'] ?? ''}'.toLowerCase();
          return name.contains(kwLower) || author.contains(kwLower);
        }).toList();
      }
      return _Group(source: source, items: items);
    } catch (e) {
      final msg = '$e';
      final friendly = msg.contains('METHOD_NOT_FOUND') || msg.contains('未实现')
          ? '没有搜索方法'
          : msg;
      // 搜索被验证拦截（403/429）：给个「去验证」入口，过完验证再搜一次
      String? verifyUrl;
      String verifyUa = '';
      var verifyDelay = 0;
      final blocked = msg.contains('403') ||
          msg.contains('429') ||
          msg.contains('验证') ||
          msg.contains('challenge');
      if (source.isTingShu && blocked) {
        try {
          final engine = ref.read(tingShuEngineProvider);
          await engine.attach(source);
          final info = await engine.verificationInfo(kw);
          if (info != null && info['validated'] != true) {
            verifyUrl = '${info['url'] ?? ''}';
            if (verifyUrl.isEmpty) verifyUrl = null;
            verifyUa = '${info['ua'] ?? ''}';
            verifyDelay = (info['delayMs'] as num?)?.toInt() ?? 0;
          }
        } catch (_) {}
      }
      return _Group(
        source: source,
        items: const [],
        error: verifyUrl != null ? '这个源要先过验证才能搜' : friendly,
        verificationUrl: verifyUrl,
        verificationUa: verifyUa,
        verificationDelayMs: verifyDelay,
      );
    }
  }

  List<Map<String, dynamic>> _normalize(dynamic raw) {
    if (raw == null) return [];
    final list = raw is List ? raw : (raw is Map ? [raw] : <dynamic>[]);
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is Map) {
        out.add(Map<String, dynamic>.from(e));
      } else if (e is String) {
        out.add({'name': e, 'url': e});
      }
    }
    out.removeWhere((e) => e['__error'] != null);
    return out;
  }

  void _saveHistory(String kw) {
    final prefs = ref.read(sharedPrefsProvider);
    final list = [..._history];
    list.remove(kw);
    list.insert(0, kw);
    final trimmed = list.take(20).toList();
    prefs.setStringList(_historyKey, trimmed);
    setState(() => _history = trimmed);
  }

  void _clearHistory() {
    ref.read(sharedPrefsProvider).remove(_historyKey);
    setState(() => _history = []);
  }
}
