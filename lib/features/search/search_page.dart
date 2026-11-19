import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../shared/widgets/common.dart';
import '../audio/data/repository_providers.dart';
import '../audio/domain/media_item.dart';

/// 搜索页：听书/视频各自独立搜索，结果分类清晰。
class SearchPage extends ConsumerStatefulWidget {
  final String type; // audio | video
  const SearchPage({super.key, required this.type});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  List<MediaItem> _results = [];
  bool _searched = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.type == AppConstants.typeAudio ? '听书' : '视频';
    return Scaffold(
      appBar: AppBar(title: Text('$label搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '搜索本地$label标题或作者',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _controller.clear();
                    setState(() {
                      _results = [];
                      _searched = false;
                    });
                  },
                ),
              ),
              onSubmitted: (_) => _doSearch(),
            ),
          ),
          Expanded(
            child: !_searched
                ? const EmptyState(icon: Icons.search, message: '输入关键词开始搜索')
                : _results.isEmpty
                    ? const EmptyState(
                        icon: Icons.search_off, message: '没有找到相关内容')
                    : ListView.builder(
                        padding: pagePadding(context, top: 4, bottom: 16),
                        itemCount: _results.length,
                        itemBuilder: (context, i) {
                          final item = _results[i];
                          return ListTile(
                            leading: CoverImage(
                                path: item.coverPath,
                                title: item.title,
                                size: 44,
                                isVideo: item.isVideo),
                            title: Text(item.title),
                            subtitle:
                                Text(item.author ?? '${item.chapterCount} 章'),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _doSearch() async {
    final kw = _controller.text.trim();
    if (kw.isEmpty) return;
    final results = await ref.read(libraryRepositoryProvider).query(
          type: widget.type,
          keyword: kw,
        );
    setState(() {
      _results = results;
      _searched = true;
    });
  }
}
