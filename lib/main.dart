import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_constants.dart';
import 'core/database/app_database.dart';
import 'core/di/providers.dart';
import 'core/log/app_logger.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/listen_stats.dart';
import 'features/audio/data/audio_handler.dart';
import 'features/backup/backup_page.dart';
import 'features/backup/log_page.dart';
import 'features/library/collection_pages.dart';
import 'features/library/library_page.dart';
import 'features/presentation/discover_page.dart';
import 'features/presentation/home_page.dart';
import 'features/search/search_page.dart';
import 'features/settings/cache_settings_page.dart';
import 'features/settings/playback_settings_page.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/theme_picker_page.dart';
import 'features/settings/webdav_play_page.dart';
import 'features/settings/widget_lock_page.dart';
import 'features/sync/sync_page.dart';
import 'features/ua/presentation/ua_settings_page.dart';
import 'plugins/data/home_feed.dart';
import 'plugins/data/plugin_resume.dart';
import 'plugins/presentation/source_center_page.dart';
import 'shared/widgets/common.dart';
import 'plugins/presentation/source_search_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();

  // 老版本默认深色，这里统一迁到暖色浅色（只做一次，之后用户手动改的尊重）
  if (!(prefs.getBool('theme_migrated_warm') ?? false)) {
    await prefs.setInt(AppConstants.keyThemeMode, 1);
    await prefs.setInt(AppConstants.keyThemeColor, 0);
    await prefs.setBool('theme_migrated_warm', true);
  }

  final db = AppDatabase();
  appLogger.attachDatabase(db);

  // 初始化音频后台服务（通知栏 / 后台播放）。
  // 加超时与降级：部分设备（尤其旧安卓）绑定前台服务可能失败或卡住，
  // 这里保证无论如何都能进入主界面，避免启动一直白屏。
  try {
    audioHandler = await AudioService.init(
      builder: () => MyAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.localreader.channel.audio',
        androidNotificationChannelName: '随意听书播放',
        androidNotificationOngoing: true,
      ),
    ).timeout(const Duration(seconds: 8));
  } catch (e, st) {
    appLogger.error('音频后台服务初始化失败，已降级为无通知栏模式',
        error: e, stack: st);
    audioHandler = MyAudioHandler();
  }

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 全面屏：内容延伸到状态栏/导航栏下方，由各页面自己避让
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
    ],
    child: const MyApp(),
  ));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final themeColor = ref.watch(themeColorProvider);
    final followSystemDark = ref.watch(followSystemDarkProvider);
    final systemDark = WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    // 墨夜是独立一套，一直保持黑色，不跟随系统也不看明暗模式
    final isNight = themeColor == AppTheme.nightSchemeIndex;
    final effectiveMode = isNight
        ? ThemeMode.dark
        : (followSystemDark
            ? ThemeMode.system
            : resolveThemeMode(themeMode));
    final isDark = isNight ||
        (followSystemDark
            ? systemDark
            : (themeMode == 2 || (themeMode == 0 && systemDark)));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(themeColor),
        darkTheme: AppTheme.dark(themeColor),
        themeMode: effectiveMode,
        // 问题 2：教程页已去掉，打开 App 直接进书源页（MainShell）
        home: const MainShell(),
        onGenerateRoute: _onGenerateRoute,
      ),
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/audio-search':
        return MaterialPageRoute(
            builder: (_) => const SearchPage(type: AppConstants.typeAudio),
            settings: settings);
      case '/video-search':
        return MaterialPageRoute(
            builder: (_) => const SearchPage(type: AppConstants.typeVideo),
            settings: settings);
      case '/backup':
        return MaterialPageRoute(
            builder: (_) => const BackupPage(), settings: settings);
      case '/settings':
        return MaterialPageRoute(
            builder: (_) => const SettingsPage(), settings: settings);
      case '/playback-settings':
        return MaterialPageRoute(
            builder: (_) => const PlaybackSettingsPage(), settings: settings);
      case '/cache-settings':
        return MaterialPageRoute(
            builder: (_) => const CacheSettingsPage(), settings: settings);
      case '/widget-lock':
        return MaterialPageRoute(
            builder: (_) => const WidgetLockPage(), settings: settings);
      case '/webdav-play':
        return MaterialPageRoute(
            builder: (_) => const WebDavPlayPage(), settings: settings);
      case '/library':
        return MaterialPageRoute(
            builder: (_) => const LibraryPage(), settings: settings);
      case '/logs':
        return MaterialPageRoute(
            builder: (_) => const LogPage(), settings: settings);
      case '/ua-settings':
        return MaterialPageRoute(
            builder: (_) => const UaSettingsPage(), settings: settings);
      case '/theme':
        return MaterialPageRoute(
            builder: (_) => const ThemePickerPage(), settings: settings);
      case '/sources':
        return MaterialPageRoute(
            builder: (_) => const SourceCenterPage(), settings: settings);
      case '/sync':
        return MaterialPageRoute(
            builder: (_) => const SyncPage(), settings: settings);
      case '/source-search':
        return MaterialPageRoute(
            builder: (_) => const SourceSearchPage(
                type: AppConstants.typeAudio),
            settings: settings);
      case '/source-search-video':
        return MaterialPageRoute(
            builder: (_) => const SourceSearchPage(
                type: AppConstants.typeVideo),
            settings: settings);
      case '/favorite-audio':
        return MaterialPageRoute(
            builder: (_) => const CollectionPage(
                kind: CollectionKind.favorite, initialType: AppConstants.typeAudio),
            settings: settings);
      case '/favorite-video':
        return MaterialPageRoute(
            builder: (_) => const CollectionPage(
                kind: CollectionKind.favorite, initialType: AppConstants.typeVideo),
            settings: settings);
      case '/history-audio':
        return MaterialPageRoute(
            builder: (_) => const CollectionPage(
                kind: CollectionKind.history, initialType: AppConstants.typeAudio),
            settings: settings);
      case '/history-video':
        return MaterialPageRoute(
            builder: (_) => const CollectionPage(
                kind: CollectionKind.history, initialType: AppConstants.typeVideo),
            settings: settings);
      case '/favorites':
        return MaterialPageRoute(
            builder: (_) => const CollectionPage(
                kind: CollectionKind.favorite),
            settings: settings);
      case '/history':
        return MaterialPageRoute(
            builder: (_) => const CollectionPage(kind: CollectionKind.history),
            settings: settings);
      case '/bookmarks':
        return MaterialPageRoute(
            builder: (_) => const BookmarkListPage(), settings: settings);
    }
    return null;
  }
}

