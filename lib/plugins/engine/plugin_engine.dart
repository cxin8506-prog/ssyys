/// 插件引擎接口（二期预留，第一版不实现业务逻辑）
///
/// 二期实现顺序：
/// 1. JS/ZIP 引擎：flutter_js 执行脚本，宿主提供网络/HTML 解析接口
/// 2. JAR 适配层：加载我的听书风格 JAR
abstract class PluginEngine {
  /// 引擎格式标识：jsZip | jar
  String get format;

  /// 从插件包加载源描述
  Future<List<dynamic>> loadSources(String pluginPath);

  /// 执行源方法（search / bookDetail / audio 等）
  Future<dynamic> invoke({
    required String sourceId,
    required String method,
    Map<String, dynamic>? params,
  });
}

/// JS 引擎占位（二期实现）
class JsPluginEngine implements PluginEngine {
  @override
  String get format => 'jsZip';

  @override
  Future<List<dynamic>> loadSources(String pluginPath) async => [];

  @override
  Future<dynamic> invoke(
          {required String sourceId,
          required String method,
          Map<String, dynamic>? params}) async =>
      null;
}

/// JAR 适配层占位（二期实现）
class JarPluginEngine implements PluginEngine {
  @override
  String get format => 'jar';

  @override
  Future<List<dynamic>> loadSources(String pluginPath) async => [];

  @override
  Future<dynamic> invoke(
          {required String sourceId,
          required String method,
          Map<String, dynamic>? params}) async =>
      null;
}
