import 'package:flutter/material.dart';

/// 主题扩展：语义化次级颜色，避免各页面硬编码深色/浅色。
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  /// 次级背景（输入框、进度条底、标签底）
  final Color surfaceAlt;

  /// 描边
  final Color outline;

  /// 次级文字（说明、时间、计数）
  final Color subtle;

  /// 主色的低饱和底（选中态、徽标底）
  final Color primarySoft;

  const AppPalette({
    required this.surfaceAlt,
    required this.outline,
    required this.subtle,
    required this.primarySoft,
  });

  @override
  AppPalette copyWith({
    Color? surfaceAlt,
    Color? outline,
    Color? subtle,
    Color? primarySoft,
  }) =>
      AppPalette(
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        outline: outline ?? this.outline,
        subtle: subtle ?? this.subtle,
        primarySoft: primarySoft ?? this.primarySoft,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      subtle: Color.lerp(subtle, other.subtle, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
    );
  }
}

/// 一套配色方案（同时给出深色与浅色的具体色值）。
class AppScheme {
  final String name;
  final Color primary;
  final Color accent;
  final Color darkBg;
  final Color darkSurface;
  final Color darkSurfaceAlt;
  final Color lightBg;
  final Color lightSurface;
  final Color lightSurfaceAlt;

  const AppScheme({
    required this.name,
    required this.primary,
    required this.accent,
    required this.darkBg,
    required this.darkSurface,
    required this.darkSurfaceAlt,
    required this.lightBg,
    required this.lightSurface,
    required this.lightSurfaceAlt,
  });
}

/// 便捷访问：context.palette.surfaceAlt
extension AppThemeContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppTheme.fallbackPalette;

  /// 卡片底色（跟随主题，不要在页面里写死深色）
  Color get cardColor => Theme.of(this).cardColor;

  /// 次级文字色
  Color get subtleColor =>
      Theme.of(this).textTheme.bodySmall?.color ?? palette.subtle;
}

class AppTheme {
  AppTheme._();

  /// 内置配色：暖阳橙（默认）/ 海蓝 / 青竹绿 / 樱花粉 / 墨夜。
  /// 墨夜已禁用（不开放选择）：只保留定义，供旧存量值迁移回落时
  /// 强制走深色；主题选择页不提供墨夜入口。
  static const List<AppScheme> schemes = [
    AppScheme(
      name: '暖阳橙',
      primary: Color(0xFFFF6B4A),
      accent: Color(0xFFFFB877),
      darkBg: Color(0xFF14100C),
      darkSurface: Color(0xFF1F1913),
      darkSurfaceAlt: Color(0xFF2B231A),
      lightBg: Color(0xFFFBF6F0),
      lightSurface: Color(0xFFFFFFFF),
      lightSurfaceAlt: Color(0xFFF6EADF),
    ),
    AppScheme(
      name: '海蓝',
      primary: Color(0xFF5AA9FF),
      accent: Color(0xFF7DE2D1),
      darkBg: Color(0xFF0C1220),
      darkSurface: Color(0xFF161F33),
      darkSurfaceAlt: Color(0xFF202C46),
      lightBg: Color(0xFFF2F6FD),
      lightSurface: Color(0xFFFFFFFF),
      lightSurfaceAlt: Color(0xFFE6EEFB),
    ),
    AppScheme(
      name: '青竹绿',
      primary: Color(0xFF3E9B6E),
      accent: Color(0xFF8FD0A8),
      darkBg: Color(0xFF0E130F),
      darkSurface: Color(0xFF171F19),
      darkSurfaceAlt: Color(0xFF222C24),
      lightBg: Color(0xFFF3F8F4),
      lightSurface: Color(0xFFFFFFFF),
      lightSurfaceAlt: Color(0xFFE4F0E8),
    ),
    AppScheme(
      name: '樱花粉',
      primary: Color(0xFFFF7FA8),
      accent: Color(0xFFFFC46B),
      darkBg: Color(0xFF150F14),
      darkSurface: Color(0xFF231A21),
      darkSurfaceAlt: Color(0xFF32252E),
      lightBg: Color(0xFFFDF4F7),
      lightSurface: Color(0xFFFFFFFF),
      lightSurfaceAlt: Color(0xFFFBE6EE),
    ),
    AppScheme(
      name: '墨夜',
      primary: Color(0xFFB8BEC9),
      accent: Color(0xFF7E8694),
      darkBg: Color(0xFF000000),
      darkSurface: Color(0xFF0B0B0B),
      darkSurfaceAlt: Color(0xFF161616),
      // 注意：墨夜的浅色值也是黑的（一直保持黑色）。配色卡上的文字
      // 颜色必须按卡片实际底色选，不能按明暗模式选，否则浅色模式下
      // 深字压黑底看不见（审计 A 补充第 1 项）。主题选择页里墨夜卡
      // 已禁用，展示时强制用浅色字。
      lightBg: Color(0xFF000000),
      lightSurface: Color(0xFF0B0B0B),
      lightSurfaceAlt: Color(0xFF161616),
    ),
  ];

  /// 开放选择的配色数量（0..3）。下标 4（墨夜）不开放。
  static const int openSchemeCount = 4;

