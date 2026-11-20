import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// 「梦幻紫樱」皮肤的基础件：渐变底、柔光卡、图标徽章、胶囊搜索、胶囊 tab。
///
/// 只做样式，不碰业务；所有颜色都从 Theme 里取，换主题自动跟着变。

/// 页面背景：顶部主色 → 次色 → 背景色的淡紫渐变。
class GradientBackdrop extends StatelessWidget {
  final Widget child;
  final double? topOpacity;

  const GradientBackdrop({super.key, required this.child, this.topOpacity});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final op = topOpacity ?? (dark ? 0.22 : 0.30);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.primary.withOpacity(op),
                scheme.secondary.withOpacity(dark ? 0.14 : 0.22),
                bg,
                bg,
              ],
              stops: const [0.0, 0.18, 0.42, 1.0],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// 柔光卡：白底(暗色为卡片色)、20 圆角、极淡投影。
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final double radius;

  const SoftCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.color,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final body = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: body,
    );
  }
}

/// 渐变圆角图标徽章（设置项左侧那种小方块）。
class IconBadge extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color? color;
  final bool filled;

  const IconBadge({
    super.key,
    required this.icon,
    this.size = 40,
    this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: filled
            ? LinearGradient(
                colors: [c, c.withOpacity(0.72)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: filled ? null : c.withOpacity(0.13),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.5, color: filled ? Colors.white : c),
    );
  }
}

/// 胶囊搜索框：白底 + 柔和投影 + 搜索图标。
class PillSearch extends StatelessWidget {
  final String hint;
  final VoidCallback onTap;
  final IconData rightIcon;

  const PillSearch({
    super.key,
    required this.hint,
    required this.onTap,
    this.rightIcon = Icons.tune_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: primary.withOpacity(0.12),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 21, color: context.subtleColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: context.subtleColor),
              ),
            ),
            Icon(rightIcon, size: 20, color: primary.withOpacity(0.75)),
          ],
        ),
      ),
    );
  }
}

/// 圆形图标按钮（顶栏齿轮/铃铛）。
class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;

  const CircleIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 38,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: primary.withOpacity(0.14),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, size: size * 0.52, color: primary),
      ),
    );
  }
}

/// 胶囊 tab 组：选中项白底投影，未选中透明。
class PillTabs extends StatelessWidget {
  final List<PillTabItem> items;
  final String value;
  final ValueChanged<String> onChanged;

  const PillTabs({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      height: 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.palette.primarySoft,
        borderRadius: BorderRadius.circular(19),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.map((e) {
          final selected = value == e.key;
          return GestureDetector(
            onTap: () => onChanged(e.key),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Theme.of(context).cardColor : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: primary.withOpacity(0.16),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : null,
              ),
              child: Text(
                e.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? primary : context.subtleColor,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class PillTabItem {
  final String key;
  final String label;

  const PillTabItem(this.key, this.label);
}

/// 章节/分区小标题：左边小图标 + 标题，右边可选「查看全部 ›」。
class SectionHeader extends StatelessWidget {
  final String title;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 14, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: primary),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Text(
                    actionLabel!,
                    style: TextStyle(fontSize: 12, color: context.subtleColor),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: context.subtleColor),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 吉祥物小气泡：「嗨，今天也来听个好故事吧～」。
class MascotBubble extends StatelessWidget {
  final String text;
  final IconData icon;

  const MascotBubble({
    super.key,
    required this.text,
    this.icon = Icons.headphones_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 190),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor.withOpacity(0.9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            text,
            style: TextStyle(fontSize: 12, height: 1.4, color: context.subtleColor),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [primary.withOpacity(0.85), Theme.of(context).colorScheme.secondary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: primary.withOpacity(0.22),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ],
    );
  }
}

/// 虚线分隔（书架一隅那种贴纸感）。
class DashedDivider extends StatelessWidget {
  final Color? color;

  const DashedDivider({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.palette.outline;
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / 8).floor();
        return Row(
          children: List.generate(
            count,
            (_) => Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                color: c.withOpacity(0.55),
              ),
            ),
          ),
        );
      },
    );
  }
}
