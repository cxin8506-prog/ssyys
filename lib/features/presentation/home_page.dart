import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart';
import '../audio/data/repository_providers.dart';
import '../audio/domain/media_item.dart';
import '../audio/presentation/audio_player_page.dart';
import '../video/presentation/video_player_page.dart';
import '../../plugins/presentation/source_switcher.dart';

/// 首页：顶部渐变卡 + 继续播放 + 快捷入口
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(libraryRepositoryProvider);
    final videoEnabled = ref.watch(videoEnabledProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 132,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
            title: Text(AppConstants.appName,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            flexibleSpace: const FlexibleSpaceBar(
              background: _Header(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _searchEntry(context),
                const SizedBox(height: 14),
                SourceSwitcher(type: AppConstants.typeAudio),
                const SizedBox(height: 18),
                _sectionTitle(context, '继续', '接着上次的位置继续听 / 看'),
                const SizedBox(height: 12),
                _buildContinueSection(context, ref, repo,
                    AppConstants.typeAudio, Icons.headphones),
                if (videoEnabled) ...[
                  const SizedBox(height: 20),
                  _buildContinueSection(context, ref, repo,
                      AppConstants.typeVideo, Icons.movie_outlined),
                ],
                const SizedBox(height: 26),
                _sectionTitle(context, '快捷入口', null),
                const SizedBox(height: 12),
                _buildQuickGrid(context, videoEnabled),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchEntry(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).pushNamed('/source-search'),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.palette.outline),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 19, color: context.subtleColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text('搜索书名 / 作者',
                  style: TextStyle(
                      fontSize: 14, color: context.subtleColor)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: context.palette.primarySoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('源搜索',
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, String? sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(sub, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      );

  Widget _buildContinueSection(BuildContext context, WidgetRef ref,
      dynamic repo, String type, IconData icon) {
    final isAudio = type == AppConstants.typeAudio;
    return FutureBuilder<List<MediaItem>>(
      future: repo.continueList(type),
      builder: (context, snap) {
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.palette.outline),
            ),
            child: Row(
              children: [
                Icon(icon, color: context.subtleColor, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isAudio ? '还没有在听的书' : '还没有在看的视频',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pushNamed('/sources'),
                  child: const Text('去添加源'),
                ),
              ],
            ),
          );
        }
        return SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
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
    return GestureDetector(
      onTap: () async {
        final chapters =
            await ref.read(libraryRepositoryProvider).chapters(item.id);
        if (chapters.isEmpty) return;
        if (item.isAudio) {
          Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AudioPlayerPage(item: item)));
        } else {
          final paths = chapters.map((c) => c.path!).toList();
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => VideoPlayerPage(
                  path: paths.first, playlist: paths, title: item.title)));
        }
      },
      child: Container(
        width: 104,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.palette.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: CoverImage(
                    path: item.coverPath,
                    title: item.title,
                    size: 62,
                    isVideo: item.isVideo),
              ),
            ),
            const SizedBox(height: 8),
            Text(item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                  value: p,
                  minHeight: 4,
                  color: Theme.of(context).colorScheme.primary,
                  backgroundColor: context.palette.surfaceAlt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickGrid(BuildContext context, bool videoEnabled) {
    final entries = <Map<String, dynamic>>[
      {'label': '源管理', 'icon': Icons.extension_outlined, 'route': '/sources'},
      {'label': '听书书架', 'icon': Icons.headphones, 'route': '/audio'},
      if (videoEnabled)
        {'label': '视频书架', 'icon': Icons.movie_outlined, 'route': '/video'},
      {'label': '收藏', 'icon': Icons.favorite_outline, 'route': '/favorites'},
      {'label': '历史', 'icon': Icons.history, 'route': '/history'},
      {'label': '书签', 'icon': Icons.bookmark_outline, 'route': '/bookmarks'},
      {'label': '设置', 'icon': Icons.settings_outlined, 'route': '/settings'},
    ];
    final primary = Theme.of(context).colorScheme.primary;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.08,
      children: entries.map((e) {
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(context).pushNamed(e['route'] as String),
          child: Container(
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.palette.outline),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: context.palette.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(e['icon'] as IconData, color: primary, size: 20),
                ),
                const SizedBox(height: 9),
                Text(e['label'] as String,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// 顶部渐变卡
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 56, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withOpacity(0.92),
            Color.alphaBlend(secondary.withOpacity(0.55), primary),
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text('随意听书',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('本地优先 · 插件扩展 · 无账号',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(16),
            ),
            child:
                const Icon(Icons.graphic_eq, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }
}
