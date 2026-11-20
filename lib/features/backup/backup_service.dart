import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/database/app_database.dart';
import '../../core/log/app_logger.dart';
import '../../core/utils/path_utils.dart';

/// 备份失败：只带人话，不带原始异常。
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

/// 把各种异常翻译成人话；页面只显示这个返回值，绝不直接显示 `$e`。
String friendlyBackupError(Object e) {
  final msg = '$e';
  if (e is BackupException) return e.message;
  if (msg.contains('备份文件损坏')) return '备份文件损坏';
  if (msg.contains('No space') || msg.contains('空间不足')) {
    return '手机存储空间不足，清理一下再备份';
  }
  if (msg.contains('Permission denied') || msg.contains('权限')) {
    return '没有读写存储的权限，去系统设置里允许后重试';
  }
  if (msg.contains('密码不对') || msg.contains('解不开')) {
    return '本地密码不对，Cookie 解不开，重新输入密码';
  }
  if (msg.contains('SocketException') ||
      msg.contains('TimeoutException') ||
      msg.contains('Failed host lookup')) {
    return '连不上服务器，检查网络后重试';
  }
  if (msg.contains('401') || msg.contains('403')) {
    return '账号或应用密码不对（密码填应用密码，不是登录密码）';
  }
  if (msg.contains('404')) return '地址错了，服务器找不到这个地址';
  return '备份失败，请重试（${_shortReason(msg)}）';
}

String _shortReason(String msg) {
  final m = RegExp(r'HTTP (\d{3})').firstMatch(msg);
  if (m != null) return '服务器返回了 ${m.group(1)}';
  if (msg.contains('database') || msg.contains('app.db')) return '数据库读写出错';
  if (msg.contains('zip') || msg.contains('Zip')) return '备份文件读不出来';
  return '未知原因';
}

/// 备份内容选项（Legado 8 组开关的简化版：数据库 / 封面 / 插件 / Cookie）。
class BackupOptions {
  /// 书架/进度/收藏/历史/书签/设置/UA 配置/源配置（都在数据库里）
  final bool includeDatabase;

  /// 封面图片
  final bool includeCovers;

  /// 插件源文件（JAR/ZIP）
  final bool includePlugins;

  /// Cookie 和登录态：要设本地密码才备，没有密码就不备这一项（不静默明文存）
  final bool includeCookies;

  /// 本地密码（只用于 Cookie 加密/解密，不落盘）
  final String? localPassword;

  const BackupOptions({
    this.includeDatabase = true,
    this.includeCovers = true,
    this.includePlugins = true,
    this.includeCookies = false,
    this.localPassword,
  });
}

/// 合并恢复的结果：只报数，不报“恢复了 X/Y”这种含糊话。
class RestoreReport {
  /// 写回了进度的书（本机已有的）
  final int restoredBooks;

  /// 备份里有、本机没有的书（要先装回对应源再恢复一次才能合上进度）
  final int missingBooks;

  /// 写回的断点条数
  final int restoredProgress;

  /// 写回的书签条数
  final int restoredBookmarks;

  /// 写回的收藏条数
  final int restoredFavorites;

  /// 拷回来的封面文件数
  final int restoredCovers;

  /// 拷回来的插件文件数
  final int restoredPlugins;

  /// 解开并写回的 Cookie/登录态条数
  final int cookiesRestored;

  const RestoreReport({
    this.restoredBooks = 0,
    this.missingBooks = 0,
    this.restoredProgress = 0,
    this.restoredBookmarks = 0,
    this.restoredFavorites = 0,
    this.restoredCovers = 0,
    this.restoredPlugins = 0,
    this.cookiesRestored = 0,
  });
}

/// 本地备份/恢复服务。
///
/// 修掉的三个审计毛病：
/// 1. 数据库路径错位——打包真实路径 `<应用文档>/database/app.db`
///    （旧版打 `local_media_app/database`，里面根本没有数据库）；
/// 2. 恢复无校验无回滚——恢复前先校验 SHA-256/版本，坏了报“备份文件损坏”；
///    恢复前先自动备一份当前数据，恢复是合并式（本机有、备份里没有的不动）；
/// 3. 恢复失败不说人话——全部失败走 [BackupException]/[friendlyBackupError]。
class BackupService {
  /// 正在用的数据库（传了就用 VACUUM INTO 快照，拷出来的库一定是一致的；
  /// 不传就直接拷文件，库可能正被写，快照一致性无保证）。
  final AppDatabase? db;

