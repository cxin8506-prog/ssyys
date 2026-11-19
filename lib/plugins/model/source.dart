/// 插件/源模型（二期预留）
///
/// 设计要点：
/// - 听书 JS/ZIP 插件（参考随身听书）：manifest.json + JS，flutter_js 执行
/// - 听书 JAR 插件（参考我的听书）：独立适配层
/// - 两套写法不同，分别适配，不共用
class SourceDescriptor {
  final String id;
  final String name;
  final String type; // audio | video
  final String format; // jsZip | jar
  final String path;
  final String version;
  bool enabled;

  SourceDescriptor({
    required this.id,
    required this.name,
    required this.type,
    required this.format,
    required this.path,
    this.version = '1.0.0',
    this.enabled = true,
  });
}

/// 源配置中心：每个源独立记忆的设置
/// 对应数据库 source_configs 表
class SourceConfig {
  final String sourceId;
  final String type;
  String? loginState; // JSON：需要登录的源
  List<String> voices = []; // 音色列表（番茄类源）
  String? selectedVoiceId; // 记住用户选的声音
  List<String> lines = []; // 视频线路列表
  String? selectedLineId; // 记住用户选的线路
  Map<String, dynamic> extra = {};

  SourceConfig({required this.sourceId, required this.type});
}
