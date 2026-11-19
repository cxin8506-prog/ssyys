import 'package:flutter/material.dart';

/// 应用主题：深色优先，简洁现代
class AppTheme {
  AppTheme._();

  // 品牌主色（青绿色，沉稳）
  static const Color primary = Color(0xFF4DD0A7);
  static const Color primaryDark = Color(0xFF26A17B);
  static const Color accent = Color(0xFFFFB74D);

  // 深色配色
  static const Color darkBg = Color(0xFF121417);
  static const Color darkSurface = Color(0xFF1C1F24);
  static const Color darkSurfaceAlt = Color(0xFF262A31);
  static const Color darkText = Color(0xFFECEFF1);
  static const Color darkTextSub = Color(0xFF9AA0A6);

  // 浅色配色
  static const Color lightBg = Color(0xFFF5F7F8);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightText = Color(0xFF1A1C1E);
  static const Color lightTextSub = Color(0xFF5F6368);

  static ThemeData get dark => ThemeData(
        useMaterial3: false,
        brightness: Brightness.dark,
        primaryColor: primary,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          secondary: accent,
          surface: darkSurface,
          background: darkBg,
          error: Color(0xFFE57373),
        ),
        scaffoldBackgroundColor: darkBg,
        cardColor: darkSurface,
        canvasColor: darkSurface,
        dividerColor: darkSurfaceAlt,
        appBarTheme: const AppBarTheme(
          backgroundColor: darkBg,
          foregroundColor: darkText,
          elevation: 0,
          centerTitle: false,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: darkSurface,
          selectedItemColor: primary,
          unselectedItemColor: darkTextSub,
          type: BottomNavigationBarType.fixed,
        ),
        iconTheme: const IconThemeData(color: darkText),
        textTheme: _textTheme(darkText, darkTextSub),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            primary: primary,
            onPrimary: Colors.black87,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: darkSurfaceAlt,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      );

  static ThemeData get light => ThemeData(
        useMaterial3: false,
        brightness: Brightness.light,
        primaryColor: primaryDark,
        colorScheme: const ColorScheme.light(
          primary: primaryDark,
          secondary: accent,
          surface: lightSurface,
          background: lightBg,
        ),
        scaffoldBackgroundColor: lightBg,
        cardColor: lightSurface,
        appBarTheme: const AppBarTheme(
          backgroundColor: lightBg,
          foregroundColor: lightText,
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: lightSurface,
          selectedItemColor: primaryDark,
          unselectedItemColor: lightTextSub,
          type: BottomNavigationBarType.fixed,
        ),
        textTheme: _textTheme(lightText, lightTextSub),
      );

  static TextTheme _textTheme(Color main, Color sub) => TextTheme(
        headlineLarge:
            TextStyle(color: main, fontWeight: FontWeight.bold, fontSize: 28),
        headlineMedium:
            TextStyle(color: main, fontWeight: FontWeight.bold, fontSize: 22),
        titleLarge:
            TextStyle(color: main, fontWeight: FontWeight.w600, fontSize: 18),
        titleMedium:
            TextStyle(color: main, fontWeight: FontWeight.w600, fontSize: 16),
        bodyLarge: TextStyle(color: main, fontSize: 15),
        bodyMedium: TextStyle(color: main, fontSize: 14),
        bodySmall: TextStyle(color: sub, fontSize: 12),
      );
}
