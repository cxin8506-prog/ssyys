import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_constants.dart';
import 'core/database/app_database.dart';
import 'core/database/library_repository.dart';
import 'core/di/providers.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/cover_color.dart';
import 'core/theme/theme_providers.dart';
import 'core/utils/listen_stats.dart';
import 'features/audio/data/audio_handler.dart';
import 'features/audio/presentation/audio_player_page.dart';
import 'features/backup/backup_page.dart';
import 'features/backup/backup_service.dart';
import 'features/backup/log_page.dart';
import 'features/presentation/main_shell.dart';
import 'features/settings/cache_settings_page.dart';
import 'features/settings/playback_settings_page.dart';
import 'features/settings/settings_page.dart';
import 'features/settings/theme_picker_page.dart';
import 'features/settings/webdav_play_page.dart';
import 'features/sync/progress_sync.dart';
import 'features/sync/sync_page.dart';
import 'features/sync/webdav_client.dart';
import 'features/ua/presentation/ua_settings_page.dart';
import 'features/video/presentation/video_player_page.dart';
import 'plugins/data/plugin_providers.dart';
import 'plugins/data/plugin_resume.dart';
import 'plugins/engine/plugin_engine.dart';
import 'plugins/model/plugin_source.dart';
import 'plugins/presentation/source_book_page.dart';
import 'plugins/presentation/source_center_page.dart';
import 'features/search/source_search_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 先装报错定位：首帧 build 抛错时 release 版只显示灰屏，
  // 装上后错会写进 error_log.txt，屏上也直接显示报错文字。
  _installErrorReporting();

  final prefs = await SharedPreferences.getInstance();
  await migrateLegacyTheme(prefs);

  // 封面取色种子先恢复（内存 + 磁盘），进播放页不闪回主题色。
  await CoverColorCache.restore(prefs);

  final db = AppDatabase();
  final repo = LibraryRepository(db);

  // 音频后台服务：不要在 main() 最开头就 init（Activity 贴上引擎有
  // 先后，太早 init 会报 Activity 没提供 FlutterEngine）。
  // 这里先把 binding / prefs / 数据库准备好再 init；init 失败等
  // 800ms 再试一次，还不行才降级为无通知栏模式直连播放。
  // 配置用播放器组的 audioServiceConfig，不自己拼一份。
  final audioHandler = await _initAudioHandler(repo);

  // 「我的听书」JAR 源调 MyExt.playerControl / todayPlaybackTime 时，
  // 原生侧经过 suishou/player 通道调进来，转给 audioHandler / 收听统计。
  MethodChannel('suishou/player').setMethodCallHandler((call) async {
    switch (call.method) {
      case 'play':
        await audioHandler.play();
        break;
      case 'pause':
        await audioHandler.pause();
        break;
      case 'skipToNext':
        await audioHandler.skipToNext();
        break;
      case 'skipToPrevious':
        await audioHandler.skipToPrevious();
        break;
      case 'rewind':
        await audioHandler.rewind();
        break;
      case 'fastForward':
        await audioHandler.fastForward();
        break;
      case 'stop':
        await audioHandler.stop();
        break;
      case 'todayPlaybackTime':
        final stats = await ListenStats.fetchListenStats();
        final today = stats['todaySeconds'];
        final seconds = today is int
            ? today
            : int.tryParse('$today') ?? 0;
        return seconds * 1000;
      default:
        throw PlatformException(
            code: 'NOT_IMPLEMENTED', message: '未知方法 ${call.method}');
    }
    return null;
  });

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 沉浸状态栏/导航栏默认开：全面屏，内容延伸到状态栏/导航栏下方，
  // 透明栏 + 图标亮度跟深浅走（MyApp 里按 isDark 算）。
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      databaseProvider.overrideWithValue(db),
      audioHandlerProvider.overrideWithValue(audioHandler),
    ],
    child: const MyApp(),
  ));
}

