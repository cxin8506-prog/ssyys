import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/database/app_database.dart';
import '../../core/di/providers.dart';
import '../../features/ua/ua_resolver.dart';
import '../engine/jar_plugin_engine.dart';
import '../engine/js_plugin_engine.dart';
import '../engine/plugin_engine.dart';
import '../engine/tingshu_plugin_engine.dart';
import '../model/plugin_source.dart';
import 'auto_cache.dart';
import 'config_schema_loader.dart';
import 'plugin_resume.dart';
import 'source_config_repository.dart';
import 'source_repository.dart';

/// 源仓储（索引 + 安装/删除/排序/分组）。
final sourceRepositoryProvider = Provider<SourceRepository>((ref) {
  return SourceRepository(
    configRepo: ref.read(sourceConfigRepositoryProvider),
  );
});

/// 源配置仓储（登录态、音色、线路、extra）。
final sourceConfigRepositoryProvider =
    Provider<SourceConfigRepository>((ref) {
  return SourceConfigRepository(ref.read(databaseProvider));
});

/// 配置声明加载器（manifest config → 脚本 config() → 能力推断）。
final configSchemaLoaderProvider = Provider<ConfigSchemaLoader>((ref) {
  return ConfigSchemaLoader(ref.read(sourceRepositoryProvider));
});

/// 全部源（读完索引后跑一次启动自愈：坏的单源 JAR 重新拆成多源）。
final sourceListProvider = FutureProvider<List<PluginSource>>((ref) async {
  final repo = ref.read(sourceRepositoryProvider);
  var all = await repo.loadAll();
  all = await repo.repairLegacyJars(all);
  return all;
});

/// 按插件分组折叠（源管理页用，一包一张卡）。
final pluginGroupListProvider = FutureProvider<List<PluginGroup>>((ref) async {
  final all = await ref.watch(sourceListProvider.future);
  final repo = ref.read(sourceRepositoryProvider);
  return repo.pluginGroups(all);
});

/// 当前源（听书/视频各记一个，详情页、播放页、搜索页共用）。
final currentSourceProvider = StateProvider.family<PluginSource?, String>(
  (ref, type) => null,
);

/// 设置当前源（同时清掉另一组里可能残留的同源引用）。
Future<void> setCurrentSource(
    WidgetRef ref, String type, PluginSource? source) async {
  ref.read(currentSourceProvider(type).notifier).state = source;
}

/// 随身听书 JS 引擎。
final jsPluginEngineProvider = Provider<JsPluginEngine>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  final timeoutSeconds =
      prefs.getInt(AppConstants.keySearchTimeoutSeconds) ?? 20;
  return JsPluginEngine(
    ref.read(sourceRepositoryProvider),
    ref.read(sourceConfigRepositoryProvider),
    ref.read(uaResolverProvider),
    searchTimeoutSeconds: timeoutSeconds,
  );
});

/// 通用 JAR 引擎（旧格式，静态方法插件）。
final jarPluginEngineProvider = Provider<JarPluginEngine>((ref) {
  return JarPluginEngine(
    ref.read(sourceRepositoryProvider),
    ref.read(sourceConfigRepositoryProvider),
    ref.read(uaResolverProvider),
  );
});

/// 我的听书 JAR 引擎（TingShu 格式）。
final tingShuEngineProvider = Provider<TingShuPluginEngine>((ref) {
  return TingShuPluginEngine(
    ref.read(sourceRepositoryProvider),
    ref.read(uaResolverProvider),
    ref.read(sourceConfigRepositoryProvider),
  );
});

/// 按源格式取引擎：tingshu 走 TingShu 引擎，jar 走通用 JAR 引擎，
/// 其余（js / jsZip / 未声明）走 JS 引擎。
PluginEngine engineForSource(WidgetRef ref, PluginSource source) {
  if (source.isTingShu) return ref.read(tingShuEngineProvider);
  if (source.isJar) return ref.read(jarPluginEngineProvider);
  return ref.read(jsPluginEngineProvider);
}

/// 断点续播（播放器组调用，顶层函数在 plugin_resume.dart）。
final pluginResumeStoreProvider = Provider<PluginResumeStore>((ref) {
  return PluginResumeStore(ref.read(sharedPrefsProvider));
});

/// 自动缓存（播放器组调用）。
final autoCacheProvider = Provider<AutoCache>((ref) {
  return AutoCache(ref.read(sharedPrefsProvider));
});
