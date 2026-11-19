import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/path_utils.dart';
import '../data/plugin_providers.dart';
import '../engine/jar_plugin_engine.dart';
import '../engine/js_plugin_engine.dart';
import '../engine/plugin_engine.dart';
import '../model/plugin_source.dart';
import '../../shared/widgets/common.dart';

/// 源详情：基本信息 + 登录态 + 音色 + 线路 + 试跑测试
class SourceDetailPage extends ConsumerStatefulWidget {
  final String sourceId;
  const SourceDetailPage({super.key, required this.sourceId});

  @override
  ConsumerState<SourceDetailPage> createState() => _SourceDetailPageState();
}

class _SourceDetailPageState extends ConsumerState<SourceDetailPage> {
  PluginSource? _source;
  SourceConfigModel? _cfg;
  List<String> _jarClasses = [];
  bool _loading = true;
  bool _busy = false;
  String _busyText = '';

  final _loginCtrl = TextEditingController();
  final _testCtrl = TextEditingController(text: '斗破苍穹');
  String? _testResult;
  bool _testOk = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _loginCtrl.dispose();
    _testCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(sourceRepositoryProvider);
    final s = await repo.byId(widget.sourceId);
    if (s == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final cfg = await ref
        .read(sourceConfigRepositoryProvider)
        .load(s.id, s.type);
    _loginCtrl.text = cfg.loginState ?? '';
    if (!mounted) return;
    setState(() {
      _source = s;
      _cfg = cfg;
      _loading = false;
    });
    if (s.isJar) {
      final jar = ref.read(jarPluginEngineProvider);
      try {
        await jar.attach(s);
        final list = await jar.listClasses();
        if (mounted) setState(() => _jarClasses = list);
      } catch (_) {}
    }
  }

  PluginEngine _engineFor(PluginSource s) =>
      s.isJar ? ref.read(jarPluginEngineProvider) : ref.read(jsPluginEngineProvider);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
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
            padding: pagePadding(context, bottom: 40),
            children: [
              _infoCard(s),
              const SizedBox(height: 16),
              _loginCard(s),
              const SizedBox(height: 16),
              _listCard(
                s,
                title: '音色',
                subtitle: '番茄一类源支持多音色，选一个默认的',
                items: _cfg?.voices ?? [],
                selected: _cfg?.selectedVoiceId,
                method: 'voices',
                onSelect: (id) {
                  _cfg!.selectedVoiceId = id;
                  _saveCfg();
                },
                onAdd: () => _addItem(isVoice: true),
                onFetch: () => _fetchItems(s, isVoice: true),
              ),
              const SizedBox(height: 16),
              _listCard(
                s,
                title: '视频线路',
                subtitle: '多线路源可手动切换，播放失败时换线路重试',
                items: _cfg?.lines ?? [],
                selected: _cfg?.selectedLineId,
                method: 'lines',
                onSelect: (id) {
                  _cfg!.selectedLineId = id;
                  _saveCfg();
                },
                onAdd: () => _addItem(isVoice: false),
                onFetch: () => _fetchItems(s, isVoice: false),
              ),
              if (s.isJar) ...[
                const SizedBox(height: 16),
                _jarCard(s),
              ],
              const SizedBox(height: 16),
              _testCard(s),
            ],
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

  // ---------------------------------------------------------------- 卡片

