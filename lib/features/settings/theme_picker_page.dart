import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_providers.dart';
import '../../shared/widgets/common.dart';

/// 主题选择页：4 套配色 + 明暗模式 + 纯黑 + 封面取色 + 字体大小。
///
/// - 墨夜不开放：只展示一张灰掉的卡片（字用浅色，写在深底上看得见），
///   不可点。浅色模式下深字压黑底看不见是审计 A 的颜色 bug。
/// - 纯黑开关只在深色下显示（浅色下藏掉）。
/// - 换主题立即生效，不重启。
class ThemePickerPage extends ConsumerWidget {
  const ThemePickerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeColor = ref.watch(themeColorProvider);
    final themeMode = ref.watch(themeModeProvider);
    final pureBlack = ref.watch(pureBlackProvider);
    final coverEnabled = ref.watch(coverColorEnabledProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final wallpaperFollow = ref.watch(wallpaperFollowProvider);
    final systemDark =
        MediaQuery.of(context).platformBrightness == Brightness.dark;
    final effectiveDark = isDarkMode(themeMode, systemDark);
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('主题与配色')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const Text(
            '主题色',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 84,
            ),
            itemCount: AppTheme.openSchemeCount + 1,
            itemBuilder: (_, i) {
              if (i == AppTheme.openSchemeCount) {
                return const _DisabledNightCard();
              }
              final scheme = AppTheme.schemes[i];
              final selected = themeColor == i;
              return _SchemeCard(
                scheme: scheme,
                selected: selected,
                onTap: () => saveThemeColor(ref, i),
              );
            },
          ),
          const SizedBox(height: 20),
          const Text(
            '明暗模式',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _ThreeWay<int>(
            options: const [
              [0, '跟随系统'],
              [1, '浅色'],
              [2, '深色'],
            ],
            value: themeMode,
            onChanged: (v) => saveThemeMode(ref, v),
          ),
          const SizedBox(height: 8),
          Text(
            '默认跟随系统。换主题立即生效，不用重启；播放器在独立服务里，不用动播放。',
            style: TextStyle(fontSize: 12, color: context.subtleColor),
          ),
          const SizedBox(height: 8),
          // 纯黑开关只在深色下显示（Voice 的做法；浅色下点了没效果是旧坑）。
          if (effectiveDark)
            InfoRow(
              title: '纯黑',
              subtitle: pureBlack ? '开' : '关',
              info: '深色模式下把背景、卡片刷成纯黑，只留主色点缀；容器描边留着，卡片还能分得清。浅色模式下没有这个开关。',
              trailing: Switch(
                value: pureBlack,
                onChanged: (v) => savePureBlack(ref, v),
              ),
            ),
          InfoRow(
            title: '封面取色',
            subtitle: coverEnabled ? '开' : '关',
            info: '播放页的颜色从当前封面取。种子色按封面地址存下来，启动时先恢复，取不到才现算；失败的不缓存，下次重试。',
            trailing: Switch(
              value: coverEnabled,
              onChanged: (v) => saveCoverColorEnabled(ref, v),
            ),
          ),
          if (isWallpaperColorSupported)
            InfoRow(
              title: '跟随壁纸',
              subtitle: wallpaperFollow ? '开' : '关',
              info: 'Android 12+ 才显示：系统给了动态色就用壁纸色重算整套配色。当前版本没有接入 dynamic_color 包（没有 Dart 2.17 兼容版），开着也会回落到暖阳橙。',
              trailing: Switch(
                value: wallpaperFollow,
                onChanged: (v) => saveWallpaperFollow(ref, v),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            '字体大小',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          _ThreeWay<double>(
            options: const [
              [0.9, '小'],
              [1.0, '标准'],
              [1.15, '大'],
            ],
            value: fontScale,
            onChanged: (v) => saveFontScale(ref, v),
          ),
          const SizedBox(height: 8),
          Text(
            '全站生效：首页、书架、播放页、设置页的字号都跟着变。',
            style: TextStyle(fontSize: 12, color: context.subtleColor),
          ),
          const SizedBox(height: 20),
          _PreviewCard(primary: primary),
        ],
      ),
    );
  }
}

/// 三段选择（自绘：Flutter 3.0 还没有分段按钮控件，那是 3.10+ 的）。
class _ThreeWay<T> extends StatelessWidget {
  final List<List<dynamic>> options;
  final T value;
  final ValueChanged<T> onChanged;

  const _ThreeWay({
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        for (final o in options)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  backgroundColor: o[0] == value
                      ? primary.withOpacity(0.16)
                      : null,
                  side: BorderSide(
                    color: o[0] == value
                        ? primary
                        : Theme.of(context).dividerColor,
                  ),
                ),
                onPressed: () => onChanged(o[0] as T),
                child: Text(
                  o[1] as String,
                  style: TextStyle(
                    color: o[0] == value
                        ? primary
                        : Theme.of(context).textTheme.bodyMedium?.color,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SchemeCard extends StatelessWidget {
  final AppScheme scheme;
  final bool selected;
  final VoidCallback onTap;

  const _SchemeCard({
    required this.scheme,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 卡片底色按配色自身的 lightSurface 取，字色必须按卡片实际底色选，
    // 不能按明暗模式选（墨夜 lightSurface 本来就是黑的，旧 bug）。
    final bg = scheme.lightSurface;
    final isBgDark =
        bg.computeLuminance() < 0.3;
    final fg = isBgDark ? Colors.white : AppTheme.lightText;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? scheme.primary
                : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                scheme.name,
                style: TextStyle(
                  color: selected ? scheme.primary : fg,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 墨夜卡片：已禁用，不可点；深底配浅字，保证看得见。
class _DisabledNightCard extends StatelessWidget {
  const _DisabledNightCard();

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemes[AppTheme.nightSchemeIndex];
    return Opacity(
      opacity: 0.6,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.lightSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '墨夜 · 已禁用',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final Color primary;

  const _PreviewCard({required this.primary});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CoverImage(
                    url: null, title: '示例书名', width: 48, height: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '示例书名',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text('作者 · 共 128 章', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: 0.42,
              backgroundColor: context.palette.surfaceAlt,
              valueColor: AlwaysStoppedAnimation<Color>(primary),
            ),
            const SizedBox(height: 6),
            Text(
              '已听 42% · 剩余 3 小时 12 分',
              style: TextStyle(fontSize: 12, color: context.subtleColor),
            ),
          ],
        ),
      ),
    );
  }
}
