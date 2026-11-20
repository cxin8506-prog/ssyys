import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import 'app_database.dart';

/// [LibraryRepository] provider：其他代理只通过它用库，不直接碰 drift。
final libraryRepositoryProvider = Provider<LibraryRepository>((ref) {
  return LibraryRepository(ref.read(databaseProvider));
});

/// 一章的断点（[Progress] 表的一行，去掉了 drift 的命名怪癖）。
class BookProgress {
  final String bookId;
  final String chapterUrl;
  final int positionMs;
  final int durationMs;
  final bool isFinished;
  final DateTime updatedAt;
  const BookProgress({
    required this.bookId,
    required this.chapterUrl,
    required this.positionMs,
    required this.durationMs,
    required this.isFinished,
    required this.updatedAt,
  });
}

/// 统一时间线的一行：历史记录与插件断点按时间合并，同一本书只留最新的一条。
class TimelineEntry {
  /// 'history' | 'progress'
  final String kind;
  final String bookId;
  final String title;
  final String? author;
  final String type;
  final String? chapterUrl;
  final int positionMs;
  final DateTime visitedAt;
  const TimelineEntry({
    required this.kind,
    required this.bookId,
    required this.title,
    this.author,
    required this.type,
    this.chapterUrl,
    required this.positionMs,
    required this.visitedAt,
  });
}

/// 书架 / 断点 / 收藏 / 历史 / 书签 / 日志 / kv 的唯一入口。
class LibraryRepository {
  final AppDatabase db;

  LibraryRepository(this.db);

  final _uuid = const Uuid();

  // ------------------------------------------------------------ 书

  /// 查书：关键词匹配标题/作者，可按类型（audio/video）与源过滤。
  Future<List<MediaItem>> query({
    String? keyword,
    String? type,
    String? sourceId,
  }) async {
    final q = db.select(db.mediaItems);
    if (keyword != null && keyword.trim().isNotEmpty) {
      final kw = '%${keyword.trim()}%';
      q.where((t) => t.title.like(kw) | t.author.like(kw));
    }
    if (type != null && type.isNotEmpty) {
      q.where((t) => t.type.equals(type));
    }
    if (sourceId != null && sourceId.isNotEmpty) {
      q.where((t) => t.sourceId.equals(sourceId));
    }
    q.orderBy([
      (t) => OrderingTerm.desc(t.lastPlayedAt),
      (t) => OrderingTerm.desc(t.createdAt),
    ]);
    return q.get();
  }

  Future<MediaItem?> getBook(String bookId) async {
    final rows = await (db.select(db.mediaItems)
          ..where((t) => t.id.equals(bookId)))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// 新建或更新一本书（WebDAV 成书、搜索详情页落库都走这里）。
  Future<void> upsertMediaItem(MediaItemsCompanion item) =>
      db.into(db.mediaItems).insertOnConflictUpdate(item);

  Future<void> deleteBook(String bookId) async {
    await (db.delete(db.mediaItems)..where((t) => t.id.equals(bookId))).go();
  }

  Future<int> countBooks() async {
    final rows =
        await db.customSelect('SELECT COUNT(*) AS c FROM media_items').get();
    return rows.first.read<int>('c');
  }

  Future<int> countFinishedBooks() async {
    final rows = await db.customSelect(
      'SELECT COUNT(*) AS c FROM media_items WHERE is_finished = 1',
    ).get();
    return rows.first.read<int>('c');
  }

  /// 最近播过的那本书（有最后播放时间，按时间倒序第一条）。
  Future<MediaItem?> getLatestPlayed() async {
    final rows = await (db.select(db.mediaItems)
          ..where((t) => t.lastPlayedAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.lastPlayedAt)])
          ..limit(1))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  /// 继续收听：有进度、没听完、最后播放时间最晚的那本。
  Future<MediaItem?> getContinueListening() async {
    final list = await getListening();
    return list.isEmpty ? null : list.first;
  }

