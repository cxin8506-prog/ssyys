import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../plugins/data/home_feed.dart';
import '../../plugins/data/plugin_providers.dart';
import '../../plugins/model/plugin_source.dart';
import '../../plugins/presentation/source_book_page.dart';
import '../../plugins/presentation/source_picker_sheet.dart';
import '../../plugins/presentation/source_search_page.dart';
import '../../shared/widgets/common.dart';
import '../audio/data/repository_providers.dart';
import '../audio/domain/media_item.dart';
import '../audio/presentation/audio_player_page.dart';
import '../video/presentation/video_player_page.dart';

/// 首页：左上角切源 + 源提供的推荐内容
///
/// 布局参考主流听书 App：
///   顶部大标题（当前源，点开是网格选源面板） → 搜索框 → 继续收听 → 推荐板块网格
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(activeHomeSourceProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _appBar(context, ref, source),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              sliver: SliverToBoxAdapter(child: _searchEntry(context, source)),
            ),
            SliverToBoxAdapter(child: _continueSection(context, ref)),
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

  // ------------------------------------------------------------ 顶部

  Widget _appBar(BuildContext context, WidgetRef ref, PluginSource? source) {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 64,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      titleSpacing: 16,
      title: _SourceTitle(
        source: source,
        onTap: () => pickHomeSource(context, ref, currentId: source?.id),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: '搜索',
          onPressed: () => _openSearch(context, source),
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  /// 标题前的短竖条
  Widget _bar(BuildContext context) => Container(
        width: 3,
        height: 15,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _searchEntry(BuildContext context, PluginSource? source) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _openSearch(context, source),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 19, color: context.subtleColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                source == null
                    ? '搜索书名 / 作者'
                    : '在「${source.name}」里搜索',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.5, color: context.subtleColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 继续收听

  Widget _continueSection(BuildContext context, WidgetRef ref) {
    final videoEnabled = ref.watch(videoEnabledProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
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
        ),
        const SizedBox(height: 10),
        _continueRow(context, ref, AppConstants.typeAudio),
        if (videoEnabled) ...[
          const SizedBox(height: 10),
          _continueRow(context, ref, AppConstants.typeVideo),
        ],
      ],
    );
  }

  Widget _continueRow(BuildContext context, WidgetRef ref, String type) {
    final isAudio = type == AppConstants.typeAudio;
    final source = ref.watch(activeHomeSourceProvider);
    final async = ref.watch(continueListProvider(type));

    return async.when(
      loading: () => const SizedBox(height: 52),
      error: (_, __) => const SizedBox(height: 52),
      data: (items) {
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.palette.outline),
              ),
              child: Row(
                children: [
                  Icon(isAudio ? Icons.headphones : Icons.movie_outlined,
                      size: 18, color: context.subtleColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isAudio ? '还没有在听的书' : '还没有在看的视频',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontSize: 12.5),
                    ),
                  ),
                  InkWell(
                    onTap: () => _openSearch(context, source),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 4),
                      child: Text('去找',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: Theme.of(context).colorScheme.primary)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return SizedBox(
          height: 152,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _continueCard(context, ref, items[i]),
          ),
        );
      },
    );
  }

  Widget _continueCard(BuildContext context, WidgetRef ref, MediaItem item) {
    final p = item.progress > 1 ? item.progress / 100 : item.progress;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final chapters =
            await ref.read(libraryRepositoryProvider).chapters(item.id);
        if (chapters.isEmpty) return;
        if (item.isAudio) {
          await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AudioPlayerPage(item: item)));
        } else {
          final paths = chapters.map((c) => c.path!).toList();
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => VideoPlayerPage(
                  path: paths.first, playlist: paths, title: item.title)));
        }
        // 回来后刷新进度
        ref.invalidate(continueListProvider(item.isAudio
            ? AppConstants.typeAudio
            : AppConstants.typeVideo));
      },
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(9),
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
                size: 56,
                isVideo: item.isVideo),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color)),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: p,
                      minHeight: 3,
                      color: Theme.of(context).colorScheme.primary,
                      backgroundColor: context.palette.surfaceAlt,
                    ),
                  ),
                ],
              ),
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
      return [
        SliverToBoxAdapter(child: _noSource(context, ref)),
      ];
    }

    final async = ref.watch(homeFeedProvider(source.id));

    // 只画一次标题：单板块用「为你推荐」，多板块用各自的标题
    return [
      const SliverToBoxAdapter(child: SizedBox(height: 26)),
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
      message: msg.length > 120 ? '${msg.substring(0, 120)}…' : msg,
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
    ref.invalidate(continueListProvider(AppConstants.typeAudio));
    ref.invalidate(continueListProvider(AppConstants.typeVideo));
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
                    source?.name ?? AppConstants.appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 22, color: context.subtleColor),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              source == null ? '点这里导入源' : '点一下切换源',
              style: TextStyle(fontSize: 10.5, color: context.subtleColor),
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
