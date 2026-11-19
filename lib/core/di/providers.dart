import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/ua/data/ua_repository.dart';
import '../../features/ua/data/ua_resolver.dart';
import '../constants/app_constants.dart';
import '../database/app_database.dart';
import '../log/app_logger.dart';

/// 数据库实例
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// SharedPreferences（同步获取，需在 main 中 initialize）
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('需在 main() 中覆盖此 Provider');
});

/// 主题模式：0=跟随系统 1=浅色 2=深色，默认深色
final themeModeProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getInt(AppConstants.keyThemeMode) ?? 1;
});

/// 视频功能总开关
final videoEnabledProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool(AppConstants.keyVideoEnabled) ??
      AppConstants.defaultVideoEnabled;
});

/// 主题配色（0=暖阳橙 1=海蓝 2=青竹绿 3=樱花粉 4=墨夜）
final themeColorProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getInt(AppConstants.keyThemeColor) ?? 0;
});

/// 跟随系统深色（默认关；墨夜主题一直保持黑色，不跟随）
final followSystemDarkProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool(AppConstants.keyFollowSystemDark) ?? false;
});

/// 播放页取色偏向（默认开：暗色主题播放页偏暗，亮色偏亮）
final playerTintProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool(AppConstants.keyPlayerTint) ?? true;
});

/// 聚合搜索（默认开）
final aggregateSearchProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool(AppConstants.keyAggregateSearch) ?? true;
});

/// 精确搜索（默认开）
final exactSearchProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool(AppConstants.keyExactSearch) ?? true;
});

/// 自动缓存（默认关）
final autoCacheProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool(AppConstants.keyAutoCache) ?? false;
});

/// 自动缓存集数（1/3/5，默认 1）
final autoCacheCountProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getInt(AppConstants.keyAutoCacheCount) ?? 1;
});

/// 仅 WiFi 下缓存（默认开）
final autoCacheWifiOnlyProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool(AppConstants.keyAutoCacheWifiOnly) ?? true;
});

/// 自动播放下一集（默认开）
final autoNextProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool(AppConstants.keyAutoNext) ?? true;
});

/// 断点续播（默认开）
final resumeEnabledProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool(AppConstants.keyResumeEnabled) ?? true;
});

/// 默认倍速（默认 1.0）
final defaultSpeedProvider = StateProvider<double>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getDouble(AppConstants.keyPlaybackSpeed) ?? 1.0;
});

/// 定时关闭默认值（分钟，0=不设置）
final sleepTimerDefaultProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getInt(AppConstants.keySleepTimerDefault) ?? 0;
});

/// 字体大小：small / standard / large（默认 standard）
final fontSizeProvider = StateProvider<String>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getString(AppConstants.keyFontSize) ?? 'standard';
});

/// 书源页源列表列数（1-5，默认 3）
final sourceColumnsProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  final v = prefs.getInt(AppConstants.keySourceColumns) ?? 3;
  return v.clamp(1, 5);
});

/// 主壳底部导航当前 tab（0=书源 1=源内容 2=收藏 3=历史）
final shellTabProvider = StateProvider<int>((ref) => 0);

/// 字体缩放倍数（供详情页简介/选集用）
double fontScaleFor(String size) {
  switch (size) {
    case 'small':
      return 0.9;
    case 'large':
      return 1.15;
    default:
      return 1.0;
  }
}

/// 缓存上限（MB）
final cacheLimitProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getInt(AppConstants.keyCacheLimitMb) ??
      AppConstants.defaultCacheLimitMb;
});

/// UA 配置仓储（基于 drift kv_settings，随数据库一起备份）
final uaRepositoryProvider = Provider<UaRepository>((ref) {
  return UaRepository(ref.read(databaseProvider));
});

/// 按源解析 UA 的解析器
final uaResolverProvider = Provider<UaResolver>((ref) {
  return UaResolver(ref.read(uaRepositoryProvider));
});

/// 将 ThemeMode 整数转换为 Flutter 枚举
ThemeMode resolveThemeMode(int v) {
  switch (v) {
    case 0:
      return ThemeMode.system;
    case 1:
      return ThemeMode.light;
    default:
      return ThemeMode.dark;
  }
}

/// 初始化数据库并挂载日志
Future<AppDatabase> initDatabase() async {
  final db = AppDatabase();
  appLogger.attachDatabase(db);
  appLogger.info('App 启动', detail: '数据库与日志已就绪');
  return db;
}
