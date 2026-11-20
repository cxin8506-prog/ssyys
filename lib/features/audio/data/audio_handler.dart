import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:local_media_app/core/database/library_repository.dart';

/// 播放失败时给界面的人话文案（我的听书播放页 toast 原文）。
const String kPlaybackErrorToast =
    '播放出错了，请在[播放页右上角]打开源网页确认能否播放。'
    '若不可以，说明资源已失效，是网站方面的问题与本程序无关，请换个源试试。';

/// 探到明确失效的地址时抛的人话异常（探测本身超时/网络异常不抛，不拦截播放）。
class HumanPlaybackException implements Exception {
  final String message;
  const HumanPlaybackException(this.message);

  @override
  String toString() => message;
}

/// 音频播放处理器：桥接 just_audio 与 audio_service（0.18）。
///
/// 播放器对象活在 handler 里（前台服务），不在任何页面里：
/// 页面只是遥控器，退出来、锁屏、切 App 都继续播；通知栏/锁屏控制、
/// 耳机拔出、断点保存全住在这里。
/// U 的 main.dart 用 [audioServiceConfig] 调 `AudioService.init`，
/// 必须走 [initAudioServiceWithRetry]（初始化失败延迟重试再降级，
/// 不要在 main() 里太早 init 死掉——1.0.2 的教训）。
class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  /// 供页面直接读底层播放器（进度流、时长流、播放状态流）。
  AudioPlayer get player => _player;

  Stream<Duration> get position => _player.positionStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<double> get speedStream => _player.speedStream;

  /// 播放失败的人话错误流（页面监听后弹 toast，不直接抛给用户看异常名）。
  final _errorController = StreamController<String>.broadcast();

  Stream<String> get errorStream => _errorController.stream;

  // ------------------------------------------------------------ 共享实例

  static MyAudioHandler? _sharedInstance;

  /// audio_service 的前台服务配置：通知频道 id `audio`、名 `随意听书播放`，
  /// 暂停后前台服务降级（通知可被划掉）。
  static AudioServiceConfig get audioServiceConfig => AudioServiceConfig(
        androidNotificationChannelId: 'audio',
        androidNotificationChannelName: '随意听书播放',
        androidNotificationIcon: 'drawable/ic_notification',
        androidStopForegroundOnPause: true,
        preloadArtwork: false,
        fastForwardInterval: const Duration(seconds: 15),
        rewindInterval: const Duration(seconds: 15),
      );

  /// 初始化音频服务：失败延迟重试（1 秒、2 秒），三次都失败就降级——
  /// 直接 new 一个 handler 直连 just_audio 播（没有前台服务/通知栏，
  /// 但至少能播），不让 App 卡死在启动。
  static Future<MyAudioHandler> initAudioServiceWithRetry({
    LibraryRepository? libraryRepository,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final handler = await AudioService.init<MyAudioHandler>(
          builder: () =>
              MyAudioHandler(libraryRepository: libraryRepository),
          config: audioServiceConfig,
        );
        _sharedInstance = handler;
        return handler;
      } catch (e) {
        lastError = e;
        debugPrint('音频服务初始化失败（第 ${attempt + 1} 次）：$e');
        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }
    debugPrint('音频服务初始化失败，已降级为直连播放：$lastError');
    final fallback = MyAudioHandler(libraryRepository: libraryRepository);
    _sharedInstance = fallback;
    return fallback;
  }

  // ------------------------------------------------------------ 断点保存

  /// 书库仓库（断点/收藏/历史走它，不直接碰 drift）。
  /// 为空时本地书断点不写盘（插件书断点走 onPluginProgress 回调，不受影响）。
  final LibraryRepository? _libraryRepository;

  /// 当前在播的本地书 id + 播放列表对应的章节标识（下标和队列对齐）。
  String? _currentBookId;
  List<String?> _chapterIds = <String?>[];

  /// 播放中每 5 秒存一次断点（AntennaPod / 随身听书的节奏）。
  Timer? _progressTimer;
  bool _savingProgress = false;
  int _lastSavedPositionMs = -1;
  String? _lastSavedChapterId;

  // ------------------------------------------------------------ 插件源播放

  /// 当前插件书的身份（setPluginBook 时传进来）。
  String? _pluginBookKey;
  String? _pluginSourceId;
  String? _pluginBookUrl;
  String _pluginTitle = '';
  String? _pluginCoverUrl;
  String? _pluginAuthor;

  /// 插件书章节表（setPluginBook 的 chapters 原样存着，取标题用）。
  /// 每章一个 Map：`title`/`name` 是章名，`url`/`chapterUrl` 是源地址。
  List<Map<String, dynamic>> _pluginChapters = <Map<String, dynamic>>[];

  /// 已解析出的可播地址缓存（下标和章节表对齐；没解析过的下标是 null）。
  /// 先查缓存再调 [onResolveChapter]，解析失败报人话错。
  List<String?> chapterUrls = <String?>[];

  /// 切章时向源要地址（参数：章下标），返回可播地址；解析失败返回 null。
  /// 由进播放页的一方（network_audio_page / source_book_page）注册。
  Future<String?> Function(int index)? onResolveChapter;

  /// 切章时向源要请求头（参数：章下标），返回 Referer/UA 等；没有就空。
  /// 和 onResolveChapter 同一次解析里拿到的头由注册方自己缓存起来，
  /// 这里只负责取。
  Map<String, String>? Function(int index)? onResolveHeaders;

  /// 只听声音（视频）模式：播完一章自动解析下一章继续播。
  /// 页面退出后也生效（回调和解析器都留在 handler 上）；
  /// 新书 setPluginBook / 清掉插件书时自动关掉，不带到下一本书。
  bool autoAdvancePlugin = false;

  /// 只听声音自动切章进行中：播完事件只触发一次，不重复切。
  bool _autoAdvancing = false;

  /// 插件源断点回调：handler 每 5 秒 / 暂停 / 切章 / 播完时调它，
  /// 页面侧写插件断点（plugin_resume）。force=true 是最后一次保存，
  /// 页面侧不节流。
  void Function(int chapterIndex, int positionMs, int durationMs, bool force)?
      onPluginProgress;

  /// 插件源切章回调：通知栏/耳机点“下一章/上一章”时调
  /// （handler 自己不知道下一章地址，要现向源解析）。
  /// 页面进页时注册；页面退出后故意留着（后台听的时候通知栏还能切章），
  /// 下次进插件播放页会被覆盖，切回本地书时 setQueue/setUris 会清掉。
  Future<void> Function()? onPluginSkipNext;
  Future<void> Function()? onPluginSkipPrevious;

  /// 插件源当前在播的章下标（单章一个 AudioSource，
  /// player.currentIndex 恒为 0，逻辑下标自己记）。
  int _pluginChapterIndex = 0;

  int get pluginChapterIndex => _pluginChapterIndex;

  int get chapterCount => _pluginChapters.length;

  String? get currentBookKey => _pluginBookKey ?? _currentBookId;

  String? get currentSourceId => _pluginSourceId;

  String get currentBookTitle => _pluginTitle;

  bool get hasPluginBook => _pluginBookKey != null;

  String chapterTitle(int index) {
    if (index < 0 || index >= _pluginChapters.length) return '';
    final c = _pluginChapters[index];
    final t = c['title'] ?? c['name'];
    if (t != null && '$t'.isNotEmpty) return '$t';
    return '第 ${index + 1} 集';
  }

  /// 把某章已知的可播地址写进缓存（调用方刚解析出来的地址先放这里，
  /// 再调 playPluginChapter 就不用重新解析）。
  void cacheChapterUrl(int index, String url) {
    if (index < 0) return;
    while (chapterUrls.length <= index) {
      chapterUrls.add(null);
    }
    chapterUrls[index] = url;
  }

  // ------------------------------------------------------------ 单书设置

  /// 单书音量增强（0–1.5）：存在这本书上，换书自动切换。
  /// just_audio 的音量最高 1.0，超过 1.0 的部分按 1.0 算。
  double _bookGain = 1.0;

  /// 单书跳过静音 / 跳过片头 / 跳过片尾（秒）。
  bool _skipSilence = true;
  int _skipIntroSeconds = 0;
  int _skipOutroSeconds = 0;

  /// 跳过片头每集只跳一次：记下已经跳过的章下标，不和暂停回退打架。
  int _introSkippedChapter = -1;

  /// 跳过片尾只触发一次（触发后直接 seek 到章末走播完流程）。
  bool _outroSkipped = false;

  bool get skipSilenceEnabled => _skipSilence;

  double get volumeBoost => _bookGain;

  double get currentSpeed => _player.speed;

  int get skipIntroSeconds => _skipIntroSeconds;

  int get skipOutroSeconds => _skipOutroSeconds;

  /// 锁屏滑杆（默认开）：关了锁屏通知上不显示可拖动的进度条。
  bool _lockScreenSlider = true;

  // ------------------------------------------------------------ 睡眠定时

  Timer? _sleepTimer;
  Timer? _sleepTickTimer;
  DateTime? _sleepEndAt;
  bool _sleepUntilChapterEnd = false;
  int? _sleepEpisodesLeft;
  final _sleepRemainingController = StreamController<Duration?>.broadcast();

  /// 睡眠定时剩余时间流（页面显示倒计时用；没设定时发 null）。
  Stream<Duration?> get sleepRemainingStream =>
      _sleepRemainingController.stream;

  Duration? get sleepRemaining {
    final end = _sleepEndAt;
    if (end == null) return null;
    final left = end.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get sleepUntilChapterEnd => _sleepUntilChapterEnd;

  int? get sleepEpisodesLeft => _sleepEpisodesLeft;

  bool get hasSleepTimer =>
      _sleepEndAt != null || _sleepUntilChapterEnd || _sleepEpisodesLeft != null;

  StreamSubscription<void>? _noisySub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;

  /// 暂停后恢复自动倒带：记下暂停的时刻，点播放时按停顿时长分档倒带。
  DateTime? _pausedAt;

  MyAudioHandler({LibraryRepository? libraryRepository})
      : _libraryRepository = libraryRepository {
    SharedPreferences.getInstance().then((p) {
      _lockScreenSlider = p.getBool('lockscreen_slider') ?? true;
      _emitState();
    });
    _player.playbackEventStream.listen(_onPlaybackEvent, onError: (e, st) {
      debugPrint('播放错误：$e');
    });

    // 播完一章：播到章末停 / 播完几集停在这里收口；
    // 插件源的自动切下一章由页面（播完监听）决定，这里只把断点存了。
    // 只有只听声音模式（autoAdvancePlugin）例外：视频页退出了，
    // 没有页面监听播完，handler 自己按需解析下一章继续播。
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _flushProgress();
        if (_sleepUntilChapterEnd) {
          _sleepUntilChapterEnd = false;
          _emitSleepRemaining(null);
          return;
        }
        if (_sleepEpisodesLeft != null) {
          _sleepEpisodesLeft = _sleepEpisodesLeft! - 1;
          if (_sleepEpisodesLeft! <= 0) {
            _sleepEpisodesLeft = null;
            _emitSleepRemaining(null);
            pause();
            return;
          }
        }
        if (autoAdvancePlugin && hasPluginBook) {
          unawaited(_autoAdvancePlugin());
        }
      }
    });

    // 耳机拔出 / 来电抢焦点：audio_session 的事件流。
    _initAudioSession();
    // 播放中断点定时保存：页面退出后 handler 还活着，继续存。
    _progressTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _saveProgressTick());
  }

  /// 音频会话：焦点 + 耳机拔出。just_audio 也用同一个 AudioSession 单例，
  /// 这里配一次（语音内容、媒体用途、抢焦点）。
  /// 被压低音量（duck）时只降音量不暂停（androidWillPauseWhenDucked: false）。
  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.duckOthers,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      _noisySub =
          session.becomingNoisyEventStream.listen((_) => _onBecomingNoisy());
      _interruptionSub =
          session.interruptionEventStream.listen(_onInterruption);
    } catch (e) {
      debugPrint('音频会话初始化失败：$e');
    }
  }

  /// 耳机拔出：暂停并往回倒 2 秒。
  Future<void> _onBecomingNoisy() async {
    if (!_player.playing) return;
    await _pauseAndRewind();
  }

  /// 音频焦点变化：开始丢焦点（来电 / 别的 App 抢走）就暂停并倒带 2 秒；
  /// 焦点回来不自动续播，等用户自己点播放（免得电话刚挂就突然出声）。
  /// duck（被压低音量）直接忽略，不暂停。
  Future<void> _onInterruption(AudioInterruptionEvent event) async {
    if (event.type == AudioInterruptionType.duck) return;
    if (!event.begin) return;
    if (!_player.playing) return;
    await _pauseAndRewind();
  }

  /// 暂停并往回倒 2 秒（播完的不倒带，停在结尾）。
  /// 耳机拔出、来电抢焦点都走这里。
  Future<void> _pauseAndRewind() async {
    try {
      final completed =
          _player.processingState == ProcessingState.completed;
      _pausedAt = DateTime.now();
      await _player.pause();
      if (!completed) {
        final pos = _player.position - const Duration(seconds: 2);
        await _player.seek(pos < Duration.zero ? Duration.zero : pos);
      }
      await _flushProgress();
      _emitState();
    } catch (e) {
      debugPrint('暂停倒带失败：$e');
    }
  }

  /// 暂停后恢复自动倒带（AntennaPod 的分档）：
  /// 停 <1 分钟倒 0.8 秒、<1 小时倒 3 秒、<1 天倒 10 秒、更久倒 20 秒；
  /// 不越过当前章节开头；播完的书不倒带；设置里关了就不倒。
  Future<void> _rewindAfterPause() async {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt == null) return;
    if (_player.processingState == ProcessingState.completed) return;
    final pos = _player.position;
    if (pos <= Duration.zero) return;
    bool enabled = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled = prefs.getBool('rewind_after_pause') ?? true;
    } catch (_) {}
    if (!enabled) return;
    final stopped = DateTime.now().difference(pausedAt);
    Duration back;
    if (stopped < const Duration(minutes: 1)) {
      back = const Duration(milliseconds: 800);
    } else if (stopped < const Duration(hours: 1)) {
      back = const Duration(seconds: 3);
    } else if (stopped < const Duration(days: 1)) {
      back = const Duration(seconds: 10);
    } else {
      back = const Duration(seconds: 20);
    }
    final target = pos - back;
    await _player.seek(target < Duration.zero ? Duration.zero : target);
  }

  // ------------------------------------------------------------ 断点保存

  /// 5 秒定时存断点：只在播的时候写；位置变化 <5000ms 不写盘。
  Future<void> _saveProgressTick() async {
    if (!_player.playing || _savingProgress) return;
    final pos = _player.position.inMilliseconds;
    if (pos <= 0) return;
    if (onPluginProgress != null) {
      if ((pos - _lastSavedPositionMs).abs() < 5000 &&
          _pluginChapterIndex == _lastSavedChapterIndex) {
        return;
      }
      _lastSavedPositionMs = pos;
      _lastSavedChapterIndex = _pluginChapterIndex;
      _savePluginProgress(force: false);
      return;
    }
    final repo = _libraryRepository;
    final bookId = _currentBookId;
    if (repo == null || bookId == null) return;
    final idx = _player.currentIndex ?? 0;
    final chapterId =
        (idx >= 0 && idx < _chapterIds.length) ? _chapterIds[idx] : null;
    if ((pos - _lastSavedPositionMs).abs() < 5000 &&
        chapterId == _lastSavedChapterId) {
      return;
    }
    _lastSavedPositionMs = pos;
    _lastSavedChapterId = chapterId;
    await _saveLocalProgress(chapterId: chapterId, positionMs: pos);
    _checkSkipOutro();
  }

  int _lastSavedChapterIndex = -1;

  /// 立刻存一次断点（暂停 / 切章 / 播完 / 服务销毁前都调）。
  Future<void> _flushProgress() async {
    if (onPluginProgress != null) {
      await _savePluginProgress(force: true);
      return;
    }
    final repo = _libraryRepository;
    final bookId = _currentBookId;
    if (repo == null || bookId == null) return;
    final idx = _player.currentIndex ?? 0;
    final chapterId =
        (idx >= 0 && idx < _chapterIds.length) ? _chapterIds[idx] : null;
    await _saveLocalProgress(
        chapterId: chapterId,
        positionMs: _player.position.inMilliseconds);
  }

  Future<void> _savePluginProgress({required bool force}) async {
    final sink = onPluginProgress;
    if (sink == null) return;
    final dur = _player.duration?.inMilliseconds ?? 0;
    sink(_pluginChapterIndex, _player.position.inMilliseconds, dur, force);
    _lastSavedPositionMs = _player.position.inMilliseconds;
    _lastSavedChapterIndex = _pluginChapterIndex;
  }

  Future<void> _saveLocalProgress(
      {String? chapterId, required int positionMs}) async {
    final repo = _libraryRepository;
    final bookId = _currentBookId;
    if (repo == null || bookId == null || _savingProgress) return;
    _savingProgress = true;
    try {
      final dur = _player.duration?.inMilliseconds ?? 0;
      final finished = _player.processingState == ProcessingState.completed ||
          (dur > 0 && positionMs >= (dur * 0.95).round());
      await repo.saveProgress(
        bookId: bookId,
        chapterUrl: chapterId ?? '',
        positionMs: positionMs,
        durationMs: dur,
        isFinished: finished,
      );
    } catch (e) {
      debugPrint('保存断点失败：$e');
    } finally {
      _savingProgress = false;
    }
  }

  /// 跳过片尾：剩下的时间 <= 跳过片尾秒数就直接跳到章末，
  /// 走播完流程切下一章；每集只触发一次。
  void _checkSkipOutro() {
    if (_skipOutroSeconds <= 0 || _outroSkipped) return;
    final dur = _player.duration;
    if (dur == null || dur <= Duration.zero) return;
    final remain = dur - _player.position;
    if (remain <= Duration(seconds: _skipOutroSeconds) &&
        remain > Duration.zero) {
      _outroSkipped = true;
      _player.seek(dur);
    }
  }

  // ------------------------------------------------------------ 插件源播放

  /// 插件源进页时调一次：bookKey = 'sourceId|bookUrl'（和插件断点的 key 一致），
  /// chapters = 各章 {title/name, url/chapterUrl}，换书自动应用这本书的
  /// 倍速 / 跳过静音 / 音量增强 / 跳过片头片尾。
  Future<void> setPluginBook({
    required String bookKey,
    required String sourceId,
    required String bookUrl,
    required String title,
    String? coverUrl,
    String? author,
    required List<Map<String, dynamic>> chapters,
    int initialIndex = 0,
  }) async {
    await _flushProgress();
    _pluginBookKey = bookKey;
    _pluginSourceId = sourceId;
    _pluginBookUrl = bookUrl;
    _pluginTitle = title;
    _pluginCoverUrl = coverUrl;
    _pluginAuthor = author;
    // 换书只听声音自动切章关掉：新书的切章由新页面自己决定。
    autoAdvancePlugin = false;
    _pluginChapters = List<Map<String, dynamic>>.from(chapters);
    // 解析缓存只按新章节数重排长度，不清空：
    // 调用方（source_book_page）可能在 setPluginBook 之前就把
    // 已经解析好的地址预填进 chapterUrls，重进同一本书时不用重新解析。
    final oldUrls = chapterUrls;
    chapterUrls = List<String?>.filled(_pluginChapters.length, null);
    for (var i = 0; i < oldUrls.length && i < chapterUrls.length; i++) {
      if (oldUrls[i] != null && oldUrls[i]!.isNotEmpty) {
        chapterUrls[i] = oldUrls[i];
      }
    }
    _pluginChapterIndex = initialIndex;
    _currentBookId = bookKey;
    _chapterIds = List<String?>.generate(
        _pluginChapters.length, (i) => _chapterSourceUrl(i));
    _lastSavedPositionMs = -1;
    _lastSavedChapterId = null;
    _lastSavedChapterIndex = -1;
    _introSkippedChapter = -1;
    _outroSkipped = false;
    final items = List<MediaItem>.generate(_pluginChapters.length, (i) {
      return MediaItem(
        id: _chapterSourceUrl(i).isNotEmpty
            ? _chapterSourceUrl(i)
            : '$bookKey#$i',
        title: chapterTitle(i),
        album: title,
        artist: author,
        artUri: coverUrl != null && coverUrl.startsWith('http')
            ? Uri.tryParse(coverUrl)
            : null,
      );
    });
    queue.add(items);
    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex.clamp(0, items.length - 1)]);
    }
    await _applyBookSettings();
    _emitState();
  }

  String _chapterSourceUrl(int index) {
    if (index < 0 || index >= _pluginChapters.length) return '';
    final c = _pluginChapters[index];
    final u = c['url'] ?? c['chapterUrl'];
    return u == null ? '' : '$u';
  }

  /// 播插件源的一章：先查 [chapterUrls] 缓存，没有就调 [onResolveChapter]
  /// 现向源解析；解析失败报人话错，不切章。
  /// 播放前先探测音频地址（Range: bytes=0-1，8 秒超时）：
  /// 404/410 提示“音频文件已失效”，401/403 提示“可能需要登录或已下架”；
  /// 探测本身出错（超时/网络异常）不拦截播放。
  Future<void> playPluginChapter(int index,
      {Duration startAt = Duration.zero}) async {
    if (index < 0 || index >= _pluginChapters.length) {
      throw const HumanPlaybackException('没有这一集');
    }
    await _flushProgress();
    _pluginChapterIndex = index;
    _introSkippedChapter = -1;
    _outroSkipped = false;
    var url = (index >= 0 && index < chapterUrls.length)
        ? chapterUrls[index]
        : null;
    if (url == null || url.isEmpty) {
      final resolver = onResolveChapter;
      if (resolver == null) {
        throw const HumanPlaybackException('源没有返回可播放地址');
      }
      url = await resolver(index);
      if (url == null || url.isEmpty) {
        throw const HumanPlaybackException('源没有返回可播放地址');
      }
      cacheChapterUrl(index, url);
    }
    final headers = onResolveHeaders?.call(index) ?? const <String, String>{};
    await _probeUrl(url);
    final item = MediaItem(
      id: _chapterSourceUrl(index).isNotEmpty
          ? _chapterSourceUrl(index)
          : url,
      title: chapterTitle(index),
      album: _pluginTitle,
      artist: _pluginAuthor,
      artUri: _pluginCoverUrl != null && _pluginCoverUrl!.startsWith('http')
          ? Uri.tryParse(_pluginCoverUrl!)
          : null,
    );
    queue.add(_pluginChapters.isEmpty
        ? <MediaItem>[item]
        : List<MediaItem>.generate(_pluginChapters.length, (i) {
            if (i == index) return item;
            return MediaItem(
              id: _chapterSourceUrl(i).isNotEmpty
                  ? _chapterSourceUrl(i)
                  : '${_pluginBookKey ?? ''}#$i',
              title: chapterTitle(i),
              album: _pluginTitle,
              artist: _pluginAuthor,
            );
          }));
    mediaItem.add(item);
    try {
      final source = url.startsWith('/')
          ? AudioSource.uri(Uri.file(url))
          : AudioSource.uri(Uri.parse(url), headers: headers);
      await _player.setAudioSource(source);
    } catch (e) {
      final msg = _humanizePlayError(e);
      _errorController.add(msg);
      throw HumanPlaybackException(msg);
    }
    // 跳过片头：每集只跳一次，不和暂停回退打架。
    var start = startAt;
    if (_skipIntroSeconds > 0 &&
        start < Duration(seconds: _skipIntroSeconds)) {
      start = Duration(seconds: _skipIntroSeconds);
      _introSkippedChapter = index;
    }
    try {
      if (start > Duration.zero) await _player.seek(start);
      _lastSavedPositionMs = start.inMilliseconds;
      _lastSavedChapterIndex = index;
      await _player.play();
    } catch (e) {
      final msg = _humanizePlayError(e);
      _errorController.add(msg);
      throw HumanPlaybackException(msg);
    }
    _emitState();
  }

  /// 只听声音自动切下一章：按需解析（不预解析，限时签名会过期），
  /// 解析失败往后再试一章，两章都失败就停住，不抛错、不死循环。
  Future<void> _autoAdvancePlugin() async {
    if (_autoAdvancing) return;
    _autoAdvancing = true;
    try {
      var next = _pluginChapterIndex + 1;
      var tried = 0;
      while (next < _pluginChapters.length && tried < 2) {
        try {
          await playPluginChapter(next);
          return;
        } catch (_) {
          tried++;
          next++;
        }
      }
    } finally {
      _autoAdvancing = false;
    }
  }

  /// 直接播一个地址（WebDAV 单文件用）：不建书、不写断点、不进播放列表。
  /// 调用方自己保证不把它和插件书会话混起来（单文件进页前先调
  /// clearPluginBook，别让断点写到别的书上）。
  Future<void> playSingleUrl({
    required MediaItem item,
    required String url,
    Map<String, String> headers = const {},
    Duration startAt = Duration.zero,
  }) async {
    await _probeUrl(url);
    queue.add(<MediaItem>[item]);
    mediaItem.add(item);
    try {
      final source = url.startsWith('/')
          ? AudioSource.uri(Uri.file(url))
          : AudioSource.uri(Uri.parse(url), headers: headers);
      await _player.setAudioSource(source);
      if (startAt > Duration.zero) await _player.seek(startAt);
      await _player.play();
    } catch (e) {
      final msg = _humanizePlayError(e);
      _errorController.add(msg);
      throw HumanPlaybackException(msg);
    }
    _emitState();
  }

  /// 播放结束（切回本地播放时）：清掉插件会话（断点回调、切章回调、
  /// 解析回调），避免断点写到别的书上、通知栏切章还去解析旧源。
  void clearPluginBook() {
    onPluginProgress = null;
    onPluginSkipNext = null;
    onPluginSkipPrevious = null;
    onResolveChapter = null;
    onResolveHeaders = null;
    autoAdvancePlugin = false;
    _pluginBookKey = null;
    _pluginSourceId = null;
    _pluginBookUrl = null;
    _pluginTitle = '';
    _pluginCoverUrl = null;
    _pluginAuthor = null;
    _pluginChapters = <Map<String, dynamic>>[];
    chapterUrls = <String?>[];
    _pluginChapterIndex = 0;
    _currentBookId = null;
    _chapterIds = <String?>[];
    _lastSavedPositionMs = -1;
    _lastSavedChapterId = null;
    _lastSavedChapterIndex = -1;
  }

  Future<void> _probeUrl(String url) async {
    if (!url.startsWith('http')) return;
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('Range', 'bytes=0-1');
      final response =
          await request.close().timeout(const Duration(seconds: 8));
      final code = response.statusCode;
      client.close(force: true);
      if (code == 404 || code == 410) {
        throw const HumanPlaybackException('音频文件已失效');
      }
      if (code == 401 || code == 403) {
        throw const HumanPlaybackException('可能需要登录或已下架');
      }
    } on HumanPlaybackException {
      rethrow;
    } on TimeoutException {
      // 探测超时不拦截播放。
    } catch (_) {
      // 探测本身出错（网络异常等）不拦截播放。
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  String _humanizePlayError(Object e) {
    final s = '$e';
    if (s.contains('404') || s.contains('410')) return '音频文件已失效';
    if (s.contains('401') || s.contains('403')) return '可能需要登录或已下架';
    if (s.contains('SocketException') ||
        s.contains('Connection closed') ||
        s.contains('Network is unreachable')) {
      return '网络不通，检查一下网络再试';
    }
    return kPlaybackErrorToast;
  }

  // ------------------------------------------------------------ 本地书播放

  /// 当前在播的是哪本书 + 播放列表对应的章节标识（下标和队列对齐）。
  /// 播放页进页时调一次；换书自动应用这本书的倍速/跳过静音/音量增强。
  Future<void> setBook(String bookId, List<String?> chapterIds) async {
    clearPluginBook();
    _currentBookId = bookId;
    _chapterIds = List<String?>.from(chapterIds);
    _lastSavedPositionMs = -1;
    _lastSavedChapterId = null;
    await _applyBookSettings();
  }

  /// 设置播放队列（本地章节列表，MediaItem.id 是可播地址/文件路径）。
  Future<void> setQueue(List<MediaItem> items, {int initialIndex = 0}) async {
    clearPluginBook();
    queue.add(items);
    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex.clamp(0, items.length - 1)]);
      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: items
              .map((m) => m.id.startsWith('/')
                  ? AudioSource.uri(Uri.file(m.id))
                  : AudioSource.uri(Uri.parse(m.id)))
              .toList(),
        ),
        initialIndex: initialIndex,
      );
    }
    await _applyBookSettings();
    _emitState();
  }

  /// 用简单 Uri 列表设置队列（本地文件路径）。
  Future<void> setUris(List<String> paths, {int initialIndex = 0}) async {
    clearPluginBook();
    final items = paths.map((p) {
      final name = p.split('/').last;
      return MediaItem(
        id: p,
        title: name,
        album: '本地听书',
      );
    }).toList();
    queue.add(items);
    if (items.isNotEmpty) {
      mediaItem.add(items[initialIndex.clamp(0, items.length - 1)]);
      await _player.setAudioSource(
        ConcatenatingAudioSource(
          children: paths.map((p) => AudioSource.uri(Uri.file(p))).toList(),
        ),
        initialIndex: initialIndex,
      );
    }
    await _applyBookSettings();
    _emitState();
  }

  // ------------------------------------------------------------ 单书设置

  String get _bookSettingsKey => currentBookKey ?? '';

  /// 应用单书设置：有这本书单独存的值就用它的，没有就用全局设置。
  Future<void> _applyBookSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bookKey = _bookSettingsKey;
      final speed = bookKey.isEmpty
          ? null
          : prefs.getDouble('book_speed_$bookKey');
      final globalSpeed = prefs.getDouble('playback_speed') ?? 1.0;
      await _player.setSpeed((speed ?? globalSpeed).clamp(0.5, 3.0));
      final perBookSilence = bookKey.isEmpty
          ? null
          : prefs.getBool('book_skip_silence_$bookKey');
      _skipSilence =
          perBookSilence ?? prefs.getBool('skip_silence') ?? true;
      await _player.setSkipSilenceEnabled(_skipSilence);
      final gain =
          bookKey.isEmpty ? null : prefs.getDouble('book_gain_$bookKey');
      _bookGain = (gain ?? 1.0).clamp(0.0, 1.5);
      await _player.setVolume(_bookGain.clamp(0.0, 1.0));
      _skipIntroSeconds = bookKey.isEmpty
          ? 0
          : prefs.getInt('book_skip_intro_$bookKey') ?? 0;
      _skipOutroSeconds = bookKey.isEmpty
          ? 0
          : prefs.getInt('book_skip_outro_$bookKey') ?? 0;
    } catch (e) {
      debugPrint('应用单书播放设置失败：$e');
    }
  }

  /// 跳过静音：存到这本书上，换书自动切换。
  Future<void> setSkipSilence(bool v) async {
    _skipSilence = v;
    await _player.setSkipSilenceEnabled(v);
    final bookKey = _bookSettingsKey;
    if (bookKey.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('book_skip_silence_$bookKey', v);
      } catch (_) {}
    }
    _emitState();
  }

  /// 音量增强（0–1.5）：存到这本书上，换书自动切换。
  Future<void> setVolumeBoost(double gain) async {
    final v = gain.clamp(0.0, 1.5);
    _bookGain = v;
    await _player.setVolume(v.clamp(0.0, 1.0));
    final bookKey = _bookSettingsKey;
    if (bookKey.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('book_gain_$bookKey', v);
      } catch (_) {}
    }
  }

  /// 跳过片头（秒）：存到这本书上，每集只跳一次。
  Future<void> setSkipIntroSeconds(int seconds) async {
    _skipIntroSeconds = seconds.clamp(0, 300);
    final bookKey = _bookSettingsKey;
    if (bookKey.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('book_skip_intro_$bookKey', _skipIntroSeconds);
      } catch (_) {}
    }
  }

  /// 跳过片尾（秒）：存到这本书上。
  Future<void> setSkipOutroSeconds(int seconds) async {
    _skipOutroSeconds = seconds.clamp(0, 300);
    final bookKey = _bookSettingsKey;
    if (bookKey.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('book_skip_outro_$bookKey', _skipOutroSeconds);
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------ 播放控制

  void _onPlaybackEvent(PlaybackEvent event) {
    _emitState();
  }

  /// 把当前播放状态发给通知栏/锁屏（锁屏滑杆开关也走这里重发）。
  /// 通知栏控制：上一章、快退、播放/暂停、快进、下一章；
  /// 收起的通知栏只显示中间三个（快退 / 播放暂停 / 快进）。
  /// 耳机/车机/手表的上一曲/下一曲走快退/快进（seek），不切章节。
  void _emitState() {
    final items = queue.value;
    final idx = items.isEmpty
        ? 0
        : (_player.currentIndex ?? _pluginChapterIndex)
            .clamp(0, items.length - 1);
    final item = items.isNotEmpty
        ? items[idx]
        : MediaItem(id: '', title: '');
    playbackState.add(PlaybackState(
      controls: <MediaControl>[
        MediaControl.skipToPrevious,
        MediaControl.rewind,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
        MediaControl.skipToNext,
      ],
      // 锁屏滑杆：systemActions 里有 seek，锁屏通知才显示可拖动的进度条。
      systemActions: _lockScreenSlider
          ? const <MediaAction>{MediaAction.seek, MediaAction.setSpeed}
          : const <MediaAction>{MediaAction.setSpeed},
      androidCompactActionIndices: const <int>[1, 2, 3],
      processingState: _mapProcessingState(_player.processingState),
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: idx,
    ));
    if (item.id.isNotEmpty) mediaItem.add(item);
  }

  /// 设置页改锁屏滑杆时调：改完立刻重发状态，通知栏马上跟着变。
  void setLockScreenSlider(bool v) {
    _lockScreenSlider = v;
    _emitState();
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  /// 跳转到指定章节（先把当前章的断点存了再切）。
  Future<void> jumpToChapter(int i) async {
    if (hasPluginBook) {
      await playPluginChapter(i);
      return;
    }
    await _flushProgress();
    await _player.seek(Duration.zero, index: i);
  }

  int get currentIndex =>
      hasPluginBook ? _pluginChapterIndex : (_player.currentIndex ?? 0);

  @override
  Future<void> play() async {
    await _rewindAfterPause();
    await _player.play();
    _emitState();
  }

  @override
  Future<void> pause() async {
    _pausedAt = DateTime.now();
    await _player.pause();
    await _flushProgress();
    _emitState();
  }

  @override
  Future<void> stop() async {
    await _flushProgress();
    _cancelSleepTimer();
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (hasPluginBook) {
      final cb = onPluginSkipNext;
      if (cb != null) {
        await cb();
        return;
      }
      final next = _pluginChapterIndex + 1;
      if (next < _pluginChapters.length) {
        await playPluginChapter(next);
      }
      return;
    }
    await _flushProgress();
    await _player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (hasPluginBook) {
      // 章内播了超过 3 秒：先回章头，不切章（免得听众丢位置）。
      if (_player.position > const Duration(seconds: 3)) {
        await _player.seek(Duration.zero);
        return;
      }
      final cb = onPluginSkipPrevious;
      if (cb != null) {
        await cb();
        return;
      }
      final prev = _pluginChapterIndex - 1;
      if (prev >= 0) {
        await playPluginChapter(prev);
      }
      return;
    }
    await _flushProgress();
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    await _player.seekToPrevious();
  }

  /// 倍速：调播放器，同时存到这本书上（换书自动切换，不用全局一个开关）。
  @override
  Future<void> setSpeed(double speed) async {
    final v = speed.clamp(0.5, 3.0);
    await _player.setSpeed(v);
    final bookKey = _bookSettingsKey;
    if (bookKey.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('book_speed_$bookKey', v);
      } catch (_) {}
    }
    _emitState();
  }

  /// 快退：步长读设置（默认 15 秒）。
  /// 基类 audio_service 0.18 的 SeekHandler 要求带一个 bool 参数
  /// （begin：按住快退的开始/结束）；本页是按一下跳一步，不用按住，
  /// 所以参数忽略。写成可选参数是为了不改调用方：
  /// audio_player_page / network_audio_page 都是无参调用。
  @override
  Future<void> seekBackward([bool begin = false]) async {
    final step = await _seekStep();
    final target = _player.position - Duration(seconds: step);
    await _player.seek(
        target < Duration.zero ? Duration.zero : target);
  }

  /// 快进：步长读设置（默认 15 秒）。begin 参数同 seekBackward，忽略。
  @override
  Future<void> seekForward([bool begin = false]) async {
    final step = await _seekStep();
    final dur = _player.duration;
    var target = _player.position + Duration(seconds: step);
    if (dur != null && target > dur) target = dur;
    await _player.seek(target);
  }

  @override
  Future<void> rewind() => seekBackward();

  @override
  Future<void> fastForward() => seekForward();

  Future<int> _seekStep() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getInt('seek_step_seconds') ?? 15).clamp(5, 60);
    } catch (_) {
      return 15;
    }
  }

  // ------------------------------------------------------------ 睡眠定时

  /// 睡眠定时：预设/自定义分钟数 + 播到本集末停 + 播完几集停，三者可叠加。
  /// 最后 60 秒淡出到 10% 音量；上次设的分钟数下次还记得。
  Future<void> setSleepTimer({
    int? minutes,
    bool untilChapterEnd = false,
    int? episodes,
  }) async {
    _cancelSleepTimer();
    _sleepUntilChapterEnd = untilChapterEnd;
    _sleepEpisodesLeft = episodes;
    if (minutes != null && minutes > 0) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('sleep_timer_last_minutes', minutes);
      } catch (_) {}
      final total = Duration(minutes: minutes);
      _sleepEndAt = DateTime.now().add(total);
      _emitSleepRemaining(total);
      _sleepTickTimer =
          Timer.periodic(const Duration(seconds: 1), (_) => _sleepTick());
      _sleepTimer = Timer(total, () async {
        await pause();
        _cancelSleepTimer();
      });
    } else if (!untilChapterEnd && episodes == null) {
      return;
    }
    if (untilChapterEnd || episodes != null) {
      _emitSleepRemaining(null);
    }
  }

  /// 上次设的睡眠定时长（分钟），没有返回 null。
  Future<int?> lastSleepMinutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt('sleep_timer_last_minutes');
    } catch (_) {
      return null;
    }
  }

  void _emitSleepRemaining(Duration? value) {
    if (!_sleepRemainingController.isClosed) {
      _sleepRemainingController.add(value);
    }
  }

  void _sleepTick() {
    final left = sleepRemaining;
    if (left == null) return;
    if (left <= Duration.zero) {
      _emitSleepRemaining(Duration.zero);
      return;
    }
    _emitSleepRemaining(left);
    // 最后 60 秒淡出到 10% 音量。
    if (left <= const Duration(seconds: 60)) {
      final factor =
          0.1 + 0.9 * (left.inMilliseconds / 60000.0).clamp(0.0, 1.0);
      _player.setVolume(_bookGain.clamp(0.0, 1.0) * factor);
    }
  }

  void cancelSleepTimer() {
    _cancelSleepTimer();
    _player.setVolume(_bookGain.clamp(0.0, 1.0));
  }

  void _cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTickTimer?.cancel();
    _sleepTickTimer = null;
    _sleepEndAt = null;
    _sleepUntilChapterEnd = false;
    _sleepEpisodesLeft = null;
    _emitSleepRemaining(null);
  }

  Future<void> dispose() async {
    _progressTimer?.cancel();
    _noisySub?.cancel();
    _interruptionSub?.cancel();
    _cancelSleepTimer();
    await _errorController.close();
    await _sleepRemainingController.close();
    // 服务销毁前强制写一次断点，再关播放器。
    await _flushProgress();
    await _player.dispose();
  }
}

/// 全局音频 handler 的 provider（U 的 main.dart 先调
/// `MyAudioHandler.initAudioServiceWithRetry()` 再 runApp，
/// 之后各处用 `ref.watch(audioHandlerProvider)` 拿它）。
/// 什么都没播过时 `audioHandler.mediaItem.value == null`。
final audioHandlerProvider = Provider<MyAudioHandler>((ref) {
  final handler = MyAudioHandler._sharedInstance;
  if (handler == null) {
    throw StateError(
        'audioHandler 未初始化：请在 main() 里先调 MyAudioHandler.initAudioServiceWithRetry()');
  }
  return handler;
});

/// 旧式全局访问（页面里图方便时用；未初始化会抛 StateError）。
MyAudioHandler get audioHandler {
  final handler = MyAudioHandler._sharedInstance;
  if (handler == null) {
    throw StateError(
        'audioHandler 未初始化：请在 main() 里先调 MyAudioHandler.initAudioServiceWithRetry()');
  }
  return handler;
}
