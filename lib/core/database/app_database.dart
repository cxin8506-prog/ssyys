import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// 数据库 provider：其他代理只通过 [LibraryRepository] 用库，
/// 不直接碰 drift；需要直接读库的页面也走这个 provider。
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// 本地数据库。所有数据保存在 App 私有目录，便于整体备份/迁移。
///
/// 数据库文件位置：`<应用文档>/database/app.db`（见 [PathUtils.databaseFile]，
/// 与 `local_media_app` 平级）。备份必须打这个真实路径。
@DriftDatabase(tables: [
  MediaItems,
  Chapters,
  Progress,
  Bookmarks,
  Favorites,
  History,
  Logs,
  KvSettings,
  SourceConfigs,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// 备份/恢复时用指定路径打开（校验、合并恢复时用临时副本）
  AppDatabase.atPath(String path) : super(_openAt(path));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // 第一版无需迁移逻辑，后续在这里加 ALTER TABLE
        },
      );

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final dbDir = Directory(p.join(dir.path, 'database'));
      if (!await dbDir.exists()) await dbDir.create(recursive: true);
      final file = File(p.join(dbDir.path, 'app.db'));
      return NativeDatabase(file);
    });
  }

  static LazyDatabase _openAt(String path) {
    return LazyDatabase(() async {
      final file = File(path);
      return NativeDatabase(file);
    });
  }

  /// 读取设置
  Future<String?> readSetting(String key) async {
    final rows =
        await (select(kvSettings)..where((t) => t.key.equals(key))).get();
    return rows.isEmpty ? null : rows.first.value;
  }

  /// 写入设置
  Future<void> writeSetting(String key, String value) =>
      into(kvSettings).insertOnConflictUpdate(
          KvSettingsCompanion.insert(key: key, value: value));

  /// 写日志
  Future<void> log(String level, String message, {String? detail}) =>
      into(logs).insert(LogsCompanion.insert(
        level: level,
        message: message,
        detail: Value(detail),
        createdAt: DateTime.now(),
      ));

  /// 只保留最新 500 条日志，删掉更早的（日志页只看最新 500 条）。
  Future<void> pruneLogs() async {
    final rows = await customSelect(
      'SELECT id FROM logs ORDER BY id DESC LIMIT 1 OFFSET 499',
    ).get();
    if (rows.isEmpty) return;
    final minKeep = rows.first.read<int>('id');
    await (delete(logs)..where((t) => t.id.isSmallerThanValue(minKeep))).go();
  }
}
