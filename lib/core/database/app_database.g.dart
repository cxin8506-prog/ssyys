// GENERATED CODE - DO NOT MODIFY BY HAND
//
// 注意：沙箱无 build_runner，本文件是按 drift 2.4.0 生成代码结构手写的等价实现，
// 对应 lib/core/database/tables.dart 的 9 张表。CI 有 build_runner 时应以
// `flutter pub run build_runner build` 重新生成并核对；手写版省略了
// fromJson/toJson/copyWith/hashCode/==/toString 这些纯便利方法（不影响 drift 运行）。

part of 'app_database.dart';

// ignore_for_file: type=lint

// ---------------------------------------------------------------------------
// MediaItems
// ---------------------------------------------------------------------------

class MediaItem extends DataClass implements Insertable<MediaItem> {
  final String id;
  final String title;
  final String? author;
  final String? coverUrl;
  final String sourceId;
  final String sourceName;
  final String type;
  final String? lastChapterUrl;
  final int lastPositionMs;
  final int lastDurationMs;
  final bool isFinished;
  final bool isFavorite;
  final DateTime? lastPlayedAt;
  final DateTime createdAt;
  const MediaItem(
      {required this.id,
      required this.title,
      this.author,
      this.coverUrl,
      required this.sourceId,
      required this.sourceName,
      required this.type,
      this.lastChapterUrl,
      required this.lastPositionMs,
      required this.lastDurationMs,
      required this.isFinished,
      required this.isFavorite,
      this.lastPlayedAt,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    if (!nullToAbsent || coverUrl != null) {
      map['cover_url'] = Variable<String>(coverUrl);
    }
    map['source_id'] = Variable<String>(sourceId);
    map['source_name'] = Variable<String>(sourceName);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || lastChapterUrl != null) {
      map['last_chapter_url'] = Variable<String>(lastChapterUrl);
    }
    map['last_position_ms'] = Variable<int>(lastPositionMs);
    map['last_duration_ms'] = Variable<int>(lastDurationMs);
    map['is_finished'] = Variable<bool>(isFinished);
    map['is_favorite'] = Variable<bool>(isFavorite);
    if (!nullToAbsent || lastPlayedAt != null) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  MediaItemsCompanion toCompanion(bool nullToAbsent) {
    return MediaItemsCompanion(
      id: Value(id),
      title: Value(title),
      author:
          author == null && nullToAbsent ? const Value.absent() : Value(author),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      sourceId: Value(sourceId),
      sourceName: Value(sourceName),
      type: Value(type),
      lastChapterUrl: lastChapterUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(lastChapterUrl),
      lastPositionMs: Value(lastPositionMs),
      lastDurationMs: Value(lastDurationMs),
      isFinished: Value(isFinished),
      isFavorite: Value(isFavorite),
      lastPlayedAt: lastPlayedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayedAt),
      createdAt: Value(createdAt),
    );
  }
}

