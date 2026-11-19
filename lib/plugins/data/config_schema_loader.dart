import 'dart:convert';

import '../../core/log/app_logger.dart';
import '../engine/plugin_engine.dart';
import '../model/plugin_source.dart';
import 'login_entry.dart';
import 'source_config_schema.dart';
import 'source_repository.dart';

/// 取源的配置声明。
///
/// 顺序：
/// 1. `manifest.json` 里的 `config` / `settings` / `params` —— 安装完就能读，不跑脚本
/// 2. 源脚本的 `config()` / `getConfig()` / `settings()` —— 运行时才生成的声明
/// 3. 什么都没声明时，按它提供的能力推断（有 voices 给音色，有 lines 给线路）
///
/// App 自己不再写死「登录态 / 音色 / 线路」这些字段，全部由源说了算。
class ConfigSchemaLoader {
  final SourceRepository repo;
  ConfigSchemaLoader(this.repo);

  Future<ConfigSchema> load(PluginSource s, PluginEngine engine) async {
    final manifest = await repo.readManifest(s);
    final login = LoginEntry.parse(manifest);

    // 1) manifest
    for (final k in const ['config', 'configs', 'settings', 'params', 'fields']) {
      if (!manifest.containsKey(k)) continue;
      final schema = parseConfigSchema(manifest[k], origin: 'manifest');
      if (!schema.isEmpty) return _withLogin(schema, login);
    }

    // 2) 脚本声明（config 可能是函数，也可能是全局对象，直接试）
    try {
      await engine.attach(s);
      final raw = await engine.invoke('config', params: {});
      final schema = parseConfigSchema(raw, origin: 'script');
      if (!schema.isEmpty) return _withLogin(schema, login);
    } catch (e) {
      final msg = '$e';
      final silent = msg.contains('未实现') || msg.contains('METHOD_NOT_FOUND');
      if (!silent) {
        appLogger.warning('读取源配置声明失败', detail: '${s.name}: $e');
      }
    }

    // 3) 能力推断（只对能明确判断方法存在与否的引擎做，避免白发请求）
    var voices = false;
    var lines = false;
    try {
      voices = (await engine.hasMethod('voices')) == true;
      lines = (await engine.hasMethod('lines')) == true;
    } catch (_) {}
    return _withLogin(inferredSchema(voices: voices, lines: lines), login);
  }

  /// 源声明了登录地址时，把登录做成一个配置项：
  /// 已经有 cookie / token 字段的就把它升级成网页登录，没有就补一项在最前面。
  ConfigSchema _withLogin(ConfigSchema schema, LoginEntry? login) {
    if (login == null || !login.valid) return schema;
    if (schema.fields.any((f) => f.isLogin)) return schema;

    ConfigField build(String key) => ConfigField(
          key: key,
          name: '登录',
          type: 'login',
          loginUrl: login.url,
          successUrl: login.successUrl,
          cookieUrl: login.cookieUrl,
          desc: '点「去登录」跳到源的网页，登录完成后自动同步 Cookie',
        );

    final idx = schema.fields.indexWhere(
        (f) => f.key == 'cookie' || f.key == 'loginState' || f.key == 'token');
    final list = [...schema.fields];
    if (idx >= 0) {
      list[idx] = build(schema.fields[idx].key);
    } else {
      list.insert(0, build('cookie'));
    }
    return ConfigSchema(
      fields: list,
      origin: schema.origin == 'none' ? 'manifest' : schema.origin,
      note: schema.note,
    );
  }

  /// 「从源获取」选项：调源方法（voices/lines/自定义），归一化成 value/label
  Future<List<ConfigOption>> fetchOptions(
    PluginSource s,
    PluginEngine engine,
    String method, {
    String url = '',
  }) async {
    await engine.attach(s);
    final raw = await engine.invoke(method, params: {'url': url});
    return normalizeOptions(raw);
  }
}

/// 把源返回的选项归一化成 value/label 列表
List<ConfigOption> normalizeOptions(dynamic raw) {
  var data = raw;
  for (var i = 0; i < 3; i++) {
    if (data is! String) break;
    final t = data.trim();
    if (t.isEmpty) return const [];
    if (!(t.startsWith('{') || t.startsWith('['))) return const [];
    try {
      data = jsonDecode(t);
    } catch (_) {
      return const [];
    }
  }

  if (data is Map) {
    for (final k in const ['list', 'data', 'items', 'voices', 'lines', 'options']) {
      if (data[k] is List) {
        data = data[k];
        break;
      }
    }
  }

  final out = <ConfigOption>[];
  if (data is List) {
    for (var i = 0; i < data.length; i++) {
      final e = data[i];
      if (e is Map) {
        final v = '${e['value'] ?? e['id'] ?? e['key'] ?? e['code'] ?? i}';
        final l = '${e['label'] ?? e['name'] ?? e['title'] ?? e['text'] ?? v}';
        out.add(ConfigOption(v, l));
      } else if (e != null) {
        out.add(ConfigOption('$e', '$e'));
      }
    }
  } else if (data is Map) {
    data.forEach((k, v) => out.add(ConfigOption('$k', '$v')));
  }
  return out;
}
