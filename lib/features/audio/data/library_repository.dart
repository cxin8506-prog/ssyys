import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/app_database.dart';
import '../../../core/log/app_logger.dart';
import '../domain/media_item.dart' as domain;
import 'importer.dart';

/// 书架数据仓库：听书/视频共用，查询按 type 隔离。
class LibraryRepository {
  final AppDatabase _db;
  final _uuid = const Uuid();

  LibraryRepository(this._db);

  // ---------- 查询 ----------

  /// 按类型 + 排序 + 筛选查询条目
  Future<List<domain.MediaItem>> query({
    required String type,
    String sortBy = AppConstants.sortByAddedAt,
    String filter = AppConstants.filterAll,
    String keyword = '',
  }) async {
    final query = _db.select(_db.mediaItems)
      ..where((tbl) => tbl.type.equals(type));

    if (keyword.isNotEmpty) {
      query.where(
          (tbl) => tbl.title.contains(keyword) | tbl.author.contains(keyword));
    }

    switch (filter) {
      case AppConstants.filterUnread:
        query.where((tbl) => tbl.status.equals(AppConstants.statusUnread));
        break;
      case AppConstants.filterReading:
        query.where((tbl) => tbl.status.equals(AppConstants.statusReading));
        break;
      case AppConstants.filterFinished:
        query.where((tbl) => tbl.status.equals(AppConstants.statusFinished));
        break;
    }

    switch (sortBy) {
      case AppConstants.sortByName:
        query.orderBy([(tbl) => OrderingTerm.asc(tbl.title)]);
        break;
      case AppConstants.sortByProgress:
        query.orderBy([(tbl) => OrderingTerm.desc(tbl.progress)]);
        break;
      case AppConstants.sortByLastRead:
        query.orderBy([(tbl) => OrderingTerm.desc(tbl.lastReadAt)]);
        break;
      default:
        query.orderBy([(tbl) => OrderingTerm.desc(tbl.addedAt)]);
    }

    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  /// 查询单条
  Future<domain.MediaItem?> getById(String id) async {
    final row = await (_db.select(_db.mediaItems)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  /// 查询章节（自然排序已写入 orderIndex）
  Future<List<domain.ChapterItem>> chapters(String itemId) async {
    final query = _db.select(_db.chapters)
      ..where((t) => t.itemId.equals(itemId))
      ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]);
    final rows = await query.get();
    return rows
        .map((r) => domain.ChapterItem(
              id: r.id,
              itemId: r.itemId,
              title: r.title,
              path: r.path,
              orderIndex: r.orderIndex,
              durationMs: r.durationMs,
              isCorrupted: r.isCorrupted,
            ))
        .toList();
  }

  /// 首页"继续阅读/播放"
  Future<List<domain.MediaItem>> continueList(String type) async {
    final query = _db.select(_db.mediaItems)
      ..where((tbl) =>
          tbl.type.equals(type) & tbl.status.equals(AppConstants.statusReading))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.lastReadAt)])
      ..limit(10);
    final rows = await query.get();
    return rows.map(_toModel).toList();
  }

  // ---------- 写入 ----------

  /// 保存导入结果（条目 + 章节 + 封面）
  Future<domain.MediaItem?> saveImport(ImportResult result) async {
    final item = result.item;
    if (item == null) return null;
    await _db.into(_db.mediaItems).insert(MediaItemsCompanion.insert(
          id: item.id,
          type: item.type,
          title: item.title,
          author: Value(item.author),
          path: item.path,
          coverPath: Value(item.coverPath),
          sourceType: Value(item.sourceType),
          chapterCount: Value(item.chapterCount),
          durationMs: Value(item.durationMs),
          sizeBytes: Value(item.sizeBytes),
          description: Value(item.description),
          status: Value(item.status),
          progress: Value(item.progress),
          addedAt: item.addedAt,
          lastReadAt: Value(item.lastReadAt),
        ));
    for (final c in result.chapters) {
      await _db.into(_db.chapters).insert(ChaptersCompanion.insert(
            id: c.id,
            itemId: c.itemId,
            title: c.title,
            path: Value(c.path),
            orderIndex: c.orderIndex,
            durationMs: Value(c.durationMs),
          ));
    }
    for (final e in result.errors) {
      appLogger.warning('导入告警', detail: e);
    }
    return item;
  }

  /// 更新进度
  Future<void> updateProgress({
    required String itemId,
    String? chapterId,
    required int positionMs,
    double? speed,
    double? progress,
  }) async {
    await _db
        .into(_db.progress)
        .insertOnConflictUpdate(ProgressCompanion.insert(
          itemId: itemId,
          chapterId: Value(chapterId),
          positionMs: Value(positionMs),
          speed: Value(speed ?? 1.0),
          updatedAt: DateTime.now(),
        ));
    final update = MediaItemsCompanion(
      status: const Value(AppConstants.statusReading),
      lastReadAt: Value(DateTime.now()),
      progress: progress != null ? Value(progress) : const Value.absent(),
    );
    await (_db.update(_db.mediaItems)..where((t) => t.id.equals(itemId)))
        .write(update);
  }

  /// 读取进度
  Future<Progres?> getProgress(String itemId) async =>
      (_db.select(_db.progress)..where((t) => t.itemId.equals(itemId)))
          .getSingleOrNull();

  /// 改名
  Future<void> rename(String id, String newTitle) =>
      (_db.update(_db.mediaItems)..where((t) => t.id.equals(id)))
          .write(MediaItemsCompanion(title: Value(newTitle)));

  /// 改封面
  Future<void> setCover(String id, String coverPath) =>
      (_db.update(_db.mediaItems)..where((t) => t.id.equals(id)))
          .write(MediaItemsCompanion(coverPath: Value(coverPath)));

  /// 删除（关联章节/进度/书签/收藏/历史由外键级联）
  Future<void> delete(String id) async {
    await (_db.delete(_db.mediaItems)..where((t) => t.id.equals(id))).go();
    appLogger.info('删除条目', detail: id);
  }

  /// 标记完成
  Future<void> markFinished(String id) =>
      (_db.update(_db.mediaItems)..where((t) => t.id.equals(id))).write(
        MediaItemsCompanion(
          status: const Value(AppConstants.statusFinished),
          progress: const Value(1.0),
        ),
      );

  // ---------- 收藏 / 历史 / 书签 ----------

  Future<void> addFavorite(String itemId, String type,
      {String group = '默认'}) async {
    await _db.into(_db.favorites).insert(FavoritesCompanion.insert(
          id: _uuid.v4(),
          itemId: itemId,
          type: type,
          groupName: Value(group),
          createdAt: DateTime.now(),
        ));
  }

  Future<void> removeFavorite(String itemId) =>
      (_db.delete(_db.favorites)..where((t) => t.itemId.equals(itemId))).go();

  Future<bool> isFavorite(String itemId) async {
    final rows = await (_db.select(_db.favorites)
          ..where((t) => t.itemId.equals(itemId)))
        .get();
    return rows.isNotEmpty;
  }

  Future<List<domain.MediaItem>> favorites(String type) async {
    final query = _db.select(_db.mediaItems).join([
      innerJoin(
          _db.favorites, _db.favorites.itemId.equalsExp(_db.mediaItems.id)),
    ])
      ..where(_db.favorites.type.equals(type))
      ..orderBy([OrderingTerm.desc(_db.favorites.createdAt)]);
    final rows = await query.get();
    return rows.map((r) => _toModel(r.readTable(_db.mediaItems))).toList();
  }

  /// 收藏分组名（“默认”在最前）
  Future<List<String>> favoriteGroups() async {
    final rows = await (_db.selectOnly(_db.favorites)
          ..addColumns([_db.favorites.groupName])
          ..groupBy([_db.favorites.groupName]))
        .get();
    final names = rows
        .map((r) => r.read(_db.favorites.groupName) ?? '默认')
        .toSet()
        .toList();
    names.remove('默认');
    names.insert(0, '默认');
    return names;
  }

  /// 某个分组下的收藏
  Future<List<domain.MediaItem>> favoritesByGroup(
      String group, String type) async {
    final query = _db.select(_db.mediaItems).join([
      innerJoin(
          _db.favorites, _db.favorites.itemId.equalsExp(_db.mediaItems.id)),
    ])
      ..where(_db.favorites.type.equals(type))
      ..where(_db.favorites.groupName.equals(group))
      ..orderBy([OrderingTerm.desc(_db.favorites.createdAt)]);
    final rows = await query.get();
    return rows.map((r) => _toModel(r.readTable(_db.mediaItems))).toList();
  }

  /// 收藏分组重命名（“默认”不能改名）
  Future<void> renameFavoriteGroup(String oldName, String newName) async {
    if (oldName == newName || oldName == '默认' || newName.trim().isEmpty) {
      return;
    }
    await (_db.update(_db.favorites)
          ..where((t) => t.groupName.equals(oldName)))
        .write(FavoritesCompanion(groupName: Value(newName.trim())));
  }

  /// 导出收藏用的原始条目（带分组）
  Future<List<Map<String, String>>> favoriteEntries() async {
    final rows = await _db.select(_db.favorites).get();
    return rows
        .map((r) => {
              'itemId': r.itemId,
              'type': r.type,
              'group': r.groupName,
            })
        .toList();
  }

  /// 清空历史（不传类型就是全部清空）
  Future<void> clearHistory([String? type]) async {
    if (type == null) {
      await _db.delete(_db.history).go();
    } else {
      await (_db.delete(_db.history)
            ..where((t) => t.type.equals(type)))
          .go();
    }
  }

  Future<void> addHistory(String itemId, String type) async {
    await _db.into(_db.history).insert(HistoryCompanion.insert(
          id: _uuid.v4(),
          itemId: itemId,
          type: type,
          visitedAt: DateTime.now(),
        ));
  }

  Future<List<domain.MediaItem>> history(String type) async {
    final query = _db.select(_db.mediaItems).join([
      innerJoin(_db.history, _db.history.itemId.equalsExp(_db.mediaItems.id)),
    ])
      ..where(_db.history.type.equals(type))
      ..orderBy([OrderingTerm.desc(_db.history.visitedAt)])
      ..limit(50);
    final rows = await query.get();
    return rows.map((r) => _toModel(r.readTable(_db.mediaItems))).toList();
  }

  Future<void> addBookmark({
    required String itemId,
    String? chapterId,
    required int positionMs,
    int? page,
    String? note,
  }) async {
    await _db.into(_db.bookmarks).insert(BookmarksCompanion.insert(
          id: _uuid.v4(),
          itemId: itemId,
          chapterId: Value(chapterId),
          positionMs: Value(positionMs),
          page: Value(page),
          note: Value(note),
          createdAt: DateTime.now(),
        ));
  }

  Future<List<Bookmark>> bookmarks(String itemId) =>
      (_db.select(_db.bookmarks)..where((t) => t.itemId.equals(itemId))).get();

  Future<void> deleteBookmark(String id) =>
      (_db.delete(_db.bookmarks)..where((t) => t.id.equals(id))).go();

  // ---------- 模型转换 ----------

  domain.MediaItem _toModel(MediaItem r) => domain.MediaItem(
        id: r.id,
        type: r.type,
        title: r.title,
        author: r.author,
        path: r.path,
        coverPath: r.coverPath,
        sourceType: r.sourceType,
        chapterCount: r.chapterCount,
        durationMs: r.durationMs,
        sizeBytes: r.sizeBytes,
        description: r.description,
        status: r.status,
        progress: r.progress,
        addedAt: r.addedAt,
        lastReadAt: r.lastReadAt,
      );
}