class MediaItemsCompanion extends UpdateCompanion<MediaItem> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> author;
  final Value<String?> coverUrl;
  final Value<String> sourceId;
  final Value<String> sourceName;
  final Value<String> type;
  final Value<String?> lastChapterUrl;
  final Value<int> lastPositionMs;
  final Value<int> lastDurationMs;
  final Value<bool> isFinished;
  final Value<bool> isFavorite;
  final Value<DateTime?> lastPlayedAt;
  final Value<DateTime> createdAt;
  const MediaItemsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.type = const Value.absent(),
    this.lastChapterUrl = const Value.absent(),
    this.lastPositionMs = const Value.absent(),
    this.lastDurationMs = const Value.absent(),
    this.isFinished = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  MediaItemsCompanion.insert({
    required String id,
    required String title,
    this.author = const Value.absent(),
    this.coverUrl = const Value.absent(),
    required String sourceId,
    required String sourceName,
    required String type,
    this.lastChapterUrl = const Value.absent(),
    this.lastPositionMs = const Value.absent(),
    this.lastDurationMs = const Value.absent(),
    this.isFinished = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    required DateTime createdAt,
  })  : id = Value(id),
        title = Value(title),
        sourceId = Value(sourceId),
        sourceName = Value(sourceName),
        type = Value(type),
        createdAt = Value(createdAt);
  static Insertable<MediaItem> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? coverUrl,
    Expression<String>? sourceId,
    Expression<String>? sourceName,
    Expression<String>? type,
    Expression<String>? lastChapterUrl,
    Expression<int>? lastPositionMs,
    Expression<int>? lastDurationMs,
    Expression<bool>? isFinished,
    Expression<bool>? isFavorite,
    Expression<DateTime>? lastPlayedAt,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (sourceId != null) 'source_id': sourceId,
      if (sourceName != null) 'source_name': sourceName,
      if (type != null) 'type': type,
      if (lastChapterUrl != null) 'last_chapter_url': lastChapterUrl,
      if (lastPositionMs != null) 'last_position_ms': lastPositionMs,
      if (lastDurationMs != null) 'last_duration_ms': lastDurationMs,
      if (isFinished != null) 'is_finished': isFinished,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (coverUrl.present) {
      map['cover_url'] = Variable<String>(coverUrl.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (lastChapterUrl.present) {
      map['last_chapter_url'] = Variable<String>(lastChapterUrl.value);
    }
    if (lastPositionMs.present) {
      map['last_position_ms'] = Variable<int>(lastPositionMs.value);
    }
    if (lastDurationMs.present) {
      map['last_duration_ms'] = Variable<int>(lastDurationMs.value);
    }
    if (isFinished.present) {
      map['is_finished'] = Variable<bool>(isFinished.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }
}

class $MediaItemsTable extends MediaItems
    with TableInfo<$MediaItemsTable, MediaItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _authorMeta =
      const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
      'author', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _coverUrlMeta =
      const VerificationMeta('coverUrl');
  @override
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
      'cover_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceIdMeta =
      const VerificationMeta('sourceId');
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
      'source_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _sourceNameMeta =
      const VerificationMeta('sourceName');
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
      'source_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastChapterUrlMeta =
      const VerificationMeta('lastChapterUrl');
  @override
  late final GeneratedColumn<String> lastChapterUrl = GeneratedColumn<String>(
      'last_chapter_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastPositionMsMeta =
      const VerificationMeta('lastPositionMs');
  @override
  late final GeneratedColumn<int> lastPositionMs = GeneratedColumn<int>(
      'last_position_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastDurationMsMeta =
      const VerificationMeta('lastDurationMs');
  @override
  late final GeneratedColumn<int> lastDurationMs = GeneratedColumn<int>(
      'last_duration_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isFinishedMeta =
      const VerificationMeta('isFinished');
  @override
  late final GeneratedColumn<bool> isFinished = GeneratedColumn<bool>(
      'is_finished', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintsDependsOnDialect({
        SqlDialect.sqlite: 'CHECK ("is_finished" IN (0, 1))',
        SqlDialect.mysql: '',
        SqlDialect.postgres: '',
      }),
      defaultValue: const Constant(false));
  static const VerificationMeta _isFavoriteMeta =
      const VerificationMeta('isFavorite');
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
      'is_favorite', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintsDependsOnDialect({
        SqlDialect.sqlite: 'CHECK ("is_favorite" IN (0, 1))',
        SqlDialect.mysql: '',
        SqlDialect.postgres: '',
      }),
      defaultValue: const Constant(false));
  static const VerificationMeta _lastPlayedAtMeta =
      const VerificationMeta('lastPlayedAt');
  @override
  late final GeneratedColumn<DateTime> lastPlayedAt =
      GeneratedColumn<DateTime>('last_played_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        author,
        coverUrl,
        sourceId,
        sourceName,
        type,
        lastChapterUrl,
        lastPositionMs,
        lastDurationMs,
        isFinished,
        isFavorite,
        lastPlayedAt,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? 'media_items';
  @override
  String get actualTableName => 'media_items';
  @override
  VerificationContext validateIntegrity(Insertable<MediaItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author')) {
      context.handle(_authorMeta,
          author.isAcceptableOrUnknown(data['author']!, _authorMeta));
    }
    if (data.containsKey('cover_url')) {
      context.handle(_coverUrlMeta,
          coverUrl.isAcceptableOrUnknown(data['cover_url']!, _coverUrlMeta));
    }
    if (data.containsKey('source_id')) {
      context.handle(_sourceIdMeta,
          sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta));
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('source_name')) {
      context.handle(
          _sourceNameMeta,
          sourceName.isAcceptableOrUnknown(
              data['source_name']!, _sourceNameMeta));
    } else if (isInserting) {
      context.missing(_sourceNameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('last_chapter_url')) {
      context.handle(
          _lastChapterUrlMeta,
          lastChapterUrl.isAcceptableOrUnknown(
              data['last_chapter_url']!, _lastChapterUrlMeta));
    }
    if (data.containsKey('last_position_ms')) {
      context.handle(
          _lastPositionMsMeta,
          lastPositionMs.isAcceptableOrUnknown(
              data['last_position_ms']!, _lastPositionMsMeta));
    }
    if (data.containsKey('last_duration_ms')) {
      context.handle(
          _lastDurationMsMeta,
          lastDurationMs.isAcceptableOrUnknown(
              data['last_duration_ms']!, _lastDurationMsMeta));
    }
    if (data.containsKey('is_finished')) {
      context.handle(_isFinishedMeta,
          isFinished.isAcceptableOrUnknown(data['is_finished']!, _isFinishedMeta));
    }
    if (data.containsKey('is_favorite')) {
      context.handle(_isFavoriteMeta,
          isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta));
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
          _lastPlayedAtMeta,
          lastPlayedAt.isAcceptableOrUnknown(
              data['last_played_at']!, _lastPlayedAtMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      author: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}author']),
      coverUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}cover_url']),
      sourceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_id'])!,
      sourceName: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}source_name'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      lastChapterUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}last_chapter_url']),
      lastPositionMs: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}last_position_ms'])!,
      lastDurationMs: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}last_duration_ms'])!,
      isFinished: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}is_finished'])!,
      isFavorite: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}is_favorite'])!,
      lastPlayedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_played_at']),
      createdAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $MediaItemsTable createAlias(String alias) {
    return $MediaItemsTable(attachedDatabase, alias);
  }
}

