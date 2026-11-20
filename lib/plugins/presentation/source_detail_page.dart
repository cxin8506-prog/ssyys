import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/path_utils.dart';
import '../../shared/widgets/common.dart';
import '../data/config_schema_loader.dart';
import '../data/plugin_providers.dart';
import '../data/source_config_schema.dart';
import '../data/web_session.dart';
import '../engine/jar_plugin_engine.dart';
import '../engine/js_plugin_engine.dart';
import '../engine/plugin_engine.dart';
import '../model/plugin_source.dart';
import 'login_web_page.dart';

/// 源详情：基本信息 + 源自己声明的配置项 + 试跑。
///
/// 这里**不再写死**「登录态 / 音色 / 视频线路」这类字段。
/// 配置项由源声明（manifest.json 的 config 字段，或脚本里的 getConfig()），
/// App 只按声明把对应的输入控件画出来，值统一存在 `source_configs.extra`。
class SourceDetailPage extends ConsumerStatefulWidget {
  final String sourceId;
  const SourceDetailPage({super.key, required this.sourceId});

  @override
  ConsumerState<SourceDetailPage> createState() => _SourceDetailPageState();
}

class _SourceDetailPageState extends ConsumerState<SourceDetailPage> {
  PluginSource? _source;
  SourceConfigModel? _cfg;

  ConfigSchema _schema = ConfigSchema.empty;
  bool _loading = true;
  bool _schemaLoading = true;
  bool _busy = false;
  String _busyText = '';
  bool _dirty = false;

  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, List<ConfigOption>> _options = {};
  final Set<String> _optionTried = {};

  final _testCtrl = TextEditingController(text: '斗破苍穹');
  String? _testResult;
  bool _testOk = true;
  bool _showSchemaHelp = false;

