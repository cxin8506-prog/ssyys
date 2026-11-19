import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../engine/jar_plugin_engine.dart';
import '../engine/js_plugin_engine.dart';
import '../model/plugin_source.dart';
import 'source_config_repository.dart';
import 'source_repository.dart';

/// 源安装/索引
final sourceRepositoryProvider = Provider<SourceRepository>((ref) {
  return SourceRepository();
});

/// 源运行配置（登录态/音色/线路）
final sourceConfigRepositoryProvider = Provider<SourceConfigRepository>((ref) {
  return SourceConfigRepository(ref.read(databaseProvider));
});

/// 已安装源列表（安装/删除后 ref.invalidate 刷新）
final sourceListProvider = FutureProvider<List<PluginSource>>((ref) async {
  return ref.read(sourceRepositoryProvider).loadAll();
});

/// 当前选中的源（按 audio / video 分别记忆）
final currentSourceProvider =
    StateProvider.family<String?, String>((ref, type) {
  final prefs = ref.read(sharedPrefsProvider);
  final key = type == AppConstants.typeVideo
      ? AppConstants.keyCurrentSourceVideo
      : AppConstants.keyCurrentSourceAudio;
  return prefs.getString(key);
});

/// 切换当前源（同时落 SharedPreferences）
void setCurrentSource(WidgetRef ref, String type, String? sourceId) {
  final prefs = ref.read(sharedPrefsProvider);
  final key = type == AppConstants.typeVideo
      ? AppConstants.keyCurrentSourceVideo
      : AppConstants.keyCurrentSourceAudio;
  if (sourceId == null) {
    prefs.remove(key);
  } else {
    prefs.setString(key, sourceId);
  }
  ref.read(currentSourceProvider(type).notifier).state = sourceId;
}

/// JS/ZIP 引擎（全局单例，内部按源缓存运行时）
final jsPluginEngineProvider = Provider<JsPluginEngine>((ref) {
  return JsPluginEngine(
    ref.read(sourceRepositoryProvider),
    ref.read(sourceConfigRepositoryProvider),
    ref.read(uaResolverProvider),
  );
});

/// JAR 引擎
final jarPluginEngineProvider = Provider<JarPluginEngine>((ref) {
  return JarPluginEngine(
    ref.read(sourceRepositoryProvider),
    ref.read(sourceConfigRepositoryProvider),
  );
});
