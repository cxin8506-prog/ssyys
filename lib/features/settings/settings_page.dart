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
    final themeColor = ref.watch(themeColorProvider);
    final videoEnabled = ref.watch(videoEnabledProvider);
    final cacheLimit = ref.watch(cacheLimitProvider);
    final prefs = ref.read(sharedPrefsProvider);
    final scheme = AppTheme.schemeAt(themeColor);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _Section(
            title: '我的内容',
            children: [
              ListTile(
                leading: _iconBadge(context, Icons.favorite_outline),
                title: const Text('收藏'),
                subtitle: const Text('听书 / 视频分别归档'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/favorites'),
              ),
              ListTile(
                leading: _iconBadge(context, Icons.history),
                title: const Text('历史'),
                subtitle: const Text('最近听过 / 看过'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/history'),
              ),
              ListTile(
                leading: _iconBadge(context, Icons.bookmark_outline),
                title: const Text('书签'),
                subtitle: const Text('播放位置标记'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/bookmarks'),
              ),
              ListTile(
                leading: _iconBadge(context, Icons.travel_explore),
                title: const Text('源搜索'),
                subtitle: const Text('在已导入的源里搜索内容'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () =>
                    Navigator.of(context).pushNamed('/source-search'),
              ),
            ],
          ),
          _Section(
            title: '外观',
            children: [
              ListTile(
                leading: _iconBadge(context, Icons.palette_outlined),
                title: const Text('主题与配色'),
                subtitle: Text(
                    '${scheme.name} · ${['跟随系统', '浅色', '深色'][themeMode]}'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/theme'),
              ),
            ],
          ),
          _Section(
            title: '内容',
            children: [
              SwitchListTile(
                secondary: _iconBadge(context, Icons.movie_outlined),
                title: const Text('视频功能'),
                subtitle: const Text('关闭后隐藏视频相关入口'),
                value: videoEnabled,
                onChanged: (v) {
                  ref.read(videoEnabledProvider.notifier).state = v;
                  prefs.setBool(AppConstants.keyVideoEnabled, v);
                },
              ),
            ],
          ),
          _Section(
            title: '源与网络',
            children: [
              ListTile(
                leading: _iconBadge(context, Icons.extension_outlined),
                title: const Text('源管理'),
                subtitle: const Text('导入 JS/ZIP、JAR 插件源，配置登录态/音色/线路'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/sources'),
              ),
              ListTile(
                leading: _iconBadge(context, Icons.http_outlined),
                title: const Text('UA 设置'),
                subtitle: const Text('按源自动切换 UA，加载受限时可修改重试'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/ua-settings'),
              ),
            ],
          ),
          _Section(
            title: '存储',
            children: [
              ListTile(
                leading: _iconBadge(context, Icons.storage_outlined),
                title: const Text('缓存上限'),
                subtitle: Text('$cacheLimit MB，超过时提示清理'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => _showCacheDialog(context, ref, prefs),
              ),
              FutureBuilder<int>(
                future: _cacheSize(),
                builder: (context, snap) => ListTile(
                  leading: _iconBadge(context, Icons.cleaning_services_outlined),
                  title: const Text('清除缓存'),
                  subtitle: Text(
                      '当前占用 ${PathUtils.formatSize((snap.data ?? 0) * 1024 * 1024)}'),
                  onTap: () => _clearCache(context, ref),
                ),
              ),
            ],
          ),
          _Section(
            title: '数据',
            children: [
              ListTile(
                leading: _iconBadge(context, Icons.cloud_outlined),
                title: const Text('坚果云同步'),
                subtitle: const Text('用 WebDAV 把备份传到云端，换机可恢复'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/sync'),
              ),
              ListTile(
                leading: _iconBadge(context, Icons.backup_outlined),
                title: const Text('本地备份与恢复'),
                subtitle: const Text('打包书架/进度/收藏/书签/设置/插件'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/backup'),
              ),
              ListTile(
                leading: _iconBadge(context, Icons.description_outlined),
                title: const Text('运行日志'),
                subtitle: const Text('查看 / 清空 / 导出'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/logs'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.secondary,
                      ],
                    ),
                  ),
                  child: const Icon(Icons.headphones, color: Colors.white),
                ),
                const SizedBox(height: 10),
                Text('随意听书 v${AppConstants.version}',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text('全本地 · 无需登录 · 数据可迁移',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconBadge(BuildContext context, IconData icon) => Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: context.palette.primarySoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
      );

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

/// 分组：标题 + 圆角卡片
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text(title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600, letterSpacing: 0.4)),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.palette.outline),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  Divider(
                      height: 1,
                      indent: 60,
                      color: context.palette.outline),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
