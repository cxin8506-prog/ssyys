/// 应用全局常量：全部设置键与默认值。
///
/// 设置键按契约“设置键与默认值”一节；默认值写死在这里，设置页照此读/写。
/// 键名与旧版保持一致（已落盘的用户数据不受影响），新增的键用新名字。
class AppConstants {
  AppConstants._();

  static const String appName = '随意听书';
  static const String version = '1.0.3';
  static const String packageName = 'com.localreader.local_media_app';

  // ---------- 数据类型 ----------
  static const String typeAudio = 'audio';
  static const String typeVideo = 'video';

  // ---------- 设置键：外观 ----------
  static const String keyThemeMode = 'theme_mode';
  static const String keyThemeColor = 'theme_color';
  static const String keyPureBlack = 'pure_black';
  static const String keyCoverColors = 'cover_colors';
  static const String keyFontSize = 'font_size';
  static const String keySourceColumns = 'source_columns';
  static const String keyFollowSystemDark = 'follow_system_dark';

  // ---------- 设置键：播放 ----------
  static const String keyPlaybackSpeed = 'playback_speed';
  static const String keySeekStepSeconds = 'seek_step_seconds';
  static const String keyAutoNext = 'auto_next';
  static const String keyResumeEnabled = 'resume_enabled';
  static const String keySkipSilence = 'skip_silence';
  static const String keyWakeLock = 'wake_lock';
  static const String keySleepTimerDefault = 'sleep_timer_default';
  static const String keyRewindAfterPause = 'rewind_after_pause';
  static const String keyLockScreenSlider = 'lockscreen_slider';
  static const String keyVideoFit = 'video_fit_mode';
  static const String keyVideoEnabled = 'video_enabled';

  // ---------- 设置键：网络 ----------
  static const String keyUaAuto = 'ua_auto';
  static const String keyAggregateSearch = 'aggregate_search';
  static const String keyExactSearch = 'exact_search';
  static const String keySearchConcurrency = 'search_concurrency';
  static const String keySearchTimeoutSeconds = 'search_timeout_seconds';
  static const String keySearchSuggestions = 'search_suggestions_enabled';

  // ---------- 设置键：存储 / 缓存 ----------
  static const String keyAutoCache = 'auto_cache';
  static const String keyAutoCacheCount = 'auto_cache_count';
  static const String keyAutoCacheWifiOnly = 'auto_cache_wifi_only';
  static const String keyAutoCacheFreq = 'auto_cache_freq';
  static const String keyAutoCleanLimit = 'auto_clean_limit';
  static const String keyCacheLimitMb = 'cache_limit_mb';

  // ---------- 设置键：备份 / 同步 ----------
  static const String keySyncEnabled = 'sync_enabled';
  static const String keySyncUrl = 'sync_url';
  static const String keySyncUser = 'sync_user';
  static const String keySyncPass = 'sync_pass';
  static const String keyAutoBackup = 'auto_backup';
  static const String keyBackupIntervalDays = 'backup_interval_days';
  static const String keyBackupKeepCount = 'backup_keep_count';
  static const String keyLastBackup = 'last_backup_ms';
  static const String keyLastSyncTime = 'last_sync_time';
  static const String keySyncProgress = 'sync_book_progress';

  // ---------- 设置键：WebDAV 播放 ----------
  static const String keyWebDavPlayUrl = 'webdav_play_url';
  static const String keyWebDavPlayUser = 'webdav_play_user';
  static const String keyWebDavPlayPass = 'webdav_play_pass';

  // ---------- 其他 ----------
  static const String keyCurrentSourceAudio = 'current_source_audio';
  static const String keyCurrentSourceVideo = 'current_source_video';
  static const String keyHomeSourceId = 'home_source_id';
  static const String keyOnboardDone = 'onboard_done';
  static const String keyNotificationAsked = 'notification_asked';
  static const String keyPluginResumeList = 'plugin_resume_list';
  static const String keyPluginBookmarks = 'plugin_bookmarks';
  static const String keyAutoCacheMap = 'auto_cache_map';

  // ---------- 收听统计 ----------
  static const String keyListenTotalSecs = 'listen_total_secs';
  static const String keyListenDay = 'listen_day';
  static const String keyListenDaySecs = 'listen_day_secs';
  static const String keyListenFinishedIds = 'listen_finished_ids';

  // ---------- 默认值 ----------
  // 外观：0 跟随系统（默认）/ 1 浅色 / 2 深色；主题色 0 暖阳橙 #FF6B4A
  static const int defaultThemeMode = 0;
  static const int defaultThemeColor = 0;
  static const bool defaultPureBlack = false;
  static const bool defaultCoverColor = true;
  static const double defaultFontScale = 1.0;
  static const int defaultSourceColumns = 3;

  // 播放
  static const double defaultSpeed = 1.0;
  static const int defaultSeekStep = 15;
  static const bool defaultAutoPlayNext = true;
  static const bool defaultResumeOnStart = true;
  static const bool defaultSkipSilence = true;
  static const bool defaultWakeLock = true;
  static const int defaultSleepTimer = 0; // 0 = 不设置
  static const bool defaultRewindAfterPause = true;
  static const bool defaultLockScreenSlider = true;
  static const bool defaultVideoEnabled = true;

  // 网络
  static const bool defaultUaAuto = true;
  static const bool defaultAggregateSearch = true;
  static const bool defaultExactSearch = true;
  static const int defaultSearchConcurrency = 6;
  static const int defaultSingleSourceTimeout = 20; // 秒

  // 存储 / 缓存
  static const bool defaultCacheAuto = false;
  static const int defaultCacheKeep = 3; // 集
  static const int defaultCacheStandard = 30; // %
  static const int defaultCacheCleanup = 40; // 个
  static const int defaultCacheLimitMb = 512;

  // 备份 / 同步
  static const bool defaultSyncEnabled = false;
  static const bool defaultAutoBackup = true;
  static const int defaultBackupIntervalDays = 1;
  static const int defaultKeepCount = 0; // 0 = 不清理
  static const bool defaultSyncProgress = false;
  static const String defaultSyncUrl = 'https://dav.jianguoyun.com/dav/';

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
}
