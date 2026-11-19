import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/path_utils.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final videoEnabled = ref.watch(videoEnabledProvider);
    final cacheLimit = ref.watch(cacheLimitProvider);
    final prefs = ref.read(sharedPrefsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _SectionTitle(title: '界面'),
          ListTile(
            leading:
                const Icon(Icons.palette_outlined, color: AppTheme.primary),
            title: const Text('主题'),
            subtitle: Text(['跟随系统', '浅色', '深色'][themeMode]),
            onTap: () => _showThemeDialog(context, ref, prefs),
          ),
          const _SectionTitle(title: '内容'),
          SwitchListTile(
            secondary:
                const Icon(Icons.movie_outlined, color: AppTheme.primary),
            title: const Text('视频功能'),
            subtitle: const Text('关闭后隐藏视频相关入口'),
            value: videoEnabled,
            onChanged: (v) {
              ref.read(videoEnabledProvider.notifier).state = v;
              prefs.setBool(AppConstants.keyVideoEnabled, v);
            },
          ),
          const _SectionTitle(title: '网络与源'),
          ListTile(
            leading:
                const Icon(Icons.http_outlined, color: AppTheme.primary),
            title: const Text('UA 设置'),
            subtitle: const Text('按源自动切换 UA / 管理手机与电脑 UA，加载受限时可修改重试'),
            onTap: () => Navigator.of(context).pushNamed('/ua-settings'),
          ),
          const _SectionTitle(title: '存储与缓存'),
          ListTile(
            leading:
                const Icon(Icons.storage_outlined, color: AppTheme.primary),
            title: const Text('缓存上限'),
            subtitle: Text('$cacheLimit MB，超过时提示清理'),
            onTap: () => _showCacheDialog(context, ref, prefs),
          ),
          FutureBuilder<int>(
            future: _cacheSize(),
            builder: (context, snap) => ListTile(
              leading: const Icon(Icons.cleaning_services_outlined,
                  color: AppTheme.primary),
              title: const Text('清除缓存'),
              subtitle: Text(
                  '当前占用 ${PathUtils.formatSize((snap.data ?? 0) * 1024 * 1024)}'),
              onTap: () => _clearCache(context, ref),
            ),
          ),
          const _SectionTitle(title: '数据'),
          ListTile(
            leading: const Icon(Icons.backup_outlined, color: AppTheme.primary),
            title: const Text('备份与恢复'),
            subtitle: const Text('本地 zip 备份书架/进度/收藏/书签/设置'),
            onTap: () => Navigator.of(context).pushNamed('/backup'),
          ),
          ListTile(
            leading:
                const Icon(Icons.description_outlined, color: AppTheme.primary),
            title: const Text('日志'),
            subtitle: const Text('查看 / 清空 / 导出运行日志'),
            onTap: () => Navigator.of(context).pushNamed('/logs'),
          ),
          const SizedBox(height: 24),
          ListTile(
            title: Text('本地影音 v${AppConstants.version}'),
            subtitle: const Text('全本地 · 无需登录 · 数据可迁移'),
          ),
        ],
      ),
    );
  }

  void _showThemeDialog(
      BuildContext context, WidgetRef ref, SharedPreferences prefs) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('主题'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
              3,
              (i) => RadioListTile<int>(
                    title: Text(['跟随系统', '浅色', '深色'][i]),
                    value: i,
                    groupValue: ref.read(themeModeProvider),
                    onChanged: (v) {
                      if (v != null) {
                        ref.read(themeModeProvider.notifier).state = v;
                        prefs.setInt(AppConstants.keyThemeMode, v);
                        Navigator.pop(context);
                      }
                    },
                  )),
        ),
      ),
    );
  }

  void _showCacheDialog(
      BuildContext context, WidgetRef ref, SharedPreferences prefs) {
    final controller =
        TextEditingController(text: '${ref.read(cacheLimitProvider)}');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('缓存上限（MB）'),
        content: TextField(
            controller: controller, keyboardType: TextInputType.number),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text) ?? 512;
              ref.read(cacheLimitProvider.notifier).state = v;
              prefs.setInt(AppConstants.keyCacheLimitMb, v);
              Navigator.pop(context);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<int> _cacheSize() async {
    final dir = await PathUtils.cacheDir;
    int total = 0;
    await for (final e in dir.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total ~/ (1024 * 1024);
  }

  void _clearCache(BuildContext context, WidgetRef ref) async {
    final dir = await PathUtils.cacheDir;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    await PathUtils.cacheDir;
    {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('缓存已清除')));
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title, style: Theme.of(context).textTheme.bodySmall),
      );
}