/// 启动报错定位：release 版首帧 build 抛错时只显示灰屏（ErrorWidget
/// 的中灰底），看不到错在哪。手机上旧版留的数据（旧 app.db、旧源
/// 索引）解析时才触发的错，桌面空库复现不了，所以先把报错原文抓出来。
///
/// 两路：① 写进应用文档目录的 error_log.txt（追加写，方便连着看
/// 多次启动的错）；② 屏上直接显示报错文字，用户截图就能看到。
/// 写日志失败只记 debugPrint，绝不抛错——handler 里再抛错会死循环。
void _installErrorReporting() {
  FlutterError.onError = (FlutterErrorDetails details) {
    final text = '--- ${DateTime.now().toIso8601String()} ---\n'
        '${details.exception}\n${details.stack ?? ''}\n';
    debugPrint(text);
    unawaited(_appendErrorLog(text));
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    // 自带 Directionality：ErrorWidget 可能替掉还没包进 MaterialApp
    // 的 widget，那时树里没有 Directionality，Text 会再抛错。
    final message = '启动出错了，请截图发给开发者：\n\n'
        '${details.exception}\n${details.stack ?? ''}';
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Text(
            message,
            style: const TextStyle(color: Colors.black, fontSize: 14),
          ),
        ),
      ),
    );
  };
}

/// 把报错文本追加进 error_log.txt（应用文档目录，和 app.db 同目录）。
/// fire-and-forget：onError 是同步回调，这里不 await；失败只记日志不抛错。
Future<void> _appendErrorLog(String text) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/error_log.txt');
    await file.writeAsString(text, mode: FileMode.append, flush: true);
  } catch (e) {
    debugPrint('写 error_log.txt 失败（只记日志）：$e');
  }
}

/// 初始化音频后台服务：失败等 800ms 再试一次，两次都不行才降级
/// 为直连播放（无通知栏）。正常设备第一次就成功，不多等。
Future<MyAudioHandler> _initAudioHandler(LibraryRepository repo) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      return await AudioService.init(
        builder: () => MyAudioHandler(libraryRepository: repo),
        config: MyAudioHandler.audioServiceConfig,
      ).timeout(Duration(seconds: attempt == 0 ? 6 : 4));
    } catch (e) {
      debugPrint('音频后台服务初始化失败（第 ${attempt + 1} 次）：$e');
      if (attempt == 0) {
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
  }
  debugPrint('音频后台服务初始化失败，已降级为无通知栏模式');
  return MyAudioHandler(libraryRepository: repo);
}

final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const MainShell(),
    ),
    GoRoute(
      path: '/sources',
      builder: (context, state) => const SourceCenterPage(),
    ),
    GoRoute(
      path: '/source/:id',
      builder: (context, state) {
        final id = state.params['id'] ?? '';
        final bookUrl = state.queryParams['bookUrl'] ?? '';
        final title = state.queryParams['title'] ?? '';
        return SourceBookPage(
          sourceId: id,
          bookUrl: bookUrl,
          title: title.isEmpty ? '' : title,
        );
      },
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => SourceSearchPage(
        type: state.queryParams['type'] ?? 'audio',
        initialSourceId: state.queryParams['sourceId'],
      ),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(
      path: '/theme',
      builder: (context, state) => const ThemePickerPage(),
    ),
    GoRoute(
      path: '/playback-settings',
      builder: (context, state) => const PlaybackSettingsPage(),
    ),
    GoRoute(
      path: '/cache-settings',
      builder: (context, state) => const CacheSettingsPage(),
    ),
    GoRoute(
      path: '/ua-settings',
      builder: (context, state) => const UaSettingsPage(),
    ),
    GoRoute(
      path: '/backup',
      builder: (context, state) => const BackupPage(),
    ),
    GoRoute(
      path: '/sync',
      builder: (context, state) => const SyncPage(),
    ),
    GoRoute(
      path: '/logs',
      builder: (context, state) => const LogPage(),
    ),
    GoRoute(
      path: '/webdav-play',
      builder: (context, state) => const WebDavPlayPage(),
    ),
    GoRoute(
      path: '/player',
      builder: (context, state) => const _NotificationPermissionGate(
        child: AudioPlayerPage(),
      ),
    ),
    GoRoute(
      path: '/video-player',
      builder: (context, state) {
        final bookKey = state.queryParams['book'] ?? '';
        final chapter =
            int.tryParse(state.queryParams['chapter'] ?? '') ?? 0;
        final lineId = state.queryParams['lineId'] ?? '';
        return _VideoPlayerRouteLoader(
          bookKey: bookKey,
          chapterIndex: chapter,
          lineId: lineId,
        );
      },
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('随意听书')),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('这个页面不存在'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => context.go('/'),
            child: const Text('回首页'),
          ),
        ],
      ),
    ),
  ),
);