/// 主壳：底部导航固定五项：书源 / 当前源真名 / 中间大播放键 / 收藏 / 历史
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  @override
  Widget build(BuildContext context) {
    final source = ref.watch(activeHomeSourceProvider);
    final index = ref.watch(shellTabProvider);
    final pages = <Widget>[
      const HomePage(),
      const DiscoverPage(),
      const CollectionPage(kind: CollectionKind.favorite),
      const CollectionPage(kind: CollectionKind.history),
    ];
    final safeIndex = index >= pages.length ? 0 : index;
    return Scaffold(
      body: IndexedStack(index: safeIndex, children: pages),
      bottomNavigationBar: StreamBuilder<PlaybackState>(
        stream: audioHandler.playbackState,
        initialData: audioHandler.playbackState.valueOrNull,
        builder: (context, snap) {
          final state = snap.data;
          return _AppBottomBar(
            index: safeIndex,
            playing: state?.playing ?? false,
            sourceName: source?.name ?? '发现',
            onPlayTap: () => openMostRecentResume(context, ref),
            onPlayLongPress: () => ListenStats.showStatsDialog(context),
            onTap: (i) => ref.read(shellTabProvider.notifier).state = i,
          );
        },
      ),
    );
  }
}

/// 悬浮式底部导航：书源 / 当前源名 / 大播放键 / 收藏 / 历史
class _AppBottomBar extends StatelessWidget {
  final int index;
  final bool playing;
  final String sourceName;
  final ValueChanged<int> onTap;
  final VoidCallback onPlayTap;
  final VoidCallback onPlayLongPress;

