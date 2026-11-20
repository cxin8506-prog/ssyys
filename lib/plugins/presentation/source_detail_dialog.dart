import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/library_repository.dart';
import '../model/plugin_source.dart';
import '../../shared/widgets/common.dart';
import 'source_book_page.dart';

/// 源详情弹窗：只做轻量入口，不要替代整页。
///
/// 左边海报，右边片名/作者/来源，下面是「取消」「添加收藏」「开始播放」。
/// 想看目录、章节列表、线路、音色，点「开始播放」或书卡进整页
///（SourceBookPage）。弹窗里没有章节列表是设计如此，不是缺功能。
Future<void> showSourceDetailDialog(
  BuildContext context,
  WidgetRef ref, {
  required PluginSource source,
  required dynamic book,
}) async {
  final title = _field(book, ['title', 'name']);
  final author = _field(book, ['author', 'artist']);
  final cover = _field(book, ['coverUrl', 'cover', 'img']);
  final url = _field(book, ['bookUrl', 'url']);
  final intro = _field(book, ['intro', 'description']);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoverImage(
            url: cover.isEmpty ? null : cover,
            title: title,
            width: 78,
            height: 104,
            radius: 8,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title.isEmpty ? '未命名' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (author.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  source.name,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                ),
                if (intro.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    intro,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () async {
            final bookKey = '${source.id}|$url';
            try {
              await ref.read(libraryRepositoryProvider).addFavorite(bookKey);
            } catch (_) {}
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已添加收藏')),
            );
          },
          child: const Text('添加收藏'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SourceBookPage(
                  sourceId: source.id,
                  bookUrl: url,
                  title: title,
                  coverUrl: cover.isEmpty ? null : cover,
                  author: author.isEmpty ? null : author,
                  intro: intro.isEmpty ? null : intro,
                  autoPlay: true,
                ),
              ),
            );
          },
          child: const Text('开始播放'),
        ),
      ],
    ),
  );
}

String _field(dynamic book, List<String> keys) {
  if (book is Map) {
    for (final k in keys) {
      final v = book[k];
      if (v != null && '$v'.isNotEmpty) return '$v';
    }
    return '';
  }
  // 非 Map 的书对象（比如 FeedBook）：按属性名取。
  try {
    final d = book as dynamic;
    final first = keys.first;
    final candidates = <dynamic>[];
    if (first == 'title' || first == 'name') {
      candidates.addAll([d.title, d.name]);
    } else if (first == 'author' || first == 'artist') {
      candidates.addAll([d.author, d.artist]);
    } else if (first == 'coverUrl' || first == 'cover') {
      candidates.addAll([d.coverUrl, d.cover, d.img]);
    } else if (first == 'bookUrl' || first == 'url') {
      candidates.addAll([d.bookUrl, d.url]);
    } else {
      candidates.addAll([d.intro, d.description]);
    }
    for (final v in candidates) {
      if (v != null && '$v'.isNotEmpty) return '$v';
    }
  } catch (_) {}
  return '';
}
