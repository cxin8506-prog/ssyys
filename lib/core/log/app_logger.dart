import 'package:logging/logging.dart' as lg;

import '../database/app_database.dart';

/// 统一日志服务：同时输出到控制台和数据库，便于查看/导出。
class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();
  static AppDatabase? _db;
  final lg.Logger _log = lg.Logger('local_media');

  void attachDatabase(AppDatabase db) {
    _db = db;
    lg.Logger.root.level = lg.Level.ALL;
    lg.Logger.root.onRecord.listen((record) {
      // ignore: avoid_print
      print('[${record.level.name}] ${record.loggerName}: ${record.message}');
    });
  }

  void info(String message, {String? detail}) {
    _log.info(message);
    _write('info', message, detail);
  }

  void warning(String message, {String? detail}) {
    _log.warning(message);
    _write('warning', message, detail);
  }

  void error(String message, {Object? error, StackTrace? stack}) {
    _log.severe(message, error, stack);
    _write('error', message, '${error ?? ''}\n${stack ?? ''}');
  }

  void _write(String level, String message, String? detail) {
    _db?.log(level, message, detail: detail).catchError((_) => 0);
  }
}

/// 便捷全局引用
final appLogger = AppLogger.instance;