  const _AppBottomBar({
    required this.index,
    required this.playing,
    required this.sourceName,
    required this.onTap,
    required this.onPlayTap,
    required this.onPlayLongPress,
  });

  List<Map<String, dynamic>> get _items => [
        {'label': '书源', 'icon': Icons.home_outlined, 'active': Icons.home},
        {'label': sourceName, 'icon': Icons.explore_outlined, 'active': Icons.explore},
        {'label': '收藏', 'icon': Icons.favorite_outline, 'active': Icons.favorite},
        {'label': '历史', 'icon': Icons.history_outlined, 'active': Icons.history},
      ];

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: context.palette.outline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: _tab(context, 0)),
          Expanded(child: _tab(context, 1)),
          const SizedBox(width: 66),
          Expanded(child: _tab(context, 2)),
          Expanded(child: _tab(context, 3)),
        ],
      ),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 10),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Padding(padding: const EdgeInsets.only(top: 16), child: bar),
            Positioned(top: 0, child: _playButton(context)),
          ],
        ),
      ),
    );
  }

  /// 底部栏标签字号按名字长度自适应，保证源真名完整显示
  /// （问题 12：「听书聚合 v1.0.8」9 个字也要完整显示，最小降到 7）
  double _labelFontSize(String label) {
    final len = label.length;
    if (len <= 4) return 10;
    if (len <= 6) return 9;
    if (len <= 8) return 8;
    return 7;
  }

  Widget _tab(BuildContext context, int i) {
    final selected = i == index;
    final primary = Theme.of(context).colorScheme.primary;
    final it = _items[i];
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => onTap(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: selected ? context.palette.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              (selected ? it['active'] : it['icon']) as IconData,
              size: 20,
              color: selected ? primary : context.subtleColor,
            ),
            const SizedBox(height: 2),
            Text(
              it['label'] as String,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                // 源真名完整显示：4 字及以内 10，5–6 字 9，7–8 字 8，更长 7
                fontSize: _labelFontSize(it['label'] as String),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? primary : context.subtleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 中间凸起的大圆钮：在播显示暂停，暂停/空闲显示播放。
  /// 点一下打开播放器接着播；长按弹出收听统计。
  Widget _playButton(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: primary,
        shape: const CircleBorder(),
        elevation: 8,
        shadowColor: primary.withOpacity(0.45),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPlayTap,
          onLongPress: onPlayLongPress,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 30,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 管理页：收藏 / 历史 / 书签 / 搜索（听书视频分开）
class LibraryHubPage extends StatelessWidget {
  const LibraryHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('管理')),
      body: ListView(
        padding: pagePadding(context, top: 16, bottom: 16),
        children: [
          _section(context, '收藏', [
            _tile(context, Icons.favorite_outline, '听书收藏', '/favorite-audio'),
            _tile(context, Icons.favorite_outline, '视频收藏', '/favorite-video'),
          ]),
          _section(context, '历史', [
            _tile(context, Icons.history, '最近听书', '/history-audio'),
            _tile(context, Icons.history, '最近视频', '/history-video'),
          ]),
          _section(context, '书签', [
            _tile(context, Icons.bookmark_outline, '书签管理', '/bookmarks'),
          ]),
          _section(context, '搜索', [
            _tile(context, Icons.search, '听书搜索', '/audio-search'),
            _tile(context, Icons.search, '视频搜索', '/video-search'),
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(title, style: Theme.of(context).textTheme.bodySmall),
          ),
          ...children,
        ],
      );

  Widget _tile(
          BuildContext context, IconData icon, String title, String route) =>
      Card(
        color: Theme.of(context).cardColor,
        child: ListTile(
          leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed(route),
        ),
      );
}
