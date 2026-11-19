// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class MediaItem extends DataClass implements Insertable<MediaItem> {
  final String id;
  final String type;
  final String title;
  final String? author;
  final String path;
  final String? coverPath;
  final String sourceType;
  final int chapterCount;
  final int? durationMs;
  final int sizeBytes;
  final String? description;
  final String status;
  final double progress;
  final DateTime addedAt;
  final DateTime? lastReadAt;
  final int sortOrder;
  const MediaItem(
      {required this.id,
      required this.type,
      required this.title,
      this.author,
      required this.path,
      this.coverPath,
      required this.sourceType,
      required this.chapterCount,
      this.durationMs,
      required this.sizeBytes,
      this.description,
      required this.status,
      required this.progress,
      required this.addedAt,
      this.lastReadAt,
      required this.sortOrder});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    map['path'] = Variable<String>(path);
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    map['source_type'] = Variable<String>(sourceType);
    map['chapter_count'] = Variable<int>(chapterCount);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['size_bytes'] = Variable<int>(sizeBytes);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['status'] = Variable<String>(status);
    map['progress'] = Variable<double>(progress);
    map['added_at'] = Variable<DateTime>(addedAt);
    if (!nullToAbsent || lastReadAt != null) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt);
    }
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  MediaItemsCompanion toCompanion(bool nullToAbsent) {
    return MediaItemsCompanion(
      id: Value(id),
      type: Value(type),
      title: Value(title),
      author:
          author == null && nullToAbsent ? const Value.absent() : Value(author),
      path: Value(path),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
      sourceType: Value(sourceType),
      chapterCount: Value(chapterCount),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      sizeBytes: Value(sizeBytes),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      status: Value(status),
      progress: Value(progress),
      addedAt: Value(addedAt),
      lastReadAt: lastReadAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadAt),
      sortOrder: Value(sortOrder),
    );
  }

  factory MediaItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaItem(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      title: serializer.fromJson<String>(json['title']),
      author: serializer.fromJson<String?>(json['author']),
      path: serializer.fromJson<String>(json['path']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
      sourceType: serializer.fromJson<String>(json['sourceType']),
      chapterCount: serializer.fromJson<int>(json['chapterCount']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      description: serializer.fromJson<String?>(json['description']),
      status: serializer.fromJson<String>(json['status']),
      progress: serializer.fromJson<double>(json['progress']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      lastReadAt: serializer.fromJson<DateTime?>(json['lastReadAt']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'title': serializer.toJson<String>(title),
      'author': serializer.toJson<String?>(author),
      'path': serializer.toJson<String>(path),
      'coverPath': serializer.toJson<String?>(coverPath),
      'sourceType': serializer.toJson<String>(sourceType),
      'chapterCount': serializer.toJson<int>(chapterCount),
      'durationMs': serializer.toJson<int?>(durationMs),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'description': serializer.toJson<String?>(description),
      'status': serializer.toJson<String>(status),
      'progress': serializer.toJson<double>(progress),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'lastReadAt': serializer.toJson<DateTime?>(lastReadAt),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  MediaItem copyWith(
          {String? id,
          String? type,
          String? title,
          Value<String?> author = const Value.absent(),
          String? path,
          Value<String?> coverPath = const Value.absent(),
          String? sourceType,
          int? chapterCount,
          Value<int?> durationMs = const Value.absent(),
          int? sizeBytes,
          Value<String?> description = const Value.absent(),
          String? status,
          double? progress,
          DateTime? addedAt,
          Value<DateTime?> lastReadAt = const Value.absent(),
          int? sortOrder}) =>
      MediaItem(
        id: id ?? this.id,
        type: type ?? this.type,
        title: title ?? this.title,
        author: author.present ? author.value : this.author,
        path: path ?? this.path,
        coverPath: coverPath.present ? coverPath.value : this.coverPath,
        sourceType: sourceType ?? this.sourceType,
        chapterCount: chapterCount ?? this.chapterCount,
        durationMs: durationMs.present ? durationMs.value : this.durationMs,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        description: description.present ? description.value : this.description,
        status: status ?? this.status,
        progress: progress ?? this.progress,
        addedAt: addedAt ?? this.addedAt,
        lastReadAt: lastReadAt.present ? lastReadAt.value : this.lastReadAt,
        sortOrder: sortOrder ?? this.sortOrder,
      );
  @override
  String toString() {
    return (StringBuffer('MediaItem(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('path: $path, ')
          ..write('coverPath: $coverPath, ')
          ..write('sourceType: $sourceType, ')
          ..write('chapterCount: $chapterCount, ')
          ..write('durationMs: $durationMs, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('progress: $progress, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      type,
      title,
      author,
      path,
      coverPath,
      sourceType,
      chapterCount,
      durationMs,
      sizeBytes,
      description,
      status,
      progress,
      addedAt,
      lastReadAt,
      sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaItem &&
          other.id == this.id &&
          other.type == this.type &&
          other.title == this.title &&
          other.author == this.author &&
          other.path == this.path &&
          other.coverPath == this.coverPath &&
          other.sourceType == this.sourceType &&
          other.chapterCount == this.chapterCount &&
          other.durationMs == this.durationMs &&
          other.sizeBytes == this.sizeBytes &&
          other.description == this.description &&
          other.status == this.status &&
          other.progress == this.progress &&
          other.addedAt == this.addedAt &&
          other.lastReadAt == this.lastReadAt &&
          other.sortOrder == this.sortOrder);
}

class MediaItemsCompanion extends UpdateCompanion<MediaItem> {
  final Value<String> id;
  final Value<String> type;
  final Value<String> title;
  final Value<String?> author;
  final Value<String> path;
  final Value<String?> coverPath;
  final Value<String> sourceType;
  final Value<int> chapterCount;
  final Value<int?> durationMs;
  final Value<int> sizeBytes;
  final Value<String?> description;
  final Value<String> status;
  final Value<double> progress;
  final Value<DateTime> addedAt;
  final Value<DateTime?> lastReadAt;
  final Value<int> sortOrder;
  const MediaItemsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.path = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.chapterCount = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.progress = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  MediaItemsCompanion.insert({
    required String id,
    required String type,
    required String title,
    this.author = const Value.absent(),
    required String path,
    this.coverPath = const Value.absent(),
    this.sourceType = const Value.absent(),
    this.chapterCount = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.description = const Value.absent(),
    this.status = const Value.absent(),
    this.progress = const Value.absent(),
    required DateTime addedAt,
    this.lastReadAt = const Value.absent(),
    this.sortOrder = const Value.absent(),
  })  : id = Value(id),
        type = Value(type),
        title = Value(title),
        path = Value(path),
        addedAt = Value(addedAt);
  static Insertable<MediaItem> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? path,
    Expression<String>? coverPath,
    Expression<String>? sourceType,
    Expression<int>? chapterCount,
    Expression<int>? durationMs,
    Expression<int>? sizeBytes,
    Expression<String>? description,
    Expression<String>? status,
    Expression<double>? progress,
    Expression<DateTime>? addedAt,
    Expression<DateTime>? lastReadAt,
    Expression<int>? sortOrder,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (path != null) 'path': path,
      if (coverPath != null) 'cover_path': coverPath,
      if (sourceType != null) 'source_type': sourceType,
      if (chapterCount != null) 'chapter_count': chapterCount,
      if (durationMs != null) 'duration_ms': durationMs,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (description != null) 'description': description,
      if (status != null) 'status': status,
      if (progress != null) 'progress': progress,
      if (addedAt != null) 'added_at': addedAt,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (sortOrder != null) 'sort_order': sortOrder,
    });
  }

  MediaItemsCompanion copyWith(
      {Value<String>? id,
      Value<String>? type,
      Value<String>? title,
      Value<String?>? author,
      Value<String>? path,
      Value<String?>? coverPath,
      Value<String>? sourceType,
      Value<int>? chapterCount,
      Value<int?>? durationMs,
      Value<int>? sizeBytes,
      Value<String?>? description,
      Value<String>? status,
      Value<double>? progress,
      Value<DateTime>? addedAt,
      Value<DateTime?>? lastReadAt,
      Value<int>? sortOrder}) {
    return MediaItemsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      author: author ?? this.author,
      path: path ?? this.path,
      coverPath: coverPath ?? this.coverPath,
      sourceType: sourceType ?? this.sourceType,
      chapterCount: chapterCount ?? this.chapterCount,
      durationMs: durationMs ?? this.durationMs,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      description: description ?? this.description,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      addedAt: addedAt ?? this.addedAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (sourceType.present) {
      map['source_type'] = Variable<String>(sourceType.value);
    }
    if (chapterCount.present) {
      map['chapter_count'] = Variable<int>(chapterCount.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (lastReadAt.present) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaItemsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('path: $path, ')
          ..write('coverPath: $coverPath, ')
          ..write('sourceType: $sourceType, ')
          ..write('chapterCount: $chapterCount, ')
          ..write('durationMs: $durationMs, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('description: $description, ')
          ..write('status: $status, ')
          ..write('progress: $progress, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
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
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
      'author', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _coverPathMeta =
      const VerificationMeta('coverPath');
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
      'cover_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceTypeMeta =
      const VerificationMeta('sourceType');
  @override
  late final GeneratedColumn<String> sourceType = GeneratedColumn<String>(
      'source_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('folder'));
  static const VerificationMeta _chapterCountMeta =
      const VerificationMeta('chapterCount');
  @override
  late final GeneratedColumn<int> chapterCount = GeneratedColumn<int>(
      'chapter_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _sizeBytesMeta =
      const VerificationMeta('sizeBytes');
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
      'size_bytes', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('unread'));
  static const VerificationMeta _progressMeta =
      const VerificationMeta('progress');
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
      'progress', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _addedAtMeta =
      const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
      'added_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _lastReadAtMeta =
      const VerificationMeta('lastReadAt');
  @override
  late final GeneratedColumn<DateTime> lastReadAt = GeneratedColumn<DateTime>(
      'last_read_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _sortOrderMeta =
      const VerificationMeta('sortOrder');
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
      'sort_order', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        type,
        title,
        author,
        path,
        coverPath,
        sourceType,
        chapterCount,
        durationMs,
        sizeBytes,
        description,
        status,
        progress,
        addedAt,
        lastReadAt,
        sortOrder
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
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
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
    if (data.containsKey('path')) {
      context.handle(
          _pathMeta, path.isAcceptableOrUnknown(data['path']!, _pathMeta));
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('cover_path')) {
      context.handle(_coverPathMeta,
          coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta));
    }
    if (data.containsKey('source_type')) {
      context.handle(
          _sourceTypeMeta,
          sourceType.isAcceptableOrUnknown(
              data['source_type']!, _sourceTypeMeta));
    }
    if (data.containsKey('chapter_count')) {
      context.handle(
          _chapterCountMeta,
          chapterCount.isAcceptableOrUnknown(
              data['chapter_count']!, _chapterCountMeta));
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    }
    if (data.containsKey('size_bytes')) {
      context.handle(_sizeBytesMeta,
          sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta));
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('progress')) {
      context.handle(_progressMeta,
          progress.isAcceptableOrUnknown(data['progress']!, _progressMeta));
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('last_read_at')) {
      context.handle(
          _lastReadAtMeta,
          lastReadAt.isAcceptableOrUnknown(
              data['last_read_at']!, _lastReadAtMeta));
    }
    if (data.containsKey('sort_order')) {
      context.handle(_sortOrderMeta,
          sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta));
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
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      author: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}author']),
      path: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}path'])!,
      coverPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cover_path']),
      sourceType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}source_type'])!,
      chapterCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}chapter_count'])!,
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms']),
      sizeBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}size_bytes'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      progress: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}progress'])!,
      addedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}added_at'])!,
      lastReadAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}last_read_at']),
      sortOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_order'])!,
    );
  }

  @override
  $MediaItemsTable createAlias(String alias) {
    return $MediaItemsTable(attachedDatabase, alias);
  }
}

