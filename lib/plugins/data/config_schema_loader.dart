import '../engine/plugin_engine.dart';
import '../model/plugin_source.dart';
import 'source_config_schema.dart';
import 'source_repository.dart';

/// 把各处归一化后的选项转成统一的 [{value, label}]。
List<Map<String, String>> normalizeOptions(dynamic raw) {
  final out = <Map<String, String>>[];
  if (raw is List) {
    for (final e in raw) {
      if (e is Map) {
        final v = e['value'] ?? e['id'] ?? e['key'];
        final l = e['label'] ?? e['name'] ?? e['title'] ?? v;
        if (v != null) {
          out.add(<String, String>{'value': '$v', 'label': '$l'});
        }
      } else if (e != null) {
        out.add(<String, String>{'value': '$e', 'label': '$e'});
      }
    }
  } else if (raw is Map) {
    raw.forEach((k, v) {
      out.add(<String, String>{'value': '$k', 'label': '$v'});
    });
  }
  return out;
}

/// 配置声明加载器（源详情页 / 设置页读源的配置项用）。
///
/// 顺序：
/// 1. manifest.json 里的 config（声明式，最优先）；
/// 2. 源的 config() 方法（JS 源调注册源对象的 config()，
///    JAR 源调原生 config 分支）；
/// 3. 能力推断：源有线路/音色时，自动补一条线路/音色选择项。
///
/// 登录入口不占用配置项：源有登录地址时，详情页单独显示“登录”按钮。
class ConfigSchemaLoader {
  final SourceRepository _repo;

  ConfigSchemaLoader(this._repo);

  Future<ConfigSchema> load(PluginSource source, PluginEngine engine) async {
    // 1) manifest 声明。
    final manifest = await _repo.readManifest(source);
    final declared = parseConfigSchema(manifest['config']);
    if (declared != null) return declared;

    // 2) 源的 config() 方法。
    try {
      final raw = await engine.config();
      final parsed = parseConfigSchema(raw);
      if (parsed != null) return parsed;
    } catch (_) {
      // 源没有 config()，继续往下推断。
    }

    // 3) 能力推断：有线路/音色就补选择项。
    List<Map<String, String>>? lines;
    List<Map<String, String>>? voices;
    try {
      lines = await engine.lines();
    } catch (_) {
      lines = null;
    }
    try {
      voices = await engine.voices();
    } catch (_) {
      voices = null;
    }
    return inferredSchema(
        voices: voices != null && voices.isNotEmpty,
        lines: lines != null && lines.isNotEmpty);
  }
}