/// 首次进播放页申请通知权限（Android 13+ 的 POST_NOTIFICATIONS，
/// 通知栏播放控制要它；Android 13 以下本来就不用申请）。
///
/// 只问一次：问过就把 `notif_permission_asked_v1` 置 true，用户拒绝
/// 也不再追问（去系统设置里能再开）；不挡页面，申请失败只记日志。
/// 播放器组不负责申请，放 main 的路由层。
class _NotificationPermissionGate extends StatefulWidget {
  const _NotificationPermissionGate({required this.child});

  final Widget child;

  @override
  State<_NotificationPermissionGate> createState() =>
      _NotificationPermissionGateState();
}

class _NotificationPermissionGateState
    extends State<_NotificationPermissionGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askOnce());
  }

  Future<void> _askOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('notif_permission_asked_v1') ?? false) return;
      await prefs.setBool('notif_permission_asked_v1', true);
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    } catch (e) {
      debugPrint('通知权限申请失败（只记日志）：$e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 视频路由加载器：source_book_page 只推
/// `/video-player?book=<sourceId|bookUrl>&chapter=<index>&lineId=...`，
/// 真正的解析在这里做（P 的 VideoPlayerPage 构造器沿用旧签名，
/// 没有 bookKey 自解析分支，所以 main 的路由层先解析好再构造）。
///
/// 步骤：bookKey 拆 sourceId/bookUrl → 源 → getPluginResume 拿断点
/// （同一集才从 positionMs 续播）和上次线路/音色 → bookDetail 拿章节
/// （先取第一页，要点集不在第一页时再取全量）→ lines 拿线路 →
/// content 解析当前集地址 → 构造 VideoPlayerPage。
///
/// playlist 不传：视频页把 playlist[i] 当现成的可播地址直接播，
/// 章节源地址（书页链接）填进去只会播失败；全量预解析也不行——
/// 解析地址常带限时签名（播一次就要重新取），提前解析好等播到
/// 时早过期了。所以视频页一次只播当前这一集，播完显示“已播完”，
/// 想看下一集回书页点下一集（和旧版行为一致）。
/// 切线路走 onSwitchLine：现调 content 解析同一集的新线地址。
class _VideoPlayerRouteLoader extends ConsumerStatefulWidget {
  const _VideoPlayerRouteLoader({
    required this.bookKey,
    required this.chapterIndex,
    required this.lineId,
  });

  final String bookKey;
  final int chapterIndex;
  final String lineId;

  @override
  ConsumerState<_VideoPlayerRouteLoader> createState() =>
      _VideoPlayerRouteLoaderState();
}

class _VideoPlayerRouteLoaderState
    extends ConsumerState<_VideoPlayerRouteLoader> {
  late final Future<_VideoTarget> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<_VideoTarget> _resolve() async {
    final sep = widget.bookKey.indexOf('|');
    if (sep < 0) throw Exception('播放地址不对');
    final sourceId = widget.bookKey.substring(0, sep);
    final bookUrl = widget.bookKey.substring(sep + 1);
    if (sourceId.isEmpty || bookUrl.isEmpty) {
      throw Exception('播放地址不对');
    }
    final source = await ref.read(sourceRepositoryProvider).byId(sourceId);
    if (source == null) throw Exception('找不到这个源，可能已被删除');

    // 断点：同一集才续播；线路/音色沿用上次的。
    final resume = await getPluginResume(widget.bookKey);
    final resumeIndex = _asInt(resume?['chapterIndex']);
    final startAtMs = resumeIndex == widget.chapterIndex
        ? _asInt(resume?['positionMs'])
        : 0;
    final voiceId = '${resume?['voiceId'] ?? ''}';

    final engine = engineForSource(ref, source);
    await engine.attach(source);

    var detail = await _bookDetail(engine, bookUrl, fullPages: false);
    var chapters = _parseChapters(detail);
    if (chapters.isEmpty) throw Exception('这个源没有返回章节');
    if (widget.chapterIndex >= chapters.length) {
      detail = await _bookDetail(engine, bookUrl, fullPages: true);
      chapters = _parseChapters(detail);
      if (chapters.isEmpty) throw Exception('这个源没有返回章节');
    }
    var index = widget.chapterIndex;
    if (index < 0) index = 0;
    if (index >= chapters.length) index = chapters.length - 1;
    final chapterNames = chapters.map(_chapterTitle).toList();
    final bookTitle = '${detail['title'] ?? detail['name'] ?? ''}';

    var lines = _parseList(detail['lines']);
    if (lines.isEmpty) {
      try {
        lines = _parseList(
            await engine.invoke('lines', params: {'url': bookUrl}));
      } catch (_) {}
    }
    final resumeLineId = '${resume?['lineId'] ?? ''}';
    final lineId = widget.lineId.isNotEmpty
        ? widget.lineId
        : (resumeLineId.isNotEmpty
            ? resumeLineId
            : (lines.isNotEmpty ? '${lines.first['id'] ?? ''}' : ''));
    var lineName = '${resume?['lineName'] ?? ''}';
    for (final l in lines) {
      if ('${l['id']}' == lineId) {
        lineName = '${l['name'] ?? l['id']}';
        break;
      }
    }

    final chapterUrl = _chapterUrl(chapters[index]);
    if (chapterUrl.isEmpty) throw Exception('这一集没有播放地址');
    final resolved = await _resolveContent(engine, chapterUrl, voiceId, lineId);
    if (resolved.url.isEmpty) throw Exception('源没有返回可播放地址');

    return _VideoTarget(
      source: source,
      engine: engine,
      bookUrl: bookUrl,
      bookTitle: bookTitle,
      chapterUrl: chapterUrl,
      chapterName: chapterNames[index],
      chapterNames: chapterNames,
      chapterUrls: chapters.map(_chapterUrl).toList(),
      voiceId: voiceId,
      lines: lines,
      lineId: lineId,
      lineName: lineName,
      startAtMs: startAtMs,
      path: resolved.url,
      headers: resolved.headers,
    );
  }

  Future<Map<String, dynamic>> _bookDetail(
    PluginEngine engine,
    String bookUrl, {
    required bool fullPages,
  }) async {
    final raw = await engine.invoke(
      'bookDetail',
      params: {
        'url': bookUrl,
        'loadEpisodes': true,
        'loadFullPages': fullPages,
      },
    );
    if (raw is! Map) throw Exception('详情加载失败');
    return Map<String, dynamic>.from(raw);
  }

  /// 现调 content 解析一章的地址（切线路也走这里：同一集换线解析）。
  Future<_ResolvedMedia> _resolveContent(
    PluginEngine engine,
    String chapterUrl,
    String voiceId,
    String lineId,
  ) async {
    final raw = await engine.invoke(
      'content',
      params: {
        'url': chapterUrl,
        'voiceId': voiceId,
        'lineId': lineId,
      },
    );
    var headers = const <String, String>{};
    if (raw is Map) {
      final h = raw['headers'];
      if (h is Map) {
        headers = h.map((k, v) => MapEntry('$k', '$v'));
      }
    }
    return _ResolvedMedia(url: _mediaUrlOf(raw), headers: headers);
  }

  List<Map<String, dynamic>> _parseChapters(Map<String, dynamic> detail) {
    final raw = detail['episodes'] ?? detail['chapters'] ?? detail['list'];
    return _parseList(raw);
  }

  List<Map<String, dynamic>> _parseList(dynamic raw) {
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['list'] ?? raw['data']) : null);
    if (list is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
      if (e is String) out.add(<String, dynamic>{'title': e, 'url': e});
    }
    return out;
  }

  String _chapterUrl(Map<String, dynamic> c) =>
      '${c['url'] ?? c['audioUrl'] ?? c['href'] ?? ''}';

  String _chapterTitle(Map<String, dynamic> c) =>
      '${c['title'] ?? c['name'] ?? ''}';

  String _mediaUrlOf(dynamic raw) {
    if (raw is String) return raw;
    if (raw is Map) {
      final u = raw['url'] ?? raw['audioUrl'] ?? raw['src'] ?? raw['playUrl'];
      return u == null ? '' : '$u';
    }
    return '';
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse('$v') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_VideoTarget>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('正在解析播放地址…'),
                ],
              ),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          final message = snapshot.error == null
              ? '拿播放地址失败'
              : '拿播放地址失败：${snapshot.error}';
          return Scaffold(
            appBar: AppBar(title: const Text('随意听书')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(message, textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.pop(),
                    child: const Text('返回'),
                  ),
                ],
              ),
            ),
          );
        }
        final t = snapshot.data!;
        return VideoPlayerPage(
          path: t.path,
          network: true,
          headers: t.headers,
          title: t.bookTitle.isEmpty
              ? t.chapterName
              : '${t.bookTitle} · ${t.chapterName}',
          startAtMs: t.startAtMs,
          sourceId: t.source.id,
          sourceName: t.source.name,
          bookUrl: t.bookUrl,
          bookTitle: t.bookTitle,
          chapterNames: t.chapterNames,
          lineName: t.lineName,
          voiceId: t.voiceId,
          lines: t.lines,
          currentLineId: t.lineId,
          onSwitchLine: (newLineId) async {
            final resolved = await t.resolveLine(newLineId);
            if (resolved.isEmpty) throw Exception('这条线路没有返回地址');
            return resolved;
          },
          // 只听声音自动切下一章：按需现解析，不预解析（限时签名会过期）；
          // 解析失败返回 null，handler 停住。
          onResolveChapter: (i) async {
            final m = await t.resolveChapterMedia(i);
            return (m == null || m.url.isEmpty) ? null : m.url;
          },
          onResolveChapterHeaders: (i) => t.headersFor(i),
        );
      },
    );
  }
}

