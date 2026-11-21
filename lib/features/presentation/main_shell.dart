import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../features/audio/data/audio_handler.dart';
import 'collection_pages.dart';
import 'discover_page.dart';
import 'history_page.dart';
import 'home_page.dart';

/// 主壳：悬浮胶囊底栏。
///
/// 五项：首页 | 发现 | 中间圆播放键（动作，不是 tab）| 收藏 | 历史。
/// 白色大圆角浮条 + 柔光投影，选中项主色浅底圆角块；中间播放键凸起。
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  bool _goingToPlayer = false;

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(shellTabProvider);
    final handler = ref.watch(audioHandlerProvider);

    const pages = <Widget>[
      HomePage(),
      DiscoverPage(),
      CollectionPage(kind: CollectionKind.favorite),
      HistoryPage(),
    ];
    var safeIndex = index;
    if (safeIndex < 0) safeIndex = 0;
    if (safeIndex >= pages.length) safeIndex = pages.length - 1;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: safeIndex, children: pages),
      bottomNavigationBar: _FloatingBar(
        selectedIndex: safeIndex,
        onTapTab: _onTap,
        onPlay: () => _onPlayPressed(handler),
        handler: handler,
      ),
    );
  }

  void _onTap(int i) {
    final current = ref.read(shellTabProvider);
    if (i == 0 && current == 0) {
      // 重复点首页：滚回顶部。
      ref.read(homeScrollToTopProvider.notifier).state++;
      return;
    }
    ref.read(shellTabProvider.notifier).state = i;
  }

  /// 中间大圆播放键：在播点一下暂停；空闲/暂停回到正在播的播放页。
  Future<void> _onPlayPressed(MyAudioHandler handler) async {
    final playing = handler.playbackState.value.playing;
    if (playing) {
      await handler.pause();
      return;
    }
    final current = handler.mediaItem.value;
    if (current == null) {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EmptyPlayerPage()),
      );
      return;
    }
    if (GoRouter.of(context).location == '/player') return;
    if (_goingToPlayer) return;
    _goingToPlayer = true;
    try {
      if (!mounted) return;
      context.push('/player');
    } finally {
      _goingToPlayer = false;
    }
  }
}

/// 悬浮胶囊底栏：白底大圆角 + 柔光投影，五项布局。
class _FloatingBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTapTab;
  final VoidCallback onPlay;
  final MyAudioHandler handler;

  const _FloatingBar({
    required this.selectedIndex,
    required this.onTapTab,
    required this.onPlay,
    required this.handler,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, safeBottom + 10),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: primary.withOpacity(0.18),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            _BarItem(
              icon: Icons.home_outlined,
              activeIcon: Icons.home_rounded,
              label: '首页',
              selected: selectedIndex == 0,
              onTap: () => onTapTab(0),
            ),
            _BarItem(
              icon: Icons.explore_outlined,
              activeIcon: Icons.explore_rounded,
              label: '发现',
              selected: selectedIndex == 1,
              onTap: () => onTapTab(1),
            ),
            _CenterPlayButton(handler: handler, onTap: onPlay),
            _BarItem(
              icon: Icons.favorite_outline,
              activeIcon: Icons.favorite_rounded,
              label: '收藏',
              selected: selectedIndex == 2,
              onTap: () => onTapTab(2),
            ),
            _BarItem(
              icon: Icons.history_outlined,
              activeIcon: Icons.history_rounded,
              label: '历史',
              selected: selectedIndex == 3,
              onTap: () => onTapTab(3),
            ),
          ],
        ),
      ),
    );
  }
}

/// 底栏单项：图标 + 小字，选中主色浅底圆角块。
class _BarItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _BarItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final subtle = Theme.of(context).textTheme.bodySmall?.color;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: selected ? primary.withOpacity(0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                selected ? activeIcon : icon,
                size: 22,
                color: selected ? primary : subtle,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? primary : subtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 中间圆形大播放键：主题主色实心圆 + 白色图标，在播显示暂停。
class _CenterPlayButton extends StatelessWidget {
  final MyAudioHandler handler;
  final VoidCallback onTap;

  const _CenterPlayButton({required this.handler, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          initialData: handler.playbackState.value,
          builder: (context, snapshot) {
            final playing = snapshot.data?.playing ?? false;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: primary.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 26,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '播放',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 什么都没播过时打开的空播放页。
class EmptyPlayerPage extends StatelessWidget {
  const EmptyPlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('播放器')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_circle_outline,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              const Text('还没有在播的内容', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Text(
                '搜一部喜欢的书或视频，播一半退出后会记在这里。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () => context.push('/search'),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('去找'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
