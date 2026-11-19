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

/// 首页：继续阅读/播放快捷入口
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(libraryRepositoryProvider);
    final videoEnabled = ref.watch(videoEnabledProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('随意听书')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('继续', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text('接着上次的位置继续听/看', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          _buildContinueSection(
              context, ref, repo, AppConstants.typeAudio, Icons.headphones),
          const SizedBox(height: 24),
          if (videoEnabled) ...[
            _buildContinueSection(
                context, ref, repo, AppConstants.typeVideo, Icons.movie),
          ],
          const SizedBox(height: 24),
          _buildQuickGrid(context),
        ],
      ),
    );
  }

  Widget _buildContinueSection(BuildContext context, WidgetRef ref,
      dynamic repo, String type, IconData icon) {
    return FutureBuilder<List<MediaItem>>(
      future: repo.continueList(type),
      builder: (context, snap) {
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return Card(
            color: AppTheme.darkSurface,
            child: ListTile(
              leading: Icon(icon, color: AppTheme.darkTextSub),
              title:
                  Text(type == AppConstants.typeAudio ? '暂无继续听的书' : '暂无继续看的视频'),
              subtitle: const Text('导入内容后，这里会显示最近进度'),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Icon(icon, color: AppTheme.primary, size: 18),
                const SizedBox(width: 6),
                Text(type == AppConstants.typeAudio ? '继续听' : '继续看',
                    style: Theme.of(context).textTheme.titleMedium),
              ]),
            ),
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) =>
                    _continueCard(context, ref, items[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _continueCard(BuildContext context, WidgetRef ref, MediaItem item) {
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
        width: 96,
        decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Expanded(
                child: CoverImage(
                    path: item.coverPath,
                    title: item.title,
                    size: 70,
                    isVideo: item.isVideo)),
            const SizedBox(height: 4),
            Text(item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
            LinearProgressIndicator(
                value: item.progress > 1 ? item.progress / 100 : item.progress,
                color: AppTheme.primary,
                backgroundColor: AppTheme.darkSurfaceAlt),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickGrid(BuildContext context) {
    // Dart 2.17 兼容：用 List<Map> 代替 record 类型
    final entries = [
      {'label': '听书书架', 'icon': Icons.headphones, 'route': '/audio'},
      {'label': '视频书架', 'icon': Icons.movie, 'route': '/video'},
      {'label': '收藏', 'icon': Icons.favorite_outline, 'route': '/favorites'},
      {'label': '历史', 'icon': Icons.history, 'route': '/history'},
      {'label': '书签', 'icon': Icons.bookmark_outline, 'route': '/bookmarks'},
      {'label': '设置', 'icon': Icons.settings_outlined, 'route': '/settings'},
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: entries.map((e) {
        return InkWell(
          onTap: () => Navigator.of(context).pushNamed(e['route'] as String),
          child: Container(
            decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12)),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(e['icon'] as IconData, color: AppTheme.primary, size: 28),
                const SizedBox(height: 8),
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
