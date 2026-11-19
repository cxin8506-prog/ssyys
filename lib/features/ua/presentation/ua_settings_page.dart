import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../data/ua_constants.dart';
import '../data/ua_repository.dart';

/// UA 设置页（第二期功能）
///
/// - 自动选择开关：开启后按源自动选 UA（PC-only 源用电脑 UA，其余手机 UA）
/// - 手机 UA 列表 / 电脑 UA 列表：新增、编辑、删除、从内置库挑选
/// - 防呆提示：手机站别加 PC UA、PC 站别加手机 UA
/// - 辅助说明：UA 可去百度搜索，注意移动端/PC 端区别
class UaSettingsPage extends ConsumerStatefulWidget {
  const UaSettingsPage({super.key});

  @override
  ConsumerState<UaSettingsPage> createState() => _UaSettingsPageState();
}

class _UaSettingsPageState extends ConsumerState<UaSettingsPage> {
  late UaRepository _repo;
  bool _auto = UaConstants.defaultAutoSelect;
  List<String> _mobile = [];
  List<String> _desktop = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(uaRepositoryProvider);
    _load();
  }

  Future<void> _load() async {
    final auto = await _repo.autoSelect();
    final mobile = await _repo.mobileUas();
    final desktop = await _repo.desktopUas();
    if (!mounted) return;
    setState(() {
      _auto = auto;
      _mobile = mobile;
      _desktop = desktop;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UA 设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                _introCard(),
                const _SectionTitle(title: '自动选择'),
                SwitchListTile(
                  secondary: const Icon(Icons.auto_awesome_outlined,
                      color: AppTheme.primary),
                  title: const Text('按源自动选择 UA'),
                  subtitle: const Text(
                      '开启：哔哩哔哩等只认电脑的源用电脑 UA，其余用手机 UA。'
                      '关闭：完全沿用原来的行为，不自动切换。'),
                  value: _auto,
                  onChanged: (v) async {
                    await _repo.setAutoSelect(v);
                    setState(() => _auto = v);
                  },
                ),
                if (_auto) _autoHint(),
                const _SectionTitle(title: '手机版 UserAgent'),
                _listCard(
                  list: _mobile,
                  isMobile: true,
                  warning:
                      '部分源是手机版站点，请勿添加 PC 版 UA，否则会导致加载出错。',
                  builtin: UaConstants.builtinMobileUas,
                ),
                const _SectionTitle(title: '电脑版 UserAgent'),
                _listCard(
                  list: _desktop,
                  isMobile: false,
                  warning:
                      '部分源是 PC 站点，请勿添加手机版 UA，否则会导致加载出错。',
                  builtin: UaConstants.builtinDesktopUas,
                ),
                const _SectionTitle(title: '说明'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(
                    'UserAgent（UA）是浏览器访问网站时表明身份的一段文字。'
                    '不知道填什么可去百度搜索「UserAgent」，注意区分移动端和 PC 端，'
                    '别把两类混用。若某个源播放/加载受限，可来本页修改 UA 后重试。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _introCard() {
    return Card(
      color: AppTheme.darkSurface,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.info_outline, color: AppTheme.primary, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'UA 决定网站把内容当成手机还是电脑来给。列表第一项为该类当前使用的 UA；'
                '可新增多条，随时编辑或删除。',
                style: TextStyle(color: AppTheme.darkTextSub, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _autoHint() {
    final pcs = UaConstants.pcOnlyKeywords.join('、');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text('当前视为电脑版源的关键词：$pcs（命中其一即用电脑 UA）',
          style: Theme.of(context).textTheme.bodySmall),
    );
  }

  Widget _listCard({
    required List<String> list,
    required bool isMobile,
    required String warning,
    required List<String> builtin,
  }) {
    return Card(
      color: AppTheme.darkSurface,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  isMobile ? Icons.smartphone : Icons.computer,
                  size: 16,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(warning,
                      style: const TextStyle(
                          color: AppTheme.accent, fontSize: 12)),
                ),
              ],
            ),
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: Text('暂无 UA，点下方新增',
                      style: TextStyle(color: AppTheme.darkTextSub))),
            )
          else
            ...List.generate(list.length, (i) {
              final value = list[i];
              return ListTile(
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: i == 0 ? AppTheme.primary : AppTheme.darkSurfaceAlt,
                  child: Text('${i + 1}',
                      style: TextStyle(
                          fontSize: 11,
                          color: i == 0 ? Colors.black87 : AppTheme.darkTextSub)),
                ),
                title: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                subtitle: i == 0
                    ? const Text('当前使用',
                        style: TextStyle(
                            color: AppTheme.primary, fontSize: 11))
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: '编辑',
                      onPressed: () => _editUa(isMobile, i, value),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: '删除',
                      onPressed: () => _deleteUa(isMobile, i),
                    ),
                  ],
                ),
              );
            }),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新增'),
                    onPressed: () => _addUa(isMobile),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.library_add_outlined, size: 18),
                    label: const Text('从内置选'),
                    onPressed: () => _pickBuiltin(isMobile, builtin),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _persist(bool isMobile, List<String> list) async {
    if (isMobile) {
      await _repo.setMobileUas(list);
    } else {
      await _repo.setDesktopUas(list);
    }
  }

  /// 把新列表写回对应分类并刷新界面
  void _applyList(bool isMobile, List<String> list, {bool refresh = true}) {
    if (isMobile) {
      _mobile = list;
    } else {
      _desktop = list;
    }
    if (refresh && mounted) setState(() {});
  }

  void _addUa(bool isMobile) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => _uaDialog(
        title: isMobile ? '新增手机 UA' : '新增电脑 UA',
        controller: controller,
        onSave: (value) async {
          final list = List<String>.from(isMobile ? _mobile : _desktop);
          list.add(value);
          await _persist(isMobile, list);
          _applyList(isMobile, list);
        },
      ),
    );
  }

  void _editUa(bool isMobile, int index, String value) {
    final controller = TextEditingController(text: value);
    showDialog(
      context: context,
      builder: (_) => _uaDialog(
        title: isMobile ? '编辑手机 UA' : '编辑电脑 UA',
        controller: controller,
        onSave: (newValue) async {
          final list = List<String>.from(isMobile ? _mobile : _desktop);
          list[index] = newValue;
          await _persist(isMobile, list);
          _applyList(isMobile, list);
        },
      ),
    );
  }

  void _deleteUa(bool isMobile, int index) {
    final list = List<String>.from(isMobile ? _mobile : _desktop);
    final removed = list.removeAt(index);
    _persist(isMobile, list);
    _applyList(isMobile, list);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('已删除'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            final current = List<String>.from(isMobile ? _mobile : _desktop);
            current.insert(index, removed);
            await _persist(isMobile, current);
            _applyList(isMobile, current);
          },
        ),
      ),
    );
  }

  void _pickBuiltin(bool isMobile, List<String> builtin) {
    final current = List<String>.from(isMobile ? _mobile : _desktop);
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(isMobile ? '选择内置手机 UA' : '选择内置电脑 UA',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            ...builtin.map((ua) {
              final added = current.contains(ua);
              return ListTile(
                title: Text(ua,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
                trailing: added
                    ? const Icon(Icons.check, color: AppTheme.primary)
                    : const Icon(Icons.add, color: AppTheme.darkTextSub),
                onTap: () {
                  if (!added) {
                    current.add(ua);
                    _persist(isMobile, current);
                    _applyList(isMobile, current);
                  }
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _uaDialog({
    required String title,
    required TextEditingController controller,
    required Future<void> Function(String) onSave,
  }) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: controller,
          maxLines: 4,
          style: const TextStyle(fontSize: 12),
          decoration: const InputDecoration(
            hintText: '粘贴 UserAgent 字符串',
            alignLabelWithHint: true,
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消')),
        TextButton(
          onPressed: () async {
            final value = controller.text.trim();
            if (value.isEmpty) return;
            await onSave(value);
            Navigator.pop(context);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(title, style: Theme.of(context).textTheme.bodySmall),
      );
}