// ---------------------------------------------------------------------------
// Chapters
// ---------------------------------------------------------------------------

class Chapter extends DataClass implements Insertable<Chapter> {
  final String id;
  final String itemId;
  final String title;
  final String? url;
  final int orderIndex;
  final int? durationMs;
  const Chapter(
      {required this.id,
      required this.itemId,
      required this.title,
      this.url,
      required this.orderIndex,
      this.durationMs});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['item_id'] = Variable<String>(itemId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    map['order_index'] = Variable<int>(orderIndex);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    return map;
  }

  ChaptersCompanion toCompanion(bool nullToAbsent) {
    return ChaptersCompanion(
      id: Value(id),
      itemId: Value(itemId),
      title: Value(title),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      orderIndex: Value(orderIndex),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
    );
  }
}

class ChaptersCompanion extends UpdateCompanion<Chapter> {
  final Value<String> id;
  final Value<String> itemId;
  final Value<String> title;
  final Value<String?> url;
  final Value<int> orderIndex;
  final Value<int?> durationMs;
  const ChaptersCompanion({
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.title = const Value.absent(),
    this.url = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.durationMs = const Value.absent(),
  });
  ChaptersCompanion.insert({
    required String id,
    required String itemId,
    required String title,
    this.url = const Value.absent(),
    required int orderIndex,
    this.durationMs = const Value.absent(),
  })  : id = Value(id),
        itemId = Value(itemId),
        title = Value(title),
        orderIndex = Value(orderIndex);
  static Insertable<Chapter> custom({
    Expression<String>? id,
    Expression<String>? itemId,
    Expression<String>? title,
    Expression<String>? url,
    Expression<int>? orderIndex,
    Expression<int>? durationMs,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (title != null) 'title': title,
      if (url != null) 'url': url,
      if (orderIndex != null) 'order_index': orderIndex,
      if (durationMs != null) 'duration_ms': durationMs,
    });
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    return map;
  }
}

class $ChaptersTable extends Chapters with TableInfo<$ChaptersTable, Chapter> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChaptersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
      'item_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES media_items (id) ON DELETE CASCADE'));
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
      'url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _orderIndexMeta =
      const VerificationMeta('orderIndex');
  @override
  late final GeneratedColumn<int> orderIndex = GeneratedColumn<int>(
      'order_index', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns =>
      [id, itemId, title, url, orderIndex, durationMs];
  @override
  String get aliasedName => _alias ?? 'chapters';
  @override
  String get actualTableName => 'chapters';
  @override
  VerificationContext validateIntegrity(Insertable<Chapter> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(_itemIdMeta,
          itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta));
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('url')) {
      context.handle(_urlMeta, url.isAcceptableOrUnknown(data['url']!, _urlMeta));
    }
    if (data.containsKey('order_index')) {
      context.handle(_orderIndexMeta,
          orderIndex.isAcceptableOrUnknown(data['order_index']!, _orderIndexMeta));
    } else if (isInserting) {
      context.missing(_orderIndexMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(_durationMsMeta,
          durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Chapter map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Chapter(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      itemId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}item_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      url: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}url']),
      orderIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}order_index'])!,
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms']),
    );
  }

  @override
  $ChaptersTable createAlias(String alias) {
    return $ChaptersTable(attachedDatabase, alias);
  }
}

// ---------------------------------------------------------------------------
// Progress
// ---------------------------------------------------------------------------