/// content 解析结果：地址 + 播放要带的头（Referer/UA 等）。
class _ResolvedMedia {
  const _ResolvedMedia({required this.url, required this.headers});

  final String url;
  final Map<String, String> headers;
}

/// 路由加载器解析好的视频目标：当前集地址 + 构造 VideoPlayerPage
/// 要的全部参数 + 切线路时现解析同一集的回调。
class _VideoTarget {
  _VideoTarget({
    required this.source,
    required this.engine,
    required this.bookUrl,
    required this.bookTitle,
    required this.chapterUrl,
    required this.chapterName,
    required this.chapterNames,
    required this.chapterUrls,
    required this.voiceId,
    required this.lines,
    required this.lineId,
    required this.lineName,
    required this.startAtMs,
    required this.path,
    required this.headers,
  });

  final PluginSource source;
  final PluginEngine engine;
  final String bookUrl;
  final String bookTitle;
  final String chapterUrl;
  final String chapterName;
  final List<String> chapterNames;

  /// 全部章节的源地址（与 chapterNames 一一对应）：只听声音自动切
  /// 下一章时按需解析，不预解析（分段地址带限时签名，提前解析会过期）。
  final List<String> chapterUrls;
  final String voiceId;
  final List<Map<String, dynamic>> lines;
  final String lineId;
  final String lineName;
  final int startAtMs;
  final String path;
  final Map<String, String> headers;

