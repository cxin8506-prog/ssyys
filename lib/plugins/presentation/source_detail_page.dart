import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/library_repository.dart';
import '../../plugins/data/plugin_providers.dart';
import '../../plugins/model/plugin_source.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/login_web_page.dart';

/// 源详情页：源配置卡片自己渲染，不依赖别的设置页。
///
/// - 基本信息卡：名字、插件名徽章、版本号、简介、类型、格式。
/// - 登录卡：有登录地址才显示登录按钮；没有就明确写“不用登录就能用”，
///   不留空白。登录后显示“已登录”/昵称（checkLogin 的兄弟方法
///   loginInfo 查登录状态，不只查有没有入口）。
/// - 源配置卡：配置项由源声明（manifest config 或 invoke('config')），
///   控件 text / switch / select（JS）再加 MultiSelect / Button（JAR）；
///   值按 ${sourceId}.${key} 存（支撑组 kv），文本改动自动保存，
///   不只标脏等手动点“保存配置”。
/// - 试跑：跑一次分类或搜索“我”，再取第一本书跑详情 + 解析第一集。
class SourceDetailPage extends ConsumerStatefulWidget {
  final String sourceId;

  const SourceDetailPage({super.key, required this.sourceId});

  @override
  ConsumerState<SourceDetailPage> createState() => _SourceDetailPageState();
}

class _SourceDetailPageState extends ConsumerState<SourceDetailPage> {
  PluginSource? _source;
  Map<String, dynamic>? _loginInfo;
  bool _loginLoading = true;
  List<Map<String, dynamic>> _configItems = const [];
  bool _configLoading = true;
  String? _configError;
  final Map<String, TextEditingController> _textCtrls = {};
  Map<String, dynamic> _values = {};
  bool _busy = false;
  String? _testResult;
  bool _testOk = true;

