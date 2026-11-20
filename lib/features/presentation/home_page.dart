import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../plugins/data/home_feed.dart';
import '../../plugins/data/login_entry.dart';
import '../../plugins/data/plugin_providers.dart';
import '../../plugins/data/plugin_resume.dart';
import '../../plugins/model/plugin_source.dart';
import '../../plugins/presentation/source_book_page.dart';
import '../../plugins/presentation/source_search_page.dart';
import '../../shared/widgets/common.dart';

/// 书源页（网格层）：顶栏只留搜索/设置两个图标（无标题、无播放键）→
/// 源组横条（瘦版）→ 源卡片网格 → 推荐
/// 点源卡片切到 tab 1（DiscoverPage，内容层），网格层随 tab 切换隐藏。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _scroll = ScrollController();
  /// 展开的分组（点横条展开/收起；默认展开第一个分组，其余收着）
  final Set<String> _openGroups = {};
  bool _groupsInit = false;
  final Map<String, bool> _loginFlags = {};
  String _lastIds = '';
  int _lastRefresh = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final source = ref.watch(activeHomeSourceProvider);
    final list = ref.watch(sourceListProvider).value ?? const <PluginSource>[];
    final enabled = list.where((s) => s.enabled).toList(growable: false);
    final isActiveTab = ref.watch(shellTabProvider) == 0;
    if (isActiveTab) _maybeRefresh(enabled);

    // 分组：按源的 group（包名，如 JAR 文件名「影视聚合」）分；
    // group 为空（JS/ZIP 源）时用源自己的名字当分组名，绝不出现「其他」
    final groups = <String>[];
    for (final s in enabled) {
      final g = _groupOf(s);
      if (!groups.contains(g)) groups.add(g);
    }
    if (!_groupsInit && groups.isNotEmpty) {
      _openGroups.add(groups.first);
      _groupsInit = true;
    }
    bool isOpen(String g) => _openGroups.contains(g);
    List<PluginSource> groupSources(String g) => enabled.where((s) {
          if (_groupOf(s) != g) return false;
          return true;
        }).toList(growable: false);
    final columns = ref.watch(sourceColumnsProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _appBar(context, ref, source),
            if (enabled.isEmpty)
              SliverToBoxAdapter(child: _noSource(context, ref))
            else
              for (final g in groups)
                if (groupSources(g).isNotEmpty) ...[
                  SliverToBoxAdapter(
                      child: _groupBar(context, g, groupSources(g).length,
                          isOpen(g), () {
                    setState(() {
                      if (_openGroups.contains(g)) {
                        _openGroups.remove(g);
                      } else {
                        _openGroups.add(g);
                      }
                    });
                  })),
                  if (isOpen(g))
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      sliver: SliverGrid(
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          mainAxisExtent: 132,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _sourceCard(groupSources(g)[i]),
                          childCount: groupSources(g).length,
                        ),
                      ),
                    ),
                ],
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

  /// 分组名：group（包名）为空时用源自己的名字，绝不出现「其他」
  String _groupOf(PluginSource s) => s.group.isEmpty ? s.name : s.group;

  /// 回到书源页时刷新登录标记（节流 2 秒，避免反复 setState）。
  void _maybeRefresh(List<PluginSource> enabled) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastRefresh < 2000) return;
    _lastRefresh = now;
    final ids = enabled.map((s) => s.id).join(',');
    if (ids != _lastIds) {
      _lastIds = ids;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadLoginFlags(enabled));
    }
  }

  /// 读每个源的登录入口，用来在卡片上标“登录”。
  /// JS 源读 manifest 里的 login；JAR（我的听书格式）没有 manifest，
  /// 问引擎的 ILogin，两种格式一视同仁。
  Future<void> _loadLoginFlags(List<PluginSource> sources) async {
    final repo = ref.read(sourceRepositoryProvider);
    var changed = false;
    for (final s in sources) {
      if (_loginFlags.containsKey(s.id)) continue;
      try {
        final manifest = await repo.readManifest(s);
        final entry = LoginEntry.parse(manifest);
        var has = entry != null && entry.valid;
        if (!has && (s.isTingShu || s.isSsts)) {
          try {
            final engine = engineForSource(ref, s);
            await engine.attach(s);
            final info = await engine.loginInfo();
            has = '${info?['url'] ?? ''}'.trim().isNotEmpty;
          } catch (_) {}
        }
        _loginFlags[s.id] = has;
      } catch (_) {
        _loginFlags[s.id] = false;
      }
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  // ------------------------------------------------------------ 顶部
  // 纠正（2026-11-20）：网格层顶栏不要标题（不要「书源」也不要源名），
  // 不要播放按钮；只留搜索放大镜（进搜索页）和设置齿轮（进设置页）。
  // 列数切换、源管理都不放顶栏（列数由设置页提供，源管理放设置页里）。
  // 背景用主题强调色（AppBarTheme）。
  Widget _appBar(BuildContext context, WidgetRef ref, PluginSource? source) {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: '搜索',
          onPressed: () => _openSearch(context, source),
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: '设置',
          onPressed: () => Navigator.of(context).pushNamed('/settings'),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  // ------------------------------------------------------------ 源组 / 源列表

  /// 分组横条（瘦版）：整条主题主色淡底 + 主色组名居中，
  /// 点一下展开这个分组的源卡片，再点一下收起。默认展开第一个分组。
  /// 颜色跟主题走：底用 primarySoft、字用 primary，深色主题下也是深底亮字。
  Widget _groupBar(BuildContext context, String name, int count, bool open,
      VoidCallback onTap) {
    final bg = context.palette.primarySoft;
    final fg = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const SizedBox(width: 28),
            Expanded(
              child: Text(name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: fg)),
            ),
            Text('$count 个',
                style: TextStyle(fontSize: 11, color: fg)),
            const SizedBox(width: 2),
            Icon(
                open
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: fg),
          ],
        ),
      ),
    );
  }

  /// 源卡片：源名（加粗，可换两行，完整显示不截断）+ 登录标记 + 介绍，两行省略
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
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(s.name,
                      maxLines: 2,
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

  /// 只有搜索能力的源：不摆「暂时没有推荐」大空白卡片，
  /// 改成一行紧凑的搜索入口（「这个源只提供搜索」+「去搜索」按钮）。
  /// 推荐按源实际能力走：推荐 → 分类（点源卡片进内容层看分类）→ 搜索入口。
  Widget _feedEmpty(BuildContext context, WidgetRef ref, PluginSource source) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.palette.outline),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded,
                size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('这个源只提供搜索',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _openSearch(context, source),
              child: const Text('去搜索'),
            ),
          ],
        ),
      ),
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
        cacheWidth: 240,
        cacheHeight: 320,
        filterQuality: FilterQuality.low,
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