  /// 「我的听书」格式源的登录入口（查一次就够了，登录地址不会变）
  Future<Map<String, dynamic>?>? _tingShuLoginFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _testCtrl.dispose();
    super.dispose();
  }

  PluginEngine _engineFor(PluginSource s) => s.isTingShu

      ? ref.read(tingShuEngineProvider)

      : s.isJar

      ? ref.read(jarPluginEngineProvider)

      : ref.read(jsPluginEngineProvider);

  Future<void> _load() async {
    final repo = ref.read(sourceRepositoryProvider);
    final s = await repo.byId(widget.sourceId);
    if (s == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final cfg = await ref.read(sourceConfigRepositoryProvider).load(s.id, s.type);
    if (!mounted) return;
    setState(() {
      _source = s;
      _cfg = cfg;
      _loading = false;
    });
    await _loadSchema(s);
  }

  /// 向源要配置声明
  Future<void> _loadSchema(PluginSource s) async {
    setState(() => _schemaLoading = true);
    final engine = _engineFor(s);
    ConfigSchema schema;
    try {
      schema = await ref.read(configSchemaLoaderProvider).load(s, engine);
    } catch (e) {
      schema = ConfigSchema.empty;
      _toast('读取配置声明失败：$e');
    }
    if (!mounted) return;
    setState(() {
      _schema = schema;
      _schemaLoading = false;
    });
    _bindControllers();
    // 动态选项（音色/线路之类）静默预取一次
    for (final f in schema.fields) {
      if (f.needsFetch) {
        await _fetchOptions(s, f, silent: true);
      }
    }
  }

  /// 为文本类字段建控制器，值来自已保存的配置或声明的默认值
  void _bindControllers() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
    for (final f in _schema.fields) {
      if (f.type != 'text' &&
          f.type != 'textarea' &&
          f.type != 'password' &&
          f.type != 'number') {
        continue;
      }
      final init = _currentValue(f);
      final ctrl = TextEditingController(text: '${init ?? ''}');
      ctrl.addListener(() {
        final cfg = _cfg;
        if (cfg == null) return;
        cfg.values[f.key] = f.type == 'number'
            ? (num.tryParse(ctrl.text) ?? ctrl.text)
            : ctrl.text;
        if (!_dirty) setState(() => _dirty = true);
      });
      _ctrls[f.key] = ctrl;
    }
  }

  dynamic _currentValue(ConfigField f) {
    final v = _cfg?.values[f.key];
    if (v == null) return f.initial;
    return v;
  }

  Future<void> _save({bool silent = false}) async {
    final cfg = _cfg;
    if (cfg == null) return;
    for (final f in _schema.fields) {
      if (!f.required) continue;
      final v = cfg.values[f.key];
      if (v == null || '$v'.trim().isEmpty) {
        _toast('「${f.name}」是必填项');
        return;
      }
      if (f.type == 'number' && (num.tryParse('$v') == null)) {
        _toast('「${f.name}」需要填数字');
        return;
      }
    }
    cfg.hydrateLegacy();
    await ref.read(sourceConfigRepositoryProvider).save(cfg);
    if (!mounted) return;
    setState(() => _dirty = false);
    if (!silent) _toast('已保存');
  }

  /// 改一个非文本项（switch / select / radio）：立即落库
  Future<void> _setValue(ConfigField f, dynamic v) async {
    final cfg = _cfg;
    if (cfg == null) return;
    cfg.values[f.key] = v;
    cfg.syncLegacy(f.key, v);
    await ref.read(sourceConfigRepositoryProvider).save(cfg);
    if (!mounted) return;
    setState(() => _dirty = false);
  }

  Future<void> _fetchOptions(PluginSource s, ConfigField f,
      {bool silent = false}) async {
    if (_optionTried.contains(f.key) && silent) return;
    _optionTried.add(f.key);
    try {
      final list = await ref.read(configSchemaLoaderProvider).fetchOptions(
            s,
            _engineFor(s),
            f.optionSource,
          );
      if (!mounted) return;
      setState(() => _options[f.key] = list);
      final cfg = _cfg;
      if (cfg != null && list.isNotEmpty) {
        final cur = '${cfg.values[f.key] ?? ''}';
        if (cur.isEmpty) {
          cfg.values[f.key] = list.first.value;
          cfg.syncLegacy(f.key, list.first.value);
          await ref.read(sourceConfigRepositoryProvider).save(cfg);
          if (mounted) setState(() {});
        }
      }
      if (!silent) {
        _toast(list.isEmpty ? '源没有返回选项' : '已获取 ${list.length} 项');
      }
    } catch (e) {
      if (!silent) _toast('获取失败：$e');
    }
  }

  /// action 类型的配置项：点一下让源自己去执行（比如「扫码登录」）
  Future<void> _runAction(PluginSource s, ConfigField f) async {
    setState(() {
      _busy = true;
      _busyText = '正在执行「${f.name}」...';
    });
    try {
      final engine = _engineFor(s);
      await engine.attach(s);
      final r = await engine.invoke(
        f.action.isEmpty ? 'action' : f.action,
        params: {
          'key': f.key,
          'name': f.name,
          'config': _cfg?.values ?? {},
        },
      );
      final text = r is String ? r : jsonEncode(r);
      if (mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(f.name),
            content: SingleChildScrollView(
              child: Text(text.length > 1200 ? '${text.substring(0, 1200)}…' : text),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
            ],
          ),
        );
      }
    } catch (e) {
      _toast('执行失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- 构建

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final s = _source;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('源详情')),
        body: const Center(child: Text('这个源已被删除')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(s.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除源',
            onPressed: _delete,
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: pagePadding(context, bottom: _dirty ? 96 : 40),
            children: [
              _infoCard(s),
              if (s.isTingShu) ...[
                const SizedBox(height: 16),
                _tingShuLoginCard(s),
              ],
              const SizedBox(height: 16),
              _configCard(s),
              const SizedBox(height: 16),
              _testCard(s),
              if (s.isJar) ...[
                const SizedBox(height: 16),
                _jarCard(s),
              ],
              const SizedBox(height: 16),
              _schemaHelpCard(),
            ],
          ),
          if (_dirty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16 + MediaQuery.of(context).padding.bottom,
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => _save(),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('保存配置'),
                ),
              ),
            ),
          if (_busy)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 14),
                    Text(_busyText,
                        style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children, EdgeInsets? padding}) =>
      Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.palette.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _infoCard(PluginSource s) {
    final primary = Theme.of(context).colorScheme.primary;
    return _card(
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.palette.primarySoft,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon((s.isJar || s.isTingShu) ? Icons.archive_outlined : Icons.code,
                  color: primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    '${s.formatLabel} · v${s.version}'
                    '${s.author.isNotEmpty ? ' · ${s.author}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Switch(
              value: s.enabled,
              onChanged: (v) async {
                await ref.read(sourceRepositoryProvider).setEnabled(s.id, v);
                setState(() => s.enabled = v);
                ref.invalidate(sourceListProvider);
              },
            ),
          ],
        ),
        if (s.description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(s.description, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        Divider(height: 1, color: context.palette.outline),
        const SizedBox(height: 10),
        Row(
          children: [
            _kv('类型', s.isAudio ? '听书源' : '视频源'),
            const SizedBox(width: 20),
            _kv('大小', PathUtils.formatSize(s.sizeBytes)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _changeType(s),
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: Text(s.isAudio ? '改为视频源' : '改为听书源'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _rename(s),
                icon: const Icon(Icons.drive_file_rename_outline, size: 16),
                label: const Text('改名'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(v,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      );

  // ------------------------------------------------------ 源声明的配置项

  String get _originLabel {
    switch (_schema.origin) {
      case 'manifest':
        return '源声明 · manifest';
      case 'script':
        return '源声明 · 脚本';
      case 'inferred':
        return '按能力推断';
      default:
        return '源未声明';
    }
  }

  Widget _configCard(PluginSource s) {
    if (_schemaLoading) {
      return _card(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text('正在读取该源声明的配置项…',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      );
    }

    if (_schema.isEmpty) {
      return _card(
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: context.subtleColor),
              const SizedBox(width: 8),
              const Text('源配置',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: () => _loadSchema(s),
                child: const Text('重新读取'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '这个源没有可设置的项，装上就能直接用。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    return _card(
      children: [
        Row(
          children: [
            Icon(Icons.tune, size: 18, color: context.subtleColor),
            const SizedBox(width: 8),
            const Text('源配置',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: context.palette.surfaceAlt,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(_originLabel,
                  style: TextStyle(fontSize: 10, color: context.subtleColor)),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _loadSchema(s),
              child: const Text('刷新'),
            ),
          ],
        ),
        if (_schema.note.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(_schema.note, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 6),
        for (final f in _schema.fields) _fieldBlock(s, f),
      ],
    );
  }

  Widget _fieldBlock(PluginSource s, ConfigField f) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  f.required ? '${f.name} *' : f.name,
                  style:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if (f.optionSource.isNotEmpty)
                GestureDetector(
                  onTap: () => _fetchOptions(s, f),
                  child: Text('从源获取',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.primary)),
                ),
            ],
          ),
          if (f.desc.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(f.desc, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          _fieldInput(s, f),
        ],
      ),
    );
  }

  Widget _fieldInput(PluginSource s, ConfigField f) {
    switch (f.type) {
      case 'login':
        return _loginBlock(s, f);

      case 'switch':
        final on = _currentValue(f) == true;
        return Row(
          children: [
            Switch(
              value: on,
              onChanged: (v) => _setValue(f, v),
            ),
            const SizedBox(width: 6),
            Text(on ? '已开启' : '已关闭',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        );

      case 'radio':
        final cur = '${_currentValue(f) ?? ''}';
        final opts = _mergedOptions(f);
        if (opts.isEmpty) return _emptyOptions(f);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in opts)
              ChoiceChip(
                label: Text(o.label, style: const TextStyle(fontSize: 12)),
                selected: cur == o.value,
                onSelected: (_) => _setValue(f, o.value),
              ),
          ],
        );

      case 'select':
        final opts = _mergedOptions(f);
        if (opts.isEmpty) return _emptyOptions(f);
        final cur = '${_currentValue(f) ?? ''}';
        final valid = opts.any((o) => o.value == cur) ? cur : null;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: context.palette.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.palette.outline),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: valid,
              hint: Text('请选择',
                  style: TextStyle(fontSize: 13, color: context.subtleColor)),
              icon: const Icon(Icons.expand_more, size: 18),
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
              items: [
                for (final o in opts)
                  DropdownMenuItem(
                    value: o.value,
                    child: Text(o.label,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                if (v != null) _setValue(f, v);
              },
            ),
          ),
        );

      case 'action':
        return OutlinedButton.icon(
          onPressed: _busy ? null : () => _runAction(s, f),
          icon: const Icon(Icons.play_arrow, size: 16),
          label: Text(f.name),
        );

      case 'password':
      case 'textarea':
      case 'number':
      case 'text':
      default:
        return TextField(
          controller: _ctrls[f.key],
          maxLines: f.type == 'textarea' ? 4 : 1,
          minLines: f.type == 'textarea' ? 3 : 1,
          obscureText: f.type == 'password',
          keyboardType:
              f.type == 'number' ? TextInputType.number : TextInputType.text,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: f.hint.isEmpty ? null : f.hint,
            isDense: true,
          ),
        );
    }
  }

  /// 网页登录：点「去登录」开 WebView，登录完自动把 Cookie 存成配置值
  Widget _loginBlock(PluginSource s, ConfigField f) {
    final cookie = '${_cfg?.values[f.key] ?? ''}'.trim();
    final logged = cookie.isNotEmpty;
    final primary = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(logged ? Icons.verified_user : Icons.person_off_outlined,
                size: 16, color: logged ? primary : context.subtleColor),
            const SizedBox(width: 6),
            Text(
              logged ? '已登录' : '未登录',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: logged ? primary : null,
              ),
            ),
            if (logged) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  WebSession.mask(cookie),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _openLogin(s, f),
                icon: const Icon(Icons.login, size: 16),
                label: Text(logged ? '重新登录' : '去登录'),
              ),
            ),
            if (logged) ...[
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => _logout(s, f),
                child: const Text('退出登录'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _manualCookie(f),
            icon: const Icon(Icons.edit_note, size: 16),
            label: const Text('手动填写 Cookie'),
          ),
        ),
      ],
    );
  }

  Future<void> _openLogin(PluginSource s, ConfigField f) async {
    if (f.loginUrl.isEmpty) {
      _toast('这个源没有提供登录地址，只能在源里补 login，或手动填 Cookie');
      return;
    }
    // 青空次元的登录态是 localStorage 里的 sorani_auth_token，旧手机 WebView
    // 跑不动它的登录页时会黑屏，所以给一个手动粘贴 token 的入口。
    final isSorani = f.loginUrl.toLowerCase().contains('sorani');
    final cookie = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => LoginWebPage(
          title: s.name,
          url: f.loginUrl,
          successUrl: f.successUrl,
          cookieUrl: f.cookieUrl,
          tokenKey: isSorani ? 'sorani_auth_token' : '',
          tokenHint: isSorani
              ? '在电脑浏览器上打开青空次元并登录，然后按 F12 打开开发者工具，'
                  '在控制台输入 localStorage.getItem("sorani_auth_token")，'
                  '把引号里的那串字符复制过来粘贴进来。'
              : '',
        ),
      ),
    );
    if (cookie == null) return; // 用户关掉了登录页
    final cfg = _cfg;
    if (cfg == null) return;
    if (cookie.isEmpty) {
      _toast('没有拿到 Cookie，登录可能没完成');
      return;
    }
    // 手动 token：登录页以 TOKEN: 开头返回，存下来当登录态用
    if (cookie.startsWith('TOKEN:')) {
      final token = cookie.substring('TOKEN:'.length).trim();
      if (token.isEmpty) {
        _toast('Token 是空的，没保存');
        return;
      }
      cfg.values[f.key] = token;
      cfg.values['token'] = token;
      if (isSorani) cfg.values['sorani_auth_token'] = token;
      cfg.syncLegacy(f.key, token);
      await ref.read(sourceConfigRepositoryProvider).save(cfg);
      if (!mounted) return;
      setState(() {});
      _toast('Token 已保存，播放时会用它登录');
      return;
    }
    cfg.values[f.key] = cookie;
    cfg.syncLegacy(f.key, cookie);
    await ref.read(sourceConfigRepositoryProvider).save(cfg);
    if (!mounted) return;
    setState(() {});
    _toast('登录成功，Cookie 已同步给这个源');
  }

  Future<void> _logout(PluginSource s, ConfigField f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('会清掉这个源保存的 Cookie，下次看需要登录的内容要重新登录。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('退出')),
        ],
      ),
    );
    if (ok != true) return;
    final cfg = _cfg;
    if (cfg == null) return;
    cfg.values[f.key] = '';
    cfg.syncLegacy(f.key, '');
    await ref.read(sourceConfigRepositoryProvider).save(cfg);
    if (!mounted) return;
    setState(() {});
    _toast('已退出登录');
  }

  /// 「我的听书」格式源的登录：登录入口在源里（ILogin），
  /// 登录完 Cookie 直接留在 WebView 里，源请求时自己会带上，不用存配置。
  Widget _tingShuLoginCard(PluginSource s) {
    _tingShuLoginFuture ??= _tingShuLoginInfo(s);
    return FutureBuilder<Map<String, dynamic>?>(
      future: _tingShuLoginFuture,
      builder: (context, snap) {
        // 还在查登录入口：先占位，别闪一下空白
        if (snap.connectionState != ConnectionState.done) {
          return _card(
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text('正在读取登录入口…',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ],
          );
        }
        final info = snap.data;
        // 源没有提供登录入口：明确写出来，别留一块空白让人以为没加载完
        if (info == null) {
          return _card(
            children: [
              Row(
                children: [
                  Icon(Icons.login, size: 16, color: context.subtleColor),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('登录',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('这个源没有提供登录入口，不用登录就能用。',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          );
        }
        final url = '${info['url'] ?? ''}';
        if (url.isEmpty) return const SizedBox.shrink();
        final desktop = info['desktop'] == true;
        return _card(
          children: [
            Row(
              children: [
                const Icon(Icons.login, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('登录',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                FutureBuilder<String>(
                  future: WebSession().cookies(url),
                  builder: (context, csnap) {
                    final logged = WebSession.looksLoggedIn(csnap.data);
                    return Text(
                      logged ? '已登录' : '未登录',
                      style: TextStyle(
                        fontSize: 12,
                        color: logged
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _openTingShuLogin(s, url, desktop),
                    icon: const Icon(Icons.login, size: 16),
                    label: const Text('去登录'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => _logoutTingShu(),
                  child: const Text('退出登录'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _tingShuLoginInfo(PluginSource s) async {
    try {
      final engine = ref.read(tingShuEngineProvider);
      await engine.attach(s);
      return engine.loginInfo();
    } catch (_) {
      return null;
    }
  }

  Future<void> _openTingShuLogin(
      PluginSource s, String url, bool desktop) async {
    // 青空次元的登录态是 localStorage 里的 sorani_auth_token，旧手机 WebView
    // 跑不动它的登录页时会黑屏，所以给一个手动粘贴 token 的入口。
    final isSorani = url.toLowerCase().contains('sorani');
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => LoginWebPage(
          title: s.name,
          url: url,
          desktop: desktop,
          tokenKey: isSorani ? 'sorani_auth_token' : '',
          tokenHint: isSorani
              ? '在电脑浏览器上打开青空次元并登录，然后按 F12 打开开发者工具，'
                  '在控制台输入 localStorage.getItem("sorani_auth_token")，'
                  '把引号里的那串字符复制过来粘贴进来。'
              : '',
        ),
      ),
    );
    if (!mounted) return;
    // 手动 token：存进源配置（localStorage 里登录页已经写过一份了）
    if (result != null && result.startsWith('TOKEN:')) {
      final token = result.substring('TOKEN:'.length).trim();
      if (token.isNotEmpty) {
        try {
          final repo = ref.read(sourceConfigRepositoryProvider);
          final cfg = await repo.load(s.id, s.type);
          cfg.values['token'] = token;
          if (isSorani) cfg.values['sorani_auth_token'] = token;
          await repo.save(cfg);
        } catch (_) {}
        setState(() {});
        _toast('Token 已保存，播放时会用它登录');
        return;
      }
    }
    // 手动填 Cookie：登录页直接返回了 Cookie 字符串，同样存进源配置，
    // 别像以前那样只弹一句提示就把 Cookie 丢掉
    if (result != null && result.isNotEmpty) {
      try {
        final repo = ref.read(sourceConfigRepositoryProvider);
        final cfg = await repo.load(s.id, s.type);
        cfg.values['cookie'] = result;
        cfg.loginState = result;
        await repo.save(cfg);
      } catch (_) {}
      setState(() {});
      _toast('登录成功，Cookie 已同步给这个源');
      return;
    }
    setState(() {});
    _toast('登录页已关闭，Cookie 已同步给这个源');
  }

  Future<void> _logoutTingShu() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('会清掉这个源保存的 Cookie，下次看需要登录的内容要重新登录。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('退出')),
        ],
      ),
    );
    if (ok != true) return;
    await WebSession().clear();
    if (!mounted) return;
    setState(() {});
    _toast('已退出登录');
  }

  Future<void> _manualCookie(ConfigField f) async {
    final ctrl = TextEditingController(text: '${_cfg?.values[f.key] ?? ''}');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动填写 Cookie'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('从浏览器登录后，复制请求里的 Cookie 整段粘进来。',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 6,
              minLines: 4,
              decoration: const InputDecoration(hintText: 'key=value; key2=value2'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (v == null) return;
    final cfg = _cfg;
    if (cfg == null) return;
    cfg.values[f.key] = v;
    cfg.syncLegacy(f.key, v);
    await ref.read(sourceConfigRepositoryProvider).save(cfg);
    if (!mounted) return;
    setState(() {});
    _toast(v.isEmpty ? '已清空 Cookie' : 'Cookie 已保存');
  }

  Widget _emptyOptions(ConfigField f) {    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        f.optionSource.isEmpty
            ? '暂无可选项'
            : '暂无，点右上「从源获取」或确认源已登录',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  /// 静态选项 + 动态取到的选项合并；当前值不在列表里时补一条，避免下拉报错
  List<ConfigOption> _mergedOptions(ConfigField f) {
    final out = <ConfigOption>[...f.options];
    for (final o in _options[f.key] ?? const <ConfigOption>[]) {
      if (!out.any((e) => e.value == o.value)) out.add(o);
    }
    final cur = '${_currentValue(f) ?? ''}';
    if (cur.isNotEmpty && !out.any((e) => e.value == cur)) {
      out.insert(0, ConfigOption(cur, cur));
    }
    return out;
  }

  Widget _schemaHelpCard() {
    return _card(
      children: [
        InkWell(
          onTap: () => setState(() => _showSchemaHelp = !_showSchemaHelp),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: context.subtleColor),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('配置项是从源来的',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Icon(
                  _showSchemaHelp ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: context.subtleColor),
            ],
          ),
        ),
        if (_showSchemaHelp) ...[
          const SizedBox(height: 10),
          Text(
            '源在 manifest.json 里写 config，或脚本里提供 getConfig()，'
            'App 就按声明画出上面这些输入框，不再固定只有登录态/音色/线路。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.palette.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _schemaSample,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                fontFamily: 'monospace',
                color: context.subtleColor,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static const String _schemaSample = '''"config": [
  {"key": "cookie", "name": "登录态", "type": "textarea",
   "hint": "token=xxx; uid=123"},
  {"key": "voiceId", "name": "音色", "type": "select",
   "source": "voices"},
  {"key": "lineId", "name": "线路", "type": "select",
   "source": "lines"},
  {"key": "quality", "name": "音质", "type": "radio",
   "options": [{"value":"std","label":"标准"},
               {"value":"hq","label":"高清"}]},
  {"key": "adFree", "name": "去广告", "type": "switch",
   "default": true}
]''';

  // ---------------------------------------------------------------- 试跑

  Widget _testCard(PluginSource s) {
    return _card(
      children: [
        Row(
          children: [
            Icon(Icons.play_circle_outline,
                size: 18, color: context.subtleColor),
            const SizedBox(width: 8),
            const Text('试跑',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        Text('用上面的配置调用一次搜索，确认源能正常出结果。',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _testCtrl,
                decoration:
                    const InputDecoration(hintText: '关键词', isDense: true),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _busy ? null : () => _runTest(s),
              child: const Text('测试'),
            ),
          ],
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.palette.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _testResult!,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: _testOk
                    ? Theme.of(context).textTheme.bodyMedium?.color
                    : Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _jarCard(PluginSource s) {
    return _card(
      children: [
        Row(
          children: [
            Icon(Icons.memory, size: 18, color: context.subtleColor),
            const SizedBox(width: 8),
            const Text('JAR 主类',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(onPressed: _editMainClass, child: const Text('修改')),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          s.entry.isEmpty ? '未识别到主类。若调用失败，请手动填写入口类名。' : s.entry,
          style: TextStyle(
              fontSize: 12,
              color: s.entry.isEmpty
                  ? Theme.of(context).colorScheme.error
                  : context.subtleColor),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- 操作

  Future<void> _runTest(PluginSource s) async {
    setState(() {
      _busy = true;
      _busyText = '正在调用源搜索...';
      _testResult = null;
    });
    try {
      // 先把当前填的值落库，试跑就用新配置
      if (_dirty) await _save(silent: true);
      final engine = _engineFor(s);
      await engine.attach(s);
      final raw = await engine.invoke('search',
          params: {'keyword': _testCtrl.text.trim(), 'page': 1});
      final list = raw is List ? raw : (raw is Map ? [raw] : <dynamic>[]);
      final buffer = StringBuffer();
      buffer.writeln('成功返回 ${list.length} 条结果');
      for (final e in list.take(3)) {
        if (e is Map) {
          buffer.writeln('· ${e['name'] ?? e['title'] ?? e['bookName'] ?? '(无标题)'}');
        } else {
          buffer.writeln('· $e');
        }
      }
      if (list.isEmpty) {
        buffer.writeln('（返回空，可能是关键词无结果或配置不对）');
        buffer.writeln(_preview(raw));
      }
      setState(() {
        _testOk = list.isNotEmpty;
        _testResult = buffer.toString().trim();
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = '调用失败：\n${_friendlyError('$e')}';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 把底层异常翻译成能看懂的原因
  String _friendlyError(String msg) {
    if (msg.contains('Failed resolution of') ||
        msg.contains('NoClassDefFoundError') ||
        msg.contains('ClassNotFoundException')) {
      final m = RegExp(r'L([\w/$]+);').firstMatch(msg);
      final cls = m == null ? '' : '${m.group(1)}'.replaceAll('/', '.');
      return '这个 JAR 插件依赖「我的听书」宿主里的类'
          '${cls.isEmpty ? '' : '（$cls）'}，\n'
          '单独加载时会找不到父类，所以调不起来。\n'
          '需要给这个插件补一份宿主兼容层，或者换用 JS/ZIP 版本的源。';
    }
    if (msg.contains('METHOD_NOT_FOUND') || msg.contains('未实现')) {
      return '这个源没有实现对应的方法（搜索/目录/播放地址）。';
    }
    if (msg.contains('SocketException') || msg.contains('TimeoutException')) {
      return '网络不通或超时：$msg';
    }
    return msg;
  }

  String _preview(dynamic raw) {
    try {
      final s = raw is String ? raw : jsonEncode(raw);
      return s.length > 300 ? '${s.substring(0, 300)}...' : s;
    } catch (_) {
      return '';
    }
  }

  Future<void> _rename(PluginSource s) async {
    final ctrl = TextEditingController(text: s.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('源名称'),
        content: TextField(controller: ctrl),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref.read(sourceRepositoryProvider).rename(s.id, name);
    await _load();
    ref.invalidate(sourceListProvider);
  }

  Future<void> _changeType(PluginSource s) async {
    final repo = ref.read(sourceRepositoryProvider);
    final all = await repo.loadAll();
    final i = all.indexWhere((e) => e.id == s.id);
    if (i < 0) return;
    all[i] = all[i].copyWith(type: s.isAudio ? 'video' : 'audio');
    await repo.saveAll(all);
    await _load();
    ref.invalidate(sourceListProvider);
    _toast('已切换类型');
  }

  Future<void> _editMainClass() async {
    final s = _source!;
    final ctrl = TextEditingController(text: s.entry);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('JAR 主类'),
        content: TextField(
          controller: ctrl,
          decoration:
              const InputDecoration(hintText: '例如 com.example.BookSource'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (v == null) return;
    await _setMainClass(v);
  }

  Future<void> _setMainClass(String cls) async {
    final repo = ref.read(sourceRepositoryProvider);
    final all = await repo.loadAll();
    for (var i = 0; i < all.length; i++) {
      if (all[i].id == widget.sourceId) {
        all[i] = PluginSource(
          id: all[i].id,
          name: all[i].name,
          type: all[i].type,
          format: all[i].format,
          version: all[i].version,
          author: all[i].author,
          description: all[i].description,
          entry: cls,
          icon: all[i].icon,
          enabled: all[i].enabled,
          installedAt: all[i].installedAt,
          sizeBytes: all[i].sizeBytes,
        );
      }
    }
    await repo.saveAll(all);
    await _load();
    _toast('主类已更新');
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除源'),
        content: const Text('会同时删除该源已填的配置，确定？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(sourceRepositoryProvider).remove(widget.sourceId);
    await ref.read(sourceConfigRepositoryProvider).clear(widget.sourceId);
    ref.invalidate(sourceListProvider);
    if (mounted) Navigator.of(context).pop();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }
}
