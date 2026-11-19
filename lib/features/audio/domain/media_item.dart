import '../../../core/constants/app_constants.dart';

/// 媒体条目的领域模型（UI 层使用）
class MediaItem {
  final String id;
  final String type; // audio | video
  final String title;
  final String? author;
  final String path;
  final String? coverPath;
  final String sourceType; // folder | single | archive
  final int chapterCount;
  final int? durationMs;
  final int sizeBytes;
  final String? description;
  final String status;
  final double progress;
  final DateTime addedAt;
  final DateTime? lastReadAt;

  const MediaItem({
    required this.id,
    required this.type,
    required this.title,
    this.author,
    required this.path,
    this.coverPath,
    this.sourceType = 'folder',
    this.chapterCount = 0,
    this.durationMs,
    this.sizeBytes = 0,
    this.description,
    this.status = AppConstants.statusUnread,
    this.progress = 0.0,
    required this.addedAt,
    this.lastReadAt,
  });

  bool get isAudio => type == AppConstants.typeAudio;
  bool get isVideo => type == AppConstants.typeVideo;

  double get progressPercent => progress <= 1.0 ? progress * 100 : progress;

  String get statusLabel {
    switch (status) {
      case AppConstants.statusReading:
        return '在读/播放中';
      case AppConstants.statusFinished:
        return '已完成';
      default:
        return '未读';
    }
  }
}

/// 章节模型
class ChapterItem {
  final String id;
  final String itemId;
  final String title;
  final String? path;
  final int orderIndex;
  final int? durationMs;
  final bool isCorrupted;

  const ChapterItem({
    required this.id,
    required this.itemId,
    required this.title,
    this.path,
    required this.orderIndex,
    this.durationMs,
    this.isCorrupted = false,
  });
}
