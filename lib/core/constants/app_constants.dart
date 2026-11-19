/// 应用全局常量
class AppConstants {
  AppConstants._();

  static const String appName = '随意听书';
  static const String version = '2.2.0';

  /// 应用包名，用于拼接私有数据目录
  static const String packageName = 'com.localreader.local_media_app';

  // ---------- 数据类型 ----------
  static const String typeAudio = 'audio';
  static const String typeVideo = 'video';

  // ---------- 阅读/播放状态 ----------
  static const String statusUnread = 'unread';
  static const String statusReading = 'reading';
  static const String statusFinished = 'finished';

  // ---------- 排序方式 ----------
  static const String sortByName = 'name';
  static const String sortByAddedAt = 'addedAt';
  static const String sortByProgress = 'progress';
  static const String sortByLastRead = 'lastRead';

  // ---------- 筛选 ----------
  static const String filterAll = 'all';
  static const String filterUnread = 'unread';
  static const String filterReading = 'reading';
  static const String filterFinished = 'finished';

  // ---------- 设置项 key ----------
  static const String keyThemeMode = 'theme_mode';
  static const String keyThemeColor = 'theme_color';
  static const String keyFollowSystemDark = 'follow_system_dark';
  static const String keyPlayerTint = 'player_tint';
  static const String keyVideoEnabled = 'video_enabled';
  static const String keyCacheLimitMb = 'cache_limit_mb';
  static const String keyPlaybackSpeed = 'playback_speed';
  static const String keySleepTimerMin = 'sleep_timer_min';
  static const String keyOnboardDone = 'onboard_done';
  static const String keyNaturalSort = 'natural_sort';
  static const String keyCurrentSourceAudio = 'current_source_audio';
  static const String keyCurrentSourceVideo = 'current_source_video';
  static const String keyHomeSourceId = 'home_source_id';

  // ---------- 搜索设置 ----------
  static const String keyAggregateSearch = 'aggregate_search';
  static const String keyExactSearch = 'exact_search';

  // ---------- 自动缓存 ----------
  static const String keyAutoCache = 'auto_cache';
  static const String keyAutoCacheCount = 'auto_cache_count';
  static const String keyAutoCacheWifiOnly = 'auto_cache_wifi_only';
  static const String keyAutoCacheFreq = 'auto_cache_freq';
  static const String keyAutoCleanLimit = 'auto_clean_limit';

  // ---------- 视频画面 ----------
  static const String keyVideoFit = 'video_fit_mode';

  // ---------- 播放设置 ----------
  static const String keyAutoNext = 'auto_next';
  static const String keyLockScreenShow = 'lockscreen_show';
  static const String keyHeadsetPause = 'headset_pause';
  static const String keySleepTimerDefault = 'sleep_timer_default';
  static const String keyResumeEnabled = 'resume_enabled';
  static const String keySkipSilence = 'skip_silence';
  static const String keyPauseOnLeave = 'pause_on_leave';
  static const String keySleepTimerExitApp = 'sleep_timer_exit_app';

  // ---------- 桌面小工具 / 锁屏 ----------
  static const String keyWidgetFollowCover = 'widget_follow_cover';
  static const String keyWidgetButtonSize = 'widget_button_size';
  static const String keyLockScreenCoverBg = 'lockscreen_cover_bg';
  static const String keyForceDefaultCover = 'force_default_cover';
  static const String keyDefaultCoverPath = 'default_cover_path';
  static const String keyLaunchIcon = 'launch_icon';

  // ---------- 显示 ----------
  static const String keyFontSize = 'font_size';
  static const String keySourceColumns = 'source_columns';
  static const String keySourceGroup = 'home_source_group';
  static const String keyDisplayModePrefix = 'display_mode_';

  // ---------- WebDAV 播放 ----------
  static const String keyWebDavPlayUrl = 'webdav_play_url';
  static const String keyWebDavPlayUser = 'webdav_play_user';
  static const String keyWebDavPlayPass = 'webdav_play_pass';

  // ---------- 断点续播（插件源） ----------
  static const String keyPluginResumeList = 'plugin_resume_list';
  static const String keyPluginBookmarks = 'plugin_bookmarks';
  static const String keyAutoCacheMap = 'auto_cache_map';

  // ---------- 收听统计 ----------
  static const String keyListenTotalSecs = 'listen_total_secs';
  static const String keyListenDay = 'listen_day';
  static const String keyListenDaySecs = 'listen_day_secs';

  // ---------- 坚果云（WebDAV）----------
  static const String keySyncUrl = 'sync_url';
  static const String keySyncUser = 'sync_user';
  static const String keySyncPass = 'sync_pass';
  static const String defaultSyncUrl = 'https://dav.jianguoyun.com/dav/';

  // ---------- 默认值 ----------
  static const int defaultCacheLimitMb = 512;
  static const double defaultSpeed = 1.0;
  static const bool defaultVideoEnabled = true;

  /// 支持的音频扩展名（小写，不含点）
  static const Set<String> audioExtensions = {
    'mp3',
    'm4a',
    'm4b',
    'flac',
    'aac',
    'wav',
    'ogg',
    'opus',
    'wma',
    'ape',
  };

  /// 支持的视频扩展名
  static const Set<String> videoExtensions = {
    'mp4',
    'mkv',
    'avi',
    'mov',
    'flv',
    'wmv',
    'webm',
    'm4v',
    'ts',
    'rmvb',
  };

  /// 支持的图片扩展名（用作封面）
  static const Set<String> imageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'bmp',
    'gif',
  };

  /// 压缩包扩展名（JAR 本质也是 ZIP）
  static const Set<String> archiveExtensions = {'zip', 'jar', 'cbz'};
}