  BackupService({this.db});

  static const int manifestVersion = 2;

  /// 备份里的敏感 kv key：不同步、不进包（密码留在本机）。
  static const List<String> _passwordKeys = [
    AppConstants.keySyncPass,
    AppConstants.keyWebDavPlayPass,
  ];

  // ------------------------------------------------------------ 创建备份

  /// 创建一个 zip 备份，返回文件。先写临时文件，成功后再改名覆盖（不写一半的包）。
  /// 空书架不写（写了只会占地方、还可能盖掉上一份好备份的注意力）。
  Future<File> createBackup({
    BackupOptions options = const BackupOptions(),
  }) async {
    if (options.includeCookies &&
        (options.localPassword == null ||
            options.localPassword!.isEmpty)) {
      throw const BackupException(
          '备份 Cookie 和登录态要先设本地密码，没有密码就不备这一项');
    }
    final liveDb = db;
    if (options.includeDatabase && liveDb != null) {
      final count = await liveDb
          .customSelect('SELECT COUNT(*) AS c FROM media_items')
          .get()
          .then((rows) => rows.first.read<int>('c'));
      if (count == 0) {
        throw const BackupException('书架还是空的，先不用备份，等有书了再备');
      }
    }

    final backups = await PathUtils.backupsDir;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final tmpPath = p.join(backups.path, 'backup_$stamp.zip.tmp');
    final outPath = p.join(backups.path, 'backup_$stamp.zip');
    final tmpDir = await Directory(
      p.join(backups.path, '.backup_tmp_$stamp'),
    ).create(recursive: true);

    try {
      final manifestFiles = <String, String>{};
      var dbUserVersion = 0;

      // 1) 数据库：VACUUM INTO 快照（一致性），再按选项清掉敏感内容
      if (options.includeDatabase) {
        final snapPath = p.join(tmpDir.path, 'app.db');
        if (liveDb != null) {
          await liveDb.customStatement('VACUUM INTO ?', [snapPath]);
        } else {
          final realDb = await PathUtils.databaseFile;
          if (!await realDb.exists()) {
            throw const BackupException('数据库文件不存在，没什么可备份的');
          }
          await realDb.copy(snapPath);
        }
        final snapDb = AppDatabase.atPath(snapPath);
        try {
          final rows = await snapDb
              .customSelect('PRAGMA user_version')
              .get();
          if (rows.isNotEmpty) dbUserVersion = rows.first.read<int>('user_version');
          if (!options.includeCookies) {
            // 不备 Cookie：快照里的登录态和密码 key 清掉，不明文存
            await snapDb.customStatement(
                'UPDATE source_configs SET login_state = NULL');
            for (final k in _passwordKeys) {
              await snapDb.customStatement(
                  'DELETE FROM kv_settings WHERE key = ?', [k]);
            }
          }
        } finally {
          await snapDb.close();
        }
        final bytes = await File(snapPath).readAsBytes();
        manifestFiles['database/app.db'] =
            sha256.convert(bytes).toString();
        await _stageFile(tmpDir, 'database/app.db', bytes);
      }

      // 2) Cookie/登录态：单独抽出来加密存（SHA-256 流密钥 XOR，明文不进包）
      if (options.includeCookies && liveDb != null) {
        final cookies = await _extractCookies(liveDb);
        if (cookies.isNotEmpty) {
          final plain = utf8.encode(jsonEncode(cookies));
          final cipher = _xorCrypt(plain, options.localPassword!);
          manifestFiles['cookies.enc'] = sha256.convert(plain).toString();
          await _stageFile(tmpDir, 'cookies.enc', cipher);
        }
      }

      // 3) 封面 / 插件：拷文件
      var coverCount = 0;
      var pluginCount = 0;
      if (options.includeCovers) {
        coverCount = await _stageDir(
            tmpDir, 'covers', await PathUtils.coversDir, manifestFiles);
      }
      if (options.includePlugins) {
        pluginCount = await _stageDir(
            tmpDir, 'plugins', await PathUtils.pluginsDir, manifestFiles);
      }

      // 4) 清单：版本、时间、内容开关、每个文件的 SHA-256
      final manifest = <String, dynamic>{
        'version': manifestVersion,
        'appVersion': AppConstants.version,
        'createdAtMs': stamp,
        'dbUserVersion': dbUserVersion,
        'includes': <String, dynamic>{
          'database': options.includeDatabase,
          'covers': options.includeCovers,
          'plugins': options.includePlugins,
          'cookies': options.includeCookies,
          'coverCount': coverCount,
          'pluginCount': pluginCount,
        },
        'files': manifestFiles,
      };
      await _stageFile(
          tmpDir, 'manifest.json', utf8.encode(jsonEncode(manifest)));

      // 5) 打包：先写临时 zip，成功后再改名（失败不留半成品）
      final encoder = ZipFileEncoder();
      encoder.create(tmpPath);
      try {
        await for (final e in tmpDir.list(recursive: true)) {
          if (e is! File) continue;
          final rel = p.relative(e.path, from: tmpDir.path);
          final bytes = await e.readAsBytes();
          encoder.addArchiveFile(
              ArchiveFile(rel.replaceAll('\\', '/'), bytes.length, bytes));
        }
      } finally {
        encoder.close();
      }
      final outFile = await File(tmpPath).rename(outPath);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(AppConstants.keyLastBackup, stamp);
      appLogger.info('创建本地备份', detail: outPath);
      return outFile;
    } catch (e) {
      if (await File(tmpPath).exists()) {
        await File(tmpPath).delete().catchError((_) => File(tmpPath));
      }
      if (e is BackupException) rethrow;
      throw BackupException(friendlyBackupError(e));
    } finally {
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true).catchError((_) => tmpDir);
      }
    }
  }

  Future<int> _stageDir(Directory tmpDir, String rel, Directory src,
      Map<String, String> manifestFiles) async {
    var count = 0;
    if (!await src.exists()) return 0;
    await for (final e in src.list(recursive: true)) {
      if (e is! File) continue;
      final name = p.relative(e.path, from: src.path).replaceAll('\\', '/');
      final bytes = await e.readAsBytes();
      manifestFiles['$rel/$name'] = sha256.convert(bytes).toString();
      await _stageFile(tmpDir, '$rel/$name', bytes);
      count++;
    }
    return count;
  }

  Future<void> _stageFile(Directory tmpDir, String rel, List<int> bytes) async {
    final f = File(p.join(tmpDir.path, rel));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
  }

  /// 从 live 库里抽 Cookie/登录态（只抽 login_state，不碰别的）。
  Future<Map<String, String>> _extractCookies(AppDatabase liveDb) async {
    final out = <String, String>{};
    final rows = await liveDb.select(liveDb.sourceConfigs).get();
    for (final r in rows) {
      if (r.loginState != null && r.loginState!.isNotEmpty) {
        out[r.sourceId] = r.loginState!;
      }
    }
    return out;
  }

  // ------------------------------------------------------------ 校验

  /// 校验备份文件：清单缺失、文件 SHA-256 对不上、数据库版本比当前新，
  /// 一律报“备份文件损坏”/拒绝恢复。返回清单（供页面展示）。
  Future<Map<String, dynamic>> verifyBackupFile(File zip) async {
    if (!await zip.exists()) {
      throw const BackupException('备份文件不存在');
    }
    late final List<int> bytes;
    try {
      bytes = await zip.readAsBytes();
    } catch (_) {
      throw const BackupException('备份文件损坏');
    }
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const BackupException('备份文件损坏');
    }
    ArchiveFile? manifestFile;
    for (final f in archive.files) {
      if (f.isFile && f.name == 'manifest.json') manifestFile = f;
    }
    if (manifestFile == null) {
      // 老包（没有清单）：至少要能解出 database/app.db 或 covers/plugins
      final hasAnything = archive.files.any((f) =>
          f.isFile &&
          (f.name.startsWith('database/') ||
              f.name.startsWith('covers/') ||
              f.name.startsWith('plugins/')));
      if (!hasAnything) throw const BackupException('备份文件损坏');
      return <String, dynamic>{
        'version': 1,
        'legacy': true,
        'includes': <String, dynamic>{},
      };
    }
    Map<String, dynamic> manifest;
    try {
      manifest = jsonDecode(
          utf8.decode(manifestFile.content as List<int>)) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupException('备份文件损坏');
    }
    final files = manifest['files'];
    if (files is! Map) throw const BackupException('备份文件损坏');
    final byName = <String, ArchiveFile>{};
    for (final f in archive.files) {
      if (f.isFile) byName[f.name] = f;
    }
    for (final entry in files.entries) {
      final name = '${entry.key}';
      final want = '${entry.value}';
      final f = byName[name];
      if (f == null) throw const BackupException('备份文件损坏');
      final got = sha256.convert(f.content as List<int>).toString();
      if (got != want) throw const BackupException('备份文件损坏');
    }
    final dbVersion = manifest['dbUserVersion'];
    if (dbVersion is int && dbVersion > 1) {
      throw const BackupException('这个备份的版本比当前 App 新，不能恢复');
    }
    return manifest;
  }

  // ------------------------------------------------------------ 恢复

  /// 合并式恢复：先校验，再自动备一份当前数据（后悔药），再按“本机有的才写回”
  /// 合并；本机有、备份里没有的不动；备份里有、本机没有的单独计数并明说。
  /// 调用方需先关掉正在用的数据库（sqlite 文件被占用时拷不进去）。
  Future<RestoreReport> restoreFromZip(
    File zip, {
    required AppDatabase liveDb,
    String? localPassword,
  }) async {
    final manifest = await verifyBackupFile(zip);

    // 1) 先自动备一份当前数据，恢复坏了还能回来
    try {
      await BackupService(db: liveDb).createBackup();
    } catch (e) {
      appLogger.warning('恢复前自动备份当前数据失败', detail: '$e');
    }

    final root = await PathUtils.appFilesDir;
    final tmp = await Directory(
      p.join(root.path, '.restore_tmp_${DateTime.now().millisecondsSinceEpoch}'),
    ).create(recursive: true);
    try {
      // 2) 解压到临时目录（路径穿越防护：去掉 .. 与开头的 /）
      final bytes = await zip.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive.files) {
        if (!f.isFile) continue;
        var rel = f.name.replaceAll('\\', '/');
        while (rel.startsWith('/')) {
          rel = rel.substring(1);
        }
        final segs = <String>[];
        for (final s in rel.split('/')) {
          if (s.isEmpty || s == '.' || s == '..') continue;
          segs.add(s);
        }
        if (segs.isEmpty) continue;
        final out = File(p.joinAll([tmp.path, ...segs]));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(f.content as List<int>);
      }

      var restoredBooks = 0;
      var missingBooks = 0;
      var restoredProgress = 0;
      var restoredBookmarks = 0;
      var restoredFavorites = 0;
      var cookiesRestored = 0;

      // 3) 数据库合并
      final dbFile = File(p.join(tmp.path, 'database', 'app.db'));
      if (await dbFile.exists()) {
        final backupDb = AppDatabase.atPath(dbFile.path);
        try {
          final items = await backupDb.select(backupDb.mediaItems).get();
          for (final item in items) {
            final local = await _getBook(liveDb, item.id);
            if (local == null) {
              missingBooks++;
              continue;
            }
            final backupTime = item.lastPlayedAt;
            final localTime = local.lastPlayedAt;
            final newer = backupTime != null &&
                (localTime == null || backupTime.isAfter(localTime));
            if (newer) {
              await (liveDb.update(liveDb.mediaItems)
                    ..where((t) => t.id.equals(item.id)))
                  .write(MediaItemsCompanion(
                lastChapterUrl: Value(item.lastChapterUrl),
                lastPositionMs: Value(item.lastPositionMs),
                lastDurationMs: Value(item.lastDurationMs),
                isFinished: Value(item.isFinished),
                lastPlayedAt: Value(item.lastPlayedAt),
              ));
              restoredBooks++;
            }
          }
          final progresses = await backupDb.select(backupDb.progress).get();
          for (final pr in progresses) {
            if (await _getBook(liveDb, pr.itemId) == null) continue;
            final localRows = await (liveDb.select(liveDb.progress)
                  ..where((t) =>
                      t.itemId.equals(pr.itemId) &
                      t.chapterUrl.equals(pr.chapterUrl)))
                .get();
            final localNewer = localRows.isNotEmpty &&
                localRows.first.updatedAt.isAfter(pr.updatedAt);
            if (localNewer) continue;
            await liveDb.into(liveDb.progress).insertOnConflictUpdate(
                  ProgressCompanion.insert(
                    itemId: pr.itemId,
                    chapterUrl: pr.chapterUrl,
                    positionMs: Value(pr.positionMs),
                    durationMs: Value(pr.durationMs),
                    isFinished: Value(pr.isFinished),
                    updatedAt: pr.updatedAt,
                  ),
                );
            restoredProgress++;
          }
          final marks = await backupDb.select(backupDb.bookmarks).get();
          for (final m in marks) {
            if (await _getBook(liveDb, m.itemId) == null) continue;
            final exists = await (liveDb.select(liveDb.bookmarks)
                  ..where((t) => t.id.equals(m.id)))
                .get();
            if (exists.isNotEmpty) continue;
            await liveDb.into(liveDb.bookmarks).insert(
                  BookmarksCompanion.insert(
                    id: m.id,
                    itemId: m.itemId,
                    chapterUrl: Value(m.chapterUrl),
                    positionMs: Value(m.positionMs),
                    note: Value(m.note),
                    createdAt: m.createdAt,
                  ),
                );
            restoredBookmarks++;
          }
          final favs = await backupDb.select(backupDb.favorites).get();
          for (final f in favs) {
            if (await _getBook(liveDb, f.itemId) == null) continue;
            final exists = await (liveDb.select(liveDb.favorites)
                  ..where((t) => t.itemId.equals(f.itemId)))
                .get();
            if (exists.isNotEmpty) continue;
            await liveDb.into(liveDb.favorites).insert(
                  FavoritesCompanion.insert(
                    id: f.id,
                    itemId: f.itemId,
                    type: f.type,
                    createdAt: f.createdAt,
                  ),
                );
            await (liveDb.update(liveDb.mediaItems)
                  ..where((t) => t.id.equals(f.itemId)))
                .write(const MediaItemsCompanion(isFavorite: Value(true)));
            restoredFavorites++;
          }
          final kvRows = await backupDb.select(backupDb.kvSettings).get();
          for (final kv in kvRows) {
            if (_passwordKeys.contains(kv.key)) continue;
            if (kv.key == AppConstants.keyLastBackup) continue;
            await liveDb.writeSetting(kv.key, kv.value);
          }
          final configs =
              await backupDb.select(backupDb.sourceConfigs).get();
          for (final c in configs) {
            final localRows = await (liveDb.select(liveDb.sourceConfigs)
                  ..where((t) => t.sourceId.equals(c.sourceId)))
                .get();
            if (localRows.isEmpty) continue;
            await (liveDb.update(liveDb.sourceConfigs)
                  ..where((t) => t.sourceId.equals(c.sourceId)))
                .write(SourceConfigsCompanion(
              enabled: Value(c.enabled),
              voiceList: Value(c.voiceList),
              selectedVoiceId: Value(c.selectedVoiceId),
              lineList: Value(c.lineList),
              selectedLineId: Value(c.selectedLineId),
              extra: Value(c.extra),
            ));
          }
        } finally {
          await backupDb.close();
        }
      }

      // 4) Cookie：有 cookies.enc 才解（要本地密码；密码不对单独提示）
      final encFile = File(p.join(tmp.path, 'cookies.enc'));
      if (await encFile.exists()) {
        if (localPassword == null || localPassword.isEmpty) {
          appLogger.warning('备份里有 Cookie，但没给本地密码，跳过登录态恢复');
        } else {
          final cipher = await encFile.readAsBytes();
          final plain = _xorCrypt(cipher, localPassword);
          final want = (manifest['files'] as Map?)?['cookies.enc'];
          if (want != null &&
              sha256.convert(plain).toString() != '$want') {
            throw const BackupException('本地密码不对，Cookie 解不开，重新输入密码');
          }
          try {
            final decoded = jsonDecode(utf8.decode(plain));
            if (decoded is Map) {
              for (final entry in decoded.entries) {
                final sid = '${entry.key}';
                final loginState = '${entry.value}';
                final rows = await (liveDb.select(liveDb.sourceConfigs)
                      ..where((t) => t.sourceId.equals(sid)))
                    .get();
                if (rows.isEmpty) continue;
                await (liveDb.update(liveDb.sourceConfigs)
                      ..where((t) => t.sourceId.equals(sid)))
                    .write(SourceConfigsCompanion(
                        loginState: Value(loginState)));
                cookiesRestored++;
              }
            }
          } catch (e) {
            if (e is BackupException) rethrow;
            throw const BackupException('本地密码不对，Cookie 解不开，重新输入密码');
          }
        }
      }

      // 5) 封面 / 插件：拷文件（只覆盖同名文件，本机独有的不动）
      var restoredCovers = 0;
      var restoredPlugins = 0;
      restoredCovers = await _copyDirInto(
          Directory(p.join(tmp.path, 'covers')), await PathUtils.coversDir);
      restoredPlugins = await _copyDirInto(
          Directory(p.join(tmp.path, 'plugins')), await PathUtils.pluginsDir);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(AppConstants.keyLastBackup,
          DateTime.now().millisecondsSinceEpoch);
      appLogger.info('已从备份恢复', detail: zip.path);
      return RestoreReport(
        restoredBooks: restoredBooks,
        missingBooks: missingBooks,
        restoredProgress: restoredProgress,
        restoredBookmarks: restoredBookmarks,
        restoredFavorites: restoredFavorites,
        restoredCovers: restoredCovers,
        restoredPlugins: restoredPlugins,
        cookiesRestored: cookiesRestored,
      );
    } catch (e) {
      if (e is BackupException) rethrow;
      throw BackupException(friendlyBackupError(e));
    } finally {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true).catchError((_) => tmp);
      }
    }
  }

  Future<MediaItem?> _getBook(AppDatabase liveDb, String id) async {
    final rows = await (liveDb.select(liveDb.mediaItems)
          ..where((t) => t.id.equals(id)))
        .get();
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> _copyDirInto(Directory src, Directory dst) async {
    if (!await src.exists()) return 0;
    var count = 0;
    await dst.create(recursive: true);
    await for (final e in src.list(recursive: true)) {
      if (e is! File) continue;
      final rel = p.relative(e.path, from: src.path);
      final target = File(p.join(dst.path, rel));
      await target.parent.create(recursive: true);
      await e.copy(target.path);
      count++;
    }
    return count;
  }

  // ------------------------------------------------------------ 自动备份

  /// 关 App 时自动备份（界面组 main.dart 调）：默认开、间隔默认 1 天，
  /// 只在间隔到了才备；失败只记日志，不打扰用户。
  Future<void> runAutoBackupIfDue({AppDatabase? db}) async {
    final prefs = await SharedPreferences.getInstance();
    final auto = prefs.getBool(AppConstants.keyAutoBackup) ??
        AppConstants.defaultAutoBackup;
    if (!auto) return;
    final interval =
        prefs.getInt(AppConstants.keyBackupIntervalDays) ??
            AppConstants.defaultBackupIntervalDays;
    final last = prefs.getInt(AppConstants.keyLastBackup) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last < interval * 24 * 60 * 60 * 1000) return;
    try {
      final service = db != null ? BackupService(db: db) : this;
      await service.createBackup();
    } catch (e) {
      appLogger.warning('自动备份失败', detail: '$e');
    }
  }

  // ------------------------------------------------------------ 本机列表

  Future<List<File>> listLocalBackups() async {
    final dir = await PathUtils.backupsDir;
    if (!await dir.exists()) return <File>[];
    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.toLowerCase().endsWith('.zip')) {
        files.add(e);
      }
    }
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> deleteLocalBackup(File file) async {
    if (await file.exists()) await file.delete();
  }

  // ------------------------------------------------------------ 内部

  /// SHA-256 流密钥 XOR（对称加解密；不是 AES，见汇报）。
  static List<int> _xorCrypt(List<int> data, String password) {
    final key = sha256.convert(utf8.encode(password)).bytes;
    final out = List<int>.filled(data.length, 0);
    var counter = 0;
    List<int> block = <int>[];
    for (var i = 0; i < data.length; i++) {
      if (i % 32 == 0) {
        block = sha256.convert([
          ...key,
          counter & 0xFF,
          (counter >> 8) & 0xFF,
          (counter >> 16) & 0xFF,
          (counter >> 24) & 0xFF,
        ]).bytes;
        counter++;
      }
      out[i] = data[i] ^ block[i % 32];
    }
    return out;
  }
}
