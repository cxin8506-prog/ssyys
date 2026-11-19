import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/di/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/common.dart';
import '../data/plugin_providers.dart';
import '../engine/plugin_engine.dart';
import '../model/plugin_source.dart';
import 'source_book_page.dart';

/// 一个源的搜索结果
class _Group {
  final PluginSource source;
  final List<Map<String, dynamic>> items;
  final String? error;

  _Group({required this.source, required this.items, this.error});
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
  bool _loading = false;
  bool _loadingMore = false;
  bool _searched = false;
  int _page = 1;
  String? _error;
  String _keyword = '';
  List<_Group> _groups = [];
  List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _sourceId = widget.initialSourceId ?? _allKey;
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
        _loadMore();
      }
    });
    final prefs = ref.read(sharedPrefsProvider);
    _history = prefs.getStringList(_historyKey) ?? [];
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
        .where((s) => s.type == widget.type && s.enabled)
        .toList(growable: false);
  }

  List<PluginSource> _targets(List<PluginSource> sources) {
    if (_isAll) return sources;
    final hit = sources.where((s) => s.id == _sourceId).toList();
    return hit.isEmpty ? sources : hit;
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
          decoration: InputDecoration(
            hintText: '搜索书名 / 作者 / 视频名',
            border: InputBorder.none,
            filled: false,
          ),
          onSubmitted: (v) => _search(v),
        ),
        actions: [
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
            Text('还没有可用的${widget.type == 'audio' ? '听书' : '视频'}源',
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

  Widget _sourceBar(List<PluginSource> sources) {
    final primary = Theme.of(context).colorScheme.primary;
    Widget chip({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      IconData? icon,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? context.palette.primarySoft : context.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? primary : context.palette.outline,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 14, color: selected ? primary : context.subtleColor),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? primary : null,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sources.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i == 0) {
            return chip(
              label: '全部',
              icon: Icons.apps,
              selected: _isAll,
              onTap: () => setState(() => _sourceId = _allKey),
            );
          }
          final s = sources[i - 1];
          return chip(
            label: s.name,
            icon: s.isJar ? Icons.archive_outlined : Icons.code,
            selected: !_isAll && _sourceId == s.id,
            onTap: () {
              setState(() => _sourceId = s.id);
              setCurrentSource(ref, widget.type, s.id);
            },
          );
        },
      ),
    );
  }

  Widget _buildBody(List<PluginSource> sources) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_searched) {
      return _historyView();
    }
    if (_groups.every((g) => g.items.isEmpty)) {
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
    for (final g in _groups) {
      if (g.items.isEmpty && g.error == null) continue;
      rows.add(_groupHeader(g));
      if (g.error != null) {
        rows.add(_groupError(g));
      }
      for (final r in g.items) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _resultTile(r, g.source),
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
          Icon(g.source.isJar ? Icons.archive_outlined : Icons.code,
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
      child: Text('这个源搜索失败：${g.error}',
          style: TextStyle(fontSize: 11.5, color: context.subtleColor)),
    );
  }

  Widget _historyView() {
    if (_history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 44, color: context.subtleColor),
            const SizedBox(height: 12),
            Text('输入关键词搜索',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 6),
            Text(_isAll ? '会在所有启用中的源里同时搜' : '只搜当前选中的源',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final h in _history)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  _ctrl.text = h;
                  _search(h);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: context.palette.surfaceAlt,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(h, style: const TextStyle(fontSize: 12.5)),
                ),
              ),
          ],
        ),
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
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
      _groups = [];
    });
    _saveHistory(kw);

    final targets = _targets(sources);
    final groups = await Future.wait(
      targets.map((s) => _searchOne(s, kw, 1)),
    );
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _loading = false;
    });
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
      _groups = [
        for (var i = 0; i < _groups.length; i++)
          _Group(
            source: _groups[i].source,
            items: [
              ..._groups[i].items,
              if (i < more.length) ...more[i].items,
            ],
            error: _groups[i].error,
          ),
      ];
      _loadingMore = false;
    });
  }

  Future<_Group> _searchOne(PluginSource source, String kw, int page) async {
    try {
      final engine = source.isJar
          ? ref.read(jarPluginEngineProvider)
          : ref.read(jsPluginEngineProvider);
      await engine.attach(source);
      final raw = await engine
          .invoke('search', params: {'keyword': kw, 'page': page});
      return _Group(source: source, items: _normalize(raw));
    } catch (e) {
      final msg = '$e';
      final friendly = msg.contains('METHOD_NOT_FOUND') || msg.contains('未实现')
          ? '没有搜索方法'
          : msg;
      return _Group(source: source, items: const [], error: friendly);
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
    final trimmed = list.take(12).toList();
    prefs.setStringList(_historyKey, trimmed);
    setState(() => _history = trimmed);
  }

  void _clearHistory() {
    ref.read(sharedPrefsProvider).remove(_historyKey);
    setState(() => _history = []);
  }
}
