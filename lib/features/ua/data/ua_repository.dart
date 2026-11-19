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

  /// 「我的 UA」列表（仅用户自定义/手动添加的，未配置时为空）
  Future<List<String>> mobileUas() =>
      _readList(UaConstants.keyMobileList, const []);

  Future<void> setMobileUas(List<String> list) =>
      _writeList(UaConstants.keyMobileList, list);

  /// 「我的 UA」列表（仅用户自定义/手动添加的，未配置时为空）
  Future<List<String>> desktopUas() =>
      _readList(UaConstants.keyDesktopList, const []);

  Future<void> setDesktopUas(List<String> list) =>
      _writeList(UaConstants.keyDesktopList, list);

  /// 当前生效的手机 UA（未显式选择时取列表第一项）
  Future<String?> mobileCurrent() async {
    final v = await _db.readSetting(UaConstants.keyMobileCurrent);
    if (v != null && v.trim().isNotEmpty) return v;
    final list = await mobileUas();
    if (list.isNotEmpty) return list.first;
    return UaConstants.builtinMobileUas.isEmpty
        ? null
        : UaConstants.builtinMobileUas.first;
  }

  Future<void> setMobileCurrent(String ua) =>
      _db.writeSetting(UaConstants.keyMobileCurrent, ua);

  /// 当前生效的电脑 UA
  Future<String?> desktopCurrent() async {
    final v = await _db.readSetting(UaConstants.keyDesktopCurrent);
    if (v != null && v.trim().isNotEmpty) return v;
    final list = await desktopUas();
    if (list.isNotEmpty) return list.first;
    return UaConstants.builtinDesktopUas.isEmpty
        ? null
        : UaConstants.builtinDesktopUas.first;
  }

  Future<void> setDesktopCurrent(String ua) =>
      _db.writeSetting(UaConstants.keyDesktopCurrent, ua);

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
