import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../plugins/data/auto_cache.dart';
import '../../shared/widgets/common.dart';

/// 缓存设置页（照我的听书的样子排）：
/// 自动缓存后续章节（默认关）/ 每本书最大缓存集数（默认 3）
/// / 缓存频率（标准）/ 只在WIFI条件下缓存 / 自动清理缓存文件（个数上限，默认 40）
/// / 清除所有音频缓存。默认关就绝不偷偷缓存。
class CacheSettingsPage extends ConsumerStatefulWidget {
  const CacheSettingsPage({super.key});

  @override
  ConsumerState<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends ConsumerState<CacheSettingsPage> {
  int _cachedCount = 0;

  @override
  void initState() {
    super.initState();
    _refreshCount();
  }

  Future<void> _refreshCount() async {
    final n = await AutoCache.cachedCount();
    if (mounted) setState(() => _cachedCount = n);
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.read(sharedPrefsProvider);
    final autoCache = ref.watch(autoCacheProvider);
    final count = ref.watch(autoCacheCountProvider);
    final freq = ref.watch(autoCacheFreqProvider);
    final wifiOnly = ref.watch(autoCacheWifiOnlyProvider);
    final cleanLimit = ref.watch(autoCleanLimitProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('缓存设置')),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 32),
        children: [
          Container(
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.palette.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('自动缓存后续章节'),
                  subtitle: const Text(
                      '在播放时根据一定的时间规则，自动缓存后续章节。注意：暂停时不触发缓存。缓存过的书籍在没有网络时可从我的收藏打开进行离线播放。'),
                  value: autoCache,
                  onChanged: (v) {
                    ref.read(autoCacheProvider.notifier).state = v;
                    prefs.setBool(AppConstants.keyAutoCache, v);
                  },
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  title: const Text('每本书最大缓存集数'),
                  subtitle:
                      const Text('当前播放章节向后缓存的数量'),
                  trailing: Text('$count 集',
                      style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.primary)),
                  onTap: () => _pickCount(context, ref, prefs, count),
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  title: const Text('缓存频率'),
                  subtitle: Text(_freqLabel(freq)),
                  trailing: Text(_freqName(freq),
                      style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.primary)),
                  onTap: () => _pickFreq(context, ref, prefs, freq),
                ),
                const Divider(height: 1, indent: 16),
                SwitchListTile(
                  title: const Text('只在WIFI条件下缓存'),
                  subtitle: const Text('开了只在 WiFi 下缓存，不用流量'),
                  value: wifiOnly,
                  onChanged: (v) {
                    ref.read(autoCacheWifiOnlyProvider.notifier).state = v;
                    prefs.setBool(AppConstants.keyAutoCacheWifiOnly, v);
                  },
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  title: const Text('自动清理缓存文件'),
                  subtitle: const Text(
                      '当超过指定的数量时，按下载的时间顺序从最老的缓存开始清理。注意：清理针对的是全部缓存，如果你同时在听多本书籍则尽量把清理上限设的大一点。'),
                  trailing: Text(
                      cleanLimit <= 0 ? '不清理' : '$cleanLimit 个',
                      style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.primary)),
                  onTap: () =>
                      _pickCleanLimit(context, ref, prefs, cleanLimit),
                ),
                const Divider(height: 1, indent: 16),
                ListTile(
                  title: const Text('清除所有音频缓存'),
                  subtitle: Text(_cachedCount > 0
                      ? '当前已缓存 $_cachedCount 集，点一下全部清除'
                      : '当前没有缓存'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => _clearAll(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _freqName(String freq) {
    switch (freq) {
      case 'fast':
        return '较快';
      case 'slow':
        return '较慢';
      default:
        return '标准';
    }
  }

  String _freqLabel(String freq) {
    switch (freq) {
      case 'fast':
        return '较快（间隔约为时长的 15%）';
      case 'slow':
        return '较慢（间隔约为时长的 50%）';
      default:
        return '标准（间隔约为时长的 30%）';
    }
  }

  void _pickCount(
      BuildContext context, WidgetRef ref, SharedPreferences prefs, int current) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('每本书最大缓存集数'),
        children: [1, 3, 5].map((v) {
          return SimpleDialogOption(
            onPressed: () {
              ref.read(autoCacheCountProvider.notifier).state = v;
              prefs.setInt(AppConstants.keyAutoCacheCount, v);
              Navigator.pop(ctx);
            },
            child: Row(
              children: [
                Text('$v 集', style: const TextStyle(fontSize: 15)),
                if (v == current) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _pickFreq(
      BuildContext context, WidgetRef ref, SharedPreferences prefs, String current) {
    const options = {'standard': '标准', 'fast': '较快', 'slow': '较慢'};
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('缓存频率'),
        children: options.entries.map((e) {
          return SimpleDialogOption(
            onPressed: () {
              ref.read(autoCacheFreqProvider.notifier).state = e.key;
              prefs.setString(AppConstants.keyAutoCacheFreq, e.key);
              Navigator.pop(ctx);
            },
            child: Row(
              children: [
                Text(e.value, style: const TextStyle(fontSize: 15)),
                if (e.key == current) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 自动清理缓存文件：单选弹窗，按缓存文件个数限（不是按 MB）
  void _pickCleanLimit(BuildContext context, WidgetRef ref,
      SharedPreferences prefs, int current) {
    const options = [0, 40, 60, 80, 100, 120, 200, 300, 400, 500];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自动清理缓存文件'),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: options.map((v) {
              return ListTile(
                title: Text(v == 0 ? '不清理' : '$v',
                    style: const TextStyle(fontSize: 15)),
                trailing: v == current
                    ? Icon(Icons.check,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  ref.read(autoCleanLimitProvider.notifier).state = v;
                  prefs.setInt(AppConstants.keyAutoCleanLimit, v);
                  Navigator.pop(ctx);
                  // 立刻按新上限清理一次
                  AutoCache.enforceCountLimit(v).then((_) => _refreshCount());
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAll(BuildContext context) async {
    final n = await AutoCache.clearAllAudioCache();
    await _refreshCount();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(n > 0 ? '已清除 $n 集音频缓存' : '当前没有缓存')));
  }
}
