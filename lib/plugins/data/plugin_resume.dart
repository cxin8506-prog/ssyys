import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 断点续播记录（插件源的书 / 视频）。
class PluginResume {
  /// 书的唯一键：`sourceId|bookUrl`。
  final String bookKey;

  /// 源 id。
  final String sourceId;

  /// 书名（没有就留空）。
  final String title;

  /// 当前章节下标。
  final int chapterIndex;

  /// 当前章节名（没有就留空）。
  final String chapterTitle;

  /// 当前播放位置（毫秒）。
  final int positionMs;

  /// 当前章节总时长（毫秒，0 表示未知）。
  final int durationMs;

  /// 源类型：audio / video。
  final String type;

  /// 当前线路 id（视频源切线续播用；没有线路的源留空）。
  final String lineId;

  /// 当前线路名（续播时显示 / 按线名恢复，没有留空）。
  final String lineName;

  /// 当前音色 id（听书源切音色用；没有留空）。
  final String voiceId;

  /// 上次保存时间（毫秒时间戳）。
  final int updatedAt;

  const PluginResume({
    required this.bookKey,
    required this.sourceId,
    required this.title,
    required this.chapterIndex,
    required this.chapterTitle,
    required this.positionMs,
    required this.durationMs,
    this.type = 'audio',
    this.lineId = '',
    this.lineName = '',
    this.voiceId = '',
    required this.updatedAt,
  });

  /// 播完的进度（>=95% 视为播完，保存时删记录）。
  bool get isFinished => durationMs > 0 && positionMs >= durationMs * 0.95;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'bookKey': bookKey,
        'sourceId': sourceId,
        'title': title,
        'chapterIndex': chapterIndex,
        'chapterTitle': chapterTitle,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'type': type,
        'lineId': lineId,
        'lineName': lineName,
        'voiceId': voiceId,
        'updatedAt': updatedAt,
      };

  factory PluginResume.fromJson(Map<String, dynamic> m) => PluginResume(
        bookKey: '${m['bookKey'] ?? ''}',
        sourceId: '${m['sourceId'] ?? ''}',
        title: '${m['title'] ?? ''}',
        chapterIndex: int.tryParse('${m['chapterIndex']}') ?? 0,
        chapterTitle: '${m['chapterTitle'] ?? ''}',
        positionMs: int.tryParse('${m['positionMs']}') ?? 0,
        durationMs: int.tryParse('${m['durationMs']}') ?? 0,
        type: '${m['type'] ?? 'audio'}',
        lineId: '${m['lineId'] ?? ''}',
        lineName: '${m['lineName'] ?? ''}',
        voiceId: '${m['voiceId'] ?? ''}',
        updatedAt: int.tryParse('${m['updatedAt']}') ??
            DateTime.now().millisecondsSinceEpoch,
      );

  PluginResume copyWith({
    String? title,
    int? chapterIndex,
    String? chapterTitle,
    int? positionMs,
    int? durationMs,
    String? type,
    String? lineId,
    String? lineName,
    String? voiceId,
    int? updatedAt,
  }) =>
      PluginResume(
        bookKey: bookKey,
        sourceId: sourceId,
        title: title ?? this.title,
        chapterIndex: chapterIndex ?? this.chapterIndex,
        chapterTitle: chapterTitle ?? this.chapterTitle,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        type: type ?? this.type,
        lineId: lineId ?? this.lineId,
        lineName: lineName ?? this.lineName,
        voiceId: voiceId ?? this.voiceId,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// 断点续播键：`sourceId|bookUrl`（播放器组和这里必须用同一格式）。
String resumeKey(String sourceId, String bookUrl) => '$sourceId|$bookUrl';

/// 断点续播存取（SharedPreferences，最多存 10 条，超了删最旧的）。
class PluginResumeStore {
  static const String _key = 'plugin_resume_list';
  static const int maxItems = 10;

  final SharedPreferences _prefs;

  PluginResumeStore(this._prefs);

  Map<String, PluginResume> _loadAll() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <String, PluginResume>{};
    try {
      final list = jsonDecode(raw);
      if (list is! List) return <String, PluginResume>{};
      final out = <String, PluginResume>{};
      for (final e in list) {
        if (e is Map) {
          final r = PluginResume.fromJson(Map<String, dynamic>.from(e));
          if (r.bookKey.isNotEmpty) out[r.bookKey] = r;
        }
      }
      return out;
    } catch (_) {
      return <String, PluginResume>{};
    }
  }

  Future<void> _saveAll(Map<String, PluginResume> map) async {
    final list = map.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final trimmed = list.length > maxItems ? list.sublist(0, maxItems) : list;
    await _prefs.setString(
        _key, jsonEncode(trimmed.map((e) => e.toJson()).toList()));
  }

  Future<PluginResume?> get(String bookKey) async => _loadAll()[bookKey];

  /// 保存进度。播完（>=95%）时删记录，不留“已播完”的残条目。
  Future<void> save(PluginResume resume) async {
    final all = _loadAll();
    if (resume.isFinished) {
      all.remove(resume.bookKey);
    } else {
      all[resume.bookKey] = resume;
    }
    await _saveAll(all);
  }

  Future<void> clear(String bookKey) async {
    final all = _loadAll();
    all.remove(bookKey);
    await _saveAll(all);
  }

  /// 全部记录（最近的在前，首页“继续收听”用）。
  Future<List<PluginResume>> listAll() async {
    final list = _loadAll().values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }
}

