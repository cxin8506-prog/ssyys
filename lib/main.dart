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
import 'features/audio/presentation/audio_library_page.dart';
import 'features/audio/presentation/import_picker_page.dart';
import 'features/backup/backup_page.dart';
import 'features/backup/log_page.dart';
import 'features/library/collection_pages.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/presentation/home_page.dart';
import 'features/search/search_page.dart';
import 'features/settings/settings_page.dart';
import 'features/ua/presentation/ua_settings_page.dart';
import 'features/video/presentation/video_library_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase();
  appLogger.attachDatabase(db);

  // 初始化音频后台服务（通知栏 / 后台播放）
  audioHandler = await AudioService.init(
    builder: () => MyAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.localreader.channel.audio',
      androidNotificationChannelName: '本地听书播放',
      androidNotificationOngoing: true,
    ),
  );

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

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
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: resolveThemeMode(themeMode),
      home: onboardDone ? const MainShell() : const OnboardingPage(),
      onGenerateRoute: _onGenerateRoute,
    );
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case '/import-picker':
        return MaterialPageRoute(
            builder: (_) => const ImportPickerPage(), settings: settings);
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
      case '/favorite-audio':
        return MaterialPageRoute(
            builder: (_) => const CollectionPage(
                kind: CollectionKind.favorite, type: AppConstants.typeAudio),
            settings: settings);
      case '/favorite-video':
        return MaterialPageRoute(
            builder: (_) => const CollectionPage(
                kind: CollectionKind.favorite, type: AppConstants.typeVideo),
            settings: settings);
      case '/history-audio':
        return MaterialPageRoute(
            builder: (_) => const CollectionPage(
                kind: CollectionKind.history, type: AppConstants.typeAudio),
            settings: settings);
      case '/history-video':
        return MaterialPageRoute(
            builder: (_) => const CollectionPage(
                kind: CollectionKind.history, type: AppConstants.typeVideo),
            settings: settings);
      case '/bookmarks':
        return MaterialPageRoute(
            builder: (_) => const BookmarkListPage(), settings: settings);
    }
    return null;
  }
}

/// 主壳：底部导航
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final videoEnabled = ref.watch(videoEnabledProvider);
    final pages = <Widget>[
      const HomePage(),
      const AudioLibraryPage(),
      if (videoEnabled) const VideoLibraryPage(),
      const LibraryHubPage(),
      const SettingsPage(),
    ];
    final items = <BottomNavigationBarItem>[
      const BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined), label: '首页'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.headphones_outlined), label: '听书'),
      if (videoEnabled)
        const BottomNavigationBarItem(
            icon: Icon(Icons.movie_outlined), label: '视频'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.library_books_outlined), label: '管理'),
      const BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined), label: '设置'),
    ];

    if (_index >= pages.length) _index = 0;

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: items,
        selectedFontSize: 12,
        unselectedFontSize: 11,
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
        padding: const EdgeInsets.all(16),
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
        color: AppTheme.darkSurface,
        child: ListTile(
          leading: Icon(icon, color: AppTheme.primary),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed(route),
        ),
      );
}