class Progres extends DataClass implements Insertable<Progres> {
  final String itemId;
  final String chapterUrl;
  final int positionMs;
  final int durationMs;
  final bool isFinished;
  final DateTime updatedAt;
  const Progres(
      {required this.itemId,
      required this.chapterUrl,
      required this.positionMs,
      required this.durationMs,
      required this.isFinished,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['item_id'] = Variable<String>(itemId);
    map['chapter_url'] = Variable<String>(chapterUrl);
    map['position_ms'] = Variable<int>(positionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['is_finished'] = Variable<bool>(isFinished);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProgressCompanion toCompanion(bool nullToAbsent) {
    return ProgressCompanion(
      itemId: Value(itemId),
      chapterUrl: Value(chapterUrl),
      positionMs: Value(positionMs),
      durationMs: Value(durationMs),
      isFinished: Value(isFinished),
      updatedAt: Value(updatedAt),
    );
  }
}

class ProgressCompanion extends UpdateCompanion<Progres> {
  final Value<String> itemId;
  final Value<String> chapterUrl;
  final Value<int> positionMs;
  final Value<int> durationMs;
  final Value<bool> isFinished;
  final Value<DateTime> updatedAt;
  const ProgressCompanion({
    this.itemId = const Value.absent(),
    this.chapterUrl = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.isFinished = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ProgressCompanion.insert({
    required String itemId,
    required String chapterUrl,
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.isFinished = const Value.absent(),
    required DateTime updatedAt,
  })  : itemId = Value(itemId),
        chapterUrl = Value(chapterUrl),
        updatedAt = Value(updatedAt);
  static Insertable<Progres> custom({
    Expression<String>? itemId,
    Expression<String>? chapterUrl,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<bool>? isFinished,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (itemId != null) 'item_id': itemId,
      if (chapterUrl != null) 'chapter_url': chapterUrl,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (isFinished != null) 'is_finished': isFinished,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (chapterUrl.present) {
      map['chapter_url'] = Variable<String>(chapterUrl.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (isFinished.present) {
      map['is_finished'] = Variable<bool>(isFinished.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }
}

class $ProgressTable extends Progress with TableInfo<$ProgressTable, Progres> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
      'item_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES media_items (id) ON DELETE CASCADE'));
  static const VerificationMeta _chapterUrlMeta =
      const VerificationMeta('chapterUrl');
  @override
  late final GeneratedColumn<String> chapterUrl = GeneratedColumn<String>(
      'chapter_url', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _positionMsMeta =
      const VerificationMeta('positionMs');
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
      'position_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isFinishedMeta =
      const VerificationMeta('isFinished');
  @override
  late final GeneratedColumn<bool> isFinished = GeneratedColumn<bool>(
      'is_finished', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintsDependsOnDialect({
        SqlDialect.sqlite: 'CHECK ("is_finished" IN (0, 1))',
        SqlDialect.mysql: '',
        SqlDialect.postgres: '',
      }),
      defaultValue: const Constant(false));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [itemId, chapterUrl, positionMs, durationMs, isFinished, updatedAt];
  @override
  String get aliasedName => _alias ?? 'progress';
  @override
  String get actualTableName => 'progress';
  @override
  VerificationContext validateIntegrity(Insertable<Progres> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('item_id')) {
      context.handle(_itemIdMeta,
          itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta));
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('chapter_url')) {
      context.handle(_chapterUrlMeta,
          chapterUrl.isAcceptableOrUnknown(data['chapter_url']!, _chapterUrlMeta));
    } else if (isInserting) {
      context.missing(_chapterUrlMeta);
    }
    if (data.containsKey('position_ms')) {
      context.handle(_positionMsMeta,
          positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta));
    }
    if (data.containsKey('duration_ms')) {
      context.handle(_durationMsMeta,
          durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta));
    }
    if (data.containsKey('is_finished')) {
      context.handle(_isFinishedMeta,
          isFinished.isAcceptableOrUnknown(data['is_finished']!, _isFinishedMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {itemId, chapterUrl};
  @override
  Progres map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Progres(
      itemId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}item_id'])!,
      chapterUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}chapter_url'])!,
      positionMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position_ms'])!,
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms'])!,
      isFinished: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_finished'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ProgressTable createAlias(String alias) {
    return $ProgressTable(attachedDatabase, alias);
  }
}

// ---------------------------------------------------------------------------
// Bookmarks
// ---------------------------------------------------------------------------

class Bookmark extends DataClass implements Insertable<Bookmark> {
  final String id;
  final String itemId;
  final String? chapterUrl;
  final int positionMs;
  final String? note;
  final DateTime createdAt;
  const Bookmark(
      {required this.id,
      required this.itemId,
      this.chapterUrl,
      required this.positionMs,
      this.note,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || chapterUrl != null) {
      map['chapter_url'] = Variable<String>(chapterUrl);
    }
    map['position_ms'] = Variable<int>(positionMs);
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  BookmarksCompanion toCompanion(bool nullToAbsent) {
    return BookmarksCompanion(
      id: Value(id),
      itemId: Value(itemId),
      chapterUrl: chapterUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterUrl),
      positionMs: Value(positionMs),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
    );
  }
}

class BookmarksCompanion extends UpdateCompanion<Bookmark> {
  final Value<String> id;
  final Value<String> itemId;
  final Value<String?> chapterUrl;
  final Value<int> positionMs;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  const BookmarksCompanion({
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.chapterUrl = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  BookmarksCompanion.insert({
    required String id,
    required String itemId,
    this.chapterUrl = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.note = const Value.absent(),
    required DateTime createdAt,
  })  : id = Value(id),
        itemId = Value(itemId),
        createdAt = Value(createdAt);
  static Insertable<Bookmark> custom({
    Expression<String>? id,
    Expression<String>? itemId,
    Expression<String>? chapterUrl,
    Expression<int>? positionMs,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (chapterUrl != null) 'chapter_url': chapterUrl,
      if (positionMs != null) 'position_ms': positionMs,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (chapterUrl.present) {
      map['chapter_url'] = Variable<String>(chapterUrl.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }
}

class $BookmarksTable extends Bookmarks
    with TableInfo<$BookmarksTable, Bookmark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookmarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
      'item_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES media_items (id) ON DELETE CASCADE'));
  static const VerificationMeta _chapterUrlMeta =
      const VerificationMeta('chapterUrl');
  @override
  late final GeneratedColumn<String> chapterUrl = GeneratedColumn<String>(
      'chapter_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _positionMsMeta =
      const VerificationMeta('positionMs');
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
      'position_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
      'note', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, itemId, chapterUrl, positionMs, note, createdAt];
  @override
  String get aliasedName => _alias ?? 'bookmarks';
  @override
  String get actualTableName => 'bookmarks';
  @override
  VerificationContext validateIntegrity(Insertable<Bookmark> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(_itemIdMeta,
          itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta));
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('chapter_url')) {
      context.handle(_chapterUrlMeta,
          chapterUrl.isAcceptableOrUnknown(data['chapter_url']!, _chapterUrlMeta));
    }
    if (data.containsKey('position_ms')) {
      context.handle(_positionMsMeta,
          positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta));
    }
    if (data.containsKey('note')) {
      context.handle(
          _noteMeta, note.isAcceptableOrUnknown(data['note']!, _noteMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Bookmark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Bookmark(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      itemId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}item_id'])!,
      chapterUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}chapter_url']),
      positionMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position_ms'])!,
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      createdAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $BookmarksTable createAlias(String alias) {
    return $BookmarksTable(attachedDatabase, alias);
  }
}

// ---------------------------------------------------------------------------
// Favorites
// ---------------------------------------------------------------------------

class Favorite extends DataClass implements Insertable<Favorite> {
  final String id;
  final String itemId;
  final String type;
  final DateTime createdAt;
  const Favorite(
      {required this.id,
      required this.itemId,
      required this.type,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['item_id'] = Variable<String>(itemId);
    map['type'] = Variable<String>(type);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  FavoritesCompanion toCompanion(bool nullToAbsent) {
    return FavoritesCompanion(
      id: Value(id),
      itemId: Value(itemId),
      type: Value(type),
      createdAt: Value(createdAt),
    );
  }
}

class FavoritesCompanion extends UpdateCompanion<Favorite> {
  final Value<String> id;
  final Value<String> itemId;
  final Value<String> type;
  final Value<DateTime> createdAt;
  const FavoritesCompanion({
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.type = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  FavoritesCompanion.insert({
    required String id,
    required String itemId,
    required String type,
    required DateTime createdAt,
  })  : id = Value(id),
        itemId = Value(itemId),
        type = Value(type),
        createdAt = Value(createdAt);
  static Insertable<Favorite> custom({
    Expression<String>? id,
    Expression<String>? itemId,
    Expression<String>? type,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (type != null) 'type': type,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }
}

class $FavoritesTable extends Favorites
    with TableInfo<$FavoritesTable, Favorite> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FavoritesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
      'item_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES media_items (id) ON DELETE CASCADE'));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, itemId, type, createdAt];
  @override
  String get aliasedName => _alias ?? 'favorites';
  @override
  String get actualTableName => 'favorites';
  @override
  VerificationContext validateIntegrity(Insertable<Favorite> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(_itemIdMeta,
          itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta));
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Favorite map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Favorite(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      itemId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}item_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      createdAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $FavoritesTable createAlias(String alias) {
    return $FavoritesTable(attachedDatabase, alias);
  }
}

// ---------------------------------------------------------------------------
// History
// ---------------------------------------------------------------------------

class HistoryData extends DataClass implements Insertable<HistoryData> {
  final String id;
  final String itemId;
  final String type;
  final String? chapterUrl;
  final DateTime visitedAt;
  const HistoryData(
      {required this.id,
      required this.itemId,
      required this.type,
      this.chapterUrl,
      required this.visitedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['item_id'] = Variable<String>(itemId);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || chapterUrl != null) {
      map['chapter_url'] = Variable<String>(chapterUrl);
    }
    map['visited_at'] = Variable<DateTime>(visitedAt);
    return map;
  }

  HistoryCompanion toCompanion(bool nullToAbsent) {
    return HistoryCompanion(
      id: Value(id),
      itemId: Value(itemId),
      type: Value(type),
      chapterUrl: chapterUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterUrl),
      visitedAt: Value(visitedAt),
    );
  }
}

class HistoryCompanion extends UpdateCompanion<HistoryData> {
  final Value<String> id;
  final Value<String> itemId;
  final Value<String> type;
  final Value<String?> chapterUrl;
  final Value<DateTime> visitedAt;
  const HistoryCompanion({
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.type = const Value.absent(),
    this.chapterUrl = const Value.absent(),
    this.visitedAt = const Value.absent(),
  });
  HistoryCompanion.insert({
    required String id,
    required String itemId,
    required String type,
    this.chapterUrl = const Value.absent(),
    required DateTime visitedAt,
  })  : id = Value(id),
        itemId = Value(itemId),
        type = Value(type),
        visitedAt = Value(visitedAt);
  static Insertable<HistoryData> custom({
    Expression<String>? id,
    Expression<String>? itemId,
    Expression<String>? type,
    Expression<String>? chapterUrl,
    Expression<DateTime>? visitedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (type != null) 'type': type,
      if (chapterUrl != null) 'chapter_url': chapterUrl,
      if (visitedAt != null) 'visited_at': visitedAt,
    });
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (chapterUrl.present) {
      map['chapter_url'] = Variable<String>(chapterUrl.value);
    }
    if (visitedAt.present) {
      map['visited_at'] = Variable<DateTime>(visitedAt.value);
    }
    return map;
  }
}

class $HistoryTable extends History with TableInfo<$HistoryTable, HistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
      'item_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES media_items (id) ON DELETE CASCADE'));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _chapterUrlMeta =
      const VerificationMeta('chapterUrl');
  @override
  late final GeneratedColumn<String> chapterUrl = GeneratedColumn<String>(
      'chapter_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _visitedAtMeta =
      const VerificationMeta('visitedAt');
  @override
  late final GeneratedColumn<DateTime> visitedAt = GeneratedColumn<DateTime>(
      'visited_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, itemId, type, chapterUrl, visitedAt];
  @override
  String get aliasedName => _alias ?? 'history';
  @override
  String get actualTableName => 'history';
  @override
  VerificationContext validateIntegrity(Insertable<HistoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(_itemIdMeta,
          itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta));
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('chapter_url')) {
      context.handle(_chapterUrlMeta,
          chapterUrl.isAcceptableOrUnknown(data['chapter_url']!, _chapterUrlMeta));
    }
    if (data.containsKey('visited_at')) {
      context.handle(_visitedAtMeta,
          visitedAt.isAcceptableOrUnknown(data['visited_at']!, _visitedAtMeta));
    } else if (isInserting) {
      context.missing(_visitedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      itemId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}item_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      chapterUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}chapter_url']),
      visitedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}visited_at'])!,
    );
  }

  @override
  $HistoryTable createAlias(String alias) {
    return $HistoryTable(attachedDatabase, alias);
  }
}

// ---------------------------------------------------------------------------
// Logs
// ---------------------------------------------------------------------------

class Log extends DataClass implements Insertable<Log> {
  final int id;
  final String level;
  final String message;
  final String? detail;
  final DateTime createdAt;
  const Log(
      {required this.id,
      required this.level,
      required this.message,
      this.detail,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['level'] = Variable<String>(level);
    map['message'] = Variable<String>(message);
    if (!nullToAbsent || detail != null) {
      map['detail'] = Variable<String>(detail);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  LogsCompanion toCompanion(bool nullToAbsent) {
    return LogsCompanion(
      id: Value(id),
      level: Value(level),
      message: Value(message),
      detail:
          detail == null && nullToAbsent ? const Value.absent() : Value(detail),
      createdAt: Value(createdAt),
    );
  }
}

class LogsCompanion extends UpdateCompanion<Log> {
  final Value<int> id;
  final Value<String> level;
  final Value<String> message;
  final Value<String?> detail;
  final Value<DateTime> createdAt;
  const LogsCompanion({
    this.id = const Value.absent(),
    this.level = const Value.absent(),
    this.message = const Value.absent(),
    this.detail = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  LogsCompanion.insert({
    this.id = const Value.absent(),
    required String level,
    required String message,
    this.detail = const Value.absent(),
    required DateTime createdAt,
  })  : level = Value(level),
        message = Value(message),
        createdAt = Value(createdAt);
  static Insertable<Log> custom({
    Expression<int>? id,
    Expression<String>? level,
    Expression<String>? message,
    Expression<String>? detail,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (level != null) 'level': level,
      if (message != null) 'message': message,
      if (detail != null) 'detail': detail,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (level.present) {
      map['level'] = Variable<String>(level.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }
}

class $LogsTable extends Logs with TableInfo<$LogsTable, Log> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<String> level = GeneratedColumn<String>(
      'level', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _messageMeta =
      const VerificationMeta('message');
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
      'message', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
      'detail', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, level, message, detail, createdAt];
  @override
  String get aliasedName => _alias ?? 'logs';
  @override
  String get actualTableName => 'logs';
  @override
  VerificationContext validateIntegrity(Insertable<Log> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('level')) {
      context.handle(
          _levelMeta, level.isAcceptableOrUnknown(data['level']!, _levelMeta));
    } else if (isInserting) {
      context.missing(_levelMeta);
    }
    if (data.containsKey('message')) {
      context.handle(_messageMeta,
          message.isAcceptableOrUnknown(data['message']!, _messageMeta));
    } else if (isInserting) {
      context.missing(_messageMeta);
    }
    if (data.containsKey('detail')) {
      context.handle(_detailMeta,
          detail.isAcceptableOrUnknown(data['detail']!, _detailMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Log map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Log(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      level: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}level'])!,
      message: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}message'])!,
      detail: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}detail']),
      createdAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $LogsTable createAlias(String alias) {
    return $LogsTable(attachedDatabase, alias);
  }
}

// ---------------------------------------------------------------------------
// KvSettings
// ---------------------------------------------------------------------------

class KvSetting extends DataClass implements Insertable<KvSetting> {
  final String key;
  final String value;
  const KvSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  KvSettingsCompanion toCompanion(bool nullToAbsent) {
    return KvSettingsCompanion(
      key: Value(key),
      value: Value(value),
    );
  }
}

class KvSettingsCompanion extends UpdateCompanion<KvSetting> {
  final Value<String> key;
  final Value<String> value;
  const KvSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
  });
  KvSettingsCompanion.insert({
    required String key,
    required String value,
  })  : key = Value(key),
        value = Value(value);
  static Insertable<KvSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
    });
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    return map;
  }
}

class $KvSettingsTable extends KvSettings
    with TableInfo<$KvSettingsTable, KvSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KvSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? 'kv_settings';
  @override
  String get actualTableName => 'kv_settings';
  @override
  VerificationContext validateIntegrity(Insertable<KvSetting> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  KvSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KvSetting(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $KvSettingsTable createAlias(String alias) {
    return $KvSettingsTable(attachedDatabase, alias);
  }
}

// ---------------------------------------------------------------------------
// SourceConfigs
// ---------------------------------------------------------------------------

class SourceConfig extends DataClass implements Insertable<SourceConfig> {
  final String sourceId;
  final String type;
  final bool enabled;
  final String? loginState;
  final String? voiceList;
  final String? selectedVoiceId;
  final String? lineList;
  final String? selectedLineId;
  final String? extra;
  const SourceConfig(
      {required this.sourceId,
      required this.type,
      required this.enabled,
      this.loginState,
      this.voiceList,
      this.selectedVoiceId,
      this.lineList,
      this.selectedLineId,
      this.extra});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['source_id'] = Variable<String>(sourceId);
    map['type'] = Variable<String>(type);
    map['enabled'] = Variable<bool>(enabled);
    if (!nullToAbsent || loginState != null) {
      map['login_state'] = Variable<String>(loginState);
    }
    if (!nullToAbsent || voiceList != null) {
      map['voice_list'] = Variable<String>(voiceList);
    }
    if (!nullToAbsent || selectedVoiceId != null) {
      map['selected_voice_id'] = Variable<String>(selectedVoiceId);
    }
    if (!nullToAbsent || lineList != null) {
      map['line_list'] = Variable<String>(lineList);
    }
    if (!nullToAbsent || selectedLineId != null) {
      map['selected_line_id'] = Variable<String>(selectedLineId);
    }
    if (!nullToAbsent || extra != null) {
      map['extra'] = Variable<String>(extra);
    }
    return map;
  }

  SourceConfigsCompanion toCompanion(bool nullToAbsent) {
    return SourceConfigsCompanion(
      sourceId: Value(sourceId),
      type: Value(type),
      enabled: Value(enabled),
      loginState: loginState == null && nullToAbsent
          ? const Value.absent()
          : Value(loginState),
      voiceList: voiceList == null && nullToAbsent
          ? const Value.absent()
          : Value(voiceList),
      selectedVoiceId: selectedVoiceId == null && nullToAbsent
          ? const Value.absent()
          : Value(selectedVoiceId),
      lineList: lineList == null && nullToAbsent
          ? const Value.absent()
          : Value(lineList),
      selectedLineId: selectedLineId == null && nullToAbsent
          ? const Value.absent()
          : Value(selectedLineId),
      extra:
          extra == null && nullToAbsent ? const Value.absent() : Value(extra),
    );
  }
}

class SourceConfigsCompanion extends UpdateCompanion<SourceConfig> {
  final Value<String> sourceId;
  final Value<String> type;
  final Value<bool> enabled;
  final Value<String?> loginState;
  final Value<String?> voiceList;
  final Value<String?> selectedVoiceId;
  final Value<String?> lineList;
  final Value<String?> selectedLineId;
  final Value<String?> extra;
  const SourceConfigsCompanion({
    this.sourceId = const Value.absent(),
    this.type = const Value.absent(),
    this.enabled = const Value.absent(),
    this.loginState = const Value.absent(),
    this.voiceList = const Value.absent(),
    this.selectedVoiceId = const Value.absent(),
    this.lineList = const Value.absent(),
    this.selectedLineId = const Value.absent(),
    this.extra = const Value.absent(),
  });
  SourceConfigsCompanion.insert({
    required String sourceId,
    required String type,
    this.enabled = const Value.absent(),
    this.loginState = const Value.absent(),
    this.voiceList = const Value.absent(),
    this.selectedVoiceId = const Value.absent(),
    this.lineList = const Value.absent(),
    this.selectedLineId = const Value.absent(),
    this.extra = const Value.absent(),
  })  : sourceId = Value(sourceId),
        type = Value(type);
  static Insertable<SourceConfig> custom({
    Expression<String>? sourceId,
    Expression<String>? type,
    Expression<bool>? enabled,
    Expression<String>? loginState,
    Expression<String>? voiceList,
    Expression<String>? selectedVoiceId,
    Expression<String>? lineList,
    Expression<String>? selectedLineId,
    Expression<String>? extra,
  }) {
    return RawValuesInsertable({
      if (sourceId != null) 'source_id': sourceId,
      if (type != null) 'type': type,
      if (enabled != null) 'enabled': enabled,
      if (loginState != null) 'login_state': loginState,
      if (voiceList != null) 'voice_list': voiceList,
      if (selectedVoiceId != null) 'selected_voice_id': selectedVoiceId,
      if (lineList != null) 'line_list': lineList,
      if (selectedLineId != null) 'selected_line_id': selectedLineId,
      if (extra != null) 'extra': extra,
    });
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (loginState.present) {
      map['login_state'] = Variable<String>(loginState.value);
    }
    if (voiceList.present) {
      map['voice_list'] = Variable<String>(voiceList.value);
    }
    if (selectedVoiceId.present) {
      map['selected_voice_id'] = Variable<String>(selectedVoiceId.value);
    }
    if (lineList.present) {
      map['line_list'] = Variable<String>(lineList.value);
    }
    if (selectedLineId.present) {
      map['selected_line_id'] = Variable<String>(selectedLineId.value);
    }
    if (extra.present) {
      map['extra'] = Variable<String>(extra.value);
    }
    return map;
  }
}

class $SourceConfigsTable extends SourceConfigs
    with TableInfo<$SourceConfigsTable, SourceConfig> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourceConfigsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sourceIdMeta =
      const VerificationMeta('sourceId');
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
      'source_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintsDependsOnDialect({
        SqlDialect.sqlite: 'CHECK ("enabled" IN (0, 1))',
        SqlDialect.mysql: '',
        SqlDialect.postgres: '',
      }),
      defaultValue: const Constant(true));
  static const VerificationMeta _loginStateMeta =
      const VerificationMeta('loginState');
  @override
  late final GeneratedColumn<String> loginState = GeneratedColumn<String>(
      'login_state', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _voiceListMeta =
      const VerificationMeta('voiceList');
  @override
  late final GeneratedColumn<String> voiceList = GeneratedColumn<String>(
      'voice_list', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _selectedVoiceIdMeta =
      const VerificationMeta('selectedVoiceId');
  @override
  late final GeneratedColumn<String> selectedVoiceId =
      GeneratedColumn<String>('selected_voice_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lineListMeta =
      const VerificationMeta('lineList');
  @override
  late final GeneratedColumn<String> lineList = GeneratedColumn<String>(
      'line_list', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _selectedLineIdMeta =
      const VerificationMeta('selectedLineId');
  @override
  late final GeneratedColumn<String> selectedLineId =
      GeneratedColumn<String>('selected_line_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _extraMeta = const VerificationMeta('extra');
  @override
  late final GeneratedColumn<String> extra = GeneratedColumn<String>(
      'extra', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        sourceId,
        type,
        enabled,
        loginState,
        voiceList,
        selectedVoiceId,
        lineList,
        selectedLineId,
        extra
      ];
  @override
  String get aliasedName => _alias ?? 'source_configs';
  @override
  String get actualTableName => 'source_configs';
  @override
  VerificationContext validateIntegrity(Insertable<SourceConfig> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('source_id')) {
      context.handle(_sourceIdMeta,
          sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta));
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('login_state')) {
      context.handle(_loginStateMeta,
          loginState.isAcceptableOrUnknown(data['login_state']!, _loginStateMeta));
    }
    if (data.containsKey('voice_list')) {
      context.handle(_voiceListMeta,
          voiceList.isAcceptableOrUnknown(data['voice_list']!, _voiceListMeta));
    }
    if (data.containsKey('selected_voice_id')) {
      context.handle(
          _selectedVoiceIdMeta,
          selectedVoiceId.isAcceptableOrUnknown(
              data['selected_voice_id']!, _selectedVoiceIdMeta));
    }
    if (data.containsKey('line_list')) {
      context.handle(_lineListMeta,
          lineList.isAcceptableOrUnknown(data['line_list']!, _lineListMeta));
    }
    if (data.containsKey('selected_line_id')) {
      context.handle(
          _selectedLineIdMeta,
          selectedLineId.isAcceptableOrUnknown(
              data['selected_line_id']!, _selectedLineIdMeta));
    }
    if (data.containsKey('extra')) {
      context.handle(
          _extraMeta, extra.isAcceptableOrUnknown(data['extra']!, _extraMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sourceId};
  @override
  SourceConfig map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceConfig(
      sourceId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_id'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      loginState: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}login_state']),
      voiceList: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}voice_list']),
      selectedVoiceId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}selected_voice_id']),
      lineList: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}line_list']),
      selectedLineId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}selected_line_id']),
      extra: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}extra']),
    );
  }

  @override
  $SourceConfigsTable createAlias(String alias) {
    return $SourceConfigsTable(attachedDatabase, alias);
  }
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  late final $MediaItemsTable mediaItems = $MediaItemsTable(this);
  late final $ChaptersTable chapters = $ChaptersTable(this);
  late final $ProgressTable progress = $ProgressTable(this);
  late final $BookmarksTable bookmarks = $BookmarksTable(this);
  late final $FavoritesTable favorites = $FavoritesTable(this);
  late final $HistoryTable history = $HistoryTable(this);
  late final $LogsTable logs = $LogsTable(this);
  late final $KvSettingsTable kvSettings = $KvSettingsTable(this);
  late final $SourceConfigsTable sourceConfigs = $SourceConfigsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        mediaItems,
        chapters,
        progress,
        bookmarks,
        favorites,
        history,
        logs,
        kvSettings,
        sourceConfigs
      ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('media_items',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('chapters', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('media_items',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('progress', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('media_items',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('bookmarks', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('media_items',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('favorites', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('media_items',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('history', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}
