import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/listen_stats.dart';

/// 左侧抽屉：源管理 / 设置 / 备份 / 源搜索 / 收听统计（所有主页面共用）
Drawer buildAppDrawer(BuildContext context) {
  final primary = Theme.of(context).colorScheme.primary;
  return Drawer(
    child: SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: primary),
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.headphones, size: 40, color: Colors.white),
                const SizedBox(height: 10),
                Text('随意听书',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: Colors.white)),
              ],
            ),
          ),
          _drawerTile(context, Icons.extension_outlined, '源管理',
              () => Navigator.of(context).pushNamed('/sources')),
          _drawerTile(context, Icons.settings_outlined, '设置',
              () => Navigator.of(context).pushNamed('/settings')),
          _drawerTile(context, Icons.backup_outlined, '备份与恢复',
              () => Navigator.of(context).pushNamed('/backup')),
          _drawerTile(context, Icons.travel_explore, '源搜索',
              () => Navigator.of(context).pushNamed('/source-search')),
          _drawerTile(context, Icons.bar_chart_outlined, '收听统计',
              () => ListenStats.showDialog(context)),
        ],
      ),
    ),
  );
}

Widget _drawerTile(
    BuildContext context, IconData icon, String title, VoidCallback onTap) {
  return ListTile(
    leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
    title: Text(title),
    onTap: () {
      Navigator.of(context).pop();
      onTap();
    },
  );
}

/// 滚动页面的统一内边距。
///
/// 全面屏（edge-to-edge）下 Scaffold 不会自动避让系统导航条/手势条，
/// 滚动内容如果只写固定 bottom，最后一块会被压住。这里统一加上安全区。
EdgeInsets pagePadding(
  BuildContext context, {
  double left = 16,
  double top = 12,
  double right = 16,
  double bottom = 28,
}) {
  final safeBottom = MediaQuery.of(context).padding.bottom;
  return EdgeInsets.fromLTRB(left, top, right, bottom + safeBottom);
}

/// 底部固定悬浮元素的避让高度（系统手势条 + 悬浮导航条）
double bottomBarInset(BuildContext context, {double extra = 0}) =>
    MediaQuery.of(context).padding.bottom + extra;

/// 封面图：有路径显示图片，否则显示占位首字
class CoverImage extends StatelessWidget {
  final String? path;
  final String title;
  final double size;
  final bool isVideo;

  const CoverImage({
    super.key,
    this.path,
    required this.title,
    this.size = 64,
    this.isVideo = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasCover =
        path != null && path!.isNotEmpty && File(path!).existsSync();
    return Container(
      width: size,
      height: size * 1.35,
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasCover
          ? Image.file(File(path!),
              fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(context))
          : _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            isVideo ? Icons.movie_outlined : Icons.headphones_outlined,
            size: size * 0.4,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.55),
          ),
          Positioned(
            bottom: 6,
            child: Text(
              title.isEmpty ? '?' : title.substring(0, 1),
              style: TextStyle(color: context.subtleColor, fontSize: 11),
            ),
          ),
        ],
      );
}

/// 空状态提示
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? hint;
  final VoidCallback? onAction;
  final String? actionLabel;

  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.hint,
    this.onAction,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: context.subtleColor.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(hint!,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center),
            ],
            if (onAction != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                  onPressed: onAction, child: Text(actionLabel ?? '添加')),
            ],
          ],
        ),
      ),
    );
  }
}

/// 简单加载指示
class LoadingOverlay extends StatelessWidget {
  final String message;
  const LoadingOverlay({super.key, this.message = '处理中...'});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(message, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
