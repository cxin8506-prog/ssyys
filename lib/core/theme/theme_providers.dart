import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../di/providers.dart';

/// 主题模式：0 = 跟随系统（默认）/ 1 = 浅色 / 2 = 深色。
///
/// 旧 bug 已修：以前注释写“默认深色”，代码实际是 `?? 1`（浅色）。
/// 现在注释和代码一致：默认 0（跟随系统），九家对照里默认全是跟随系统。
final themeModeProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  final v = prefs.getInt('theme_mode') ?? 0;
  if (v < 0 || v > 2) return 0;
  return v;
});

/// 主题色：0 暖阳橙 / 1 海蓝 / 2 青竹绿 / 3 樱花粉（默认）。
/// 默认改成樱花粉：这是二次元向 App，第一眼就应该是粉而不是橙。
/// 墨夜（旧下标 4）不开放：读到旧存量 4 时迁移回 3，不再提供入口。
final themeColorProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  final v = prefs.getInt('theme_color') ?? 3;
  if (v < 0 || v > 3) return 3;
  return v;
});

/// 纯黑：默认关；只在深色下显示开关（浅色下藏掉，点了也没效果是旧坑）。
final pureBlackProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('pure_black') ?? false;
});

/// 封面取色：默认开。种子色持久化在 cover_color.dart 里。
final coverColorEnabledProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('cover_colors') ?? true;
});

/// 字体缩放：0.9 小 / 1.0 标准（默认）/ 1.15 大，全站经
/// MediaQuery.textScaleFactor 生效（Flutter 3.0 没有 textScaler，
/// textScaler 是 Flutter 3.13+ 的 API，这里用 3.0 能编过的写法）。
final fontScaleProvider = StateProvider<double>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  final v = prefs.getDouble('font_scale') ?? 1.0;
  if (v == 0.9 || v == 1.0 || v == 1.15) return v;
  return 1.0;
});

/// 跟随壁纸：默认关，只在 Android 12+（SDK 31+）显示。
/// dynamic_color 包不在 pubspec 里（任何代理都不许改依赖），且没有
/// Dart 2.17 兼容版可供安全接入，所以开着也回落到暖阳橙；
/// 主题选择页里会写明这一点，不假装已取到壁纸色。
final wallpaperFollowProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('wallpaper_follow') ?? false;
});

/// 是否 Android 12+（跟随壁纸档只在这种设备上显示）。
/// Dart 侧没有 SDK_INT：用 Platform.operatingSystemVersion 的主版本号
/// 粗判（Android 上形如 "12" / "13"）；解析不到就隐藏，不撒谎显示。
bool get isWallpaperColorSupported {
  if (!Platform.isAndroid) return false;
  final raw = Platform.operatingSystemVersion.trim();
  final first = raw.split(RegExp(r'[^0-9]')).firstWhere(
        (s) => s.isNotEmpty,
        orElse: () => '',
      );
  final major = int.tryParse(first);
  if (major == null) return false;
  return major >= 12;
}

/// 主题模式 0/1/2 → Flutter ThemeMode。墨夜由调用方先行处理。
ThemeMode resolveThemeMode(int mode) {
  switch (mode) {
    case 1:
      return ThemeMode.light;
    case 2:
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

/// 当前是否深色（含跟随系统时的系统深色）。
bool isDarkMode(int mode, bool systemDark) {
  if (mode == 2) return true;
  if (mode == 1) return false;
  return systemDark;
}

/// 写回主题设置（provider + 落盘一起做，避免只改一处）。
Future<void> saveThemeMode(WidgetRef ref, int mode) async {
  ref.read(themeModeProvider.notifier).state = mode;
  final prefs = ref.read(sharedPrefsProvider);
  await prefs.setInt('theme_mode', mode);
}

Future<void> saveThemeColor(WidgetRef ref, int index) async {
  ref.read(themeColorProvider.notifier).state = index;
  final prefs = ref.read(sharedPrefsProvider);
  await prefs.setInt('theme_color', index);
}

Future<void> savePureBlack(WidgetRef ref, bool value) async {
  ref.read(pureBlackProvider.notifier).state = value;
  final prefs = ref.read(sharedPrefsProvider);
  await prefs.setBool('pure_black', value);
}

Future<void> saveCoverColorEnabled(WidgetRef ref, bool value) async {
  ref.read(coverColorEnabledProvider.notifier).state = value;
  final prefs = ref.read(sharedPrefsProvider);
  await prefs.setBool('cover_colors', value);
}

Future<void> saveFontScale(WidgetRef ref, double value) async {
  ref.read(fontScaleProvider.notifier).state = value;
  final prefs = ref.read(sharedPrefsProvider);
  await prefs.setDouble('font_scale', value);
}

Future<void> saveWallpaperFollow(WidgetRef ref, bool value) async {
  ref.read(wallpaperFollowProvider.notifier).state = value;
  final prefs = ref.read(sharedPrefsProvider);
  await prefs.setBool('wallpaper_follow', value);
}

/// 旧存量迁移：主题色 4（墨夜）→ 0（暖阳橙），模式越界 → 0。
Future<void> migrateLegacyTheme(SharedPreferences prefs) async {
  final color = prefs.getInt('theme_color');
  if (color != null && (color < 0 || color > 3)) {
    await prefs.setInt('theme_color', 0);
  }
  final mode = prefs.getInt('theme_mode');
  if (mode != null && (mode < 0 || mode > 2)) {
    await prefs.setInt('theme_mode', 0);
  }
  // 旧版把“默认深色”写进过 theme_mode=1 的迁移标记：1.0.3 之前
  // 新装默认被写成浅色；这次重写默认改为跟随系统，只对从未手动
  // 改过主题的用户迁移（有手动改过的标记不动）。
  final migrated = prefs.getBool('theme_migrated_v2') ?? false;
  if (!migrated) {
    final manuallySet = prefs.getBool('theme_manually_set') ?? false;
    if (!manuallySet) {
      await prefs.setInt('theme_mode', 0);
    }
    await prefs.setBool('theme_migrated_v2', true);
  }
}
