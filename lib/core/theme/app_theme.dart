import 'package:flutter/material.dart';

/// 主题扩展：提供语义化的次级颜色，避免各页面硬编码深色/浅色。
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

/// 一套配色方案（同时给出深色与浅色的具体色值）
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

  /// 内置配色（设置页可切换）：暖阳橙（默认）/ 海蓝 / 青竹绿 / 樱花粉 / 墨夜
  /// 墨夜是独立一套，浅色值也全是黑，一直保持黑色
  static const List<AppScheme> schemes = [
    AppScheme(
      name: '暖阳橙',
      primary: Color(0xFFF08C3A),
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
      lightBg: Color(0xFF000000),
      lightSurface: Color(0xFF0B0B0B),
      lightSurfaceAlt: Color(0xFF161616),
    ),
  ];

  /// 墨夜主题的下标（独立一套，一直保持黑色）
  static const int nightSchemeIndex = 4;

  static AppScheme schemeAt(int index) {
    if (index < 0 || index >= schemes.length) return schemes.first;
    return schemes[index];
  }

  /// 兼容旧代码引用的品牌色（默认青玉）
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

  static ThemeData dark([int schemeIndex = 0]) {
    final s = schemeAt(schemeIndex);
    final palette = AppPalette(
      surfaceAlt: s.darkSurfaceAlt,
      outline: Color.alphaBlend(s.primary.withOpacity(0.14), s.darkSurface),
      subtle: const Color(0xFF9AA8A1),
      primarySoft: s.primary.withOpacity(0.16),
    );
    return _build(
      brightness: Brightness.dark,
      primary: s.primary,
      accent: s.accent,
      bg: s.darkBg,
      surface: s.darkSurface,
      text: darkText,
      sub: darkTextSub,
      palette: palette,
    );
  }

  static ThemeData light([int schemeIndex = 0]) {
    // 墨夜是独立一套，一直保持黑色：浅色主题也直接用深色
    if (schemeIndex == nightSchemeIndex) return dark(schemeIndex);
    final s = schemeAt(schemeIndex);
    final palette = AppPalette(
      surfaceAlt: s.lightSurfaceAlt,
      outline: const Color(0xFFEDE3D8),
      subtle: lightTextSub,
      primarySoft: s.primary.withOpacity(0.14),
    );
    return _build(
      brightness: Brightness.light,
      primary: _darkenForLight(s.primary),
      accent: s.accent,
      bg: s.lightBg,
      surface: s.lightSurface,
      text: lightText,
      sub: lightTextSub,
      palette: palette,
    );
  }

  /// 浅色主题下主色需要压暗一点，否则按钮上的白字对比度不足
  static Color _darkenForLight(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness * 0.74).clamp(0.30, 0.56)).toColor();
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
    final base = ThemeData(
      useMaterial3: false,
      brightness: brightness,
      primaryColor: primary,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: brightness,
      ).copyWith(
        primary: primary,
        secondary: accent,
        surface: surface,
        background: bg,
        error: isDark ? const Color(0xFFFF8A80) : const Color(0xFFD93F35),
      ),
      scaffoldBackgroundColor: bg,
      cardColor: surface,
      canvasColor: bg,
      dividerColor: palette.outline,
      splashFactory: InkRipple.splashFactory,
    );

    return base.copyWith(
      extensions: <ThemeExtension<dynamic>>[palette],
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: sub,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
      ),
      iconTheme: IconThemeData(color: text),
      textTheme: _textTheme(text, sub),
      cardTheme: CardTheme(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.outline, width: 1),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: sub,
        textColor: text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          primary: primary,
          onPrimary: isDark ? Colors.black87 : Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          primary: text,
          side: BorderSide(color: palette.outline),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(primary: primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceAlt,
        hintStyle: TextStyle(color: sub, fontSize: 14),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: palette.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith(
            (s) => s.contains(MaterialState.selected) ? Colors.white : null),
        trackColor: MaterialStateProperty.resolveWith(
            (s) => s.contains(MaterialState.selected) ? primary : null),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? palette.surfaceAlt : const Color(0xFF2C3230),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      dividerTheme: DividerThemeData(color: palette.outline, thickness: 1),
    );
  }

  static TextTheme _textTheme(Color main, Color sub) => TextTheme(
        headlineLarge:
            TextStyle(color: main, fontWeight: FontWeight.bold, fontSize: 28),
        headlineMedium:
            TextStyle(color: main, fontWeight: FontWeight.bold, fontSize: 22),
        titleLarge:
            TextStyle(color: main, fontWeight: FontWeight.w700, fontSize: 18),
        titleMedium:
            TextStyle(color: main, fontWeight: FontWeight.w600, fontSize: 16),
        bodyLarge: TextStyle(color: main, fontSize: 15),
        bodyMedium: TextStyle(color: main, fontSize: 14),
        bodySmall: TextStyle(color: sub, fontSize: 12),
      );
}
