/// 插件源模型：一个 [PluginSource] 就是源管理页里的一行。
///
/// JAR 和 JS 共用这一套模型，不再分两套：
/// - 一个 ZIP 插件拆出来的多个源，共用同一个 [pluginId]（解压目录名），
///   各自的 [sstsId] 是 registerSource 注册时写的 id；
/// - 一个 JAR 包拆出来的多个源，共用同一个 [jarPath]，各自记
///   [entryClass] + [sourceIndex]。
///
/// 落盘位置：`<应用文档>/local_media_app/plugins/index.json`，
/// 由 [SourceRepository] 读写。
class PluginSource {
  /// 源唯一 id。JS 单源插件里等于 pluginId；随身听书格式里等于 sstsId；
  /// 我的听书格式里是 `ts_<包签名>_<下标>`。
  final String id;

  /// 源名（显示用）。
  final String name;

  /// 内容类型：`audio`（听书）或 `video`（视频）。
  final String type;

  /// 插件格式：`js`（JS/ZIP）、`jar`（通用 JAR）、`tingshu`（我的听书格式 JAR）。
  /// 旧索引里可能还写着 `jsZip` / `tingShu`，读进来时统一归一化。
  final String format;

  /// 插件版本号（manifest / 包里声明的，没有就是 1.0.0）。
  final String version;

  /// 作者（manifest 里声明的，没有就是空）。
  final String author;

  /// 简介（manifest 或源自己写的描述）。
  final String description;

  /// 源首页地址（源的 url，可空）。
  final String? url;

  /// JS：入口脚本在插件目录里的相对路径；JAR：主类名（可空，运行时再探测）。
  final String entry;

  /// JAR 源：JAR 文件的绝对路径（同一个包里的多个源共用一份）。
  final String? jarPath;

  /// 我的听书格式：含 getSources 的入口类名。
  final String? entryClass;

  /// 我的听书格式：这个源在 getSources() 返回列表里的下标。
  final int sourceIndex;

  /// 所属插件包名（JAR 文件主名 / ZIP 插件名），源管理按它折叠分组。
  final String group;

  /// 所属插件包的目录 id（多个源共用一份解压目录）。
  /// 单源旧写法里它就等于源自己的 id。
  final String? pluginId;

  /// 随身听书格式：registerSource 的 id。旧写法为空。
  final String? sstsId;

  /// 首字图标（没有时界面用名字首字画一个）。
  final String? icon;

  /// 是否启用。关掉就是停用，不删除；禁用的源不参与搜索和书源页。
  bool enabled;

  /// 排序值：越小越靠前。源管理页的上移/下移就是交换这个值。
  final int order;

  /// 安装时间（毫秒时间戳）。
  final int installedAt;

  /// 插件包占用的字节数（目录大小，多源包按源均摊）。
  final int sizeBytes;

  PluginSource({
    required this.id,
    required this.name,
    this.type = 'audio',
    this.format = 'js',
    this.version = '1.0.0',
    this.author = '',
    this.description = '',
    this.url,
    this.entry = '',
    this.jarPath,
    this.entryClass,
    this.sourceIndex = 0,
    this.group = '',
    this.pluginId,
    this.sstsId,
    this.icon,
    this.enabled = true,
    this.order = 0,
    required this.installedAt,
    this.sizeBytes = 0,
  });

  bool get isAudio => type == 'audio';
  bool get isVideo => type == 'video';

  /// JS/ZIP 格式（含旧写法 jsZip）。
  bool get isJs => format == 'js';

  /// 通用 JAR 格式（单个主类静态方法）。
  bool get isJar => format == 'jar';

  /// 我的听书格式 JAR（含旧写法 tingShu）。
  bool get isTingShu => format == 'tingshu';

  /// 随身听书格式（registerSource 注册的源）。
  bool get isSsts => sstsId != null && sstsId!.isNotEmpty;

  String get formatLabel {
    if (isTingShu) return 'JAR 源包';
    if (isJar) return 'JAR 插件';
    return 'JS/ZIP 插件';
  }