  /// 在听：有进度、没听完，按最后播放时间倒序；听完的沉底（不在这里）。
  Future<List<MediaItem>> getListening() async {
    return (db.select(db.mediaItems)
          ..where((t) =>
              t.lastPositionMs.isBiggerThanValue(0) & t.isFinished.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.lastPlayedAt)]))
        .get();
  }

  /// 听完：isFinished，按最后播放时间倒序。
  Future<List<MediaItem>> getFinished() async {
    return (db.select(db.mediaItems)
          ..where((t) => t.isFinished.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.lastPlayedAt)]))
        .get();
  }

  // ------------------------------------------------------------ 章节

  Future<List<Chapter>> getChapters(String itemId) async {
    return (db.select(db.chapters)
          ..where((t) => t.itemId.equals(itemId))
          ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
        .get();
  }

  /// 整批换掉一本书的章节（详情页取到章节列表后缓存）。
  Future<void> saveChapters(
    String itemId,
    List<Map<String, dynamic>> chapters,
  ) async {
    await db.transaction(() async {
      await (db.delete(db.chapters)..where((t) => t.itemId.equals(itemId)))
          .go();
      for (var i = 0; i < chapters.length; i++) {
        final c = chapters[i];
        await db.into(db.chapters).insert(ChaptersCompanion.insert(
              id: '${itemId}_$i',
              itemId: itemId,
              title: '${c['name'] ?? c['title'] ?? '第${i + 1}章'}',
              url: Value('${c['url'] ?? ''}'),
              orderIndex: i,
              durationMs: Value(c['durationMs'] as int?),
            ));
      }
    });
  }

  // ------------------------------------------------------------ 断点

  /// 存断点：写 Progress 行，同时刷新书上的最后章节/位置/听完标记/最后播放时间。
  /// 位置变化 <5000ms 不写盘由调用方（播放器）节流，这里只管写。
  Future<void> saveProgress({
    required String bookId,
    required String chapterUrl,
    required int positionMs,
    required int durationMs,
    required bool isFinished,
  }) async {
    final now = DateTime.now();
    await db.into(db.progress).insertOnConflictUpdate(
          ProgressCompanion.insert(
            itemId: bookId,
            chapterUrl: chapterUrl,
            positionMs: Value(positionMs),
            durationMs: Value(durationMs),
            isFinished: Value(isFinished),
            updatedAt: now,
          ),
        );
    final book = await getBook(bookId);
    if (book != null) {
      final wasFinished = book.isFinished;
      await (db.update(db.mediaItems)..where((t) => t.id.equals(bookId)))
          .write(MediaItemsCompanion(
        lastChapterUrl: Value(chapterUrl),
        lastPositionMs: Value(positionMs),
        lastDurationMs: Value(durationMs),
        isFinished: Value(isFinished),
        lastPlayedAt: Value(now),
      ));
      if (isFinished && !wasFinished) {
        await _markFinishedInStats(bookId);
      }
    }
  }

  Future<BookProgress?> getProgress(String bookId, String chapterUrl) async {
    final rows = await (db.select(db.progress)
          ..where((t) =>
              t.itemId.equals(bookId) & t.chapterUrl.equals(chapterUrl)))
        .get();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return BookProgress(
      bookId: r.itemId,
      chapterUrl: r.chapterUrl,
      positionMs: r.positionMs,
      durationMs: r.durationMs,
      isFinished: r.isFinished,
      updatedAt: r.updatedAt,
    );
  }

  /// 这本书最近一次的断点（不论哪一章）。
  Future<BookProgress?> getLatestProgress(String bookId) async {
    final rows = await (db.select(db.progress)
          ..where((t) => t.itemId.equals(bookId))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
          ..limit(1))
        .get();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return BookProgress(
      bookId: r.itemId,
      chapterUrl: r.chapterUrl,
      positionMs: r.positionMs,
      durationMs: r.durationMs,
      isFinished: r.isFinished,
      updatedAt: r.updatedAt,
    );
  }

  /// 清断点（按类型分别清，不动另一类型的断点）。
  Future<void> clearProgress({String? type}) async {
    if (type == null || type.isEmpty) {
      await db.delete(db.progress).go();
      await db
          .update(db.mediaItems)
          .write(const MediaItemsCompanion(
            lastPositionMs: Value(0),
            lastDurationMs: Value(0),
            isFinished: Value(false),
          ));
      return;
    }
    final books = await (db.select(db.mediaItems)
          ..where((t) => t.type.equals(type)))
        .get();
    for (final b in books) {
      await (db.delete(db.progress)..where((t) => t.itemId.equals(b.id))).go();
      await (db.update(db.mediaItems)..where((t) => t.id.equals(b.id))).write(
        const MediaItemsCompanion(
          lastPositionMs: Value(0),
          lastDurationMs: Value(0),
          isFinished: Value(false),
        ),
      );
    }
  }

  // ------------------------------------------------------------ 收藏

  Future<void> addFavorite(String bookId) async {
    final book = await getBook(bookId);
    if (book == null) return;
    await db.into(db.favorites).insertOnConflictUpdate(
          FavoritesCompanion.insert(
            id: _uuid.v4(),
            itemId: bookId,
            type: book.type,
            createdAt: DateTime.now(),
          ),
        );
    await (db.update(db.mediaItems)..where((t) => t.id.equals(bookId)))
        .write(const MediaItemsCompanion(isFavorite: Value(true)));
  }

  Future<void> removeFavorite(String bookId) async {
    await (db.delete(db.favorites)..where((t) => t.itemId.equals(bookId))).go();
    await (db.update(db.mediaItems)..where((t) => t.id.equals(bookId)))
        .write(const MediaItemsCompanion(isFavorite: Value(false)));
  }

  Future<bool> isFavorite(String bookId) async {
    final rows = await (db.select(db.favorites)
          ..where((t) => t.itemId.equals(bookId)))
        .get();
    return rows.isNotEmpty;
  }

  /// 收藏的书（按收藏时间倒序），可按类型过滤。
  Future<List<MediaItem>> getFavorites({String? type}) async {
    final favIds = await (db.select(db.favorites)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    final out = <MediaItem>[];
    for (final f in favIds) {
      if (type != null && type.isNotEmpty && f.type != type) continue;
      final book = await getBook(f.itemId);
      if (book != null) out.add(book);
    }
    return out;
  }

  // ------------------------------------------------------------ 历史

  Future<void> addHistory(
    String bookId, {
    required String type,
    String? chapterUrl,
  }) async {
    await db.into(db.history).insert(HistoryCompanion.insert(
          id: _uuid.v4(),
          itemId: bookId,
          type: type,
          chapterUrl: Value(chapterUrl),
          visitedAt: DateTime.now(),
        ));
  }

  Future<List<HistoryData>> getHistoryRows({String? type}) async {
    final q = db.select(db.history);
    if (type != null && type.isNotEmpty) {
      q.where((t) => t.type.equals(type));
    }
    q.orderBy([(t) => OrderingTerm.desc(t.visitedAt)]);
    return q.get();
  }

  /// 统一时间线：历史记录 + 插件断点按时间合并，同一本书只留最新的一条。
  /// 不许插件断点全排在前、本地历史全排在后。
  Future<List<TimelineEntry>> getHistory({String? type}) async {
    final byBook = <String, TimelineEntry>{};

    final rows = await getHistoryRows(type: type);
    for (final r in rows) {
      final book = await getBook(r.itemId);
      if (book == null) continue;
      byBook[r.itemId] = TimelineEntry(
        kind: 'history',
        bookId: r.itemId,
        title: book.title,
        author: book.author,
        type: r.type,
        chapterUrl: r.chapterUrl,
        positionMs: book.lastPositionMs,
        visitedAt: r.visitedAt,
      );
    }

    final progRows = await (db.select(db.progress)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
    for (final p in progRows) {
      final book = await getBook(p.itemId);
      if (book == null) continue;
      if (type != null && type.isNotEmpty && book.type != type) continue;
      final old = byBook[p.itemId];
      if (old != null && !p.updatedAt.isAfter(old.visitedAt)) continue;
      byBook[p.itemId] = TimelineEntry(
        kind: 'progress',
        bookId: p.itemId,
        title: book.title,
        author: book.author,
        type: book.type,
        chapterUrl: p.chapterUrl,
        positionMs: p.positionMs,
        visitedAt: p.updatedAt,
      );
    }

    final list = byBook.values.toList();
    list.sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    return list;
  }

  /// 按书删历史：该书的历史行 + 断点一起清，书本身保留。
  Future<void> deleteHistoryByBook(String bookId) async {
    await (db.delete(db.history)..where((t) => t.itemId.equals(bookId))).go();
    await (db.delete(db.progress)..where((t) => t.itemId.equals(bookId))).go();
    await (db.update(db.mediaItems)..where((t) => t.id.equals(bookId))).write(
      const MediaItemsCompanion(
        lastPositionMs: Value(0),
        lastDurationMs: Value(0),
        isFinished: Value(false),
      ),
    );
  }

  /// 清空历史：只清 History 表，按类型分别清；断点要清走 [clearProgress]。
  Future<void> clearHistory({String? type}) async {
    if (type == null || type.isEmpty) {
      await db.delete(db.history).go();
      return;
    }
    await (db.delete(db.history)..where((t) => t.type.equals(type))).go();
  }

  // ------------------------------------------------------------ 书签

  Future<String> saveBookmark({
    required String bookId,
    String? chapterUrl,
    required int positionMs,
    String? note,
  }) async {
    final id = _uuid.v4();
    await db.into(db.bookmarks).insert(BookmarksCompanion.insert(
          id: id,
          itemId: bookId,
          chapterUrl: Value(chapterUrl),
          positionMs: Value(positionMs),
          note: Value(note),
          createdAt: DateTime.now(),
        ));
    return id;
  }

  Future<List<Bookmark>> getBookmarks(String bookId) async {
    return (db.select(db.bookmarks)
          ..where((t) => t.itemId.equals(bookId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  Future<void> deleteBookmark(String id) async {
    await (db.delete(db.bookmarks)..where((t) => t.id.equals(id))).go();
  }

  // ------------------------------------------------------------ 日志

  Future<void> log(String level, String message, {String? detail}) =>
      db.log(level, message, detail: detail);

  Future<List<Log>> getLogs({int limit = 500}) async {
    return (db.select(db.logs)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<void> clearLogs() async {
    await db.delete(db.logs).go();
  }

  // ------------------------------------------------------------ kv

  Future<String?> getString(String key) => db.readSetting(key);

  Future<void> setString(String key, String value) =>
      db.writeSetting(key, value);

  Future<bool?> getBool(String key) async {
    final v = await db.readSetting(key);
    if (v == null) return null;
    return v == '1' || v.toLowerCase() == 'true';
  }

  Future<void> setBool(String key, bool value) =>
      db.writeSetting(key, value ? '1' : '0');

  Future<int?> getInt(String key) async {
    final v = await db.readSetting(key);
    if (v == null) return null;
    return int.tryParse(v);
  }

  Future<void> setInt(String key, int value) =>
      db.writeSetting(key, value.toString());

  // ------------------------------------------------------------ 内部

  /// 书第一次听完时记进收听统计的已听完 id 集合（供 listen_stats 读）。
  Future<void> _markFinishedInStats(String bookId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(AppConstants.keyListenFinishedIds);
      final ids = <String>[];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) ids.addAll(decoded.whereType<String>());
      }
      if (!ids.contains(bookId)) {
        ids.add(bookId);
        await prefs.setString(
            AppConstants.keyListenFinishedIds, jsonEncode(ids));
      }
    } catch (_) {
      // 统计写失败不影响断点本身
    }
  }
}
