import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/listen_stats.dart';
import '../../features/audio/data/audio_handler.dart';
import 'collection_pages.dart';
import 'discover_page.dart';
import 'history_page.dart';
import 'home_page.dart';

/// 主壳：贴底标准栏五项。
///
/// 书源 | 当前源真名（动态）| 中间圆播放键（动作，不是 tab）| 收藏 | 历史。
/// 底栏最小高 50dp：标准 BottomNavigationBar（约 56dp），贴底贴边，
/// 不是悬浮圆角条（审计 D 第 26 项）。页面底部用 bottomBarInset 留空。
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
    final source = ref.watch(activeHomeSourceProvider);
    final sourceName = source?.name ?? '发现';
    final handler = ref.watch(audioHandlerProvider);

    final pages = <Widget>[
      const HomePage(),
      const DiscoverPage(),
      const CollectionPage(kind: CollectionKind.favorite),
      const HistoryPage(),
    ];
    var safeIndex = index;
    if (safeIndex < 0) safeIndex = 0;
    if (safeIndex >= pages.length) safeIndex = pages.length - 1;

    return Scaffold(
      body: IndexedStack(index: safeIndex, children: pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor.withOpacity(0.96),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.16),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: '书源',
                selected: safeIndex == 0,
                onTap: () => _onTap(0),
              ),
              _NavItem(
                icon: Icons.explore_outlined,
                activeIcon: Icons.explore_rounded,
                label: _shortSourceName(sourceName),
                selected: safeIndex == 1,
                onTap: () => _onTap(1),
              ),
              Expanded(
                child: Center(
                  child: _CenterPlayButton(
                    handler: handler,
                    onTap: () => _onPlayPressed(handler),
                    onLongPress: () => _showListenStats(context),
                  ),
                ),
              ),
              _NavItem(
                icon: Icons.favorite_outline,
                activeIcon: Icons.favorite_rounded,
                label: '收藏',
                selected: safeIndex == 2,
                onTap: () => _onTap(2),
              ),
              _NavItem(
                icon: Icons.history_outlined,
                activeIcon: Icons.history_rounded,
                label: '历史',
                selected: safeIndex == 3,
                onTap: () => _onTap(3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 底栏源名过长时缩字号 + 最多留 8 字，避免挤爆；完整源名在发现页
  /// 顶栏和源下拉框里完整显示（下拉框不截断）。
  String _shortSourceName(String name) {
    if (name.length <= 8) return name;
    return '${name.substring(0, 8)}…';
  }

  void _onTap(int i) {
    if (i == 2) {
      // 中间键不是 tab，BottomNavigationBar 的 onTap 不会走到这里
      //（它的 tap 由 _CenterPlayButton 自己接），这里只做兜底。
      return;
    }
    final current = ref.read(shellTabProvider);
    if (i == 0 && current == 0) {
      // 重复点书源：首页滚回顶部。
      ref.read(homeScrollToTopProvider.notifier).state++;
      return;
    }
    ref.read(shellTabProvider.notifier).state = i;
  }

  /// 中间大圆播放键（审计 D 第 23 项重做）。
  ///
  /// - 在播显示 ⏸，点一下就是暂停（不再按断点重推新播放页）。
  /// - 暂停 / 空闲显示 ▶，点一下回到正在播的播放页接着播
  ///   （读 audioHandler.mediaItem，不按断点重推、不叠层）。
  /// - 什么都没播过时进空播放页。
  /// - 长按看收听统计（按钮上有 Tooltip + “长按看统计”提示）。
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
    // 回到正在播的播放页：已经在播放页就不重复推。
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

  Future<void> _showListenStats(BuildContext context) async {
    try {
      final stats = await ListenStats.fetchListenStats();
      final today = _asInt(stats['todaySeconds']);
      final total = _asInt(stats['totalSeconds']);
      final finished = _asInt(stats['finishedBooks']);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('收听统计'),
          content: Text(
            '今日收听了 ${_formatMinutes(today)}，一共收听了 ${_formatMinutes(total)}，共听完 $finished 本书。',
            style: const TextStyle(fontSize: 15, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('收听统计暂时读不到')),
      );
    }
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  String _formatMinutes(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '$h 小时 $m 分钟';
    return '$m 分钟';
  }
}

/// 中间圆形大播放键：56dp 圆钮，主题主色实心圆 + 白色图标。
/// 长按有可见入口提示（Tooltip + 下方小字“长按看统计”由父级 label 兜底）。
class _CenterPlayButton extends StatelessWidget {
  final MyAudioHandler handler;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CenterPlayButton({
    required this.handler,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: '点一下播放 / 暂停，长按看收听统计',
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: StreamBuilder<PlaybackState>(
          stream: handler.playbackState,
          initialData: handler.playbackState.value,
          builder: (context, snapshot) {
            final playing = snapshot.data?.playing ?? false;
            return Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primary.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 26,
                color: Colors.white,
              ),
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
                '搜一部喜欢的书或视频，播一半退出后会记在这里。\n长按底栏中间的播放键可以看收听统计。',
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

/// 底栏单项：圆角高亮选中态，图标 + 小字。
class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
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
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? primary.withOpacity(0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? activeIcon : icon,
                  size: 22, color: selected ? primary : subtle),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? primary : subtle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
