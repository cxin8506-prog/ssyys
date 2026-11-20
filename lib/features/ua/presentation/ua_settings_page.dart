import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../ua_constants.dart';
import '../ua_repository.dart';
import '../ua_resolver.dart';

/// UA 设置页：只存两条当前值（手机一条、电脑一条），两个文本框可改；
/// 内置推荐是筛过的（主流、真实、不容易被站方发现是伪造的），分手机/电脑两栏；
/// 规则表用户可增删改、每条可开关；按站记忆可逐条清除。
///
/// TabBar 颜色钉死白色（AppBar 底色是主题 primary，绝不许用 primary 色当选中色，
/// 否则字在 primary 底色上看不见——旧审计 B 第 10.1 项）。
class UaSettingsPage extends ConsumerStatefulWidget {
  const UaSettingsPage({super.key});

  @override
  ConsumerState<UaSettingsPage> createState() => _UaSettingsPageState();
}

class _UaSettingsPageState extends ConsumerState<UaSettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _desktopCtrl = TextEditingController();

  bool _autoSelect = true;
  String _mobileCurrent = '';
  String _desktopCurrent = '';
  List<String> _mobileList = const [];
  List<String> _desktopList = const [];
  List<UaRule> _rules = const [];
  Map<String, String> _siteMemory = const {};
  String _query = '';

  UaRepository get _repo => UaRepository(ref.read(databaseProvider));

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _mobileCtrl.dispose();
    _desktopCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final repo = _repo;
    final auto = await repo.autoSelect();
    final mobile = await repo.mobileCurrent();
    final desktop = await repo.desktopCurrent();
    final mobileList = await repo.mobileUas();
    final desktopList = await repo.desktopUas();
    final rules = await repo.rules();
    final memory = await repo.siteMemory();
    if (!mounted) return;
    setState(() {
      _autoSelect = auto;
      _mobileCurrent = mobile;
      _desktopCurrent = desktop;
      _mobileList = mobileList;
      _desktopList = desktopList;
      _rules = rules;
      _siteMemory = memory;
      _mobileCtrl.text = mobile;
      _desktopCtrl.text = desktop;
    });
  }

  Future<void> _setMobileCurrent(String ua) async {
    await ref.read(uaResolverProvider).setMobileCurrent(ua);
    await _reload();
  }

  Future<void> _setDesktopCurrent(String ua) async {
    await ref.read(uaResolverProvider).setDesktopCurrent(ua);
    await _reload();
  }

  Future<void> _resetDefaults() async {
    await _repo.resetToDefaults();
    // 恢复默认也要发 onUaChanged，让引擎清会话、重建 WebView
    await ref.read(uaResolverProvider).setMobileCurrent(
        UaConstants.defaultMobileUa);
    await ref.read(uaResolverProvider).setDesktopCurrent(
        UaConstants.defaultDesktopUa);
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已恢复默认 UA')));
  }

  List<UaPreset> _filteredPresets(bool mobile) {
    final all =
        mobile ? UaConstants.mobilePresets : UaConstants.desktopPresets;
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.ua.toLowerCase().contains(q) ||
            p.tag.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('模拟浏览器信息'),
        bottom: TabBar(
          controller: _tabController,
          // AppBar 底色是主题 primary：选中/未选中/指示器一律用白色系，
          // 绝不许用 primary 色（旧审计 B 第 10.1 项：字隐形）
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: '手机'),
            Tab(text: '电脑'),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动选择 UA'),
            subtitle: const Text('按站点规则自动在手机/电脑 UA 间切换；'
                '关了只按下面两条当前值走'),
            value: _autoSelect,
            onChanged: (v) async {
              await _repo.setAutoSelect(v);
              setState(() => _autoSelect = v);
            },
          ),
          const SizedBox(height: 8),
          const Text('当前 UA',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('只存这两条：手机一条、电脑一条。改完立即生效，'
              '引擎会清会话、重建 WebView、重载或重播。',
              style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 10),
          _currentField(
            label: '手机 UA',
            controller: _mobileCtrl,
            current: _mobileCurrent,
            onSave: _setMobileCurrent,
          ),
          const SizedBox(height: 10),
          _currentField(
            label: '电脑 UA',
            controller: _desktopCtrl,
            current: _desktopCurrent,
            onSave: _setDesktopCurrent,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.restore_outlined),
              label: const Text('恢复默认 UA'),
              onPressed: _resetDefaults,
            ),
          ),
          const SizedBox(height: 20),
          const Text('内置推荐',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('筛过的：只留主流、真实、不容易被站方发现是伪造的。'
              '点一下就设为对应平台的当前值。',
              style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 10),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: '按名字 / UA / 标签搜，比如 微信、Pixel',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 320,
            child: TabBarView(
              controller: _tabController,
              children: [
                _presetList(mobile: true),
                _presetList(mobile: false),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('我的 UA',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('粘贴新增'),
                onPressed: _addCustomUa,
              ),
            ],
          ),
          const Text('自己粘贴的 UA，点一下设为当前值；长按可编辑。',
              style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 6),
          ..._customTiles(),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('规则表',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('新增规则'),
                onPressed: () => _editRule(null),
              ),
              TextButton(
                onPressed: () async {
                  await _repo.resetRules();
                  await _reload();
                },
                child: const Text('恢复预设'),
              ),
            ],
          ),
          const Text('域名或关键词 → 用电脑版还是手机版；每条可开关。',
              style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 6),
          ..._ruleTiles(),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text('按站记忆',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await _repo.clearAllSiteMemory();
                  await _reload();
                },
                child: const Text('全部清除'),
              ),
            ],
          ),
          const Text('在某个源/站手动切过 UA 后会记住，下次打开这个源还用它。',
              style: TextStyle(fontSize: 12.5)),
          const SizedBox(height: 6),
          if (_siteMemory.isEmpty)
            const Text('暂无按站记忆', style: TextStyle(fontSize: 13)),
          ..._siteMemory.entries.map((e) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.key, style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(UaConstants.labelOf(e.value),
                    style: const TextStyle(fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: '清除这条记忆',
                  onPressed: () async {
                    await _repo.clearSiteUa(e.key);
                    await _reload();
                  },
                ),
              )),
        ],
      ),
    );
  }

  Widget _currentField({
    required String label,
    required TextEditingController controller,
    required String current,
    required Future<void> Function(String) onSave,
  }) {
    final isCurrent = controller.text.trim() == current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                maxLines: 3,
                minLines: 2,
                style: const TextStyle(fontSize: 12.5),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: isCurrent
                  ? null
                  : () => onSave(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _presetList({required bool mobile}) {
    final presets = _filteredPresets(mobile);
    if (presets.isEmpty) {
      return const Center(child: Text('没有匹配的推荐'));
    }
    final current = mobile ? _mobileCurrent : _desktopCurrent;
    return ListView.builder(
      itemCount: presets.length,
      itemBuilder: (context, i) {
        final p = presets[i];
        final selected = p.ua == current;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).disabledColor,
          ),
          title: Text(p.name,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.normal)),
          subtitle: Text(p.tag, style: const TextStyle(fontSize: 12)),
          onTap: () =>
              mobile ? _setMobileCurrent(p.ua) : _setDesktopCurrent(p.ua),
        );
      },
    );
  }

  List<Widget> _customTiles() {
    final tiles = <Widget>[];
    for (final entry in <MapEntry<bool, String>>[
      ..._mobileList.map((u) => MapEntry(true, u)),
      ..._desktopList.map((u) => MapEntry(false, u)),
    ]) {
      final isMobile = entry.key;
      final ua = entry.value;
      // 内置推荐不算“我的 UA”，只展示自定义的
      final builtin = isMobile
          ? UaConstants.builtinMobileUas
          : UaConstants.builtinDesktopUas;
      if (builtin.contains(ua)) continue;
      final current = isMobile ? _mobileCurrent : _desktopCurrent;
      tiles.add(ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(UaConstants.labelOf(ua),
            style: const TextStyle(fontSize: 13.5)),
        subtitle: Text(ua,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ua == current)
              const Icon(Icons.check, size: 18, color: Colors.green),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: '删除',
              onPressed: () => _deleteCustomUa(isMobile, ua),
            ),
          ],
        ),
        onTap: () =>
            isMobile ? _setMobileCurrent(ua) : _setDesktopCurrent(ua),
        onLongPress: () => _editCustomUa(isMobile, ua),
      ));
    }
    if (tiles.isEmpty) {
      tiles.add(const Text('还没有自定义 UA', style: TextStyle(fontSize: 13)));
    }
    return tiles;
  }

  Future<void> _addCustomUa() async {
    final ctrl = TextEditingController();
    var mobile = _tabController.index == 0;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('新增自定义 UA'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '粘贴 UA 字符串',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('平台'),
                  const SizedBox(width: 12),
                  DropdownButton<bool>(
                    value: mobile,
                    items: const [
                      DropdownMenuItem(value: true, child: Text('手机')),
                      DropdownMenuItem(value: false, child: Text('电脑')),
                    ],
                    onChanged: (v) =>
                        setDlg(() => mobile = v ?? true),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(
                  ctx, {'ua': ctrl.text.trim(), 'mobile': mobile}),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final ua = (result['ua'] as String?) ?? '';
    if (ua.isEmpty) return;
    final isMobile = result['mobile'] as bool;
    if (isMobile) {
      await _repo.setMobileUas([..._mobileList, ua]);
      await _setMobileCurrent(ua);
    } else {
      await _repo.setDesktopUas([..._desktopList, ua]);
      await _setDesktopCurrent(ua);
    }
    await _reload();
  }

  Future<void> _editCustomUa(bool isMobile, String oldUa) async {
    final ctrl = TextEditingController(text: oldUa);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑 UA'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration:
              const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (result == null || result.isEmpty || result == oldUa) return;
    if (isMobile) {
      await _repo.setMobileUas(
          _mobileList.map((u) => u == oldUa ? result : u).toList());
      if (_mobileCurrent == oldUa) await _setMobileCurrent(result);
    } else {
      await _repo.setDesktopUas(
          _desktopList.map((u) => u == oldUa ? result : u).toList());
      if (_desktopCurrent == oldUa) await _setDesktopCurrent(result);
    }
    await _reload();
  }

  Future<void> _deleteCustomUa(bool isMobile, String ua) async {
    if (isMobile) {
      await _repo
          .setMobileUas(_mobileList.where((u) => u != ua).toList());
    } else {
      await _repo
          .setDesktopUas(_desktopList.where((u) => u != ua).toList());
    }
    await _reload();
  }

  List<Widget> _ruleTiles() {
    return _rules.map((rule) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(rule.pattern,
            style: const TextStyle(fontSize: 13.5)),
        subtitle: Text(rule.desktop ? '用电脑版 UA' : '用手机版 UA',
            style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: rule.enabled,
              onChanged: (v) async {
                final updated = _rules
                    .map((r) => r.id == rule.id
                        ? r.copyWith(enabled: v)
                        : r)
                    .toList();
                await _repo.setRules(updated);
                await _reload();
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: '编辑',
              onPressed: () => _editRule(rule),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: '删除',
              onPressed: () async {
                final updated =
                    _rules.where((r) => r.id != rule.id).toList();
                await _repo.setRules(updated);
                await _reload();
              },
            ),
          ],
        ),
      );
    }).toList();
  }

  Future<void> _editRule(UaRule? rule) async {
    final patternCtrl = TextEditingController(text: rule?.pattern ?? '');
    var desktop = rule?.desktop ?? true;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(rule == null ? '新增规则' : '编辑规则'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: patternCtrl,
                decoration: const InputDecoration(
                  labelText: '域名或关键词',
                  hintText: '比如 pan.baidu.com',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('用'),
                  const SizedBox(width: 12),
                  DropdownButton<bool>(
                    value: desktop,
                    items: const [
                      DropdownMenuItem(value: true, child: Text('电脑版')),
                      DropdownMenuItem(value: false, child: Text('手机版')),
                    ],
                    onChanged: (v) => setDlg(() => desktop = v ?? true),
                  ),
                  const Text(' UA'),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, {
                'pattern': patternCtrl.text.trim(),
                'desktop': desktop,
              }),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final pattern = (result['pattern'] as String?) ?? '';
    if (pattern.isEmpty) return;
    final isDesktop = result['desktop'] as bool;
    List<UaRule> updated;
    if (rule == null) {
      updated = [
        ..._rules,
        UaRule(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          pattern: pattern,
          desktop: isDesktop,
        ),
      ];
    } else {
      updated = _rules
          .map((r) => r.id == rule.id
              ? r.copyWith(pattern: pattern, desktop: isDesktop)
              : r)
          .toList();
    }
    await _repo.setRules(updated);
    await _reload();
  }
}
