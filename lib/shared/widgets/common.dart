import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 通用小部件：封面、书卡、空状态、说明行、格式化。
///
/// 颜色一律跟主题走，不写死深色/浅色；文字不写死 Colors.white
///（白字 bug 的根因就是颜色没指定、任由默认样式接手）。

String formatDuration(int ms) {
  if (ms <= 0) return '00:00';
  final totalSeconds = ms ~/ 1000;
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:$mm:$ss';
  return '$mm:$ss';
}

String formatDateTime(DateTime? dt) {
  if (dt == null) return '';
  final y = dt.year;
  final mo = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final mi = dt.minute.toString().padLeft(2, '0');
  return '$y-$mo-$d $h:$mi';
}

String formatListen(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h > 0) return '$h 小时 $m 分钟';
  return '$m 分钟';
}

/// 封面：网络图加载失败时显示首字占位，不留空白黑块。
class CoverImage extends StatelessWidget {
  final String? url;
  final String title;
  final double width;
  final double height;
  final double radius;

  const CoverImage({
    super.key,
    this.url,
    required this.title,
    this.width = 78,
    this.height = 104,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.16),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Text(
        title.isEmpty ? '书' : title.characters.first,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontSize: width * 0.32,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: width,
            height: height,
            color: context.palette.surfaceAlt,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      ),
    );
  }
}

/// 空状态：只写真实存在的入口，不写代码里不存在的路径。
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? hint;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.hint,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: context.subtleColor),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.subtleColor),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 分组标题（瘦版横条）。
class SectionTitle extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const SectionTitle({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 带说明的设置行：标题 + 副标题 + 右侧控件 + info 图标（点弹 Dialog）。
class InfoRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String info;
  final Widget? trailing;
  final VoidCallback? onTap;

  const InfoRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.info,
    this.trailing,
    this.onTap,
  });

  /// 设置项左侧小图标：按标题关键词挑，挑不到给个通用点。
  IconData _iconFor(String title) {
    const map = <String, IconData>{
      '主题': Icons.palette_outlined,
      '字体': Icons.format_size_rounded,
      '封面': Icons.image_outlined,
      '壁纸': Icons.wallpaper_rounded,
      '播放': Icons.graphic_eq_rounded,
      '视频': Icons.smart_display_outlined,
      'UA': Icons.public_rounded,
      '聚合': Icons.hub_outlined,
      '精确': Icons.filter_alt_outlined,
      '建议': Icons.tips_and_updates_outlined,
      '并发': Icons.speed_rounded,
      '超时': Icons.timer_outlined,
      '缓存': Icons.download_rounded,
      '备份': Icons.cloud_sync_outlined,
      '源管理': Icons.extension_outlined,
      '云同步': Icons.cloud_outlined,
      'WebDAV': Icons.folder_shared_outlined,
      '日志': Icons.article_outlined,
      '统计': Icons.insights_rounded,
      '通知': Icons.notifications_none_rounded,
      '账号': Icons.person_outline_rounded,
      '关于': Icons.info_outline_rounded,
      '下载': Icons.download_rounded,
      '评论': Icons.forum_outlined,
      '帮助': Icons.help_outline_rounded,
'夜间': Icons.dark_mode_outlined,
    };
    for (final e in map.entries) {
      if (title.contains(e.key)) return e.value;
    }
    return Icons.chevron_right;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.13),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Icon(_iconFor(title), size: 19, color: primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12, color: context.subtleColor),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.info_outline, size: 18),
              color: context.subtleColor,
              tooltip: '说明',
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(title),
                    content: Text(info, style: const TextStyle(fontSize: 14, height: 1.6)),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('知道了'),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    ),
  ),
);
  }
}

/// 首字图标（源卡片用）：42×42 圆角 12，渐变底 + 首字。
class SourceAvatar extends StatelessWidget {
  final String name;
  final double size;

  const SourceAvatar({super.key, required this.name, this.size = 42});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final first = name.isEmpty ? '源' : name.characters.first;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [primary, primary.withOpacity(0.65)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        first,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