  PluginSource copyWith({
    String? name,
    String? type,
    String? format,
    String? version,
    String? description,
    String? url,
    String? entry,
    String? entryClass,
    bool? enabled,
    int? order,
  }) {
    return PluginSource(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      format: format ?? this.format,
      version: version ?? this.version,
      author: author,
      description: description ?? this.description,
      url: url ?? this.url,
      entry: entry ?? this.entry,
      jarPath: jarPath,
      entryClass: entryClass ?? this.entryClass,
      sourceIndex: sourceIndex,
      group: group,
      pluginId: pluginId,
      sstsId: sstsId,
      icon: icon,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      installedAt: installedAt,
      sizeBytes: sizeBytes,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'type': type,
      'format': format,
      'version': version,
      'author': author,
      'description': description,
      'url': url,
      'entry': entry,
      'jarPath': jarPath,
      'entryClass': entryClass,
      'sourceIndex': sourceIndex,
      'group': group,
      'pluginId': pluginId,
      'sstsId': sstsId,
      'icon': icon,
      'enabled': enabled,
      'order': order,
      'installedAt': installedAt,
      'sizeBytes': sizeBytes,
    };
  }

  factory PluginSource.fromJson(Map<String, dynamic> j) {
    return PluginSource(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '未命名源').toString(),
      type: (j['type'] ?? 'audio').toString(),
      format: _normalizeFormat((j['format'] ?? 'js').toString()),
      version: (j['version'] ?? '1.0.0').toString(),
      author: (j['author'] ?? '').toString(),
      description: (j['description'] ?? '').toString(),
      url: j['url']?.toString(),
      entry: (j['entry'] ?? '').toString(),
      jarPath: j['jarPath']?.toString(),
      entryClass: j['entryClass']?.toString(),
      sourceIndex: int.tryParse('${j['sourceIndex']}') ?? 0,
      group: (j['group'] ?? '').toString(),
      pluginId: j['pluginId']?.toString(),
      sstsId: j['sstsId']?.toString(),
      icon: j['icon']?.toString(),
      enabled: j['enabled'] == null ? true : j['enabled'] == true,
      order: int.tryParse('${j['order']}') ?? 0,
      installedAt: int.tryParse('${j['installedAt']}') ?? 0,
      sizeBytes: int.tryParse('${j['sizeBytes']}') ?? 0,
    );
  }

  static String _normalizeFormat(String raw) {
    switch (raw) {
      case 'jsZip':
      case 'jszip':
      case 'zip':
        return 'js';
      case 'tingShu':
      case 'tingshu':
      case 'ting_shu':
        return 'tingshu';
      case 'jar':
        return 'jar';
      default:
        return 'js';
    }
  }
}

/// 源管理页按插件折叠后的一组：一个插件包一张卡，里面是它的全部源。
class PluginGroup {
  /// 分组键：pluginId（没有时用第一个源的 id）。
  final String pluginId;

  /// 显示名：插件包名（JAR 文件主名 / ZIP 插件名）。
  final String name;

  /// 组内源（按 order 排好）。
  final List<PluginSource> sources;

  const PluginGroup({
    required this.pluginId,
    required this.name,
    required this.sources,
  });

  int get totalCount => sources.length;
  int get enabledCount => sources.where((s) => s.enabled).length;

  /// 包内任一源启用时，整包开关显示开启（随身听书 5.7 的做法）。
  bool get anyEnabled => enabledCount > 0;
}

/// 一个源的运行配置（登录态 / 音色列表 / 视频线路 / 源声明的配置值）。
///
/// 落库在 `source_configs` 表（随备份走），不要和 [PluginSource] 混在一起：
/// PluginSource 是「装了什么」，SourceConfigModel 是「这个源怎么配」。
class SourceConfigModel {
  final String sourceId;
  final String type;

  /// 登录态：任意 JSON（cookie、token 等，由源自己解释）。
  String? loginState;

  /// 音色列表，元素形如 `{"id": "...", "name": "..."}`。
  List<Map<String, dynamic>> voices;

  /// 当前选中的音色 id。
  String? selectedVoiceId;

  /// 视频线路列表，元素形如 `{"id": "...", "name": "..."}`。
  List<Map<String, dynamic>> lines;

  /// 当前选中的线路 id。
  String? selectedLineId;

  /// 源自己声明的配置值（key -> value）。
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
  })  : voices = voices ?? <Map<String, dynamic>>[],
        lines = lines ?? <Map<String, dynamic>>[],
        extra = extra ?? <String, dynamic>{};

  /// [extra] 的别名：播放页和引擎按 `values` 读配置。
  Map<String, dynamic> get values => extra;

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

  /// 读一个配置项，兼容旧的固定字段名。
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

  /// 写一个配置项，同时同步到旧的固定字段（播放页/引擎仍按老字段读）。
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

  /// 把 values 里的同名字段回填到固定字段（从库里读出来后调一次）。
  void hydrateLegacy() {
    for (final k in const <String>[
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
