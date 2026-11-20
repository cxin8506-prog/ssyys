import 'dart:convert';

import '../../core/database/app_database.dart';
import 'ua_constants.dart';

/// UA 配置仓储：读写开关、两条当前值、自定义列表、规则表、按站记忆。
///
/// 全部落在 kv_settings 表，因此自动随 database 目录进入本地 zip 备份。
/// 列表以 JSON 数组字符串存储；未初始化时回退到内置 UA 库。
class UaRepository {
  final AppDatabase _db;

  UaRepository(this._db);

  /// 自动选择开关（默认开；关了只按“手机/电脑”两条当前值走，不再按规则表切）
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

  Future<List<String>> desktopUas() =>
      _readList(UaConstants.keyDesktopList, const []);

  Future<void> setDesktopUas(List<String> list) =>
      _writeList(UaConstants.keyDesktopList, list);

  /// 当前生效的手机 UA（未显式选择时取内置推荐第一条）
  Future<String> mobileCurrent() async {
    final v = await _db.readSetting(UaConstants.keyMobileCurrent);
    if (v != null && v.trim().isNotEmpty) return v;
    final list = await mobileUas();
    if (list.isNotEmpty) return list.first;
    return UaConstants.defaultMobileUa;
  }

  Future<void> setMobileCurrent(String ua) =>
      _db.writeSetting(UaConstants.keyMobileCurrent, ua);

  /// 当前生效的电脑 UA
  Future<String> desktopCurrent() async {
    final v = await _db.readSetting(UaConstants.keyDesktopCurrent);
    if (v != null && v.trim().isNotEmpty) return v;
    final list = await desktopUas();
    if (list.isNotEmpty) return list.first;
    return UaConstants.defaultDesktopUa;
  }

  Future<void> setDesktopCurrent(String ua) =>
      _db.writeSetting(UaConstants.keyDesktopCurrent, ua);

  /// 恢复默认 UA（两条当前值回到内置推荐第一条）
  Future<void> resetToDefaults() async {
    await setMobileCurrent(UaConstants.defaultMobileUa);
    await setDesktopCurrent(UaConstants.defaultDesktopUa);
  }

  // ------------------------------------------------------------ 规则表

  /// 规则表：域名/关键词 → UA。未配过时返回预设规则。
  Future<List<UaRule>> rules() async {
    final raw = await _db.readSetting(UaConstants.keyRules);
    if (raw == null || raw.isEmpty) {
      return List<UaRule>.from(UaConstants.defaultRules);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = <UaRule>[];
        for (final e in decoded) {
          if (e is Map) {
            list.add(UaRule.fromJson(Map<String, dynamic>.from(e)));
          }
        }
        return list.where((r) => r.pattern.isNotEmpty).toList();
      }
    } catch (_) {
      // 数据损坏时回退到预设规则
    }
    return List<UaRule>.from(UaConstants.defaultRules);
  }

  Future<void> setRules(List<UaRule> rules) => _db.writeSetting(
        UaConstants.keyRules,
        jsonEncode(rules.map((r) => r.toJson()).toList()),
      );

  Future<void> resetRules() =>
      setRules(List<UaRule>.from(UaConstants.defaultRules));

  // ------------------------------------------------------------ 按站记忆

  /// 按站记忆：sourceId → 用户手动切过的 UA。下次打开这个源还用它，优先于规则表。
  Future<Map<String, String>> siteMemory() async {
    final raw = await _db.readSetting(UaConstants.keySiteMemory);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final out = <String, String>{};
        decoded.forEach((k, v) {
          if (v is String && v.isNotEmpty) out['$k'] = v;
        });
        return out;
      }
    } catch (_) {
      // 数据损坏按空处理
    }
    return <String, String>{};
  }

  Future<String?> siteUa(String sourceId) async {
    final map = await siteMemory();
    return map[sourceId];
  }

  Future<void> setSiteUa(String sourceId, String ua) async {
    final map = await siteMemory();
    map[sourceId] = ua;
    await _db.writeSetting(UaConstants.keySiteMemory, jsonEncode(map));
  }

  Future<void> clearSiteUa(String sourceId) async {
    final map = await siteMemory();
    map.remove(sourceId);
    await _db.writeSetting(UaConstants.keySiteMemory, jsonEncode(map));
  }

  Future<void> clearAllSiteMemory() async {
    await _db.writeSetting(UaConstants.keySiteMemory, '{}');
  }

  // ------------------------------------------------------------ 搜索专属 UA

  /// 某个源搜索专用的 UA（抄 TVBox 的 SUserAgent）；没设返回 null。
  Future<String?> searchUa(String sourceId) async {
    final v = await _db.readSetting('${UaConstants.keySearchUaPrefix}$sourceId');
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  Future<void> setSearchUa(String sourceId, String? ua) async {
    final key = '${UaConstants.keySearchUaPrefix}$sourceId';
    if (ua == null || ua.trim().isEmpty) {
      await _db.writeSetting(key, '');
      return;
    }
    await _db.writeSetting(key, ua.trim());
  }

  // ------------------------------------------------------------ 内部

  Future<List<String>> _readList(String key, List<String> fallback) async {
    final raw = await _db.readSetting(key);
    if (raw == null || raw.isEmpty) return List<String>.from(fallback);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } catch (_) {
      // 数据损坏时回退
    }
    return List<String>.from(fallback);
  }

  Future<void> _writeList(String key, List<String> list) =>
      _db.writeSetting(key, jsonEncode(list));
}