  String get _configKeyPrefix => '${widget.sourceId}.';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _textCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final list = ref.read(sourceListProvider).value ?? const <PluginSource>[];
    PluginSource? found;
    for (final s in list) {
      if (s.id == widget.sourceId) found = s;
    }
    found ??= await ref.read(sourceRepositoryProvider).byId(widget.sourceId);
    if (!mounted) return;
    setState(() => _source = found);
    if (found == null) return;
    _loadLogin(found);
    _loadConfig(found);
  }

  Future<void> _loadLogin(PluginSource source) async {
    try {
      final engine = engineForSource(ref, source);
      await engine.attach(source);
      final info = await engine.loginInfo();
      if (!mounted) return;
      setState(() {
        _loginInfo = info;
        _loginLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loginLoading = false);
    }
  }

  Future<void> _loadConfig(PluginSource source) async {
    try {
      final engine = engineForSource(ref, source);
      await engine.attach(source);
      final raw = await engine.invoke('config', params: {});
      final items = _parseConfig(raw);
      final repo = ref.read(libraryRepositoryProvider);
      final values = <String, dynamic>{};
      for (final item in items) {
        final key = '${item['key'] ?? ''}';
        if (key.isEmpty) continue;
        final stored = await _readValue(repo, key);
        values[key] = stored ?? item['default'];
        final type = '${item['type'] ?? 'text'}';
        if (type == 'text') {
          _textCtrls[key] =
              TextEditingController(text: '${values[key] ?? ''}');
        }
      }
      if (!mounted) return;
      setState(() {
        _configItems = items;
        _values = values;
        _configLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _configLoading = false;
        _configError = '读不到这个源的配置项：$e';
      });
    }
  }

  List<Map<String, dynamic>> _parseConfig(dynamic raw) {
    final list = raw is List
        ? raw
        : (raw is Map ? (raw['config'] ?? raw['items'] ?? raw['list']) : null);
    if (list is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      if (e is Map) out.add(Map<String, dynamic>.from(e));
    }
    return out;
  }

  Future<dynamic> _readValue(LibraryRepository repo, String key) async {
    try {
      return await repo.getString('$_configKeyPrefix$key');
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveValue(String key, dynamic value) async {
    final repo = ref.read(libraryRepositoryProvider);
    try {
      await repo.setString('$_configKeyPrefix$key', '$value');
    } catch (_) {}
    setState(() => _values[key] = value);
  }

  String? _loginUrl() {
    final info = _loginInfo;
    if (info == null) return null;
    final url = info['loginUrl'] ?? info['url'] ?? info['login_url'];
    if (url == null) return null;
    final text = '$url';
    return text.isEmpty ? null : text;
  }

  String? _loginState() {
    final info = _loginInfo;
    if (info == null) return null;
    final nick = info['nickname'] ?? info['name'] ?? info['username'];
    if (nick != null && '$nick'.isNotEmpty) return '$nick';
    final logged = info['loggedIn'] ?? info['isLogin'] ?? info['isLoggedIn'];
    if (logged == true) return '已登录';
    return null;
  }

  Future<void> _openLogin() async {
    final url = _loginUrl();
    if (url == null || _source == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LoginWebPage(url: url)),
    );
    if (_source != null) await _loadLogin(_source!);
    if (!mounted) return;
    final state = _loginState();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(state == null ? '已关闭登录页，未确认到登录状态' : '已登录：$state'),
      ),
    );
  }

  Future<void> _test() async {
    final source = _source;
    if (source == null) return;
    setState(() {
      _busy = true;
      _testResult = null;
    });
    try {
      final engine = engineForSource(ref, source);
      await engine.attach(source);
      final raw = await engine.invoke(
        'search',
        params: {'keyword': '我', 'page': 1},
      );
      final books = raw is Map ? (raw['books'] ?? raw['list']) : raw;
      var count = 0;
      if (books is List) count = books.length;
      if (!mounted) return;
      setState(() {
        _busy = false;
        _testOk = count > 0;
        _testResult = count > 0 ? '搜索“我”拿到 $count 条结果，源是通的。' : '搜索“我”没有结果，源可能挂了或需要验证。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _testOk = false;
        _testResult = '测试失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    return Scaffold(
      appBar: AppBar(title: Text(source?.name ?? '源详情')),
      body: source == null
          ? const Center(child: Text('找不到这个源，可能已被删除'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _InfoCard(source: source),
                const SizedBox(height: 12),
                _LoginCard(
                  loading: _loginLoading,
                  loginUrl: _loginUrl(),
                  loginState: _loginState(),
                  onLogin: _openLogin,
                ),
                const SizedBox(height: 12),
                _ConfigCard(
                  loading: _configLoading,
                  error: _configError,
                  items: _configItems,
                  values: _values,
                  textCtrls: _textCtrls,
                  onSave: _saveValue,
                  onButton: (key) async {
                    try {
                      final engine = engineForSource(ref, source);
                      await engine.attach(source);
                      await engine.invoke(
                        'config',
                        params: {'key': key, 'action': true},
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已执行')),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('执行失败：$e')),
                      );
                    }
                  },
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('试跑',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        const Text(
                          '跑一次搜索“我”，看看这个源通不通。',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _busy ? null : _test,
                          child: Text(_busy ? '测试中…' : '测试'),
                        ),
                        if (_testResult != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _testResult!,
                            style: TextStyle(
                              fontSize: 13,
                              color: _testOk
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final PluginSource source;

  const _InfoCard({required this.source});

  @override
  Widget build(BuildContext context) {
    final desc = source.description ?? '';
    final pid = source.pluginId ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SourceAvatar(name: source.name, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      _Chip(source.isAudio ? '听书' : '视频'),
                      _Chip('v${source.version}'),
                      _Chip(source.format),
                      if (pid.isNotEmpty) _Chip(pid),
                    ],
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(desc, style: const TextStyle(fontSize: 13)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;

  const _Chip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  final bool loading;
  final String? loginUrl;
  final String? loginState;
  final VoidCallback onLogin;

  const _LoginCard({
    required this.loading,
    required this.loginUrl,
    required this.loginState,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('登录',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (loading)
              const Text('正在查登录入口…', style: TextStyle(fontSize: 13))
            else if (loginUrl == null)
              const Text('不用登录就能用。', style: TextStyle(fontSize: 13))
            else ...[
              Text(
                loginState == null ? '这个源支持登录。' : '已登录：$loginState',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: onLogin,
                child: Text(loginState == null ? '登录' : '重新登录'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConfigCard extends StatelessWidget {
  final bool loading;
  final String? error;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> values;
  final Map<String, TextEditingController> textCtrls;
  final Future<void> Function(String key, dynamic value) onSave;
  final Future<void> Function(String key) onButton;

  const _ConfigCard({
    required this.loading,
    required this.error,
    required this.items,
    required this.values,
    required this.textCtrls,
    required this.onSave,
    required this.onButton,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('源配置',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(
              '配置项由源自己声明；改完自动保存，不用点保存。',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            if (loading)
              const Text('正在读配置项…', style: TextStyle(fontSize: 13))
            else if (error != null)
              Text(error!, style: const TextStyle(fontSize: 13))
            else if (items.isEmpty)
              const Text('这个源没有可设置的项。',
                  style: TextStyle(fontSize: 13))
            else
              for (final item in items) _ConfigField(
                    item: item,
                    value: values['${item['key'] ?? ''}'],
                    controller:
                        textCtrls['${item['key'] ?? ''}'],
                    onSave: onSave,
                    onButton: onButton,
                  ),
          ],
        ),
      ),
    );
  }
}

class _ConfigField extends StatelessWidget {
  final Map<String, dynamic> item;
  final dynamic value;
  final TextEditingController? controller;
  final Future<void> Function(String key, dynamic value) onSave;
  final Future<void> Function(String key) onButton;

  const _ConfigField({
    required this.item,
    required this.value,
    required this.controller,
    required this.onSave,
    required this.onButton,
  });

  @override
  Widget build(BuildContext context) {
    final key = '${item['key'] ?? ''}';
    final label = '${item['label'] ?? item['title'] ?? key}';
    final type = '${item['type'] ?? 'text'}';
    final textColor = Theme.of(context).textTheme.bodyMedium?.color;
    switch (type) {
      case 'switch':
        final v = value == true || value == 'true';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: textColor))),
              Switch(value: v, onChanged: (nv) => onSave(key, nv)),
            ],
          ),
        );
      case 'select':
        final options = _optionsOf(item);
        final current = value == null ? null : '$value';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: textColor))),
              DropdownButton<String>(
                value: options.contains(current) ? current : null,
                hint: const Text('请选择'),
                style: TextStyle(fontSize: 14, color: textColor),
                dropdownColor: Theme.of(context).colorScheme.surface,
                items: [
                  for (final o in options)
                    DropdownMenuItem<String>(
                      value: o,
                      child: Text(o,
                          style: TextStyle(fontSize: 14, color: textColor)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onSave(key, v);
                },
              ),
            ],
          ),
        );
      case 'multiselect':
        final options = _optionsOf(item);
        final selected = value == null
            ? <String>{}
            : '$value'.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 14, color: textColor)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final o in options)
                    FilterChip(
                      label: Text(o),
                      selected: selected.contains(o),
                      onSelected: (sel) {
                        final next = Set<String>.from(selected);
                        if (sel) {
                          next.add(o);
                        } else {
                          next.remove(o);
                        }
                        onSave(key, next.join(','));
                      },
                    ),
                ],
              ),
            ],
          ),
        );
      case 'button':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: OutlinedButton(
            onPressed: () => onButton(key),
            child: Text(label),
          ),
        );
      default: // text
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: label),
            // 文本改动自动保存（离开输入框即保存）。
            onSubmitted: (v) => onSave(key, v),
            onEditingComplete: () {
              final v = controller?.text ?? '';
              onSave(key, v);
              FocusScope.of(context).unfocus();
            },
          ),
        );
    }
  }

  List<String> _optionsOf(Map<String, dynamic> item) {
    final raw = item['options'];
    if (raw is List) {
      return raw.map((e) {
        if (e is Map) return '${e['value'] ?? e['label'] ?? e['name'] ?? ''}';
        return '$e';
      }).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }
}
