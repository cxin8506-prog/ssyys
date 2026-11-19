import 'dart:convert';

import '../../../core/database/app_database.dart';
import 'ua_constants.dart';

/// UA 配置仓储：读写开关与两类 UA 列表。
///
/// 全部落在 kv_settings 表，因此自动随 database 目录进入本地 zip 备份。
/// 列表以 JSON 数组字符串存储；未初始化时回退到内置 UA 库。
class UaRepository {
  final AppDatabase _db;

  UaRepository(this._db);

  /// 自动选择开关
  Future<bool> autoSelect() async {
    final v = await _db.readSetting(UaConstants.keyAutoSelect);
    if (v == null) return UaConstants.defaultAutoSelect;
    return v == '1';
  }

  Future<void> setAutoSelect(bool enabled) =>
      _db.writeSetting(UaConstants.keyAutoSelect, enabled ? '1' : '0');

  /// 手机 UA 列表：未配置时返回内置库
  Future<List<String>> mobileUas() =>
      _readList(UaConstants.keyMobileList, UaConstants.builtinMobileUas);

  Future<void> setMobileUas(List<String> list) =>
      _writeList(UaConstants.keyMobileList, list);

  /// 电脑 UA 列表：未配置时返回内置库
  Future<List<String>> desktopUas() =>
      _readList(UaConstants.keyDesktopList, UaConstants.builtinDesktopUas);

  Future<void> setDesktopUas(List<String> list) =>
      _writeList(UaConstants.keyDesktopList, list);

  Future<List<String>> _readList(String key, List<String> fallback) async {
    final raw = await _db.readSetting(key);
    if (raw == null || raw.isEmpty) return List<String>.from(fallback);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {
      // 数据损坏时回退到内置库
    }
    return List<String>.from(fallback);
  }

  Future<void> _writeList(String key, List<String> list) =>
      _db.writeSetting(key, jsonEncode(list));
}
