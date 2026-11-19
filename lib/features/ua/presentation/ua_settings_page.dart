import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../data/ua_constants.dart';
import '../data/ua_repository.dart';

/// UA 设置（参考主流源管理类 App 的做法）
///
/// 结构：
/// - 顶部「当前生效」卡：自动选择开关 + 当前手机/电脑 UA
/// - 手机 UA / 电脑 UA 两个分栏
/// - 每栏：搜索 + 内置推荐（点选即生效）+ 我的 UA（新增/编辑/删除）
class UaSettingsPage extends ConsumerStatefulWidget {
  const UaSettingsPage({super.key});

  @override
  ConsumerState<UaSettingsPage> createState() => _UaSettingsPageState();
}

class _UaSettingsPageState extends ConsumerState<UaSettingsPage>
    with SingleTickerProviderStateMixin {
  late UaRepository _repo;
  late TabController _tabs;

  bool _auto = UaConstants.defaultAutoSelect;
  String? _mobileCurrent;
  String? _desktopCurrent;
  List<String> _mobileMine = [];
  List<String> _desktopMine = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _repo = ref.read(uaRepositoryProvider);
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final auto = await _repo.autoSelect();
    final mc = await _repo.mobileCurrent();
    final dc = await _repo.desktopCurrent();
    final mm = await _repo.mobileUas();
    final dm = await _repo.desktopUas();
    if (!mounted) return;
    setState(() {
      _auto = auto;
      _mobileCurrent = mc;
      _desktopCurrent = dc;
      _mobileMine = mm;
      _desktopMine = dm;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UA 设置'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Theme.of(context).colorScheme.primary,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: context.subtleColor,
          tabs: const [
            Tab(text: '手机 UA'),
            Tab(text: '电脑 UA'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addCustom(isMobile: _tabs.index == 0),
        backgroundColor: Theme.of(context).colorScheme.primary,
        icon: const Icon(Icons.add, color: Colors.black87),
        label: const Text('自定义', style: TextStyle(color: Colors.black87)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _currentCard(),
                _searchBar(),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _buildTab(isMobile: true),
                      _buildTab(isMobile: false),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------- 当前生效

  Widget _currentCard() {
    final primary = Theme.of(context).colorScheme.primary;
    final mcName =
        _mobileCurrent == null ? '未设置' : UaConstants.labelOf(_mobileCurrent!);
    final dcName = _desktopCurrent == null
        ? '未设置'
        : UaConstants.labelOf(_desktopCurrent!);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.outline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: context.palette.primarySoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.auto_awesome, size: 20, color: primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('按源自动选择 UA',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      _auto
                          ? '哔哩哔哩等 PC 站用电脑 UA，其余用手机 UA'
                          : '已关闭：沿用各源自己的默认行为',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Switch(
                value: _auto,
                onChanged: (v) async {
                  await _repo.setAutoSelect(v);
                  setState(() => _auto = v);
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(height: 1, color: context.palette.outline),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _currentItem(
                    icon: Icons.smartphone, label: '手机端', name: mcName),
              ),
              Container(width: 1, height: 30, color: context.palette.outline),
              Expanded(
                child: _currentItem(
                    icon: Icons.desktop_windows, label: '电脑端', name: dcName),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _currentItem(
      {required IconData icon, required String label, required String name}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.subtleColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: TextField(
        decoration: const InputDecoration(
          hintText: '搜索浏览器 / 机型 / UA 关键字',
          prefixIcon: Icon(Icons.search, size: 20),
          isDense: true,
        ),
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      ),
    );
  }

  // ---------------------------------------------------------------- 分栏

  Widget _buildTab({required bool isMobile}) {
    final presets =
        isMobile ? UaConstants.mobilePresets : UaConstants.desktopPresets;
    final mine = isMobile ? _mobileMine : _desktopMine;
    final current = isMobile ? _mobileCurrent : _desktopCurrent;

    final filteredPresets = presets.where((p) {
      if (_query.isEmpty) return true;
      return p.name.toLowerCase().contains(_query) ||
          p.ua.toLowerCase().contains(_query) ||
          p.tag.toLowerCase().contains(_query);
    }).toList();

    final filteredMine = mine.where((ua) {
      if (_query.isEmpty) return true;
      return ua.toLowerCase().contains(_query) ||
          UaConstants.labelOf(ua).toLowerCase().contains(_query);
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      children: [
        _hint(isMobile),
        const SizedBox(height: 14),
        _groupTitle('内置推荐', '${filteredPresets.length} 条'),
        const SizedBox(height: 8),
        ...filteredPresets.map((p) => _presetTile(p, current, isMobile)),
        const SizedBox(height: 18),
        _groupTitle('我的 UA', '${mine.length} 条'),
        const SizedBox(height: 8),
        if (filteredMine.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.palette.outline),
            ),
            child: Column(
              children: [
                Icon(Icons.playlist_add, color: context.subtleColor, size: 28),
                const SizedBox(height: 8),
                Text('还没有自定义 UA',
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text('点右下角「自定义」粘贴一条 UA 即可',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          )
        else
          ...filteredMine.map((ua) => _mineTile(ua, current, isMobile)),
        const SizedBox(height: 18),
        _helpCard(),
      ],
    );
  }

  Widget _hint(bool isMobile) {
    final text = isMobile
        ? '部分源是手机版站点，别在这里放 PC 版 UA，否则会加载出错。'
        : '部分源是 PC 版站点，别在这里放手机版 UA，否则会加载出错。';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 16, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.secondary)),
          ),
        ],
      ),
    );
  }

  Widget _groupTitle(String title, String count) => Row(
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(count, style: Theme.of(context).textTheme.bodySmall),
        ],
      );

  Widget _presetTile(UaPreset p, String? current, bool isMobile) {
    final selected = current == p.ua;
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _setCurrent(p.ua, isMobile),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: selected ? context.palette.primarySoft : context.cardColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? primary : context.palette.outline,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(_iconFor(p.tag),
                  size: 20, color: selected ? primary : context.subtleColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500)),
                        ),
                        const SizedBox(width: 6),
                        _tag(p.tag),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(p.ua,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              selected
                  ? Icon(Icons.check_circle, size: 20, color: primary)
                  : Icon(Icons.radio_button_unchecked,
                      size: 18, color: context.palette.outline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mineTile(String ua, String? current, bool isMobile) {
    final selected = current == ua;
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? context.palette.primarySoft : context.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? primary : context.palette.outline,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _setCurrent(ua, isMobile),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(UaConstants.labelOf(ua),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w500)),
                    const SizedBox(height: 3),
                    Text(ua,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 11)),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: Icon(Icons.edit_outlined,
                  size: 18, color: context.subtleColor),
              onPressed: () => _editCustom(ua, isMobile),
              tooltip: '编辑',
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  size: 18, color: context.subtleColor),
              onPressed: () => _deleteCustom(ua, isMobile),
              tooltip: '删除',
            ),
          ],
        ),
      ),
    );
  }

  Widget _helpCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, size: 16, color: context.subtleColor),
              const SizedBox(width: 6),
              const Text('怎么找 UA？',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '在百度搜「UserAgent」或「我的浏览器UA」，注意分清手机端和电脑端。'
            '部分源播放或加载受限时，来这里换一条 UA 再试。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _tag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 10, color: context.subtleColor)),
      );

  IconData _iconFor(String tag) {
    switch (tag) {
      case '微信':
        return Icons.chat_bubble_outline;
      case 'Safari':
        return Icons.explore_outlined;
      case 'Chrome':
        return Icons.public;
      case 'Edge':
        return Icons.waves;
      case 'Firefox':
        return Icons.local_fire_department_outlined;
      case 'QQ浏览器':
      case 'UC':
      case '夸克':
      case '360':
      case 'Opera':
        return Icons.travel_explore;
      default:
        return Icons.smartphone;
    }
  }

  // ---------------------------------------------------------------- 操作

  Future<void> _setCurrent(String ua, bool isMobile) async {
    if (isMobile) {
      await _repo.setMobileCurrent(ua);
      setState(() => _mobileCurrent = ua);
    } else {
      await _repo.setDesktopCurrent(ua);
      setState(() => _desktopCurrent = ua);
    }
    _toast('已切换到「${UaConstants.labelOf(ua)}」');
  }

  Future<void> _addCustom({required bool isMobile}) async {
    final controller = TextEditingController();
    final ua = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isMobile ? '添加手机 UA' : '添加电脑 UA'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              maxLines: 4,
              minLines: 3,
              decoration: const InputDecoration(
                hintText: '粘贴完整 UA，通常以 Mozilla/5.0 开头',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    icon: const Icon(Icons.paste, size: 16),
                    label: const Text('从剪贴板粘贴'),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) controller.text = data!.text!;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ua == null || ua.isEmpty) return;
    await _upsert(ua, isMobile);
  }

  Future<void> _editCustom(String old, bool isMobile) async {
    final controller = TextEditingController(text: old);
    final ua = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑 UA'),
        content:
            TextField(controller: controller, maxLines: 4, minLines: 3),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ua == null || ua.isEmpty || ua == old) return;
    final list = isMobile
        ? List<String>.from(_mobileMine)
        : List<String>.from(_desktopMine);
    final i = list.indexOf(old);
    if (i >= 0) list[i] = ua;
    if (isMobile) {
      await _repo.setMobileUas(list);
      if (_mobileCurrent == old) await _repo.setMobileCurrent(ua);
    } else {
      await _repo.setDesktopUas(list);
      if (_desktopCurrent == old) await _repo.setDesktopCurrent(ua);
    }
    await _load();
    _toast('已更新');
  }

  Future<void> _deleteCustom(String ua, bool isMobile) async {
    final list = isMobile
        ? List<String>.from(_mobileMine)
        : List<String>.from(_desktopMine);
    list.remove(ua);
    if (isMobile) {
      await _repo.setMobileUas(list);
    } else {
      await _repo.setDesktopUas(list);
    }
    await _load();
    _toast('已删除');
  }

  Future<void> _upsert(String ua, bool isMobile) async {
    final list = isMobile
        ? List<String>.from(_mobileMine)
        : List<String>.from(_desktopMine);
    if (!list.contains(ua)) list.insert(0, ua);
    if (isMobile) {
      await _repo.setMobileUas(list);
      await _repo.setMobileCurrent(ua);
    } else {
      await _repo.setDesktopUas(list);
      await _repo.setDesktopCurrent(ua);
    }
    await _load();
    _toast('已添加并设为当前');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }
}
