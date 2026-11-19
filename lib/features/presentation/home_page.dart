import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/path_utils.dart';
import '../../features/audio/data/repository_providers.dart';
import '../../features/audio/domain/media_item.dart' as domain;
import '../../plugins/data/home_feed.dart';
import '../../plugins/data/login_entry.dart';
import '../../plugins/data/plugin_providers.dart';
import '../../plugins/data/plugin_resume.dart';
import '../../plugins/model/plugin_source.dart';
import '../../plugins/presentation/source_book_page.dart';
import '../../plugins/presentation/source_picker_sheet.dart';
import '../../plugins/presentation/source_search_page.dart';
import '../../shared/widgets/common.dart';

/// 书源页（首页）：筛选框 → 继续区 → 源组横条 → 源列表（一行多个卡片）→ 推荐
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _filterCtrl = TextEditingController();
  String _filter = '';
  String _group = '全部';
  final Map<String, bool> _loginFlags = {};
  String _lastIds = '';
  List<PluginResume> _resumes = [];
  int _lastResumeRefresh = 0;

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(activeHomeSourceProvider);
    final list = ref.watch(sourceListProvider).value ?? const <PluginSource>[];
    final enabled = list.where((s) => s.enabled).toList(growable: false);
    final isActiveTab = ref.watch(shellTabProvider) == 0;
    if (isActiveTab) _maybeRefresh(enabled);

    final groups = <String>['全部'];
    for (final s in enabled) {
      if (s.group.isNotEmpty && !groups.contains(s.group)) groups.add(s.group);
    }
    if (!groups.contains(_group)) _group = '全部';

    final filtered = enabled.where((s) {
      if (_group != '全部' && s.group != _group) return false;
      if (_filter.isNotEmpty &&
          !s.name.toLowerCase().contains(_filter.toLowerCase())) {
        return false;
      }
      return true;
    }).toList(growable: false);
    final columns = ref.watch(sourceColumnsProvider);

    return Scaffold(
      drawer: buildAppDrawer(context),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _appBar(context, ref, source),
            SliverToBoxAdapter(child: _filterBox(context)),
            SliverToBoxAdapter(child: _continueSection(context)),
            if (groups.length > 1)
              SliverToBoxAdapter(child: _groupBar(context, groups)),
            SliverToBoxAdapter(child: _sourceListHeader(context, columns)),
            if (enabled.isEmpty)
              SliverToBoxAdapter(child: _noSource(context, ref))
            else if (filtered.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text('没有符合条件的源',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    mainAxisExtent: 96,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _sourceCard(filtered[i]),
                    childCount: filtered.length,
                  ),
                ),
              ),
            ..._feedSlivers(context, ref, source),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
            SliverToBoxAdapter(
              child: SizedBox(
                  height: MediaQuery.of(context).padding.bottom + 8),
            ),
          ],
        ),
      ),
    );
  }

  /// 回到书源页时刷新断点和登录标记（节流 2 秒，避免反复 setState）
  void _maybeRefresh(List<PluginSource> enabled) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastResumeRefresh < 2000) return;
    _lastResumeRefresh = now;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final list = await PluginResumeStore.loadAll();
      if (mounted) setState(() => _resumes = list);
      ref.invalidate(continueListProvider(AppConstants.typeAudio));
      ref.invalidate(continueListProvider(AppConstants.typeVideo));
    });
    final ids = enabled.map((s) => s.id).join(',');
    if (ids != _lastIds) {
      _lastIds = ids;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadLoginFlags(enabled));
    }
  }

  /// 读每个源的登录入口（manifest 里的 login），用来在卡片上标“登录”
  Future<void> _loadLoginFlags(List<PluginSource> sources) async {
    final repo = ref.read(sourceRepositoryProvider);
    var changed = false;
    for (final s in sources) {
      if (_loginFlags.containsKey(s.id)) continue;
      try {
        final manifest = await repo.readManifest(s);
        final entry = LoginEntry.parse(manifest);
        _loginFlags[s.id] = entry != null && entry.valid;
      } catch (_) {
        _loginFlags[s.id] = false;
      }
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  // ------------------------------------------------------------ 顶部

  Widget _appBar(BuildContext context, WidgetRef ref, PluginSource? source) {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      leading: Builder(
        builder: (ctx) => IconButton(
          icon: const Icon(Icons.menu),
          tooltip: '菜单',
          onPressed: () => Scaffold.of(ctx).openDrawer(),
        ),
      ),
      titleSpacing: 0,
      title: _SourceTitle(
        source: source,
        onTap: () => pickHomeSource(context, ref, currentId: source?.id),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.play_arrow_rounded),
          tooltip: '播放',
          onPressed: () => openMostRecentResume(context, ref),
        ),
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: '搜索',
          onPressed: () => _openSearch(context, source),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  /// 顶部一个“筛选书源”输入框，输字按名字筛选源
  Widget _filterBox(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _filterCtrl,
        decoration: InputDecoration(
          hintText: '筛选书源',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _filter.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _filterCtrl.clear();
                    setState(() => _filter = '');
                  },
                ),
        ),
        onChanged: (v) => setState(() => _filter = v.trim()),
      ),
    );
  }

  // ------------------------------------------------------------ 继续区

  Widget _continueSection(BuildContext context) {
    final audioLocal =
        ref.watch(continueListProvider(AppConstants.typeAudio)).value ?? [];
    final videoLocal =
        ref.watch(continueListProvider(AppConstants.typeVideo)).value ?? [];
    final plugin = _resumes.take(2).toList();
    final local = <domain.MediaItem>[...audioLocal, ...videoLocal]
      ..sort((a, b) {
        final x = a.lastReadAt ?? a.addedAt;
        final y = b.lastReadAt ?? b.addedAt;
        return y.compareTo(x);
      });
    final localTop = local.take(2).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _bar(context),
              const SizedBox(width: 8),
              Text('继续',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          if (plugin.isEmpty && localTop.isEmpty) ...[
            _emptyContinue(context, '还没有在听的书', AppConstants.typeAudio),
            const SizedBox(height: 8),
            _emptyContinue(context, '还没有在看的视频', AppConstants.typeVideo),
          ] else ...[
            for (final r in plugin) ...[
              _resumeCard(context, r),
              const SizedBox(height: 8),
            ],
            for (final item in localTop) ...[
              _localContinueCard(context, item),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _emptyContinue(BuildContext context, String text, String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.outline),
      ),
      child: Row(
        children: [
          Icon(
              type == AppConstants.typeAudio
                  ? Icons.headphones_outlined
                  : Icons.movie_outlined,
              size: 20,
              color: context.subtleColor),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text, style: const TextStyle(fontSize: 13.5))),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SourceSearchPage(type: type),
            )),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              minimumSize: const Size(0, 30),
            ),
            child: const Text('去找', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _resumeCard(BuildContext context, PluginResume r) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => openResume(context, ref, r),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.palette.outline),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: r.coverUrl.startsWith('http')
                  ? Image.network(
                      r.coverUrl,
                      width: 48,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _coverPlaceholder(r),
                    )
                  : _coverPlaceholder(r),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.bookTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    '${r.chapterName} · 已播 ${PathUtils.formatDuration(r.positionMs)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: r.progress,
                      minHeight: 4,
                      color: primary,
                      backgroundColor: context.palette.surfaceAlt,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.play_circle_fill, size: 30, color: primary),
          ],
        ),
      ),
    );
  }

  Widget _coverPlaceholder(PluginResume r) {
    return Container(
      width: 48,
      height: 64,
      color: context.palette.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(
        r.isAudio ? Icons.headphones_outlined : Icons.movie_outlined,
        size: 20,
        color: Theme.of(context).colorScheme.primary.withOpacity(0.55),
      ),
    );
  }

  Widget _localContinueCard(BuildContext context, domain.MediaItem item) {
    final primary = Theme.of(context).colorScheme.primary;
    final p = item.progress > 1 ? item.progress / 100 : item.progress;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => openLocalItem(context, ref, item),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.palette.outline),
        ),
        child: Row(
          children: [
            CoverImage(
                path: item.coverPath,
                title: item.title,
                size: 48,
                isVideo: item.isVideo),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    item.isAudio ? '听书 · 已听 ${(p * 100).round()}%' : '视频 · 已看 ${(p * 100).round()}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: p.clamp(0.0, 1.0),
                      minHeight: 4,
                      color: primary,
                      backgroundColor: context.palette.surfaceAlt,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.play_circle_fill, size: 30, color: primary),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 源组 / 源列表

  Widget _groupBar(BuildContext context, List<String> groups) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      height: 46,
      padding: const EdgeInsets.only(top: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: groups.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final g = groups[i];
          final selected = _group == g;
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _group = g),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? context.palette.primarySoft
                    : context.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? primary : context.palette.outline,
                  width: selected ? 1.4 : 1,
                ),
              ),
              child: Text(g,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? primary : null,
                  )),
            ),
          );
        },
      ),
    );
  }

  Widget _sourceListHeader(BuildContext context, int columns) {
    final prefs = ref.read(sharedPrefsProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          _bar(context),
          const SizedBox(width: 8),
          Text('源列表',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (_group != '全部') ...[
            const SizedBox(width: 6),
            Text(_group, style: Theme.of(context).textTheme.bodySmall),
          ],
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.grid_view_rounded, size: 20),
            tooltip: '列数：$columns 列',
            onPressed: () async {
              final picked = await showMenu<int>(
                context: context,
                position: const RelativeRect.fromLTRB(100, 100, 16, 0),
                items: [1, 2, 3, 4, 5]
                    .map((n) => PopupMenuItem<int>(
                          value: n,
                          child: Row(
                            children: [
                              Text('$n 列'),
                              if (n == columns) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.check,
                                    size: 16,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary),
                              ],
                            ],
                          ),
                        ))
                    .toList(),
              );
              if (picked != null) {
                ref.read(sourceColumnsProvider.notifier).state = picked;
                prefs.setInt(AppConstants.keySourceColumns, picked);
              }
            },
          ),
        ],
      ),
    );
  }

  /// 源卡片：源名（加粗）+ 登录标记 + 介绍，两行省略
  Widget _sourceCard(PluginSource s) {
    final primary = Theme.of(context).colorScheme.primary;
    final hasLogin = _loginFlags[s.id] ?? false;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        setHomeSource(ref, s.id);
        ref.read(shellTabProvider.notifier).state = 1;
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.palette.outline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(s.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
                if (hasLogin) ...[
                  const SizedBox(width: 4),
                  Text('登录',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: primary)),
                ],
                if (hasLogin) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.lightbulb_outline,
                      size: 14, color: primary),
                ],
                const SizedBox(width: 2),
                Icon(Icons.search, size: 14, color: context.subtleColor),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              s.description.isEmpty
                  ? (s.isAudio ? '听书源' : '视频源')
                  : s.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, height: 1.4, color: context.subtleColor),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 推荐内容

  List<Widget> _feedSlivers(
      BuildContext context, WidgetRef ref, PluginSource? source) {
    if (source == null) {
      if (ref.watch(sourceListProvider).isLoading) {
        return [
          SliverToBoxAdapter(child: _feedLoading(context, '正在读取已安装的源…')),
        ];
      }
      return const [];
    }

    final async = ref.watch(homeFeedProvider(source.id));

    return [
      const SliverToBoxAdapter(child: SizedBox(height: 10)),
      ...async.when(
        data: (sections) {
          final usable = sections.where((s) => s.books.isNotEmpty).toList();
          if (usable.isEmpty) {
            return [SliverToBoxAdapter(child: _feedEmpty(context, ref, source))];
          }
          final out = <Widget>[];
          for (final sec in usable) {
            out.add(SliverToBoxAdapter(
              child: _sectionHeader(context, ref, source, sec),
            ));
            out.add(SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverGrid(
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.55,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _BookCard(book: sec.books[i], source: source),
                  childCount: sec.books.length,
                ),
              ),
            ));
          }
          return out;
        },
        loading: () => [
          SliverToBoxAdapter(
              child: _feedLoading(context, '正在加载「${source.name}」的推荐…')),
        ],
        error: (e, _) => [
          SliverToBoxAdapter(child: _feedError(context, ref, source, e)),
        ],
      ),
    ];
  }

  Widget _sectionHeader(
      BuildContext context, WidgetRef ref, PluginSource source, FeedSection sec) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 6, 0),
      child: Row(
        children: [
          _bar(context),
          const SizedBox(width: 8),
          Text(sec.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: context.subtleColor,
            tooltip: '换一批',
            onPressed: () => ref.invalidate(homeFeedProvider(source.id)),
          ),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context) => Container(
        width: 3,
        height: 15,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _feedLoading(BuildContext context, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(title, style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 6,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 10,
              childAspectRatio: 0.55,
            ),
            itemBuilder: (_, __) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  width: 70,
                  decoration: BoxDecoration(
                    color: context.palette.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// 推荐加载失败：只显示人话提示和重试，不把英文报错原文甩给用户
  Widget _feedError(
      BuildContext context, WidgetRef ref, PluginSource source, Object e) {
    final msg = '$e';
    final noMethod = msg.contains('未实现') || msg.contains('METHOD_NOT_FOUND');
    if (noMethod) return _feedEmpty(context, ref, source);

    final hint = (msg.contains('403') || msg.toLowerCase().contains('ua'))
        ? '可能被源站限制了，去「UA 设置」换一条 UA 再试。'
        : '有些源的网络较慢，可以稍后重试。';

    return _Notice(
      icon: Icons.cloud_off_outlined,
      title: '推荐加载失败',
      message: '这个源的推荐暂时打不开，可以重试或直接搜索。',
      hint: hint,
      actions: [
        OutlinedButton(
          onPressed: () => ref.invalidate(homeFeedProvider(source.id)),
          child: const Text('重试'),
        ),
        TextButton(
          onPressed: () => _openSearch(context, source),
          child: const Text('直接搜索'),
        ),
      ],
    );
  }

  Widget _feedEmpty(BuildContext context, WidgetRef ref, PluginSource source) {
    return _Notice(
      icon: Icons.widgets_outlined,
      title: '「${source.name}」没有配置首页推荐',
      message: '这个源只提供搜索能力，去搜索里找你想听的内容。',
      hint: '也可以在左上角换一个带推荐位的源。',
      actions: [
        ElevatedButton(
          onPressed: () => _openSearch(context, source),
          child: const Text('去搜索'),
        ),
        TextButton(
          onPressed: () =>
              pickHomeSource(context, ref, currentId: source.id),
          child: const Text('换个源'),
        ),
      ],
    );
  }

  Widget _noSource(BuildContext context, WidgetRef ref) {
    return _Notice(
      icon: Icons.extension_outlined,
      title: '还没有可用的源',
      message: '导入一个插件源，首页会显示它配置的推荐内容。',
      hint: '听书、视频都可以用插件源在线播放。',
      actions: [
        ElevatedButton(
          onPressed: () async {
            await Navigator.of(context).pushNamed('/sources');
            ref.invalidate(sourceListProvider);
          },
          child: const Text('导入源'),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ 动作

  void _openSearch(BuildContext context, PluginSource? source) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SourceSearchPage(
        type: source?.type ?? AppConstants.typeAudio,
        initialSourceId: source?.id,
      ),
    ));
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(sourceListProvider);
    final s = ref.read(activeHomeSourceProvider);
    if (s == null) return;
    ref.invalidate(homeFeedProvider(s.id));
    try {
      await ref.read(homeFeedProvider(s.id).future);
    } catch (_) {
      // 错误交给页面展示
    }
  }
}

// ---------------------------------------------------------------- 顶部标题

class _SourceTitle extends StatelessWidget {
  final PluginSource? source;
  final VoidCallback onTap;

  const _SourceTitle({required this.source, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    source?.name ?? '我的听书',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 22, color: Colors.white70),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              source == null ? '点这里导入源' : '点一下切换源',
              style: const TextStyle(fontSize: 10.5, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 推荐卡片

class _BookCard extends StatelessWidget {
  final FeedBook book;
  final PluginSource source;

  const _BookCard({required this.book, required this.source});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SourceBookPage(
          sourceId: source.id,
          bookUrl: book.url,
          title: book.title,
          coverUrl: book.cover.isEmpty ? null : book.cover,
          author: book.author,
          intro: book.intro,
        ),
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _cover(context)),
          const SizedBox(height: 7),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
          if (book.author.isNotEmpty) ...[
            const SizedBox(height: 3),
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
    final radius = BorderRadius.circular(10);
    final placeholder = Container(
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: radius,
      ),
      alignment: Alignment.center,
      child: Icon(
        source.isAudio ? Icons.headphones : Icons.movie_outlined,
        size: 22,
        color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
      ),
    );

    if (book.cover.isEmpty || !book.cover.startsWith('http')) {
      return placeholder;
    }
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        book.cover,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => placeholder,
        loadingBuilder: (ctx, child, progress) =>
            progress == null ? child : placeholder,
      ),
    );
  }
}

// ---------------------------------------------------------------- 空/错误提示

class _Notice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? hint;
  final List<Widget> actions;

  const _Notice({
    required this.icon,
    required this.title,
    required this.message,
    this.hint,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.palette.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 30, color: context.subtleColor),
            const SizedBox(height: 12),
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(message,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(height: 1.5)),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint!,
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: context.subtleColor.withOpacity(0.85))),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}
