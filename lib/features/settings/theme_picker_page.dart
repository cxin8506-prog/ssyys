import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart';

/// 主题选择：6 套配色 × 3 种明暗模式，带实时预览
class ThemePickerPage extends ConsumerWidget {
  const ThemePickerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final colorIndex = ref.watch(themeColorProvider);
    final prefs = ref.read(sharedPrefsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('主题')),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 32),
        children: [
          Text('配色', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('选一套喜欢的色调，整页界面会跟着变',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.0,
            children: List.generate(AppTheme.schemes.length, (i) {
              final s = AppTheme.schemes[i];
              final selected = i == colorIndex;
              return _SchemeCard(
                scheme: s,
                selected: selected,
                dark: mode != 1,
                onTap: () {
                  ref.read(themeColorProvider.notifier).state = i;
                  prefs.setInt(AppConstants.keyThemeColor, i);
                },
              );
            }),
          ),
          const SizedBox(height: 28),
          Text('明暗模式', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: List.generate(3, (i) {
              final labels = ['跟随系统', '浅色', '深色'];
              final icons = [
                Icons.brightness_auto_outlined,
                Icons.light_mode_outlined,
                Icons.dark_mode_outlined
              ];
              final selected = mode == i;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: i == 2 ? 0 : 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      ref.read(themeModeProvider.notifier).state = i;
                      prefs.setInt(AppConstants.keyThemeMode, i);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: selected
                            ? context.palette.primarySoft
                            : context.cardColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : context.palette.outline,
                          width: selected ? 1.6 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(icons[i],
                              size: 22,
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : context.subtleColor),
                          const SizedBox(height: 8),
                          Text(labels[i],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              )),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 28),
          Text('预览', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _PreviewCard(colorIndex: colorIndex),
        ],
      ),
    );
  }
}

class _SchemeCard extends StatelessWidget {
  final AppScheme scheme;
  final bool selected;
  final bool dark;
  final VoidCallback onTap;

  const _SchemeCard({
    required this.scheme,
    required this.selected,
    required this.dark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = dark ? scheme.darkSurface : scheme.lightSurface;
    final fg = dark ? AppTheme.darkText : AppTheme.lightText;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? scheme.primary : context.palette.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.accent],
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 10),
            Text(scheme.name,
                style: TextStyle(
                    color: selected ? scheme.primary : fg,
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final int colorIndex;
  const _PreviewCard({required this.colorIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.secondary,
                    ],
                  ),
                ),
                child: const Icon(Icons.headphones, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('示例书名',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('作者 · 共 128 章',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.subtleColor),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: 0.42,
              minHeight: 6,
              color: Theme.of(context).colorScheme.primary,
              backgroundColor: context.palette.surfaceAlt,
            ),
          ),
          const SizedBox(height: 8),
          Text('已听 42% · 剩余 3 小时 12 分',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