  /// 已解析过的某一章请求头（下标 → 头）：和 resolveChapterMedia
  /// 同一次解析里拿到的，播下一章时取。
  final Map<int, Map<String, String>> _chapterHeaders =
      <int, Map<String, String>>{};

  /// 按需解析一章的可播地址 + 请求头（只听声音自动切下一章用）。
  /// 解析失败返回 null，调用方停住，不抛错。
  Future<_ResolvedMedia?> resolveChapterMedia(int index) async {
    if (index < 0 || index >= chapterUrls.length) return null;
    final url = chapterUrls[index];
    if (url.isEmpty) return null;
    try {
      final raw = await engine.invoke(
        'content',
        params: {
          'url': url,
          'voiceId': voiceId,
          'lineId': lineId,
        },
      );
      var headers = const <String, String>{};
      if (raw is Map) {
        final h = raw['headers'];
        if (h is Map) {
          headers = h.map((k, v) => MapEntry('$k', '$v'));
        }
      }
      final u = raw is String
          ? raw
          : (raw is Map
              ? '${raw['url'] ?? raw['audioUrl'] ?? raw['src'] ?? raw['playUrl'] ?? ''}'
              : '');
      if (u.isEmpty) return null;
      _chapterHeaders[index] = headers;
      return _ResolvedMedia(url: u, headers: headers);
    } catch (_) {
      return null;
    }
  }

