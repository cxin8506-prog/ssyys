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
import 'features/audio/data/audio_handler.dart';
import 'features/audio/data/repository_providers.dart';
import 'features/audio/domain/media_item.dart' as domain;
import 'features/audio/presentation/audio_player_page.dart';
import 'features/backup/backup_page.dart';
import 'features/backup/log_page.dart';
import 'features/library/collection_pages.dart';
import 'features/library/library_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/presentation/discover_page.dart';
import 'features/presentation/home_page.dart';
import 'features/search/search_page.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/theme_picker_page.dart';
import 'features/sync/sync_page.dart';
import 'features/video/presentation/video_player_page.dart';
import 'plugins/presentation/source_center_page.dart';
import 'shared/widgets/common.dart';
import 'plugins/presentation/source_search_page.dart';
import 'features/ua/presentation/ua_settings_page.dart';

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

  final onboardDone = prefs.getBool(AppConstants.keyOnboardDone) ?? false;

  runApp(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
    ],
    child: MyApp(onboardDone: onboardDone),
  ));
}

class MyApp extends ConsumerWidget {
  final bool onboardDone;
  const MyApp({super.key, required this.onboardDone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final themeColor = ref.watch(themeColorProvider);
    final systemDark = WidgetsBinding.instance.platformDispatcher.platformBrightness ==
        Brightness.dark;
    final isDark = themeMode == 2 || (themeMode == 0 && systemDark);

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
        themeMode: resolveThemeMode(themeMode),
        home: onboardDone ? const MainShell() : const OnboardingPage(),
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

/// 主壳：底部导航（首页 / 书架 / 源 / 我的）
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const HomePage(),
      const LibraryPage(),
      const DiscoverPage(),
      const SettingsPage(),
    ];
    if (_index >= pages.length) _index = 0;
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: StreamBuilder<PlaybackState>(
        stream: audioHandler.playbackState,
        initialData: audioHandler.playbackState.valueOrNull,
        builder: (context, snap) {
          final state = snap.data;
          return _AppBottomBar(
            index: _index,
            playing: state?.playing ?? false,
            hasMedia: state?.playing ?? false,
            onPlayTap: () => _openPlayer(),
            onTap: (i) => setState(() => _index = i),
          );
        },
      ),
    );
  }

  /// 中间大播放键：有在播的直接回播放页，没有就打开最近听/看的那条
  Future<void> _openPlayer() async {
    final playing = audioHandler.playbackState.valueOrNull?.playing ?? false;
    if (playing) {
      await audioHandler.pause();
      return;
    }
    final audio = await ref
        .read(continueListProvider(AppConstants.typeAudio).future)
        .catchError((_) => <domain.MediaItem>[]);
    final video = await ref
        .read(continueListProvider(AppConstants.typeVideo).future)
        .catchError((_) => <domain.MediaItem>[]);
    final items = <domain.MediaItem>[...audio, ...video]..sort((a, b) {
        final x = a.lastReadAt ?? a.addedAt;
        final y = b.lastReadAt ?? b.addedAt;
        return y.compareTo(x);
      });
    if (items.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('还没有在播的内容，先去搜一部吧'),
        behavior: SnackBarBehavior.floating,
      ));
      setState(() => _index = 0);
      return;
    }
    await _openRecent(items.first);
  }

  /// 打开最近在听/在看的那一条
  Future<void> _openRecent(domain.MediaItem item) async {
    final chapters =
        await ref.read(libraryRepositoryProvider).chapters(item.id);
    if (!mounted || chapters.isEmpty) return;
    if (item.isAudio) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AudioPlayerPage(item: item)),
      );
    } else {
      final paths = chapters.map((c) => c.path!).toList();
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VideoPlayerPage(
            path: paths.first, playlist: paths, title: item.title),
      ));
    }
    if (!mounted) return;
    ref.invalidate(continueListProvider(
        item.isAudio ? AppConstants.typeAudio : AppConstants.typeVideo));
  }
}

/// 悬浮式底部导航：首页 / 书架 / 大播放键 / 发现 / 我的
class _AppBottomBar extends StatelessWidget {
  final int index;
  final bool playing;
  final bool hasMedia;
  final ValueChanged<int> onTap;
  final VoidCallback onPlayTap;

  const _AppBottomBar({
    required this.index,
    required this.playing,
    required this.hasMedia,
    required this.onTap,
    required this.onPlayTap,
  });

  static const _items = <Map<String, dynamic>>[
    {'label': '首页', 'icon': Icons.home_outlined, 'active': Icons.home},
    {'label': '书架', 'icon': Icons.menu_book_outlined, 'active': Icons.menu_book},
    {'label': '发现', 'icon': Icons.explore_outlined, 'active': Icons.explore},
    {'label': '我的', 'icon': Icons.person_outline, 'active': Icons.person},
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
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? primary : context.subtleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 中间凸起的大圆钮：在播显示暂停，暂停/空闲显示播放
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
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: hasMedia && !playing ? 28 : 30,
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
