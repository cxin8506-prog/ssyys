import 'package:drift/drift.dart';

/// 媒体条目表：听书和视频共用，用 type 字段区分（严格隔离靠查询过滤实现）
class MediaItems extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()(); // audio | video
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get path => text()(); // 文件夹或文件路径
  TextColumn get coverPath => text().nullable()();
  TextColumn get sourceType =>
      text().withDefault(const Constant('folder'))(); // folder|single|archive
  IntColumn get chapterCount => integer().withDefault(const Constant(0))();
  IntColumn get durationMs => integer().nullable()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('unread'))();
  RealColumn get progress =>
      real().withDefault(const Constant(0))(); // 0.0 ~ 1.0
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get lastReadAt => dateTime().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 章节表（自然排序后写入 sortOrder）
class Chapters extends Table {
  TextColumn get id => text()();
  TextColumn get itemId =>
      text().references(MediaItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get path => text().nullable()(); // 本地路径或源 URL
  IntColumn get orderIndex => integer()();
  IntColumn get durationMs => integer().nullable()();
  BoolColumn get isCorrupted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// 播放/阅读进度（每条媒体一份）
class Progress extends Table {
  TextColumn get itemId =>
      text().references(MediaItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get chapterId => text().nullable()();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  RealColumn get speed => real().withDefault(const Constant(1.0))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {itemId};
}

/// 书签（时间点/页码）
class Bookmarks extends Table {
  TextColumn get id => text()();
  TextColumn get itemId =>
      text().references(MediaItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get chapterId => text().nullable()();
  IntColumn get positionMs => integer().withDefault(const Constant(0))();
  IntColumn get page => integer().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 收藏（type 字段区分听书/视频，互不干扰）
class Favorites extends Table {
  TextColumn get id => text()();
  TextColumn get itemId =>
      text().references(MediaItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()(); // audio | video
  TextColumn get groupName => text().withDefault(const Constant('默认'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 历史记录（与收藏分开）
class History extends Table {
  TextColumn get id => text()();
  TextColumn get itemId =>
      text().references(MediaItems, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()();
  DateTimeColumn get visitedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 日志表（关键操作与错误）
class Logs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get level => text()(); // info|warning|error
  TextColumn get message => text()();
  TextColumn get detail => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

/// 设置项（kv）
class KvSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// 源配置中心（二期预留：登录态/音色/线路）
class SourceConfigs extends Table {
  TextColumn get sourceId => text()();
  TextColumn get type => text()(); // audio | video
  TextColumn get enabled => text().withDefault(const Constant('true'))();
  TextColumn get loginState => text().nullable()(); // JSON
  TextColumn get voiceList => text().nullable()(); // JSON 数组
  TextColumn get selectedVoiceId => text().nullable()();
  TextColumn get lineList => text().nullable()(); // JSON 数组
  TextColumn get selectedLineId => text().nullable()();
  TextColumn get extra => text().nullable()(); // JSON

  @override
  Set<Column> get primaryKey => {sourceId};
}