  /// 已解析过的某一章请求头；没解析过返回空。
  Map<String, String> headersFor(int index) =>
      _chapterHeaders[index] ?? const <String, String>{};

  /// 切线路：现调 content 解析同一集的新线地址。
  Future<String> resolveLine(String newLineId) async {
    final raw = await engine.invoke(
      'content',
      params: {
        'url': chapterUrl,
        'voiceId': voiceId,
        'lineId': newLineId,
      },
    );
    if (raw is String) return raw;
    if (raw is Map) {
      final u = raw['url'] ?? raw['audioUrl'] ?? raw['src'] ?? raw['playUrl'];
      return u == null ? '' : '$u';
    }
    return '';
  }
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  bool _bootChecked = false;

  late final SharedPreferences _prefs;
  late final AppDatabase _db;
  late final LibraryRepository _repo;

  /// 播放状态订阅：播着才起 15 秒进度同步定时器，停了就停掉。
  StreamSubscription<PlaybackState>? _playbackSub;
  Timer? _syncTimer;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prefs = ref.read(sharedPrefsProvider);
    _db = ref.read(databaseProvider);
    _repo = ref.read(libraryRepositoryProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootCheck());
    final handler = ref.read(audioHandlerProvider);
    _playbackSub = handler.playbackState.listen(_onPlaybackState);
    _onPlaybackState(handler.playbackState.value);
  }

  @override
  void dispose() {
    _playbackSub?.cancel();
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 关 App 时（detached）自动备份：S 的 runAutoBackupIfDue，
  /// 默认开、间隔默认 1 天，只在间隔到了才备；失败只记日志。
  /// 注意：系统杀进程时 detached 不一定跑得到，备不上是已知缺口，
  /// 不是每次关 App 都一定备。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _runAutoBackupOnClose();
    }
  }

  Future<void> _runAutoBackupOnClose() async {
    try {
      await BackupService(db: _db).runAutoBackupIfDue();
    } catch (e) {
      debugPrint('关 App 自动备份失败（只记日志）：$e');
    }
  }

  /// 播放状态变化 → 15 秒进度同步定时器的起停。
  void _onPlaybackState(PlaybackState state) {
    if (state.playing) {
      _syncTimer ??= Timer.periodic(
        const Duration(seconds: 15),
        (_) => _syncProgressOnce(),
      );
    } else {
      _syncTimer?.cancel();
      _syncTimer = null;
    }
  }

  /// 15 秒定时进度同步（S 的 ProgressSync.syncAll：先下载云端更新的，
  /// 再上传在听的书）。只在播放期间跑；重叠的一次跳过；失败只记日志
  /// 不打扰用户。门禁：同步总开关 + 进度同步开关 + WebDAV 配置齐全，
  /// 缺一个就不跑（默认进度同步是关的，要在同步页里打开才同步）。
  Future<void> _syncProgressOnce() async {
    if (!mounted || _syncing) return;
    _syncing = true;
    try {
      if (!(_prefs.getBool(AppConstants.keySyncEnabled) ??
          AppConstants.defaultSyncEnabled)) {
        return;
      }
      if (!(_prefs.getBool(AppConstants.keySyncProgress) ??
          AppConstants.defaultSyncProgress)) {
        return;
      }
      final url = _prefs.getString(AppConstants.keySyncUrl) ?? '';
      final user = _prefs.getString(AppConstants.keySyncUser) ?? '';
      final pass = _prefs.getString(AppConstants.keySyncPass) ?? '';
      if (url.isEmpty || user.isEmpty || pass.isEmpty) return;
      final client = WebDavClient(
        baseUrl: url,
        username: user,
        password: pass,
      );
      await ProgressSync.syncAll(repo: _repo, client: client);
    } catch (e) {
      debugPrint('进度同步失败（只记日志）：$e');
    } finally {
      _syncing = false;
    }
  }

  /// 启动后一次：云端备份检查（有更新的就弹框问要不要恢复）。
  /// 自动备份不在启动时做，关 App 时才做（见 didChangeAppLifecycleState）。
  Future<void> _bootCheck() async {
    if (_bootChecked) return;
    _bootChecked = true;
    try {
      final info = await checkCloudBackup();
      if (!mounted || info == null) return;
      final name = '${info['name'] ?? '云端备份'}';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('发现云端新备份'),
          content: Text('云端有一份更新的备份「$name」，要恢复吗？'),
          actions: [
            TextButton(
              onPressed: () async {
                // 点取消：把本地 lastBackup 置为二者较大值，
                // 下次不再问这一份（S 的 markCloudBackupSeen）。
                await markCloudBackupSeen(info);
                Navigator.pop(ctx);
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/sync');
              },
              child: const Text('去恢复'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('云端备份检查失败（只记日志）：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final themeColor = ref.watch(themeColorProvider);
    final pureBlack = ref.watch(pureBlackProvider);
    final fontScale = ref.watch(fontScaleProvider);
    // 注意：MyApp 自己就是建 MaterialApp 的那一层，它的 context 上面
    // 还没有 MediaQuery（MediaQuery 是 MaterialApp 建出来的），所以
    // 这里不能调 MediaQuery.of(context)，会直接抛空值错误导致灰屏。
    // 系统深浅改从 window 上读。
    final systemDark =
        WidgetsBinding.instance.window.platformBrightness ==
            Brightness.dark;
    // 墨夜（下标 4）不开放，themeColor 已钳制在 0..3；这里只做兜底。
    final isNight = themeColor == AppTheme.nightSchemeIndex;
    final effectiveMode =
        isNight ? ThemeMode.dark : resolveThemeMode(themeMode);
    final isDark =
        isNight || isDarkMode(themeMode, systemDark);

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
      child: MaterialApp.router(
        title: '随意听书',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(themeColor),
        darkTheme: AppTheme.dark(themeColor, pureBlack),
        themeMode: effectiveMode,
        routeInformationParser: _router.routeInformationParser,
        routerDelegate: _router.routerDelegate,
        // 字体大小全站生效（Flutter 3.0 用 textScaleFactor；
        // textScaler 是 Flutter 3.13+ 的 API，3.0 编不过）。
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaleFactor: fontScale),
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
