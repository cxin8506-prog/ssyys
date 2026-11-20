import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_providers.dart';
import '../../core/utils/listen_stats.dart';
import '../../shared/widgets/common.dart';

/// 设置页：按五组——外观 / 播放 / 网络 / 存储 / 关于。
///
/// - 每项都有默认值（写死在 provider 定义里，见 core/di/providers.dart）。
/// - 每行带说明 info 图标，点弹 Dialog。
/// - 设置页内搜索：输入关键词过滤各组条目。
/// - 每项要点得动、每个开关真接线，不许假开关。
/// - 桌面小工具和锁屏那 6 项没接线的不要留；选择启动图标是假开关
///   不要留（没有 activity-alias 和第二套图标资源就不做这个功能）。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _match(String text) {
    if (_query.isEmpty) return true;
    return text.toLowerCase().contains(_query.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = ref.watch(themeColorProvider);
    final themeMode = ref.watch(themeModeProvider);
    final coverEnabled = ref.watch(coverColorEnabledProvider);
    final fontScale = ref.watch(fontScaleProvider);
    final videoEnabled = ref.watch(videoEnabledProvider);
    final scheme = AppTheme.schemeAt(themeColor);
    const modeLabels = ['跟随系统', '浅色', '深色'];
    final modeIndex = themeMode < 0 ? 0 : (themeMode > 2 ? 2 : themeMode);
    // 副标题跟着当前主题实时更新（审计 A 补充第 2 项顺手做实）。
    final themeSubtitle =
        '${scheme.name} · ${modeLabels[modeIndex]}${coverEnabled ? ' · 封面取色' : ''}';

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索设置项',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          if (_match('外观 主题 字体 封面取色 壁纸')) ...[
            const SectionTitle(title: '外观'),
            _NavRow(
              title: '主题与配色',
              subtitle: themeSubtitle,
              info: '换主题立即生效，不用重启。主题色点一下就换；纯黑只在深色下显示；封面取色让播放页颜色跟着封面走。',
              onTap: () => context.push('/theme'),
            ),
            _ValueRow(
              title: '字体大小',
              subtitle: fontScale == 0.9
                  ? '小'
                  : (fontScale == 1.15 ? '大' : '标准'),
              info: '全站字号缩放：小 0.9 / 标准 1.0 / 大 1.15。首页、书架、播放页、设置页都跟着变。',
              onTap: () => _pickFontScale(context),
            ),
            _SwitchRow(
              title: '封面取色',
              subtitle: coverEnabled ? '开' : '关',
              info: '播放页的颜色从当前封面取。种子色按封面地址存下来，启动时先恢复，取不到才现算；失败的不缓存，下次重试。',
              value: coverEnabled,
              onChanged: (v) => saveCoverColorEnabled(ref, v),
            ),
            if (isWallpaperColorSupported)
              _SwitchRow(
                title: '跟随壁纸',
                subtitle: ref.watch(wallpaperFollowProvider) ? '开' : '关',
                info: 'Android 12+ 才显示：系统给了动态色就用壁纸色重算整套配色。当前版本没有接入 dynamic_color 包（没有 Dart 2.17 兼容版），开着也会回落到暖阳橙。',
                value: ref.watch(wallpaperFollowProvider),
                onChanged: (v) => saveWallpaperFollow(ref, v),
              ),
          ],
          if (_match('播放 倍速 快进 自动播放 断点续播 跳过无声 锁屏 视频')) ...[
            const SectionTitle(title: '播放'),
            _NavRow(
              title: '播放设置',
              subtitle: '默认倍速、快退步长、跳过无声、锁屏滑杆、定时关闭',
              info: '倍速、快进步长、自动连播、断点续播、跳过无声、锁屏进度条、睡眠定时默认值都在这里。',
              onTap: () => context.push('/playback-settings'),
            ),
            _SwitchRow(
              title: '视频功能',
              subtitle: videoEnabled ? '开' : '关',
              info: '关闭后隐藏视频相关入口：视频源、视频搜索、视频收藏/历史入口都会藏起来，不只是书架分栏。',
              value: videoEnabled,
              onChanged: (v) => saveBoolSetting(
                  ref, videoEnabledProvider, 'video_enabled', v),
            ),
          ],
          if (_match('网络 搜索 UA 模拟浏览器 并发 超时')) ...[
            const SectionTitle(title: '网络'),
            _NavRow(
              title: '模拟浏览器信息（UA）',
              subtitle: '手机 / 电脑两条 UA，恢复默认 UA',
              info: '设置里只存两条当前值 UA（手机一条、电脑一条），两个文本框可改，带“恢复默认 UA”按钮。换 UA 立即生效。',
              onTap: () => context.push('/ua-settings'),
            ),
            _SwitchRow(
              title: '聚合搜索',
              subtitle: ref.watch(aggregateSearchProvider) ? '开' : '关',
              info: '默认开：一次搜全部源，结果按源分组。关了按源分开搜。',
              value: ref.watch(aggregateSearchProvider),
              onChanged: (v) => saveBoolSetting(
                  ref, aggregateSearchProvider, 'aggregate_search', v),
            ),
            _SwitchRow(
              title: '精确搜索',
              subtitle: ref.watch(exactSearchProvider) ? '开' : '关',
              info: '默认开：按书名/作者过滤掉和关键词不相关的结果。',
              value: ref.watch(exactSearchProvider),
              onChanged: (v) => saveBoolSetting(
                  ref, exactSearchProvider, 'exact_search', v),
            ),
            _SwitchRow(
              title: '搜索建议',
              subtitle: ref.watch(searchSuggestionsProvider) ? '开' : '关',
              info: '默认开：输入时停 300ms 出建议下拉（热门词 + 历史里含输入词的），少于 2 个字不显示；点一条直接搜。',
              value: ref.watch(searchSuggestionsProvider),
              onChanged: (v) => saveBoolSetting(
                  ref,
                  searchSuggestionsProvider,
                  'search_suggestions_enabled',
                  v),
            ),
            _ValueRow(
              title: '聚合搜索并发数',
              subtitle: '${ref.watch(searchConcurrencyProvider)}',
              info: '同时搜几个源，默认 6，范围 1–32。',
              onTap: () => _pickInt(
                context,
                title: '聚合搜索并发数',
                value: ref.watch(searchConcurrencyProvider),
                min: 1,
                max: 32,
                onPicked: (v) => saveIntSetting(
                    ref, searchConcurrencyProvider, 'search_concurrency', v),
              ),
            ),
            _ValueRow(
              title: '单源超时',
              subtitle: '${ref.watch(searchTimeoutProvider)} 秒',
              info: '一个源搜多久没回就当它超时，只坏自己，不拖住别的源。默认 20 秒。',
              onTap: () => _pickInt(
                context,
                title: '单源超时（秒）',
                value: ref.watch(searchTimeoutProvider),
                min: 5,
                max: 120,
                onPicked: (v) => saveIntSetting(ref,
                    searchTimeoutProvider, 'search_timeout_seconds', v),
              ),
            ),
          ],
          if (_match('存储 缓存 数据目录 清理')) ...[
            const SectionTitle(title: '存储'),
            _NavRow(
              title: '缓存设置',
              subtitle: '自动缓存、清理缓存',
              info: '缓存只自动缓存后续章节，不做手动下载；isCacheable() 返回 false 的源一集都不下；集数上不出现感叹号。',
              onTap: () => context.push('/cache-settings'),
            ),
            _NavRow(
              title: '备份与恢复',
              subtitle: '本地备份、坚果云同步',
              info: '换机可恢复。关 App 时自动备份（默认 1 天一次）；启动时检查云端新备份，有更新的会问要不要恢复。',
              onTap: () => context.push('/backup'),
            ),
          ],
          if (_match('关于 源管理 日志 同步 播放 版本 收听统计')) ...[
            const SectionTitle(title: '关于'),
            _NavRow(
              title: '源管理',
              subtitle: '导入 JS/ZIP、JAR 插件源',
              info: '按插件折叠管理源：导入、启用/停用、排序、测试、登录、调试日志。',
              onTap: () => context.push('/sources'),
            ),
            _NavRow(
              title: '云同步',
              subtitle: ref.watch(syncEnabledProvider) ? '已开启' : '未开启',
              info: '坚果云 WebDAV 同步书架、播放记录、每集进度、书签。默认关闭。',
              onTap: () => context.push('/sync'),
            ),
            _NavRow(
              title: 'WebDAV 播放',
              subtitle: '能成书、能选集、能连续播',
              info: 'WebDAV 上的音频能成书、选集、连续播、不断点。',
              onTap: () => context.push('/webdav-play'),
            ),
            _NavRow(
              title: '运行日志',
              subtitle: '查看与复制日志',
              info: '关键操作与错误的日志，能复制，不存本地文件以外的东西。',
              onTap: () => context.push('/logs'),
            ),
            _NavRow(
              title: '收听统计',
              subtitle: '今日与累计收听',
              info: '今日收听了多久，一共收听了多久，听完几本书。也可以长按底栏中间的播放键查看。',
              onTap: () => _showListenStats(context),
            ),
            const _AboutRow(),
          ],
        ],
      ),
    );
  }

  Future<void> _pickFontScale(BuildContext context) async {
    final current = ref.read(fontScaleProvider);
    final picked = await showDialog<double>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('字体大小'),
        children: [
          for (final e in const [
            [0.9, '小'],
            [1.0, '标准'],
            [1.15, '大'],
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e[0] as double),
              child: Row(
                children: [
                  Text(e[1] as String),
                  const Spacer(),
                  if (current == (e[0] as double))
                    const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) await saveFontScale(ref, picked);
  }

  Future<void> _pickInt(
    BuildContext context, {
    required String title,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onPicked,
  }) async {
    final controller = TextEditingController(text: '$value');
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(hintText: '$min–$max'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim()) ?? value;
              Navigator.pop(ctx, v.clamp(min, max));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _showListenStats(BuildContext context) async {
    try {
      final stats = await ListenStats.fetchListenStats();
      final today = _asInt(stats['todaySeconds']);
      final total = _asInt(stats['totalSeconds']);
      final finished = _asInt(stats['finishedBooks']);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('收听统计'),
          content: Text(
            '今日收听了 ${formatListen(today)}，一共收听了 ${formatListen(total)}，共听完 $finished 本书。',
            style: const TextStyle(fontSize: 15, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('收听统计暂时读不到')),
      );
    }
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String info;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.info,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InfoRow(
      title: title,
      subtitle: subtitle,
      info: info,
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}

class _NavRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String info;
  final VoidCallback onTap;

  const _NavRow({
    required this.title,
    required this.subtitle,
    required this.info,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InfoRow(
      title: title,
      subtitle: subtitle,
      info: info,
      trailing:
          Icon(Icons.chevron_right, size: 20, color: context.subtleColor),
      onTap: onTap,
    );
  }
}

class _ValueRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String info;
  final VoidCallback onTap;

  const _ValueRow({
    required this.title,
    required this.subtitle,
    required this.info,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InfoRow(
      title: title,
      subtitle: subtitle,
      info: info,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(subtitle, style: TextStyle(fontSize: 13, color: context.subtleColor)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, size: 20, color: context.subtleColor),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow();

  @override
  Widget build(BuildContext context) {
    return const InfoRow(
      title: '随意听书',
      subtitle: '版本 1.0.3+6 · 本地音频 / 视频播放器',
      info: '本地音频 / 视频播放器。内容只从导入的插件来。',
    );
  }
}
