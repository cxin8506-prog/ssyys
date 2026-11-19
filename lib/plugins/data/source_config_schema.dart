import 'dart:convert';

/// 一个下拉/单选项
class ConfigOption {
  final String value;
  final String label;
  const ConfigOption(this.value, this.label);
}

/// 源自己声明的一项配置。
///
/// 插件在 manifest.json 里写：
/// ```json
/// "config": [
///   {"key": "cookie", "name": "登录态", "type": "textarea",
///    "hint": "token=xxx; uid=123", "desc": "不登录只能试听"},
///   {"key": "voice", "name": "音色", "type": "select", "source": "voices"},
///   {"key": "line",  "name": "线路", "type": "select", "source": "lines"},
///   {"key": "quality", "name": "音质", "type": "radio",
///    "options": [{"value": "std", "label": "标准"}, {"value": "hq", "label": "高清"}]},
///   {"key": "adFree", "name": "去广告", "type": "switch", "default": true}
/// ]
/// ```
/// 也可以由脚本运行时提供：`function getConfig() { return [...] }`，
/// App 在源详情页调用一次取回声明。
class ConfigField {
  /// 存值用的 key，同时用于插件侧读取（host.config[key]）
  final String key;

  /// 显示名
  final String name;

  /// text | textarea | password | number | switch | select | radio | action
  final String type;
  final String hint;
  final String desc;
  final dynamic defaultValue;
  final bool required;

  /// 静态选项
  final List<ConfigOption> options;

  /// 动态选项来源：voices / lines / 源里的任意方法名
  final String optionSource;

  /// action 类型点击时调用的源方法
  final String action;

  /// login 类型：网页登录地址
  final String loginUrl;

  /// login 类型：登录成功后跳到的地址（用于自动判定登录完成）
  final String successUrl;

  /// login 类型：登录后从这个地址读 Cookie（默认用 loginUrl 的 origin）
  final String cookieUrl;

  const ConfigField({
    required this.key,
    required this.name,
    this.type = 'text',
    this.hint = '',
    this.desc = '',
    this.defaultValue,
    this.required = false,
    this.options = const [],
    this.optionSource = '',
    this.action = '',
    this.loginUrl = '',
    this.successUrl = '',
    this.cookieUrl = '',
  });

  bool get isAction => type == 'action';
  bool get isLogin => type == 'login';
  bool get needsFetch => optionSource.isNotEmpty && options.isEmpty;

  /// 默认值（switch 一定是 bool，number 一定是 num）
  dynamic get initial {
    final d = defaultValue;
    if (type == 'switch') {
      if (d is bool) return d;
      if (d == null) return false;
      final s = '$d'.toLowerCase();
      return s == 'true' || s == '1' || s == 'yes' || s == 'on';
    }
    if (type == 'number') {
      if (d is num) return d;
      final n = num.tryParse('${d ?? ''}');
      return n ?? 0;
    }
    return d == null ? '' : '$d';
  }
}

/// 一份完整声明
class ConfigSchema {
  final List<ConfigField> fields;

  /// 声明来源：manifest | script | inferred | none
  final String origin;

  /// 源自己写的说明（可选）
  final String note;

  const ConfigSchema({
    this.fields = const [],
    this.origin = 'none',
    this.note = '',
  });

  bool get isEmpty => fields.isEmpty;
  static const empty = ConfigSchema();
}

// ---------------------------------------------------------------- 解析

const _keyNames = ['key', 'id', 'field', 'param', 'name', 'code'];
const _labelNames = [
  'label',
  'title',
  'text',
  'displayName',
  'name',
  'desc',
];

/// 把插件返回的声明归一化成 [ConfigSchema]。
///
/// 兼容写法：
/// - `[{ key, name, type, ... }]`
/// - `{ fields: [...] }` / `config` / `settings` / `params` / `items`
/// - `{ cookie: {...}, voice: {...} }`（map 当 key）
/// - 单条 `{ key, name }`
ConfigSchema parseConfigSchema(
  dynamic raw, {
  String origin = 'script',
  String note = '',
}) {
  final data = _decode(raw);
  if (data == null) return ConfigSchema(origin: 'none');

  List<dynamic>? list;

  if (data is List) {
    list = data;
  } else if (data is Map) {
    final m = Map<String, dynamic>.from(data);
    note = note.isNotEmpty ? note : _str(m, const ['note', 'desc', 'tip']) ?? '';

    for (final k in const [
      'fields',
      'config',
      'configs',
      'settings',
      'params',
      'items',
      'list',
      'options',
      'form',
    ]) {
      final v = m[k];
      if (v is List) {
        list = v;
        break;
      }
      // { config: { fields: [...] } }
      if (v is Map && v.values.any((e) => e is List)) {
        final inner = parseConfigSchema(v, origin: origin, note: note);
        if (!inner.isEmpty) return inner;
      }
    }

    if (list == null) {
      // 形如 { cookie: { name: '登录态' }, voice: {...} }
      final allMap = m.isNotEmpty && m.values.every((e) => e is Map);
      if (allMap) {
        list = m.entries
            .map((e) => {...Map<String, dynamic>.from(e.value as Map), 'key': e.key})
            .toList();
      } else if (m.containsKey('key') || m.containsKey('type')) {
        list = [m];
      }
    }
  }

  if (list == null) return ConfigSchema(origin: 'none');

  final fields = <ConfigField>[];
  final seen = <String>{};
  for (var i = 0; i < list.length; i++) {
    final f = _field(list[i], i);
    if (f == null) continue;
    if (!seen.add(f.key)) continue;
    fields.add(f);
  }
  return ConfigSchema(
    fields: fields,
    origin: fields.isEmpty ? 'none' : origin,
    note: note,
  );
}

