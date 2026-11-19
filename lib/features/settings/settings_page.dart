import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/path_utils.dart';
import '../../shared/widgets/common.dart';

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
        padding: pagePadding(context, top: 8, bottom: 32),
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
              SwitchListTile(
                secondary: _iconBadge(context, Icons.download_outlined),
                title: const Text('自动缓存'),
                subtitle: const Text('播完当前一集自动缓存后面的集，默认关'),
                value: ref.watch(autoCacheProvider),
                onChanged: (v) {
                  ref.read(autoCacheProvider.notifier).state = v;
                  prefs.setBool(AppConstants.keyAutoCache, v);
                },
              ),
              if (ref.watch(autoCacheProvider)) ...[
                ListTile(
                  leading: _iconBadge(context, Icons.format_list_numbered),
                  title: const Text('缓存集数'),
                  subtitle: const Text('播完一集后自动缓存后面几集'),
                  trailing: Text(
                      '${ref.watch(autoCacheCountProvider)} 集',
                      style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.primary)),
                  onTap: () => _pickCacheCount(context, ref, prefs),
                ),
                SwitchListTile(
                  secondary: _iconBadge(context, Icons.wifi_outlined),
                  title: const Text('仅 WiFi 下缓存'),
                  subtitle: const Text('开了只在 WiFi 下缓存，不用流量'),
                  value: ref.watch(autoCacheWifiOnlyProvider),
                  onChanged: (v) {
                    ref.read(autoCacheWifiOnlyProvider.notifier).state = v;
                    prefs.setBool(AppConstants.keyAutoCacheWifiOnly, v);
                  },
                ),
              ],
              ListTile(
                leading: _iconBadge(context, Icons.play_circle_outline),
                title: const Text('播放设置'),
                subtitle: const Text('默认倍速、自动连播、定时关闭、断点续播'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () =>
                    Navigator.of(context).pushNamed('/playback-settings'),
              ),
              ListTile(
                leading: _iconBadge(context, Icons.widgets_outlined),
                title: const Text('桌面小工具和锁屏'),
                subtitle: const Text('小工具主题、锁屏封面、默认封面、启动图标'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/widget-lock'),
              ),
              ListTile(
                leading: _iconBadge(context, Icons.text_fields_outlined),
                title: const Text('字体大小'),
                subtitle: Text(
                    '当前：${{'small': '小', 'standard': '标准', 'large': '大'}[ref.watch(fontSizeProvider)] ?? '标准'}'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => _pickFontSize(context, ref, prefs),
              ),
              SwitchListTile(
                secondary: _iconBadge(context, Icons.manage_search_outlined),
                title: const Text('聚合搜索'),
                subtitle: const Text('合并所有源的搜索结果一起显示'),
                value: ref.watch(aggregateSearchProvider),
                onChanged: (v) {
                  ref.read(aggregateSearchProvider.notifier).state = v;
                  prefs.setBool(AppConstants.keyAggregateSearch, v);
                },
              ),
              SwitchListTile(
                secondary: _iconBadge(context, Icons.filter_alt_outlined),
                title: const Text('精确搜索'),
                subtitle: const Text('只留和关键词相关的结果'),
                value: ref.watch(exactSearchProvider),
                onChanged: (v) {
                  ref.read(exactSearchProvider.notifier).state = v;
                  prefs.setBool(AppConstants.keyExactSearch, v);
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
            title: '其它设置',
            children: [
              ListTile(
                leading: _iconBadge(context, Icons.folder_outlined),
                title: const Text('本地书库设置'),
                subtitle: const Text('导入手机本地的音频文件做书库'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/library'),
              ),
              ListTile(
                leading: _iconBadge(context, Icons.cloud_outlined),
                title: const Text('WebDAV 播放设置'),
                subtitle: const Text('连自己的 WebDAV 书库直接播'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/webdav-play'),
              ),
              ListTile(
                leading: _iconBadge(context, Icons.cloud_queue_outlined),
                title: const Text('阿里云盘设置'),
                subtitle: const Text('还没接入'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/cloud-ali'),
              ),
              ListTile(
                leading: _iconBadge(context, Icons.cloud_queue_outlined),
                title: const Text('百度网盘设置'),
                subtitle: const Text('还没接入'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/cloud-baidu'),
              ),
              ListTile(
                leading: _iconBadge(context, Icons.cloud_queue_outlined),
                title: const Text('115网盘设置'),
                subtitle: const Text('还没接入'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/cloud-115'),
              ),
              ListTile(
                leading: _iconBadge(context, Icons.lan_outlined),
                title: const Text('SMB 设置'),
                subtitle: const Text('连接局域网共享，还没接入'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(context).pushNamed('/cloud-smb'),
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
    final current = ref.read(cacheLimitProvider);
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('缓存上限'),
        children: [256, 512, 1024].map((v) {
          return SimpleDialogOption(
            onPressed: () {
              ref.read(cacheLimitProvider.notifier).state = v;
              prefs.setInt(AppConstants.keyCacheLimitMb, v);
              Navigator.pop(ctx);
            },
            child: Row(
              children: [
                Text(v == 1024 ? '1 GB' : '$v MB',
                    style: const TextStyle(fontSize: 15)),
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

  void _pickCacheCount(
      BuildContext context, WidgetRef ref, SharedPreferences prefs) {
    final current = ref.read(autoCacheCountProvider);
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('缓存集数'),
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

  void _pickFontSize(
      BuildContext context, WidgetRef ref, SharedPreferences prefs) {
    final current = ref.read(fontSizeProvider);
    const options = {'small': '小', 'standard': '标准', 'large': '大'};
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('字体大小'),
        children: options.entries.map((e) {
          return SimpleDialogOption(
            onPressed: () {
              ref.read(fontSizeProvider.notifier).state = e.key;
              prefs.setString(AppConstants.keyFontSize, e.key);
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
