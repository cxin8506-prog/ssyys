import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/plugin_providers.dart';

/// 首页顶部的源切换条（参考 Mihon / 听书类 App 的源选择器）
class SourceSwitcher extends ConsumerWidget {
  /// audio | video
  final String type;
  const SourceSwitcher({super.key, this.type = 'audio'});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(sourceListProvider);
    final current = ref.watch(currentSourceProvider(type));
    final all = async.value ?? const [];
    final list = all.where((s) => s.type == type && s.enabled).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.hub_outlined, size: 16, color: context.subtleColor),
            const SizedBox(width: 6),
            Text('当前源',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(
              onPressed: () async {
                await Navigator.of(context).pushNamed('/sources');
                ref.invalidate(sourceListProvider);
              },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('管理源', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (list.isEmpty)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              await Navigator.of(context).pushNamed('/sources');
              ref.invalidate(sourceListProvider);
            },
            child: Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: context.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.palette.outline),
              ),
              child: Row(
                children: [
                  Icon(Icons.add_circle_outline,
                      size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('还没有${type == 'audio' ? '听书' : '视频'}源，点这里导入插件',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                  Icon(Icons.chevron_right,
                      size: 18, color: context.subtleColor),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final s = list[i];
                final selected = current == s.id;
                final primary = Theme.of(context).colorScheme.primary;
                return InkWell(
                  borderRadius: BorderRadius.circular(17),
                  onTap: () => setCurrentSource(ref, type, s.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? context.palette.primarySoft
                          : context.cardColor,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: selected ? primary : context.palette.outline,
                        width: selected ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (selected) ...[
                          Icon(Icons.check, size: 13, color: primary),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          s.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: selected ? primary : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
