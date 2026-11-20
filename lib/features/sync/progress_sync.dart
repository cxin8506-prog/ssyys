import 'dart:convert';

import '../../core/database/library_repository.dart';
import '../../core/log/app_logger.dart';
import 'webdav_client.dart';

/// 进度实时同步（和整包备份分开的两条线，照 Legado / Audiobookshelf）：
/// 每本书一个小文件 `progress/<bookId>.json`，15 秒一同步（调用方计时），
/// 流量下调用方自己放宽到 60 秒；失败只记日志，连续失败 2 次才写一条警告，
/// 不弹窗打扰用户。启动时只下载比本地 syncTime 新、且位置比本地靠前的进度。
class ProgressSync {
  ProgressSync._();

  static const String _dir = 'progress';
  static int _failures = 0;

  static String _syncTimeKey(String bookId) => 'sync_time_$bookId';

  static String _fileName(String bookId) => '$_dir/$bookId.json';

  /// 上传一本书的当前进度（有变化才传；传完写本地 syncTime）。
  static Future<void> uploadBookProgress({
    required LibraryRepository repo,
    required WebDavClient client,
    required String bookId,
  }) async {
    try {
      final progress = await repo.getLatestProgress(bookId);
      if (progress == null) return;
      final lastSync = await repo.getInt(_syncTimeKey(bookId)) ?? 0;
      final updatedMs = progress.updatedAt.millisecondsSinceEpoch;
      if (updatedMs <= lastSync) return;
      final payload = <String, dynamic>{
        'bookId': bookId,
        'chapterUrl': progress.chapterUrl,
        'positionMs': progress.positionMs,
        'durationMs': progress.durationMs,
        'isFinished': progress.isFinished,
        'updatedAtMs': updatedMs,
      };
      await client.putText(_fileName(bookId), jsonEncode(payload));
      await repo.setInt(_syncTimeKey(bookId), updatedMs);
      _failures = 0;
    } catch (e) {
      _failures++;
      if (_failures == 2) {
        appLogger.warning('同步进度失败（已连续失败 2 次）', detail: '$e');
      }
    }
  }

  /// 启动时下载：只下载比本地 syncTime 新、且位置比本地靠前的进度。
  static Future<void> downloadNewerProgress({
    required LibraryRepository repo,
    required WebDavClient client,
  }) async {
    try {
      final items = await client.listProgress();
      for (final item in items) {
        final bookId = item.name.replaceAll('.json', '');
        if (bookId.isEmpty) continue;
        final text = await client.getText(_fileName(bookId));
        if (text == null || text.isEmpty) continue;
        Map<String, dynamic> data;
        try {
          data = jsonDecode(text) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }
        final remoteUpdatedMs = (data['updatedAtMs'] as num?)?.toInt() ?? 0;
        final lastSync = await repo.getInt(_syncTimeKey(bookId)) ?? 0;
        if (remoteUpdatedMs <= lastSync) continue;
        final book = await repo.getBook(bookId);
        if (book == null) continue;
        final chapterUrl = '${data['chapterUrl'] ?? ''}';
        final positionMs = (data['positionMs'] as num?)?.toInt() ?? 0;
        final durationMs = (data['durationMs'] as num?)?.toInt() ?? 0;
        final isFinished = data['isFinished'] == true;
        final local = await repo.getProgress(bookId, chapterUrl);
        // 位置比本地靠前才覆盖；本地靠前时云端被忽略，本地赢
        final remoteAhead = local == null ||
            positionMs > local.positionMs ||
            (isFinished && !local.isFinished);
        if (!remoteAhead) {
          await repo.setInt(_syncTimeKey(bookId), remoteUpdatedMs);
          continue;
        }
        await repo.saveProgress(
          bookId: bookId,
          chapterUrl: chapterUrl,
          positionMs: positionMs,
          durationMs: durationMs,
          isFinished: isFinished,
        );
        await repo.setInt(_syncTimeKey(bookId), remoteUpdatedMs);
      }
      _failures = 0;
    } catch (e) {
      _failures++;
      if (_failures == 2) {
        appLogger.warning('下载云端进度失败（已连续失败 2 次）', detail: '$e');
      }
    }
  }

  /// 全量同步一次：先下载云端更新的，再上传本地更新的。
  static Future<void> syncAll({
    required LibraryRepository repo,
    required WebDavClient client,
  }) async {
    await downloadNewerProgress(repo: repo, client: client);
    final listening = await repo.getListening();
    for (final book in listening) {
      await uploadBookProgress(repo: repo, client: client, bookId: book.id);
    }
  }
}
