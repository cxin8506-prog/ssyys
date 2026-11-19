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
    final model = SourceConfigModel(
      sourceId: r.sourceId,
      type: r.type,
      loginState: r.loginState,
      voices: _decodeList(r.voiceList),
      selectedVoiceId: r.selectedVoiceId,
      lines: _decodeList(r.lineList),
      selectedLineId: r.selectedLineId,
      extra: _decodeMap(r.extra),
    );
    // 源自己声明的配置值可能在 extra 里，回填到旧字段供播放页/引擎读取
    model.hydrateLegacy();
    return model;
  }

  Future<void> save(SourceConfigModel c) async {
    // 源声明的配置值可能直接写进了 values，同步回旧字段再落库
    c.hydrateLegacy();
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

  /// 某个源的全部配置（供插件运行时读取）
  Future<Map<String, dynamic>> runtimeConfig(String sourceId) async {
    final c = await load(sourceId, '');
    return buildRuntimeConfig(c);
  }

  /// 把源声明的配置值合并成一份运行时对象，塞给插件：
  /// - 源自己声明的 key 原样展开（host.config[key]）
  /// - 兼容老写法：loginState / cookie / voiceId / lineId / voices / lines
  Map<String, dynamic> buildRuntimeConfig(SourceConfigModel c) {
    final out = <String, dynamic>{};
    out.addAll(c.values);

    String _text(dynamic v) => v == null ? '' : '$v';

    if (_text(out['loginState']).isEmpty && _text(c.loginState).isNotEmpty) {
      out['loginState'] = c.loginState;
    }
    if (_text(out['cookie']).isEmpty && _text(c.loginState).isNotEmpty) {
      out['cookie'] = c.loginState;
    }
    if (_text(out['voiceId']).isEmpty && _text(c.selectedVoiceId).isNotEmpty) {
      out['voiceId'] = c.selectedVoiceId;
    }
    if (_text(out['lineId']).isEmpty && _text(c.selectedLineId).isNotEmpty) {
      out['lineId'] = c.selectedLineId;
    }
    if (c.voices.isNotEmpty) out['voices'] = c.voices;
    if (c.lines.isNotEmpty) out['lines'] = c.lines;
    // 老插件可能读 host.config.extra.xxx，这里给个同内容的副本
    out['extra'] = Map<String, dynamic>.from(c.values);
    return out;
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
