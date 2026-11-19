import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/home_feed.dart';
import '../data/plugin_providers.dart';
import '../model/plugin_source.dart';

/// 首页左上角点开后的「网格状选源」面板。
///
/// 返回被选中的源 id；用户点「管理源」返回 null（调用方自己刷新列表）。
Future<String?> showSourcePicker(
  BuildContext context,
  WidgetRef ref, {
  String? selectedId,
}) async {
  final sources = await ref.read(sourceListProvider.future);
  final enabled = sources.where((s) => s.enabled).toList(growable: false);

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => _SourcePickerSheet(
      sources: enabled,
      selectedId: selectedId,
    ),
  );
}

class _SourcePickerSheet extends StatelessWidget {
  final List<PluginSource> sources;
  final String? selectedId;

  const _SourcePickerSheet({required this.sources, this.selectedId});

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.72;
    return Container(
      constraints: BoxConstraints(maxHeight: maxH),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: context.palette.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: [
                  Text('选择源',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('${sources.length} 个',
                      style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushNamed('/sources');
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('管理源', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
            if (sources.isEmpty)
              Flexible(child: _empty(context))
            else
              Flexible(child: _sourceList(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).pushNamed('/sources');
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('导入 / 管理源'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  /// 源多的时候按「包名」分组：一个 JAR 里的多个源排在一起
  Widget _sourceList(BuildContext context) {
    final groups = <String, List<PluginSource>>{};
    for (final s in sources) {
      groups.putIfAbsent(s.group, () => []).add(s);
    }
    if (groups.length <= 1) return _grid(context, sources);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      children: [
        for (final e in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
            child: Row(
              children: [
                Text(
                  e.key.isEmpty ? '单个源' : e.key,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: context.subtleColor,
                  ),
                ),
                const SizedBox(width: 6),
                Text('${e.value.length} 个',
                    style: TextStyle(fontSize: 11, color: context.subtleColor)),
              ],
            ),
          ),
          _grid(context, e.value),
        ],
      ],
    );
  }

  Widget _grid(BuildContext context, List<PluginSource> list) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: list.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 14,
        crossAxisSpacing: 10,
        childAspectRatio: 0.94,
      ),
      itemBuilder: (_, i) => _SourceTile(
        source: list[i],
        selected: list[i].id == selectedId,
        onTap: () => Navigator.of(context).pop(list[i].id),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension_outlined, size: 48, color: context.subtleColor),
          const SizedBox(height: 12),
          Text('还没有可用的源', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('导入一个插件源，首页就会显示它配置的推荐内容',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final PluginSource source;
  final bool selected;
  final VoidCallback onTap;

  const _SourceTile({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final name = source.name;
    final letter = name.isEmpty ? '?' : name.substring(0, 1);
    final iconUrl = source.icon;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
        decoration: BoxDecoration(
          color: selected ? context.palette.primarySoft : context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? primary : Colors.transparent,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected
                        ? primary.withOpacity(0.18)
                        : context.cardColor,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: Alignment.center,
                  child: iconUrl != null && iconUrl.startsWith('http')
                      ? Image.network(
                          iconUrl,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _letter(letter, primary),
                        )
                      : _letter(letter, primary),
                ),
                if (selected)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      width: 17,
                      height: 17,
                      decoration: BoxDecoration(
                        color: primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Theme.of(context).cardColor, width: 2),
                      ),
                      child: const Icon(Icons.check,
                          size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? primary : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              source.isAudio ? '听书' : '视频',
              style: TextStyle(fontSize: 10, color: context.subtleColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _letter(String letter, Color primary) => Text(
        letter,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
      );
}

/// 供首页调用：选源 → 写入 → 若变了返回 true
Future<bool> pickHomeSource(
  BuildContext context,
  WidgetRef ref, {
  required String? currentId,
}) async {
  final picked = await showSourcePicker(context, ref, selectedId: currentId);
  ref.invalidate(sourceListProvider);
  if (picked == null || picked == currentId) return false;
  setHomeSource(ref, picked);
  return true;
}
