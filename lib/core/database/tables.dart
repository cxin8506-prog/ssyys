import 'package:drift/drift.dart';

/// 媒体条目表：听书和视频共用一张表，type 字段区分（audio | video）。
/// 断点/历史/收藏统一走这张表 + Progress/History/Favorites，不另开表。
class MediaItems extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get coverUrl => text().nullable()();
  TextColumn get sourceId => text()();
  TextColumn get sourceName => text()();
  TextColumn get type => text()(); // audio | video
  TextColumn get lastChapterUrl => text().nullable()();
  IntColumn get lastPositionMs => integer().withDefault(const Constant(0))();
  IntColumn get lastDurationMs => integer().withDefault(const Constant(0))();
  BoolColumn get isFinished => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 章节表：一本书的章节列表（插件详情页取到的章节可缓存于此）。
class Chapters extends Table {
  TextColumn get id => text()();
  TextColumn get itemId =>
      text().references(MediaItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get url => text().nullable()();
  IntColumn get orderIndex => integer()();
  IntColumn get durationMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 播放进度：每本书每章一份（bookId + chapterUrl 联合主键）。
class Progress extends Table {
  TextColumn get itemId =>
      text().references(MediaItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get chapterUrl => text()();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  BoolColumn get isFinished => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {itemId, chapterUrl};
}

/// 书签：某本书某章某个时间点的标记。
class Bookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get itemId =>
      text().references(MediaItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get chapterUrl => text().nullable()();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 收藏：type 字段区分听书/视频，互不干扰。
class Favorites extends Table {
  TextColumn get id => text()();
  TextColumn get itemId =>
      text().references(MediaItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()(); // audio | video
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 历史记录：一次播放/打开记一行，带时间；与 Progress 按时间合并成统一时间线。
class History extends Table {
  TextColumn get id => text()();
  TextColumn get itemId =>
      text().references(MediaItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()(); // audio | video
  TextColumn get chapterUrl => text().nullable()();
  DateTimeColumn get visitedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 运行日志：只存数据库 Logs 表，最新 500 条；不写本地文件。
class Logs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get level => text()(); // info | warning | error
  TextColumn get message => text()();
  TextColumn get detail => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// 设置项（kv）：UA 配置、源配置以外的轻量设置也走这里。
class KvSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 源配置中心：登录态 / 音色 / 线路 / 额外 JSON，按源 id 一行。
class SourceConfigs extends Table {
  TextColumn get sourceId => text()();
  TextColumn get type => text()(); // audio | video
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  TextColumn get loginState => text().nullable()(); // JSON
  TextColumn get voiceList => text().nullable()(); // JSON 数组
  TextColumn get selectedVoiceId => text().nullable()();
  TextColumn get lineList => text().nullable()(); // JSON 数组
  TextColumn get selectedLineId => text().nullable()();
  TextColumn get extra => text().nullable()(); // JSON

  @override
  Set<Column> get primaryKey => {sourceId};
}
