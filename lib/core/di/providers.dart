import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../plugins/model/plugin_source.dart';

/// App 级 provider（U 定义）。
///
/// 约定：每个设置项的默认值都写死在这里，和提示词第六节（六）/
/// 功能清单第五节的表一致；读写一律经过 SharedPreferences，
/// provider 只负责内存态 + 落盘，行为由消费方（播放器组/引擎组/
/// 支撑组）按这些值执行。
///
/// 注意：databaseProvider 在支撑组的 lib/core/database/app_database.dart
/// 里定义，不在这里；main.dart 从那边 import。

/// SharedPreferences 实例：main() 里 overrideWithValue 注入。
/// 未注入时抛错，避免静默读到空值。
final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('需在 main() 中覆盖 sharedPrefsProvider');
});

/// 底栏当前 tab：0 书源 / 1 当前源 / 2 收藏 / 3 历史。
/// 中间大播放键不是 tab，不占下标（点它走播放逻辑，不切 tab）。
final shellTabProvider = StateProvider<int>((ref) => 0);

/// 首页回顶部信号：底栏书源 tab 被重复点时 +1，HomePage 监听到就
/// 把列表滚回顶部（双击书架回顶部同款做法）。
final homeScrollToTopProvider = StateProvider<int>((ref) => 0);

/// 当前首页源（发现页读它取分类、底栏读它显示当前源名、书源页读它
/// 标选中卡片）：null = 还没选源。
/// 设源写法（统一口径）：调用方直接改 state，不另设 setHomeSource 方法：
///   ref.read(activeHomeSourceProvider.notifier).state = source;
/// 其中 source 是 PluginSource（不是 id 字符串）。
final activeHomeSourceProvider =
    StateProvider<PluginSource?>((ref) => null);

/// 源顺序：源 ID 列表。不在列表里的排最后，再按名称排（随身听书做法）。
final sourceOrderProvider = StateProvider<List<String>>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getStringList('source_order') ?? const <String>[];
});

Future<void> saveSourceOrder(WidgetRef ref, List<String> order) async {
  ref.read(sourceOrderProvider.notifier).state = order;
  await ref.read(sharedPrefsProvider).setStringList('source_order', order);
}

/// 按 SourceOrder 排源：列表里的按顺序，不在的排最后再按名称。
List<T> sortSourcesByOrder<T>(
  List<T> items,
  List<String> order,
  String Function(T) idOf,
  String Function(T) nameOf,
) {
  final sorted = List<T>.from(items);
  sorted.sort((a, b) {
    final ia = order.indexOf(idOf(a));
    final ib = order.indexOf(idOf(b));
    final ra = ia >= 0 ? ia : 1000000;
    final rb = ib >= 0 ? ib : 1000000;
    if (ra != rb) return ra.compareTo(rb);
    return nameOf(a).compareTo(nameOf(b));
  });
  return sorted;
}

// ------------------------------------------------------------------ 播放

/// 默认倍速：默认 1.0，范围 0.5–3.0。
final defaultSpeedProvider = StateProvider<double>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getDouble('playback_speed') ?? 1.0;
});

/// 快退 / 快进步长（秒）：默认 15，选项 5 / 10 / 15 / 30 / 60。
final seekStepProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getInt('seek_step_seconds') ?? 15;
});

/// 自动播放下一集：默认开。音频和视频都读它（旧坑：只管视频不管音频）。
final autoNextProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('auto_next') ?? true;
});

/// 启动时恢复上次播放：默认开。恢复到断点但不自动播。
final resumeEnabledProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('resume_enabled') ?? true;
});

/// 跳过无声：默认开。
final skipSilenceProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('skip_silence') ?? true;
});

/// 锁屏滑杆：默认开。关了锁屏通知就没有可拖动的进度条。
final lockScreenSliderProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('lockscreen_slider') ?? true;
});

/// 熄屏保活（WakeLock）：默认开，介意耗电可关。
final wakeLockProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('wake_lock') ?? true;
});