class Chapter extends DataClass implements Insertable<Chapter> {
  final String id;
  final String itemId;
  final String title;
  final String? path;
  final int orderIndex;
  final int? durationMs;
  final bool isCorrupted;
  const Chapter(
      {required this.id,
      required this.itemId,
      required this.title,
      this.path,
      required this.orderIndex,
      this.durationMs,
      required this.isCorrupted});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['item_id'] = Variable<String>(itemId);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || path != null) {
      map['path'] = Variable<String>(path);
    }
    map['order_index'] = Variable<int>(orderIndex);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['is_corrupted'] = Variable<bool>(isCorrupted);
    return map;
  }

  ChaptersCompanion toCompanion(bool nullToAbsent) {
    return ChaptersCompanion(
      id: Value(id),
      itemId: Value(itemId),
      title: Value(title),
      path: path == null && nullToAbsent ? const Value.absent() : Value(path),
      orderIndex: Value(orderIndex),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      isCorrupted: Value(isCorrupted),
    );
  }

  factory Chapter.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Chapter(
      id: serializer.fromJson<String>(json['id']),
      itemId: serializer.fromJson<String>(json['itemId']),
      title: serializer.fromJson<String>(json['title']),
      path: serializer.fromJson<String?>(json['path']),
      orderIndex: serializer.fromJson<int>(json['orderIndex']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      isCorrupted: serializer.fromJson<bool>(json['isCorrupted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'itemId': serializer.toJson<String>(itemId),
      'title': serializer.toJson<String>(title),
      'path': serializer.toJson<String?>(path),
      'orderIndex': serializer.toJson<int>(orderIndex),
      'durationMs': serializer.toJson<int?>(durationMs),
      'isCorrupted': serializer.toJson<bool>(isCorrupted),
    };
  }

  Chapter copyWith(
          {String? id,
          String? itemId,
          String? title,
          Value<String?> path = const Value.absent(),
          int? orderIndex,
          Value<int?> durationMs = const Value.absent(),
          bool? isCorrupted}) =>
      Chapter(
        id: id ?? this.id,
        itemId: itemId ?? this.itemId,
        title: title ?? this.title,
        path: path.present ? path.value : this.path,
        orderIndex: orderIndex ?? this.orderIndex,
        durationMs: durationMs.present ? durationMs.value : this.durationMs,
        isCorrupted: isCorrupted ?? this.isCorrupted,
      );
  @override
  String toString() {
    return (StringBuffer('Chapter(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('title: $title, ')
          ..write('path: $path, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('durationMs: $durationMs, ')
          ..write('isCorrupted: $isCorrupted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, itemId, title, path, orderIndex, durationMs, isCorrupted);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chapter &&
          other.id == this.id &&
          other.itemId == this.itemId &&
          other.title == this.title &&
          other.path == this.path &&
          other.orderIndex == this.orderIndex &&
          other.durationMs == this.durationMs &&
          other.isCorrupted == this.isCorrupted);
}

class ChaptersCompanion extends UpdateCompanion<Chapter> {
  final Value<String> id;
  final Value<String> itemId;
  final Value<String> title;
  final Value<String?> path;
  final Value<int> orderIndex;
  final Value<int?> durationMs;
  final Value<bool> isCorrupted;
  const ChaptersCompanion({
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.title = const Value.absent(),
    this.path = const Value.absent(),
    this.orderIndex = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.isCorrupted = const Value.absent(),
  });
  ChaptersCompanion.insert({
    required String id,
    required String itemId,
    required String title,
    this.path = const Value.absent(),
    required int orderIndex,
    this.durationMs = const Value.absent(),
    this.isCorrupted = const Value.absent(),
  })  : id = Value(id),
        itemId = Value(itemId),
        title = Value(title),
        orderIndex = Value(orderIndex);
  static Insertable<Chapter> custom({
    Expression<String>? id,
    Expression<String>? itemId,
    Expression<String>? title,
    Expression<String>? path,
    Expression<int>? orderIndex,
    Expression<int>? durationMs,
    Expression<bool>? isCorrupted,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (title != null) 'title': title,
      if (path != null) 'path': path,
      if (orderIndex != null) 'order_index': orderIndex,
      if (durationMs != null) 'duration_ms': durationMs,
      if (isCorrupted != null) 'is_corrupted': isCorrupted,
    });
  }

  ChaptersCompanion copyWith(
      {Value<String>? id,
      Value<String>? itemId,
      Value<String>? title,
      Value<String?>? path,
      Value<int>? orderIndex,
      Value<int?>? durationMs,
      Value<bool>? isCorrupted}) {
    return ChaptersCompanion(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      title: title ?? this.title,
      path: path ?? this.path,
      orderIndex: orderIndex ?? this.orderIndex,
      durationMs: durationMs ?? this.durationMs,
      isCorrupted: isCorrupted ?? this.isCorrupted,
    );
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
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (orderIndex.present) {
      map['order_index'] = Variable<int>(orderIndex.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (isCorrupted.present) {
      map['is_corrupted'] = Variable<bool>(isCorrupted.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChaptersCompanion(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('title: $title, ')
          ..write('path: $path, ')
          ..write('orderIndex: $orderIndex, ')
          ..write('durationMs: $durationMs, ')
          ..write('isCorrupted: $isCorrupted')
          ..write(')'))
        .toString();
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
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, true,
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
  static const VerificationMeta _isCorruptedMeta =
      const VerificationMeta('isCorrupted');
  @override
  late final GeneratedColumn<bool> isCorrupted =
      GeneratedColumn<bool>('is_corrupted', aliasedName, false,
          type: DriftSqlType.bool,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintsDependsOnDialect({
            SqlDialect.sqlite: 'CHECK ("is_corrupted" IN (0, 1))',
            SqlDialect.mysql: '',
            SqlDialect.postgres: '',
          }),
          defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns =>
      [id, itemId, title, path, orderIndex, durationMs, isCorrupted];
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
    if (data.containsKey('path')) {
      context.handle(
          _pathMeta, path.isAcceptableOrUnknown(data['path']!, _pathMeta));
    }
    if (data.containsKey('order_index')) {
      context.handle(
          _orderIndexMeta,
          orderIndex.isAcceptableOrUnknown(
              data['order_index']!, _orderIndexMeta));
    } else if (isInserting) {
      context.missing(_orderIndexMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    }
    if (data.containsKey('is_corrupted')) {
      context.handle(
          _isCorruptedMeta,
          isCorrupted.isAcceptableOrUnknown(
              data['is_corrupted']!, _isCorruptedMeta));
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
      path: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}path']),
      orderIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}order_index'])!,
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms']),
      isCorrupted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_corrupted'])!,
    );
  }

  @override
  $ChaptersTable createAlias(String alias) {
    return $ChaptersTable(attachedDatabase, alias);
  }
}

class Progres extends DataClass implements Insertable<Progres> {
  final String itemId;
  final String? chapterId;
  final int positionMs;
  final double speed;
  final DateTime updatedAt;
  const Progres(
      {required this.itemId,
      this.chapterId,
      required this.positionMs,
      required this.speed,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || chapterId != null) {
      map['chapter_id'] = Variable<String>(chapterId);
    }
    map['position_ms'] = Variable<int>(positionMs);
    map['speed'] = Variable<double>(speed);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProgressCompanion toCompanion(bool nullToAbsent) {
    return ProgressCompanion(
      itemId: Value(itemId),
      chapterId: chapterId == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterId),
      positionMs: Value(positionMs),
      speed: Value(speed),
      updatedAt: Value(updatedAt),
    );
  }

  factory Progres.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Progres(
      itemId: serializer.fromJson<String>(json['itemId']),
      chapterId: serializer.fromJson<String?>(json['chapterId']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      speed: serializer.fromJson<double>(json['speed']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'itemId': serializer.toJson<String>(itemId),
      'chapterId': serializer.toJson<String?>(chapterId),
      'positionMs': serializer.toJson<int>(positionMs),
      'speed': serializer.toJson<double>(speed),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Progres copyWith(
          {String? itemId,
          Value<String?> chapterId = const Value.absent(),
          int? positionMs,
          double? speed,
          DateTime? updatedAt}) =>
      Progres(
        itemId: itemId ?? this.itemId,
        chapterId: chapterId.present ? chapterId.value : this.chapterId,
        positionMs: positionMs ?? this.positionMs,
        speed: speed ?? this.speed,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  @override
  String toString() {
    return (StringBuffer('Progres(')
          ..write('itemId: $itemId, ')
          ..write('chapterId: $chapterId, ')
          ..write('positionMs: $positionMs, ')
          ..write('speed: $speed, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(itemId, chapterId, positionMs, speed, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Progres &&
          other.itemId == this.itemId &&
          other.chapterId == this.chapterId &&
          other.positionMs == this.positionMs &&
          other.speed == this.speed &&
          other.updatedAt == this.updatedAt);
}

class ProgressCompanion extends UpdateCompanion<Progres> {
  final Value<String> itemId;
  final Value<String?> chapterId;
  final Value<int> positionMs;
  final Value<double> speed;
  final Value<DateTime> updatedAt;
  const ProgressCompanion({
    this.itemId = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.speed = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  ProgressCompanion.insert({
    required String itemId,
    this.chapterId = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.speed = const Value.absent(),
    required DateTime updatedAt,
  })  : itemId = Value(itemId),
        updatedAt = Value(updatedAt);
  static Insertable<Progres> custom({
    Expression<String>? itemId,
    Expression<String>? chapterId,
    Expression<int>? positionMs,
    Expression<double>? speed,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (itemId != null) 'item_id': itemId,
      if (chapterId != null) 'chapter_id': chapterId,
      if (positionMs != null) 'position_ms': positionMs,
      if (speed != null) 'speed': speed,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  ProgressCompanion copyWith(
      {Value<String>? itemId,
      Value<String?>? chapterId,
      Value<int>? positionMs,
      Value<double>? speed,
      Value<DateTime>? updatedAt}) {
    return ProgressCompanion(
      itemId: itemId ?? this.itemId,
      chapterId: chapterId ?? this.chapterId,
      positionMs: positionMs ?? this.positionMs,
      speed: speed ?? this.speed,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (chapterId.present) {
      map['chapter_id'] = Variable<String>(chapterId.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (speed.present) {
      map['speed'] = Variable<double>(speed.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgressCompanion(')
          ..write('itemId: $itemId, ')
          ..write('chapterId: $chapterId, ')
          ..write('positionMs: $positionMs, ')
          ..write('speed: $speed, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
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
  static const VerificationMeta _chapterIdMeta =
      const VerificationMeta('chapterId');
  @override
  late final GeneratedColumn<String> chapterId = GeneratedColumn<String>(
      'chapter_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _positionMsMeta =
      const VerificationMeta('positionMs');
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
      'position_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _speedMeta = const VerificationMeta('speed');
  @override
  late final GeneratedColumn<double> speed = GeneratedColumn<double>(
      'speed', aliasedName, false,
      type: DriftSqlType.double,
      requiredDuringInsert: false,
      defaultValue: const Constant(1.0));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [itemId, chapterId, positionMs, speed, updatedAt];
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
    if (data.containsKey('chapter_id')) {
      context.handle(_chapterIdMeta,
          chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta));
    }
    if (data.containsKey('position_ms')) {
      context.handle(
          _positionMsMeta,
          positionMs.isAcceptableOrUnknown(
              data['position_ms']!, _positionMsMeta));
    }
    if (data.containsKey('speed')) {
      context.handle(
          _speedMeta, speed.isAcceptableOrUnknown(data['speed']!, _speedMeta));
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
  Set<GeneratedColumn> get $primaryKey => {itemId};
  @override
  Progres map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Progres(
      itemId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}item_id'])!,
      chapterId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}chapter_id']),
      positionMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position_ms'])!,
      speed: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}speed'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ProgressTable createAlias(String alias) {
    return $ProgressTable(attachedDatabase, alias);
  }
}

class Bookmark extends DataClass implements Insertable<Bookmark> {
  final String id;
  final String itemId;
  final String? chapterId;
  final int positionMs;
  final int? page;
  final String? note;
  final DateTime createdAt;
  const Bookmark(
      {required this.id,
      required this.itemId,
      this.chapterId,
      required this.positionMs,
      this.page,
      this.note,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['item_id'] = Variable<String>(itemId);
    if (!nullToAbsent || chapterId != null) {
      map['chapter_id'] = Variable<String>(chapterId);
    }
    map['position_ms'] = Variable<int>(positionMs);
    if (!nullToAbsent || page != null) {
      map['page'] = Variable<int>(page);
    }
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
      chapterId: chapterId == null && nullToAbsent
          ? const Value.absent()
          : Value(chapterId),
      positionMs: Value(positionMs),
      page: page == null && nullToAbsent ? const Value.absent() : Value(page),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      createdAt: Value(createdAt),
    );
  }

  factory Bookmark.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Bookmark(
      id: serializer.fromJson<String>(json['id']),
      itemId: serializer.fromJson<String>(json['itemId']),
      chapterId: serializer.fromJson<String?>(json['chapterId']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      page: serializer.fromJson<int?>(json['page']),
      note: serializer.fromJson<String?>(json['note']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'itemId': serializer.toJson<String>(itemId),
      'chapterId': serializer.toJson<String?>(chapterId),
      'positionMs': serializer.toJson<int>(positionMs),
      'page': serializer.toJson<int?>(page),
      'note': serializer.toJson<String?>(note),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Bookmark copyWith(
          {String? id,
          String? itemId,
          Value<String?> chapterId = const Value.absent(),
          int? positionMs,
          Value<int?> page = const Value.absent(),
          Value<String?> note = const Value.absent(),
          DateTime? createdAt}) =>
      Bookmark(
        id: id ?? this.id,
        itemId: itemId ?? this.itemId,
        chapterId: chapterId.present ? chapterId.value : this.chapterId,
        positionMs: positionMs ?? this.positionMs,
        page: page.present ? page.value : this.page,
        note: note.present ? note.value : this.note,
        createdAt: createdAt ?? this.createdAt,
      );
  @override
  String toString() {
    return (StringBuffer('Bookmark(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('chapterId: $chapterId, ')
          ..write('positionMs: $positionMs, ')
          ..write('page: $page, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, itemId, chapterId, positionMs, page, note, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Bookmark &&
          other.id == this.id &&
          other.itemId == this.itemId &&
          other.chapterId == this.chapterId &&
          other.positionMs == this.positionMs &&
          other.page == this.page &&
          other.note == this.note &&
          other.createdAt == this.createdAt);
}

class BookmarksCompanion extends UpdateCompanion<Bookmark> {
  final Value<String> id;
  final Value<String> itemId;
  final Value<String?> chapterId;
  final Value<int> positionMs;
  final Value<int?> page;
  final Value<String?> note;
  final Value<DateTime> createdAt;
  const BookmarksCompanion({
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.page = const Value.absent(),
    this.note = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  BookmarksCompanion.insert({
    required String id,
    required String itemId,
    this.chapterId = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.page = const Value.absent(),
    this.note = const Value.absent(),
    required DateTime createdAt,
  })  : id = Value(id),
        itemId = Value(itemId),
        createdAt = Value(createdAt);
  static Insertable<Bookmark> custom({
    Expression<String>? id,
    Expression<String>? itemId,
    Expression<String>? chapterId,
    Expression<int>? positionMs,
    Expression<int>? page,
    Expression<String>? note,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (chapterId != null) 'chapter_id': chapterId,
      if (positionMs != null) 'position_ms': positionMs,
      if (page != null) 'page': page,
      if (note != null) 'note': note,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  BookmarksCompanion copyWith(
      {Value<String>? id,
      Value<String>? itemId,
      Value<String?>? chapterId,
      Value<int>? positionMs,
      Value<int?>? page,
      Value<String?>? note,
      Value<DateTime>? createdAt}) {
    return BookmarksCompanion(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      chapterId: chapterId ?? this.chapterId,
      positionMs: positionMs ?? this.positionMs,
      page: page ?? this.page,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
    );
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
    if (chapterId.present) {
      map['chapter_id'] = Variable<String>(chapterId.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (page.present) {
      map['page'] = Variable<int>(page.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookmarksCompanion(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('chapterId: $chapterId, ')
          ..write('positionMs: $positionMs, ')
          ..write('page: $page, ')
          ..write('note: $note, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
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
  static const VerificationMeta _chapterIdMeta =
      const VerificationMeta('chapterId');
  @override
  late final GeneratedColumn<String> chapterId = GeneratedColumn<String>(
      'chapter_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _positionMsMeta =
      const VerificationMeta('positionMs');
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
      'position_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _pageMeta = const VerificationMeta('page');
  @override
  late final GeneratedColumn<int> page = GeneratedColumn<int>(
      'page', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
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
      [id, itemId, chapterId, positionMs, page, note, createdAt];
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
    if (data.containsKey('chapter_id')) {
      context.handle(_chapterIdMeta,
          chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta));
    }
    if (data.containsKey('position_ms')) {
      context.handle(
          _positionMsMeta,
          positionMs.isAcceptableOrUnknown(
              data['position_ms']!, _positionMsMeta));
    }
    if (data.containsKey('page')) {
      context.handle(
          _pageMeta, page.isAcceptableOrUnknown(data['page']!, _pageMeta));
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
      chapterId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}chapter_id']),
      positionMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position_ms'])!,
      page: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}page']),
      note: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $BookmarksTable createAlias(String alias) {
    return $BookmarksTable(attachedDatabase, alias);
  }
}

class Favorite extends DataClass implements Insertable<Favorite> {
  final String id;
  final String itemId;
  final String type;
  final String groupName;
  final DateTime createdAt;
  const Favorite(
      {required this.id,
      required this.itemId,
      required this.type,
      required this.groupName,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['item_id'] = Variable<String>(itemId);
    map['type'] = Variable<String>(type);
    map['group_name'] = Variable<String>(groupName);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  FavoritesCompanion toCompanion(bool nullToAbsent) {
    return FavoritesCompanion(
      id: Value(id),
      itemId: Value(itemId),
      type: Value(type),
      groupName: Value(groupName),
      createdAt: Value(createdAt),
    );
  }

  factory Favorite.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Favorite(
      id: serializer.fromJson<String>(json['id']),
      itemId: serializer.fromJson<String>(json['itemId']),
      type: serializer.fromJson<String>(json['type']),
      groupName: serializer.fromJson<String>(json['groupName']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'itemId': serializer.toJson<String>(itemId),
      'type': serializer.toJson<String>(type),
      'groupName': serializer.toJson<String>(groupName),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Favorite copyWith(
          {String? id,
          String? itemId,
          String? type,
          String? groupName,
          DateTime? createdAt}) =>
      Favorite(
        id: id ?? this.id,
        itemId: itemId ?? this.itemId,
        type: type ?? this.type,
        groupName: groupName ?? this.groupName,
        createdAt: createdAt ?? this.createdAt,
      );
  @override
  String toString() {
    return (StringBuffer('Favorite(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('type: $type, ')
          ..write('groupName: $groupName, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, itemId, type, groupName, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Favorite &&
          other.id == this.id &&
          other.itemId == this.itemId &&
          other.type == this.type &&
          other.groupName == this.groupName &&
          other.createdAt == this.createdAt);
}

class FavoritesCompanion extends UpdateCompanion<Favorite> {
  final Value<String> id;
  final Value<String> itemId;
  final Value<String> type;
  final Value<String> groupName;
  final Value<DateTime> createdAt;
  const FavoritesCompanion({
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.type = const Value.absent(),
    this.groupName = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  FavoritesCompanion.insert({
    required String id,
    required String itemId,
    required String type,
    this.groupName = const Value.absent(),
    required DateTime createdAt,
  })  : id = Value(id),
        itemId = Value(itemId),
        type = Value(type),
        createdAt = Value(createdAt);
  static Insertable<Favorite> custom({
    Expression<String>? id,
    Expression<String>? itemId,
    Expression<String>? type,
    Expression<String>? groupName,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (type != null) 'type': type,
      if (groupName != null) 'group_name': groupName,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  FavoritesCompanion copyWith(
      {Value<String>? id,
      Value<String>? itemId,
      Value<String>? type,
      Value<String>? groupName,
      Value<DateTime>? createdAt}) {
    return FavoritesCompanion(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      type: type ?? this.type,
      groupName: groupName ?? this.groupName,
      createdAt: createdAt ?? this.createdAt,
    );
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
    if (groupName.present) {
      map['group_name'] = Variable<String>(groupName.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FavoritesCompanion(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('type: $type, ')
          ..write('groupName: $groupName, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
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
  static const VerificationMeta _groupNameMeta =
      const VerificationMeta('groupName');
  @override
  late final GeneratedColumn<String> groupName = GeneratedColumn<String>(
      'group_name', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('默认'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, itemId, type, groupName, createdAt];
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
    if (data.containsKey('group_name')) {
      context.handle(_groupNameMeta,
          groupName.isAcceptableOrUnknown(data['group_name']!, _groupNameMeta));
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
      groupName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}group_name'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $FavoritesTable createAlias(String alias) {
    return $FavoritesTable(attachedDatabase, alias);
  }
}

class HistoryData extends DataClass implements Insertable<HistoryData> {
  final String id;
  final String itemId;
  final String type;
  final DateTime visitedAt;
  const HistoryData(
      {required this.id,
      required this.itemId,
      required this.type,
      required this.visitedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['item_id'] = Variable<String>(itemId);
    map['type'] = Variable<String>(type);
    map['visited_at'] = Variable<DateTime>(visitedAt);
    return map;
  }

  HistoryCompanion toCompanion(bool nullToAbsent) {
    return HistoryCompanion(
      id: Value(id),
      itemId: Value(itemId),
      type: Value(type),
      visitedAt: Value(visitedAt),
    );
  }

  factory HistoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryData(
      id: serializer.fromJson<String>(json['id']),
      itemId: serializer.fromJson<String>(json['itemId']),
      type: serializer.fromJson<String>(json['type']),
      visitedAt: serializer.fromJson<DateTime>(json['visitedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'itemId': serializer.toJson<String>(itemId),
      'type': serializer.toJson<String>(type),
      'visitedAt': serializer.toJson<DateTime>(visitedAt),
    };
  }

  HistoryData copyWith(
          {String? id, String? itemId, String? type, DateTime? visitedAt}) =>
      HistoryData(
        id: id ?? this.id,
        itemId: itemId ?? this.itemId,
        type: type ?? this.type,
        visitedAt: visitedAt ?? this.visitedAt,
      );
  @override
  String toString() {
    return (StringBuffer('HistoryData(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('type: $type, ')
          ..write('visitedAt: $visitedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, itemId, type, visitedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryData &&
          other.id == this.id &&
          other.itemId == this.itemId &&
          other.type == this.type &&
          other.visitedAt == this.visitedAt);
}

class HistoryCompanion extends UpdateCompanion<HistoryData> {
  final Value<String> id;
  final Value<String> itemId;
  final Value<String> type;
  final Value<DateTime> visitedAt;
  const HistoryCompanion({
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.type = const Value.absent(),
    this.visitedAt = const Value.absent(),
  });
  HistoryCompanion.insert({
    required String id,
    required String itemId,
    required String type,
    required DateTime visitedAt,
  })  : id = Value(id),
        itemId = Value(itemId),
        type = Value(type),
        visitedAt = Value(visitedAt);
  static Insertable<HistoryData> custom({
    Expression<String>? id,
    Expression<String>? itemId,
    Expression<String>? type,
    Expression<DateTime>? visitedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (type != null) 'type': type,
      if (visitedAt != null) 'visited_at': visitedAt,
    });
  }

  HistoryCompanion copyWith(
      {Value<String>? id,
      Value<String>? itemId,
      Value<String>? type,
      Value<DateTime>? visitedAt}) {
    return HistoryCompanion(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      type: type ?? this.type,
      visitedAt: visitedAt ?? this.visitedAt,
    );
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
    if (visitedAt.present) {
      map['visited_at'] = Variable<DateTime>(visitedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryCompanion(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('type: $type, ')
          ..write('visitedAt: $visitedAt')
          ..write(')'))
        .toString();
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
  static const VerificationMeta _visitedAtMeta =
      const VerificationMeta('visitedAt');
  @override
  late final GeneratedColumn<DateTime> visitedAt = GeneratedColumn<DateTime>(
      'visited_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, itemId, type, visitedAt];
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
      visitedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}visited_at'])!,
    );
  }

  @override
  $HistoryTable createAlias(String alias) {
    return $HistoryTable(attachedDatabase, alias);
  }
}

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

  factory Log.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Log(
      id: serializer.fromJson<int>(json['id']),
      level: serializer.fromJson<String>(json['level']),
      message: serializer.fromJson<String>(json['message']),
      detail: serializer.fromJson<String?>(json['detail']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'level': serializer.toJson<String>(level),
      'message': serializer.toJson<String>(message),
      'detail': serializer.toJson<String?>(detail),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Log copyWith(
          {int? id,
          String? level,
          String? message,
          Value<String?> detail = const Value.absent(),
          DateTime? createdAt}) =>
      Log(
        id: id ?? this.id,
        level: level ?? this.level,
        message: message ?? this.message,
        detail: detail.present ? detail.value : this.detail,
        createdAt: createdAt ?? this.createdAt,
      );
  @override
  String toString() {
    return (StringBuffer('Log(')
          ..write('id: $id, ')
          ..write('level: $level, ')
          ..write('message: $message, ')
          ..write('detail: $detail, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, level, message, detail, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Log &&
          other.id == this.id &&
          other.level == this.level &&
          other.message == this.message &&
          other.detail == this.detail &&
          other.createdAt == this.createdAt);
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

  LogsCompanion copyWith(
      {Value<int>? id,
      Value<String>? level,
      Value<String>? message,
      Value<String?>? detail,
      Value<DateTime>? createdAt}) {
    return LogsCompanion(
      id: id ?? this.id,
      level: level ?? this.level,
      message: message ?? this.message,
      detail: detail ?? this.detail,
      createdAt: createdAt ?? this.createdAt,
    );
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

  @override
  String toString() {
    return (StringBuffer('LogsCompanion(')
          ..write('id: $id, ')
          ..write('level: $level, ')
          ..write('message: $message, ')
          ..write('detail: $detail, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
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
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $LogsTable createAlias(String alias) {
    return $LogsTable(attachedDatabase, alias);
  }
}

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

  factory KvSetting.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KvSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  KvSetting copyWith({String? key, String? value}) => KvSetting(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  @override
  String toString() {
    return (StringBuffer('KvSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KvSetting &&
          other.key == this.key &&
          other.value == this.value);
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

  KvSettingsCompanion copyWith({Value<String>? key, Value<String>? value}) {
    return KvSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
    );
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

  @override
  String toString() {
    return (StringBuffer('KvSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
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

class SourceConfig extends DataClass implements Insertable<SourceConfig> {
  final String sourceId;
  final String type;
  final String enabled;
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
    map['enabled'] = Variable<String>(enabled);
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

  factory SourceConfig.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourceConfig(
      sourceId: serializer.fromJson<String>(json['sourceId']),
      type: serializer.fromJson<String>(json['type']),
      enabled: serializer.fromJson<String>(json['enabled']),
      loginState: serializer.fromJson<String?>(json['loginState']),
      voiceList: serializer.fromJson<String?>(json['voiceList']),
      selectedVoiceId: serializer.fromJson<String?>(json['selectedVoiceId']),
      lineList: serializer.fromJson<String?>(json['lineList']),
      selectedLineId: serializer.fromJson<String?>(json['selectedLineId']),
      extra: serializer.fromJson<String?>(json['extra']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sourceId': serializer.toJson<String>(sourceId),
      'type': serializer.toJson<String>(type),
      'enabled': serializer.toJson<String>(enabled),
      'loginState': serializer.toJson<String?>(loginState),
      'voiceList': serializer.toJson<String?>(voiceList),
      'selectedVoiceId': serializer.toJson<String?>(selectedVoiceId),
      'lineList': serializer.toJson<String?>(lineList),
      'selectedLineId': serializer.toJson<String?>(selectedLineId),
      'extra': serializer.toJson<String?>(extra),
    };
  }

  SourceConfig copyWith(
          {String? sourceId,
          String? type,
          String? enabled,
          Value<String?> loginState = const Value.absent(),
          Value<String?> voiceList = const Value.absent(),
          Value<String?> selectedVoiceId = const Value.absent(),
          Value<String?> lineList = const Value.absent(),
          Value<String?> selectedLineId = const Value.absent(),
          Value<String?> extra = const Value.absent()}) =>
      SourceConfig(
        sourceId: sourceId ?? this.sourceId,
        type: type ?? this.type,
        enabled: enabled ?? this.enabled,
        loginState: loginState.present ? loginState.value : this.loginState,
        voiceList: voiceList.present ? voiceList.value : this.voiceList,
        selectedVoiceId: selectedVoiceId.present
            ? selectedVoiceId.value
            : this.selectedVoiceId,
        lineList: lineList.present ? lineList.value : this.lineList,
        selectedLineId:
            selectedLineId.present ? selectedLineId.value : this.selectedLineId,
        extra: extra.present ? extra.value : this.extra,
      );
  @override
  String toString() {
    return (StringBuffer('SourceConfig(')
          ..write('sourceId: $sourceId, ')
          ..write('type: $type, ')
          ..write('enabled: $enabled, ')
          ..write('loginState: $loginState, ')
          ..write('voiceList: $voiceList, ')
          ..write('selectedVoiceId: $selectedVoiceId, ')
          ..write('lineList: $lineList, ')
          ..write('selectedLineId: $selectedLineId, ')
          ..write('extra: $extra')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sourceId, type, enabled, loginState,
      voiceList, selectedVoiceId, lineList, selectedLineId, extra);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceConfig &&
          other.sourceId == this.sourceId &&
          other.type == this.type &&
          other.enabled == this.enabled &&
          other.loginState == this.loginState &&
          other.voiceList == this.voiceList &&
          other.selectedVoiceId == this.selectedVoiceId &&
          other.lineList == this.lineList &&
          other.selectedLineId == this.selectedLineId &&
          other.extra == this.extra);
}

class SourceConfigsCompanion extends UpdateCompanion<SourceConfig> {
  final Value<String> sourceId;
  final Value<String> type;
  final Value<String> enabled;
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
    Expression<String>? enabled,
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

  SourceConfigsCompanion copyWith(
      {Value<String>? sourceId,
      Value<String>? type,
      Value<String>? enabled,
      Value<String?>? loginState,
      Value<String?>? voiceList,
      Value<String?>? selectedVoiceId,
      Value<String?>? lineList,
      Value<String?>? selectedLineId,
      Value<String?>? extra}) {
    return SourceConfigsCompanion(
      sourceId: sourceId ?? this.sourceId,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      loginState: loginState ?? this.loginState,
      voiceList: voiceList ?? this.voiceList,
      selectedVoiceId: selectedVoiceId ?? this.selectedVoiceId,
      lineList: lineList ?? this.lineList,
      selectedLineId: selectedLineId ?? this.selectedLineId,
      extra: extra ?? this.extra,
    );
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
      map['enabled'] = Variable<String>(enabled.value);
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

  @override
  String toString() {
    return (StringBuffer('SourceConfigsCompanion(')
          ..write('sourceId: $sourceId, ')
          ..write('type: $type, ')
          ..write('enabled: $enabled, ')
          ..write('loginState: $loginState, ')
          ..write('voiceList: $voiceList, ')
          ..write('selectedVoiceId: $selectedVoiceId, ')
          ..write('lineList: $lineList, ')
          ..write('selectedLineId: $selectedLineId, ')
          ..write('extra: $extra')
          ..write(')'))
        .toString();
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
  late final GeneratedColumn<String> enabled = GeneratedColumn<String>(
      'enabled', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('true'));
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
  late final GeneratedColumn<String> selectedVoiceId = GeneratedColumn<String>(
      'selected_voice_id', aliasedName, true,
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
  late final GeneratedColumn<String> selectedLineId = GeneratedColumn<String>(
      'selected_line_id', aliasedName, true,
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
      context.handle(
          _loginStateMeta,
          loginState.isAcceptableOrUnknown(
              data['login_state']!, _loginStateMeta));
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
          .read(DriftSqlType.string, data['${effectivePrefix}enabled'])!,
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
