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
  return prefs.getInt(AppConstants.keyThemeMode) ?? 2;
});

/// 视频功能总开关
final videoEnabledProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool(AppConstants.keyVideoEnabled) ??
      AppConstants.defaultVideoEnabled;
});

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