/// 暂停后自动倒带：默认开（按停顿时长分档倒带，播放器组实现）。
final rewindAfterPauseProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('rewind_after_pause') ?? true;
});

/// 睡眠定时默认值（分钟）：0 = 不设置；-1 = 播到章末停。
final sleepTimerDefaultProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getInt('sleep_timer_default') ?? 0;
});

/// 自动换线：默认开。失败自动按顺序试下一条线。
final autoChangeLineProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('auto_change_line') ?? true;
});

/// 视频功能：默认开。关了隐藏视频源、视频搜索、视频收藏/历史入口
/// （旧坑：只藏了书架的视频分栏，其他入口全都不受控制）。
final videoEnabledProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('video_enabled') ?? true;
});

// ------------------------------------------------------------------ 网络

/// 聚合搜索：默认开。关了按源分开搜。
final aggregateSearchProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('aggregate_search') ?? true;
});

/// 精确搜索：默认开。按书名/作者子串过滤。
final exactSearchProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('exact_search') ?? true;
});

/// 聚合搜索并发数：默认 6，范围 1–32。
final searchConcurrencyProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getInt('search_concurrency') ?? 6;
});

/// 单源超时（秒）：默认 20。
final searchTimeoutProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getInt('search_timeout_seconds') ?? 20;
});

/// 搜索建议：默认开。输入停 300ms 后出下拉建议（热门词 + 搜索历史里含
/// 输入词的），词少于 2 个字符不显示；点一条直接搜。
final searchSuggestionsProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('search_suggestions_enabled') ?? true;
});

// ------------------------------------------------------------------ 存储

/// 自动缓存后续章节：默认关。isCacheable() 返回 false 的源一集都不下。
final autoCacheProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('auto_cache') ?? false;
});

/// 每本书最大缓存集数：默认 3。
final autoCacheCountProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getInt('auto_cache_count') ?? 3;
});

/// 缓存频率：standard（30%）/ fast（15%）/ slow（50%），默认 standard。
final autoCacheFreqProvider = StateProvider<String>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getString('auto_cache_freq') ?? 'standard';
});

/// 只在 Wi-Fi 下缓存：默认开。
final autoCacheWifiOnlyProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('auto_cache_wifi_only') ?? true;
});

/// 自动清理缓存文件数：默认 40。
final autoCleanLimitProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getInt('auto_clean_limit') ?? 40;
});

/// 云同步（坚果云 WebDAV）：默认关。
final syncEnabledProvider = StateProvider<bool>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getBool('sync_enabled') ?? false;
});

/// 源卡片列数：默认 3。
final sourceColumnsProvider = StateProvider<int>((ref) {
  final prefs = ref.read(sharedPrefsProvider);
  return prefs.getInt('source_columns') ?? 3;
});

/// 通用写回：改 provider + 落盘一起做，避免只改一处。
Future<void> saveBoolSetting(
  WidgetRef ref,
  StateProvider<bool> provider,
  String key,
  bool value,
) async {
  ref.read(provider.notifier).state = value;
  await ref.read(sharedPrefsProvider).setBool(key, value);
}

Future<void> saveIntSetting(
  WidgetRef ref,
  StateProvider<int> provider,
  String key,
  int value,
) async {
  ref.read(provider.notifier).state = value;
  await ref.read(sharedPrefsProvider).setInt(key, value);
}

Future<void> saveDoubleSetting(
  WidgetRef ref,
  StateProvider<double> provider,
  String key,
  double value,
) async {
  ref.read(provider.notifier).state = value;
  await ref.read(sharedPrefsProvider).setDouble(key, value);
}

Future<void> saveStringSetting(
  WidgetRef ref,
  StateProvider<String> provider,
  String key,
  String value,
) async {
  ref.read(provider.notifier).state = value;
  await ref.read(sharedPrefsProvider).setString(key, value);
}
