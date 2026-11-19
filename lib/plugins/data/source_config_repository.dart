import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../model/plugin_source.dart';

/// 源配置仓储：登录态、音色列表、视频线路（落 source_configs 表，随备份走）
class SourceConfigRepository {
  final AppDatabase db;
  SourceConfigRepository(this.db);

  Future<SourceConfigModel> load(String sourceId, String type) async {
    final rows = await (db.select(db.sourceConfigs)
          ..where((t) => t.sourceId.equals(sourceId)))
        .get();
    if (rows.isEmpty) {
      return SourceConfigModel(sourceId: sourceId, type: type);
    }
    final r = rows.first;
    return SourceConfigModel(
      sourceId: r.sourceId,
      type: r.type,
      loginState: r.loginState,
      voices: _decodeList(r.voiceList),
      selectedVoiceId: r.selectedVoiceId,
      lines: _decodeList(r.lineList),
      selectedLineId: r.selectedLineId,
      extra: _decodeMap(r.extra),
    );
  }

  Future<void> save(SourceConfigModel c) async {
    await db.into(db.sourceConfigs).insertOnConflictUpdate(
          SourceConfigsCompanion.insert(
            sourceId: c.sourceId,
            type: c.type,
            loginState: Value(c.loginState),
            voiceList: Value(jsonEncode(c.voices)),
            selectedVoiceId: Value(c.selectedVoiceId),
            lineList: Value(jsonEncode(c.lines)),
            selectedLineId: Value(c.selectedLineId),
            extra: Value(jsonEncode(c.extra)),
          ),
        );
  }

  Future<void> clear(String sourceId) async {
    await (db.delete(db.sourceConfigs)
          ..where((t) => t.sourceId.equals(sourceId)))
        .go();
  }

  /// 某个源的全部配置（供插件运行时读取登录态/音色/线路）
  Future<Map<String, dynamic>> runtimeConfig(String sourceId) async {
    final c = await load(sourceId, '');
    return {
      'loginState': c.loginState,
      'voiceId': c.selectedVoiceId,
      'lineId': c.selectedLineId,
      'extra': c.extra,
    };
  }

  List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final v = jsonDecode(raw);
      if (v is List) {
        return v
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final v = jsonDecode(raw);
      if (v is Map) return Map<String, dynamic>.from(v);
    } catch (_) {}
    return {};
  }
}