  /// 墨夜主题的下标（独立一套，一直保持黑色）
  static const int nightSchemeIndex = 4;

  static AppScheme schemeAt(int index) {
    if (index < 0 || index >= schemes.length) return schemes.first;
    return schemes[index];
  }

  /// 兼容旧代码引用的品牌色
  static Color get primary => schemes.first.primary;
  static Color get primaryDark => schemes.first.primary;
  static Color get accent => schemes.first.accent;

  static const AppPalette fallbackPalette = AppPalette(
    surfaceAlt: Color(0xFF223028),
    outline: Color(0xFF2E3B34),
    subtle: Color(0xFF9AA8A1),
    primarySoft: Color(0x333DD9A4),
  );

  static const Color darkText = Color(0xFFECEFF1);
  static const Color darkTextSub = Color(0xFF9AA0A6);
  static const Color lightText = Color(0xFF2A2724);
  static const Color lightTextSub = Color(0xFF837A70);

  static ThemeData dark([int schemeIndex = 0, bool pureBlack = false]) {
    final s = schemeAt(schemeIndex);
    // 纯黑（Voice pureBlack）：只刷背景系（背景/卡片/最低层），
    // 容器描边和主色点缀留着，别全刷黑导致卡片分不清。
    final bg = pureBlack ? const Color(0xFF000000) : s.darkBg;
    final surface = pureBlack ? const Color(0xFF0B0B0B) : s.darkSurface;
    final surfaceAlt = pureBlack ? const Color(0xFF161616) : s.darkSurfaceAlt;
    final palette = AppPalette(
      surfaceAlt: surfaceAlt,
      outline: Color.alphaBlend(s.primary.withOpacity(0.14), surface),
      subtle: const Color(0xFF9AA8A1),
      primarySoft: s.primary.withOpacity(0.16),
    );
    return _build(
      brightness: Brightness.dark,
      primary: s.primary,
      accent: s.accent,
      bg: bg,
      surface: surface,
      text: darkText,
      sub: darkTextSub,
      palette: palette,
    );
  }

  static ThemeData light([int schemeIndex = 0]) {
    final s = schemeAt(schemeIndex);
    // 墨夜强制走深色：浅色值也是黑的，浅色主题下整页会全黑。
    if (schemeIndex == nightSchemeIndex) return dark(schemeIndex);
    // 浅色主题下主色按 HSL 亮度压暗，否则按钮上的白字对比度不够。
    final primary = _darkenForLight(s.primary);
    final palette = AppPalette(
      surfaceAlt: s.lightSurfaceAlt,
      outline: Color.alphaBlend(primary.withOpacity(0.16), s.lightSurface),
      subtle: lightTextSub,
      primarySoft: primary.withOpacity(0.12),
    );
    return _build(
      brightness: Brightness.light,
      primary: primary,
      accent: s.accent,
      bg: s.lightBg,
      surface: s.lightSurface,
      text: lightText,
      sub: lightTextSub,
      palette: palette,
    );
  }

  static Color _darkenForLight(Color c) {
    final hsl = HSLColor.fromColor(c);
    final l = (hsl.lightness * 0.74).clamp(0.0, 1.0);
    return hsl.withLightness(l).toColor();
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color primary,
    required Color accent,
    required Color bg,
    required Color surface,
    required Color text,
    required Color sub,
    required AppPalette palette,
  }) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: Colors.white,
      secondary: accent,
      onSecondary: isDark ? Colors.black : Colors.white,
      error: const Color(0xFFD32F2F),
      onError: Colors.white,
      background: bg,
      onBackground: text,
      surface: surface,
      onSurface: text,
    );
    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      primaryColor: primary,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      cardColor: surface,
      dividerColor: palette.outline,
      extensions: <ThemeExtension<dynamic>>[palette],
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        toolbarTextStyle: TextStyle(color: Colors.white, fontSize: 15),
      ),
      // 底栏：贴底标准栏，图标与文字都跟主题走，不写死颜色。
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: sub,
        selectedLabelStyle:
            const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(color: text, fontSize: 20),
        titleMedium: TextStyle(color: text, fontSize: 16),
        titleSmall: TextStyle(color: text, fontSize: 14),
        bodyLarge: TextStyle(color: text, fontSize: 15),
        bodyMedium: TextStyle(color: text, fontSize: 14),
        bodySmall: TextStyle(color: sub, fontSize: 12),
        labelLarge: TextStyle(color: text, fontSize: 13),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return Colors.white;
          return isDark ? const Color(0xFF8A8A8A) : const Color(0xFFBDBDBD);
        }),
        trackColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return primary;
          return isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0);
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: palette.surfaceAlt,
        thumbColor: primary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceAlt,
        selectedColor: primary.withOpacity(0.16),
        labelStyle: TextStyle(color: text, fontSize: 13),
        secondaryLabelStyle: TextStyle(color: text, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      tabBarTheme: TabBarTheme(
        labelColor: primary,
        unselectedLabelColor: sub,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: primary, width: 3),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF2B2B2B) : const Color(0xFF323232),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),
    );
  }
}
