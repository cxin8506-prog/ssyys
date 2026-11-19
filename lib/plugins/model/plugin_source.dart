/// 插件源：安装到本地的第三方源（JS/ZIP 或 JAR）
///
/// 与 [SourceConfig] 的区别：
/// - PluginSource 是「装了什么」，落盘在 plugins/index.json
/// - SourceConfig 是「这个源怎么配」，落库在 source_configs 表（登录态/音色/线路）
class PluginSource {
  final String id;
  final String name;

  /// audio | video
  final String type;

  /// jsZip | jar
  final String format;

  final String version;
  final String author;
  final String description;

  /// JS：入口脚本相对路径；JAR：主类名（可空，运行时再探测）
  final String entry;
  final String? icon;
  bool enabled;
  final int installedAt;
  final int sizeBytes;

  PluginSource({
    required this.id,
    required this.name,
    required this.type,
    required this.format,
    this.version = '1.0.0',
    this.author = '',
    this.description = '',
    this.entry = '',
    this.icon,
    this.enabled = true,
    required this.installedAt,
    this.sizeBytes = 0,
  });

  bool get isAudio => type == 'audio';
  bool get isJar => format == 'jar';
  bool get isJsZip => format == 'jsZip';

  String get formatLabel =>
      isJar ? 'JAR 插件' : (format == 'rule' ? '规则插件' : 'JS/ZIP 插件');

  PluginSource copyWith({bool? enabled, String? name, String? type}) =>
      PluginSource(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        format: format,
        version: version,
        author: author,
        description: description,
        entry: entry,
        icon: icon,
        enabled: enabled ?? this.enabled,
        installedAt: installedAt,
        sizeBytes: sizeBytes,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'format': format,
        'version': version,
        'author': author,
        'description': description,
        'entry': entry,
        'icon': icon,
        'enabled': enabled,
        'installedAt': installedAt,
        'sizeBytes': sizeBytes,
      };

  factory PluginSource.fromJson(Map<String, dynamic> j) => PluginSource(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '未命名源').toString(),
        type: (j['type'] ?? 'audio').toString(),
        format: (j['format'] ?? 'jsZip').toString(),
        version: (j['version'] ?? '1.0.0').toString(),
        author: (j['author'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        entry: (j['entry'] ?? '').toString(),
        icon: j['icon']?.toString(),
        enabled: j['enabled'] == null ? true : j['enabled'] == true,
        installedAt: int.tryParse('${j['installedAt']}') ?? 0,
        sizeBytes: int.tryParse('${j['sizeBytes']}') ?? 0,
      );
}

/// 源的运行配置（登录态 / 音色 / 视频线路）
class SourceConfigModel {
  final String sourceId;
  final String type;

  /// 登录态：任意 JSON（cookie、token、账号密码等，由源自己解释）
  String? loginState;

  /// 音色列表（番茄类源），元素形如 {"id":"...","name":"..."}
  List<Map<String, dynamic>> voices;

  /// 当前选中的音色 id
  String? selectedVoiceId;

  /// 视频线路列表，元素形如 {"id":"...","name":"..."}
  List<Map<String, dynamic>> lines;

  /// 当前选中的线路 id
  String? selectedLineId;

  /// 源自己声明的配置值（key -> value），与 [extra] 是同一份数据
  Map<String, dynamic> extra;

  SourceConfigModel({
    required this.sourceId,
    required this.type,
    this.loginState,
    List<Map<String, dynamic>>? voices,
    this.selectedVoiceId,
    List<Map<String, dynamic>>? lines,
    this.selectedLineId,
    Map<String, dynamic>? extra,
  })  : voices = voices ?? [],
        lines = lines ?? [],
        extra = extra ?? {};

  String? get selectedVoiceName {
    for (final v in voices) {
      if ('${v['id']}' == selectedVoiceId) return '${v['name'] ?? v['id']}';
    }
    final fallback = valueOf('voiceId');
    if (fallback != null && '$fallback'.isNotEmpty) return '$fallback';
    return null;
  }

  String? get selectedLineName {
    for (final l in lines) {
      if ('${l['id']}' == selectedLineId) return '${l['name'] ?? l['id']}';
    }
    final fallback = valueOf('lineId');
    if (fallback != null && '$fallback'.isNotEmpty) return '$fallback';
    return null;
  }

  /// 源自己声明的配置值（key -> value），与 [extra] 是同一份数据
  Map<String, dynamic> get values => extra;

  /// 读一个配置项，兼容旧的固定字段
  dynamic valueOf(String key) {
    if (extra.containsKey(key)) return extra[key];
    switch (key) {
      case 'voiceId':
      case 'voice':
      case 'selectedVoiceId':
        return selectedVoiceId;
      case 'lineId':
      case 'line':
      case 'selectedLineId':
        return selectedLineId;
      case 'loginState':
      case 'cookie':
      case 'token':
        return loginState;
    }
    return null;
  }

  /// 写一个配置项，同时同步旧的固定字段（播放页/引擎仍按老字段读）
  void setValue(String key, dynamic v) {
    extra[key] = v;
    syncLegacy(key, v);
  }

  void syncLegacy(String key, dynamic v) {
    final s = v == null ? null : '$v';
    switch (key) {
      case 'voiceId':
      case 'voice':
      case 'selectedVoiceId':
        selectedVoiceId = s;
        break;
      case 'lineId':
      case 'line':
      case 'selectedLineId':
        selectedLineId = s;
        break;
      case 'loginState':
      case 'cookie':
      case 'token':
        loginState = s;
        break;
    }
  }

  /// 把 values 里的同名字段回填到旧字段（从库里读出来后调一次）
  void hydrateLegacy() {
    for (final k in const [
      'voiceId',
      'voice',
      'selectedVoiceId',
      'lineId',
      'line',
      'selectedLineId',
      'loginState',
      'cookie',
      'token',
    ]) {
      if (extra.containsKey(k)) syncLegacy(k, extra[k]);
    }
  }
}