  Widget _card({required List<Widget> children, EdgeInsets? padding}) => Container(
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
              child: Icon(s.isJar ? Icons.archive_outlined : Icons.code,
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

  Widget _loginCard(PluginSource s) {
    return _card(
      children: [
        Row(
          children: [
            Icon(Icons.lock_outline, size: 18, color: context.subtleColor),
            const SizedBox(width: 8),
            const Text('登录态',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(
              onPressed: () => _saveLogin(s),
              child: const Text('保存'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '部分源需要登录才能拿到内容。把 Cookie 或 token 粘贴到下面，'
          '格式由源自己解释（一般是 key=value; key2=value2）。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _loginCtrl,
          maxLines: 4,
          minLines: 3,
          decoration: const InputDecoration(hintText: '例如：token=xxxx; uid=123456'),
        ),
      ],
    );
  }

  Widget _listCard(
    PluginSource s, {
    required String title,
    required String subtitle,
    required List<Map<String, dynamic>> items,
    required String? selected,
    required String method,
    required void Function(String id) onSelect,
    required VoidCallback onAdd,
    required VoidCallback onFetch,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return _card(
      children: [
        Row(
          children: [
            Icon(Icons.tune, size: 18, color: context.subtleColor),
            const SizedBox(width: 8),
            Text(title,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(
              onPressed: _busy ? null : onFetch,
              child: const Text('从源获取'),
            ),
          ],
        ),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: context.palette.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('暂无，可点「从源获取」或手动添加',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          )
        else
          ...items.map((item) {
            final id = '${item['id']}';
            final name = '${item['name'] ?? id}';
            final sel = selected == id;
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onSelect(id),
              onLongPress: () => _removeItem(items, item),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: sel ? context.palette.primarySoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: sel ? primary : context.palette.outline),
                ),
                child: Row(
                  children: [
                    Icon(
                        sel
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: sel ? primary : context.palette.outline),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(name,
                            style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('手动添加'),
          ),
        ),
      ],
    );
  }

  Widget _jarCard(PluginSource s) {
    final current = s.entry;
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
          current.isEmpty
              ? '未识别到主类。若调用失败，请手动填写入口类名。'
              : current,
          style: TextStyle(
              fontSize: 12,
              color: current.isEmpty
                  ? Theme.of(context).colorScheme.error
                  : context.subtleColor),
        ),
        if (_jarClasses.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('包内类（${_jarClasses.length}）',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _jarClasses.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ActionChip(
                label: Text(
                  _jarClasses[i].split('.').last,
                  style: const TextStyle(fontSize: 11),
                ),
                onPressed: () => _setMainClass(_jarClasses[i]),
              ),
            ),
          ),
        ],
      ],
    );
  }

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
        Text('用关键词调用一次搜索，确认源能正常出结果。',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _testCtrl,
                decoration: const InputDecoration(
                    hintText: '关键词', isDense: true),
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

  // ---------------------------------------------------------------- 操作

  Future<void> _saveCfg() async {
    final cfg = _cfg;
    if (cfg == null) return;
    await ref.read(sourceConfigRepositoryProvider).save(cfg);
    setState(() {});
    _toast('已保存');
  }

  Future<void> _saveLogin(PluginSource s) async {
    final cfg = _cfg;
    if (cfg == null) return;
    cfg.loginState = _loginCtrl.text.trim();
    await ref.read(sourceConfigRepositoryProvider).save(cfg);
    _toast('登录态已保存');
  }

  Future<void> _fetchItems(PluginSource s, {required bool isVoice}) async {
    setState(() {
      _busy = true;
      _busyText = '正在从源获取${isVoice ? '音色' : '线路'}...';
    });
    try {
      final engine = _engineFor(s);
      await engine.attach(s);
      final raw = await engine.invoke(isVoice ? 'voices' : 'lines',
          params: {'url': ''});
      final list = _normalizeList(raw);
      if (list.isEmpty) {
        _toast('源没有返回${isVoice ? '音色' : '线路'}列表');
      } else {
        final cfg = _cfg!;
        if (isVoice) {
          cfg.voices = list;
          cfg.selectedVoiceId ??= '${list.first['id']}';
        } else {
          cfg.lines = list;
          cfg.selectedLineId ??= '${list.first['id']}';
        }
        await ref.read(sourceConfigRepositoryProvider).save(cfg);
        setState(() {});
        _toast('已获取 ${list.length} 条');
      }
    } catch (e) {
      _toast('获取失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _normalizeList(dynamic raw) {
    if (raw == null) return [];
    final out = <Map<String, dynamic>>[];
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final e = raw[i];
        if (e is Map) {
          out.add({
            'id': '${e['id'] ?? e['key'] ?? i}',
            'name': '${e['name'] ?? e['title'] ?? e['id'] ?? '选项${i + 1}'}',
          });
        } else if (e != null) {
          out.add({'id': '$i', 'name': '$e'});
        }
      }
    } else if (raw is Map) {
      raw.forEach((k, v) {
        out.add({'id': '$k', 'name': '$v'});
      });
    }
    return out;
  }

  Future<void> _addItem({required bool isVoice}) async {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isVoice ? '添加音色' : '添加线路'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '显示名称'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: idCtrl,
              decoration: const InputDecoration(
                  labelText: '源内 id（可留空，默认用名称）'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('添加')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    final id = idCtrl.text.trim().isEmpty ? name : idCtrl.text.trim();
    final cfg = _cfg!;
    final item = <String, dynamic>{'id': id, 'name': name};
    if (isVoice) {
      cfg.voices = [...cfg.voices, item];
      cfg.selectedVoiceId ??= id;
    } else {
      cfg.lines = [...cfg.lines, item];
      cfg.selectedLineId ??= id;
    }
    await ref.read(sourceConfigRepositoryProvider).save(cfg);
    setState(() {});
  }

  Future<void> _removeItem(
      List<Map<String, dynamic>> items, Map<String, dynamic> item) async {
    final cfg = _cfg!;
    items.remove(item);
    if (cfg.selectedVoiceId == '${item['id']}') cfg.selectedVoiceId = null;
    if (cfg.selectedLineId == '${item['id']}') cfg.selectedLineId = null;
    await ref.read(sourceConfigRepositoryProvider).save(cfg);
    setState(() {});
  }

  Future<void> _runTest(PluginSource s) async {
    setState(() {
      _busy = true;
      _busyText = '正在调用源搜索...';
      _testResult = null;
    });
    try {
      final engine = _engineFor(s);
      await engine.attach(s);
      final raw = await engine.invoke('search',
          params: {'keyword': _testCtrl.text.trim(), 'page': 1});
      final list = raw is List ? raw : (raw is Map ? [raw] : <dynamic>[]);
      final buffer = StringBuffer();
      buffer.writeln('成功返回 ${list.length} 条结果');
      for (final e in list.take(3)) {
        if (e is Map) {
          buffer.writeln(
              '· ${e['name'] ?? e['title'] ?? e['bookName'] ?? '(无标题)'}');
        } else {
          buffer.writeln('· $e');
        }
      }
      if (list.isEmpty) {
        buffer.writeln('（返回空，可能是关键词无结果或插件需登录）');
        buffer.writeln(_preview(raw));
      }
      setState(() {
        _testOk = list.isNotEmpty;
        _testResult = buffer.toString().trim();
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = '调用失败：\n$e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
        content: const Text('会同时删除该源的配置（登录态/音色/线路），确定？'),
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
    await ref
        .read(sourceConfigRepositoryProvider)
        .clear(widget.sourceId);
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
