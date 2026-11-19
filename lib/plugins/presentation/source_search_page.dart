import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../data/plugin_providers.dart';
import '../engine/plugin_engine.dart';
import '../model/plugin_source.dart';
import 'source_book_page.dart';

/// 源搜索：选一个源，输入关键词，返回结果列表
class SourceSearchPage extends ConsumerStatefulWidget {
  final String type;

  /// 从首页进来时带上的源，保证和首页选的是同一个
  final String? initialSourceId;

  const SourceSearchPage({super.key, this.type = AppConstants.typeAudio, this.initialSourceId});

  @override
  ConsumerState<SourceSearchPage> createState() => _SourceSearchPageState();
}

class _SourceSearchPageState extends ConsumerState<SourceSearchPage> {
  final _ctrl = TextEditingController();
  String? _sourceId;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _sourceId = widget.initialSourceId ??
        ref.read(currentSourceProvider(widget.type));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<PluginSource> _sources() {
    final all = ref.watch(sourceListProvider).value ?? const [];
    return all
        .where((s) => s.type == widget.type && s.enabled)
        .toList(growable: false);
  }

  PluginSource? _current(List<PluginSource> list) {
    if (list.isEmpty) return null;
    for (final s in list) {
      if (s.id == _sourceId) return s;
    }
    return list.first;
  }

  @override
  Widget build(BuildContext context) {
    final sources = _sources();
    final current = _current(sources);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: widget.type == AppConstants.typeAudio
                ? '搜索书名 / 作者'
                : '搜索视频名',
            border: InputBorder.none,
            filled: false,
          ),
          onSubmitted: (_) => _search(current),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _search(current),
          ),
        ],
      ),
      body: Column(
        children: [
          if (sources.isEmpty)
            _noSourceHint()
          else ...[
            _sourceBar(sources, current),
            const Divider(height: 1),
            Expanded(child: _buildBody(current)),
          ],
        ],
      ),
    );
  }

  Widget _noSourceHint() {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.extension_outlined,
                  size: 48, color: context.subtleColor),
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
      ),
    );
  }

  Widget _sourceBar(List<PluginSource> sources, PluginSource? current) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sources.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final s = sources[i];
          final selected = current?.id == s.id;
          final primary = Theme.of(context).colorScheme.primary;
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() => _sourceId = s.id);
              setCurrentSource(ref, widget.type, s.id);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color:
                    selected ? context.palette.primarySoft : context.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? primary : context.palette.outline,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(s.isJar ? Icons.archive_outlined : Icons.code,
                      size: 14,
                      color: selected ? primary : context.subtleColor),
                  const SizedBox(width: 6),
                  Text(s.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? primary : null,
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(PluginSource? current) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 40, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text('搜索失败', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => _search(current),
                    child: const Text('重试'),
                  ),
                  const SizedBox(width: 10),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/ua-settings'),
                    child: const Text('改 UA 试试'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 44, color: context.subtleColor),
              const SizedBox(height: 12),
              Text('输入关键词搜索',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              Text('结果由「${current?.name ?? '当前源'}」提供',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _resultTile(_results[i], current),
    );
  }

  Widget _resultTile(Map<String, dynamic> r, PluginSource? source) {
    final name = _pick(r, ['name', 'title', 'bookName', 'videoName']) ?? '未命名';
    final author = _pick(r, ['author', 'writer', 'upName']) ?? '';
    final intro = _pick(r, ['intro', 'desc', 'description', 'summary']) ?? '';
    final cover = _pick(r, ['cover', 'img', 'coverUrl', 'pic']);
    final url = _pick(r, ['url', 'bookUrl', 'detailUrl', 'id']) ?? '';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        if (source == null) return;
        await Navigator.of(context).push(MaterialPageRoute(
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

  Future<void> _search(PluginSource? source) async {
    final kw = _ctrl.text.trim();
    if (kw.isEmpty) return;
    if (source == null) {
      setState(() => _error = '没有可用的源');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });
    try {
      final engine = source.isJar
          ? ref.read(jarPluginEngineProvider)
          : ref.read(jsPluginEngineProvider);
      await engine.attach(source);
      final raw = await engine
          .invoke('search', params: {'keyword': kw, 'page': 1});
      final list = _normalize(raw);
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
        if (list.isEmpty) _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        final msg = '$e';
        _error = msg.contains('METHOD_NOT_FOUND') ||
                msg.contains('未实现')
            ? '这个源没有提供搜索方法（${PluginMethods.labels['search']}）'
            : msg;
        if (msg.toLowerCase().contains('ua') ||
            msg.contains('403') ||
            msg.contains('限制')) {
          _error = '$msg\n\n可以到「UA 设置」换一条 UA 再试。';
        }
      });
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
    // 过滤掉明显的错误对象
    out.removeWhere((e) => e['__error'] != null);
    return out;
  }
}
