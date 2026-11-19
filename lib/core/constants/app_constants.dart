/// 应用全局常量
class AppConstants {
  AppConstants._();

  static const String appName = '本地影音';
  static const String version = '1.0.0';

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
  static const String keyVideoEnabled = 'video_enabled';
  static const String keyCacheLimitMb = 'cache_limit_mb';
  static const String keyPlaybackSpeed = 'playback_speed';
  static const String keySleepTimerMin = 'sleep_timer_min';
  static const String keyOnboardDone = 'onboard_done';
  static const String keyNaturalSort = 'natural_sort';

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