/// 源没声明时按可用方法兜底：有 voices 给音色下拉，有 lines 给线路下拉
ConfigSchema inferredSchema({bool voices = false, bool lines = false}) {
  final fields = <ConfigField>[
    if (voices)
      const ConfigField(
        key: 'voiceId',
        name: '音色',
        type: 'select',
        optionSource: 'voices',
        desc: '该源支持多音色，选一个默认的',
      ),
    if (lines)
      const ConfigField(
        key: 'lineId',
        name: '线路',
        type: 'select',
        optionSource: 'lines',
        desc: '多线路源可指定默认线路，播放失败会换线路重试',
      ),
  ];
  return ConfigSchema(
    fields: fields,
    origin: fields.isEmpty ? 'none' : 'inferred',
    note: '该源没有声明配置项，这里按它提供的能力自动生成。',
  );
}

ConfigField? _field(dynamic e, int index) {
  if (e is String) {
    final s = e.trim();
    if (s.isEmpty) return null;
    return ConfigField(key: s, name: s, type: 'text');
  }
  if (e is! Map) return null;
  final m = Map<String, dynamic>.from(e);

  final key = _str(m, _keyNames) ?? 'field$index';
  var name = _str(m, _labelNames) ?? key;
  if (name == key) {
    name = _str(m, const ['title', 'label', 'text', 'desc']) ?? key;
  }

  final type = normalizeType(_str(m, const ['type', 'widget', 'inputType', 'kind']));
  final opts = _options(m);

  return ConfigField(
    key: key,
    name: name,
    type: type,
    hint: _str(m, const ['hint', 'placeholder', 'tip', 'tips']) ?? '',
    desc: _str(m, const ['desc', 'description', 'summary', 'help', 'remark']) ?? '',
    defaultValue: m['default'] ?? m['value'] ?? m['def'] ?? m['init'],
    required: m['required'] == true,
    options: opts,
    optionSource: _str(m, const ['source', 'from', 'optionsFrom', 'dynamic']) ?? '',
    action: _str(m, const ['action', 'command', 'method']) ?? '',
    loginUrl: _str(m, const ['url', 'loginUrl', 'loginURL', 'href', 'link']) ?? '',
    successUrl: _str(m, const ['successUrl', 'successURL', 'redirectUrl']) ?? '',
    cookieUrl: _str(m, const ['cookieUrl', 'cookieURL', 'domain']) ?? '',
  );
}

String normalizeType(String? raw) {
  final t = (raw ?? '').toLowerCase().trim();
  switch (t) {
    case 'text':
    case 'string':
    case 'str':
    case 'input':
    case 'edit':
      return 'text';
    case 'textarea':
    case 'multiline':
    case 'text-area':
    case 'longtext':
      return 'textarea';
    case 'password':
    case 'secret':
    case 'pwd':
      return 'password';
    case 'number':
    case 'int':
    case 'integer':
    case 'float':
    case 'digit':
      return 'number';
    case 'switch':
    case 'bool':
    case 'boolean':
    case 'checkbox':
    case 'toggle':
      return 'switch';
    case 'radio':
      return 'radio';
    case 'select':
    case 'dropdown':
    case 'choice':
    case 'enum':
    case 'picker':
    case 'single':
    case 'list':
      return 'select';
    case 'action':
    case 'button':
    case 'command':
      return 'action';
    case 'login':
    case 'webview':
    case 'web-login':
    case 'web_login':
    case 'oauth':
    case 'auth':
      return 'login';
    default:
      return 'text';
  }
}

List<ConfigOption> _options(Map<String, dynamic> m) {
  final raw = m['options'] ?? m['items'] ?? m['values'] ?? m['choices'];
  if (raw == null) return const [];
  if (raw is List) {
    final out = <ConfigOption>[];
    for (final e in raw) {
      if (e is Map) {
        final v = '${e['value'] ?? e['id'] ?? e['key'] ?? e['code'] ?? ''}';
        final l = '${e['label'] ?? e['name'] ?? e['title'] ?? e['text'] ?? v}';
        if (v.isEmpty && l.isEmpty) continue;
        out.add(ConfigOption(v.isEmpty ? l : v, l));
      } else if (e != null) {
        out.add(ConfigOption('$e', '$e'));
      }
    }
    return out;
  }
  if (raw is Map) {
    return raw.entries
        .map((e) => ConfigOption('${e.key}', '${e.value}'))
        .toList(growable: false);
  }
  return const [];
}

String? _str(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v == null) continue;
    if (v is Map || v is List) continue;
    final s = '$v'.trim();
    if (s.isNotEmpty && s != 'null') return s;
  }
  return null;
}

dynamic _decode(dynamic raw) {
  var v = raw;
  for (var i = 0; i < 3; i++) {
    if (v is! String) break;
    final t = v.trim();
    if (t.isEmpty) return null;
    if (!(t.startsWith('{') || t.startsWith('[') || t.startsWith('"'))) {
      return null;
    }
    try {
      v = jsonDecode(t);
    } catch (_) {
      return null;
    }
  }
  return v;
}