/// 播放器组调用的顶层函数（三个必填参数的签名按契约一字不差；
/// type/lineId/lineName/voiceId 是后加的可选命名参数，不传时沿用旧记录）。
/// 注意：这里每次都重新拿 SharedPreferences 实例——播放器在后台
/// 隔离区（audio_service）里也可能调，Riverpod 的 provider 不一定在。
Future<SharedPreferences> _resumePrefs() =>
    SharedPreferences.getInstance();

/// 取一条断点记录，没有返回 null。
/// [bookKey] 格式：`sourceId|bookUrl`。
Future<Map<String, dynamic>?> getPluginResume(String bookKey) async {
  final store = PluginResumeStore(await _resumePrefs());
  final r = await store.get(bookKey);
  return r?.toJson();
}

/// 保存断点。没有旧记录时建一条新记录（标题/章节名/源 id 不传就留空）。
/// 播完（>=95%）时删记录。
/// [type]：新记录的类型（'audio'/'video'）。只凭 bookKey 认不出是视频还是
/// 音频，调用方知道类型时请传进来；不传时沿用旧记录的 type，再没有才默认 audio。
/// [title]/[chapterTitle]/[sourceId]/[lineId]/[lineName]/[voiceId]：不传时
/// 沿用旧记录的值。
/// [bookKey] 格式：`sourceId|bookUrl`。
Future<void> savePluginResume(String bookKey,
    {required int chapterIndex,
    required int positionMs,
    required int durationMs,
    String? type,
    String? title,
    String? chapterTitle,
    String? sourceId,
    String? lineId,
    String? lineName,
    String? voiceId}) async {
  final store = PluginResumeStore(await _resumePrefs());
  final old = await store.get(bookKey);
  final now = DateTime.now().millisecondsSinceEpoch;
  final parts = bookKey.split('|');
  final resume = PluginResume(
    bookKey: bookKey,
    sourceId: sourceId ?? old?.sourceId ?? (parts.isNotEmpty ? parts.first : ''),
    title: title ?? old?.title ?? '',
    chapterIndex: chapterIndex,
    chapterTitle: chapterTitle ?? old?.chapterTitle ?? '',
    positionMs: positionMs,
    durationMs: durationMs,
    type: type ?? old?.type ?? 'audio',
    lineId: lineId ?? old?.lineId ?? '',
    lineName: lineName ?? old?.lineName ?? '',
    voiceId: voiceId ?? old?.voiceId ?? '',
    updatedAt: now,
  );
  await store.save(resume);
}

/// 清掉一条断点记录。
Future<void> clearPluginResume(String bookKey) async {
  final store = PluginResumeStore(await _resumePrefs());
  await store.clear(bookKey);
}
