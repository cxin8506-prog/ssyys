import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../audio/presentation/audio_library_page.dart';
import '../video/presentation/video_library_page.dart';

/// 书架：听书 / 视频 两个内嵌分栏（参考主流阅读类 App 的书架结构）
class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videoEnabled = ref.watch(videoEnabledProvider);
    final primary = Theme.of(context).colorScheme.primary;

    if (!videoEnabled) {
      return const AudioLibraryPage();
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('书架'),
          bottom: TabBar(
            indicatorColor: primary,
            indicatorSize: TabBarIndicatorSize.label,
            labelColor: primary,
            unselectedLabelColor: context.subtleColor,
            labelStyle: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 15),
            tabs: const [
              Tab(text: '听书'),
              Tab(text: '视频'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AudioLibraryPage(embedded: true),
            VideoLibraryPage(embedded: true),
          ],
        ),
      ),
    );
  }
}
