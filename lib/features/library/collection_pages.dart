import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/path_utils.dart';
import '../../plugins/data/plugin_resume.dart';
import '../../shared/widgets/common.dart';
import '../audio/data/repository_providers.dart';
import '../audio/domain/media_item.dart';
import '../audio/presentation/audio_player_page.dart';
import '../../plugins/presentation/source_book_page.dart';
import '../video/presentation/video_player_page.dart';

/// 收藏 / 历史 通用页面：听书与视频分栏
/// 收藏是网格/列表卡片，历史是列表行（上次播放：线路名 + 进度时间 + 源标签）
enum CollectionKind { favorite, history, bookmark }

class CollectionPage extends ConsumerStatefulWidget {
  final CollectionKind kind;
  final String initialType;

  const CollectionPage({
    super.key,
    required this.kind,
    this.initialType = AppConstants.typeAudio,
  });

  @override
  ConsumerState<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends ConsumerState<CollectionPage> {
  late String _type;

  /// 听书/视频小开关是否收起（收起后只露当前类型 + 小箭头，点箭头再展开）
  bool _typeHidden = false;

  // 收藏：分组、排序、布局（默认没有任何分组，点铅笔输名字才建）
  static const String _customGroupsKey = 'favorite_custom_groups';
  static const String _typeSwitchHiddenKey = 'collection_type_hidden';
  List<String> _groups = [];
  String _group = '全部';
  int _sort = 0; // 0 按加入时间，1 按名称，2 按最近阅读
  bool _grid = true; // true 网格，false 列表

  // 历史：插件源最近播放（断点）
  List<PluginResume> _resumes = [];

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _typeHidden =
        ref.read(sharedPrefsProvider).getBool(_typeSwitchHiddenKey) ?? false;
    if (widget.kind == CollectionKind.favorite) _loadGroups();
  }

  Future<void> _loadGroups() async {
    final prefs = await _prefs();
    final custom = prefs.getStringList(_customGroupsKey) ?? [];
    final dbGroups =
        await ref.read(libraryRepositoryProvider).favoriteGroups();
    final all = <String>[
      if (dbGroups.contains('默认')) '默认',
      ...custom,
      for (final g in dbGroups)
        if (g != '默认' && !custom.contains(g)) g,
    ];
    if (mounted) setState(() => _groups = all);
  }

  Future<SharedPreferences> _prefs() async =>
      SharedPreferences.getInstance();

  /// 收起/展开听书/视频小开关（记下来，下次打开还这样）
  void _toggleTypeHidden() {
    setState(() => _typeHidden = !_typeHidden);
    ref
        .read(sharedPrefsProvider)
        .setBool(_typeSwitchHiddenKey, _typeHidden);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(_title),
        actions: [
          if (widget.kind == CollectionKind.favorite)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '新建分组',
              onPressed: _createGroup,
            ),
          if (widget.kind == CollectionKind.favorite) _favoriteMenu(),
          if (widget.kind == CollectionKind.history)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空历史',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: Column(
        children: [
          _typeSwitch(),
          if (widget.kind == CollectionKind.favorite && _groups.isNotEmpty)
            _buildGroupChips(),
          Expanded(
            child: FutureBuilder<List<MediaItem>>(
              future: _load(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snap.data ?? [];
                if (widget.kind == CollectionKind.history) {
                  return _buildHistoryList(items);
                }
                if (items.isEmpty) {
                  return EmptyState(
                    icon: _icon,
                    message: '暂无收藏',
                    hint: _type == AppConstants.typeAudio
                        ? '在听书页长按条目，或播放页点收藏'
                        : '在视频页长按条目即可加入',
                  );
                }
                return _grid ? _buildGrid(items) : _buildFavoriteList(items);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<List<MediaItem>> _load() async {
    final repo = ref.read(libraryRepositoryProvider);
    if (widget.kind == CollectionKind.favorite) {
      final items = _group == '全部'
          ? await repo.favorites(_type)
          : await repo.favoritesByGroup(_group, _type);
      return _sorted(items);
    }
    _resumes = (await PluginResumeStore.loadAll())
        .where((r) => r.type == _type)
        .toList();
    return repo.history(_type);
  }

  List<MediaItem> _sorted(List<MediaItem> items) {
    final list = List<MediaItem>.of(items);
    if (_sort == 1) {
      list.sort((a, b) => a.title.compareTo(b.title));
    } else if (_sort == 2) {
      list.sort((a, b) =>
          (b.lastReadAt ?? b.addedAt).compareTo(a.lastReadAt ?? a.addedAt));
    }
    return list;
  }

  String get _title =>
      widget.kind == CollectionKind.favorite ? '收藏' : '历史';

  IconData get _icon => widget.kind == CollectionKind.favorite
      ? Icons.favorite_border
      : Icons.history;

  // ---------- 收藏：顶栏菜单（排序 / 布局 / 导出 / 导入） ----------

  Widget _favoriteMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: '更多',
      onSelected: (v) async {
        switch (v) {
          case 'sort_time':
            setState(() => _sort = 0);
            break;
          case 'sort_name':
            setState(() => _sort = 1);
            break;
          case 'sort_recent':
            setState(() => _sort = 2);
            break;
          case 'layout_grid':
            setState(() => _grid = true);
            break;
          case 'layout_list':
            setState(() => _grid = false);
            break;
          case 'export':
            _exportFavorites();
            break;
          case 'import':
            _importFavorites();
            break;
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'sort_time', child: Text('排序：按加入时间')),
        const PopupMenuItem(value: 'sort_name', child: Text('排序：按名称')),
        const PopupMenuItem(value: 'sort_recent', child: Text('排序：按最近阅读')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'layout_grid', child: Text('布局：网格')),
        const PopupMenuItem(value: 'layout_list', child: Text('布局：列表')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'export', child: Text('导出收藏')),
        const PopupMenuItem(value: 'import', child: Text('导入收藏')),
      ],
    );
  }

  /// 收藏导出：写一个 JSON 文件，提示里给路径
  Future<void> _exportFavorites() async {
    final entries =
        await ref.read(libraryRepositoryProvider).favoriteEntries();
    if (entries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('没有收藏可导出')));
      }
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/收藏导出.json');
    await file.writeAsString(jsonEncode(entries));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出到 ${file.path}')));
    }
  }

  /// 收藏导入：选一个之前导出的 JSON，本地没有的条目跳过
  Future<void> _importFavorites() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      final raw = jsonDecode(await File(path).readAsString());
      if (raw is! List) throw const FormatException('文件格式不对');
      final repo = ref.read(libraryRepositoryProvider);
      int ok = 0, skip = 0;
      for (final e in raw) {
        if (e is! Map) {
          skip++;
          continue;
        }
        final itemId = '${e['itemId'] ?? ''}';
        final type = '${e['type'] ?? ''}';
        final group = '${e['group'] ?? '默认'}';
        if (itemId.isEmpty) {
          skip++;
          continue;
        }
        final item = await repo.getById(itemId);
        if (item == null || await repo.isFavorite(itemId)) {
          skip++;
          continue;
        }
        await repo.addFavorite(itemId, type.isEmpty ? item.type : type,
            group: group);
        ok++;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '已导入 $ok 条${skip > 0 ? '，跳过 $skip 条（本地没有这本书或已收藏）' : ''}')));
        _loadGroups();
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  /// 听书/视频切换：紧凑的分段小开关，不占一整行大 tab；长按收起，
  /// 收起后只露当前类型 + 小箭头，点箭头再展开。收藏/历史共用。
  Widget _typeSwitch() {
    final primary = Theme.of(context).colorScheme.primary;
    if (_typeHidden) {
      return Align(
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _toggleTypeHidden,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.palette.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_type == AppConstants.typeAudio ? '听书' : '视频',
                      style: TextStyle(
                          fontSize: 12, color: context.subtleColor)),
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      size: 16, color: context.subtleColor),
                ],
              ),
            ),
          ),
        ),
      );
    }
    Widget btn(String label, String type) {
      final on = _type == type;
      return GestureDetector(
        onTap: () {
          if (_type != type) setState(() => _type = type);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: on ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: on
                      ? Theme.of(context).colorScheme.onPrimary
                      : context.subtleColor,
                  fontWeight:
                      on ? FontWeight.w600 : FontWeight.w400)),
        ),
      );
    }

    return Align(
      alignment: Alignment.center,
      child: GestureDetector(
        onLongPress: _toggleTypeHidden,
        child: Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: context.palette.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              btn('听书', AppConstants.typeAudio),
              btn('视频', AppConstants.typeVideo),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 收藏：分组横条（长按改名） ----------

  Widget _buildGroupChips() {
    final names = ['全部', ..._groups];
    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: names.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final name = names[i];
          final selected = _group == name;
          return GestureDetector(
            onLongPress: name == '全部' || name == '默认'
                ? null
                : () => _renameGroup(name),
            child: ChoiceChip(
              label: Text(name,
                  style: TextStyle(
                      color: selected
                          ? Theme.of(context).colorScheme.onPrimary
                          : null,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400)),
              selected: selected,
              selectedColor: Theme.of(context).colorScheme.primary,
              onSelected: (_) => setState(() => _group = name),
            ),
          );
        },
      ),
    );
  }

  /// 铅笔：输入名称新建自定义分组（没建之前页面上不显示任何分组）
  Future<void> _createGroup() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新建分组'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入分组名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    if (_groups.contains(name)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已有「$name」分组')));
      }
      return;
    }
    final prefs = await _prefs();
    final custom = prefs.getStringList(_customGroupsKey) ?? [];
    custom.add(name);
    await prefs.setStringList(_customGroupsKey, custom);
    await _loadGroups();
    if (mounted) {
      setState(() => _group = name);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已创建分组「$name」')));
    }
  }

  /// 分类重命名（“默认”不能改）
  Future<void> _renameGroup(String oldName) async {
    final ctrl = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('重命名分类'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '新分类名'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == oldName) return;
    await ref
        .read(libraryRepositoryProvider)
        .renameFavoriteGroup(oldName, newName);
    final prefs = await _prefs();
    final custom = prefs.getStringList(_customGroupsKey) ?? [];
    if (custom.contains(oldName)) {
      custom[custom.indexOf(oldName)] = newName;
      await prefs.setStringList(_customGroupsKey, custom);
    }
    if (_group == oldName) _group = newName;
    await _loadGroups();
    if (mounted) setState(() {});
  }

  // ---------- 收藏：网格 / 列表 ----------

  Widget _buildGrid(List<MediaItem> items) {
    return GridView.builder(
      padding: pagePadding(context, top: 14, bottom: 24),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 18,
        childAspectRatio: 0.62,
      ),
      itemBuilder: (_, i) => _card(items[i]),
    );
  }

  Widget _buildFavoriteList(List<MediaItem> items) {
    return ListView.separated(
      padding: pagePadding(context, top: 8, bottom: 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final item = items[i];
        return ListTile(
          leading: SizedBox(
            width: 44,
            height: 60,
            child: CoverImage(
                path: item.coverPath,
                title: item.title,
                size: 44,
                isVideo: item.isVideo),
          ),
          title: Text(item.title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${item.chapterCount} 章',
              style: Theme.of(context).textTheme.bodySmall),
          onTap: () => _openItem(item),
          onLongPress: () => _menu(item),
        );
      },
    );
  }

  // ---------- 历史：列表行 ----------

  Widget _buildHistoryList(List<MediaItem> items) {
    if (items.isEmpty && _resumes.isEmpty) {
      return const EmptyState(
        icon: Icons.history,
        message: '还没有记录',
        hint: '听过 / 看过的都会记在这里，点一行接着播',
      );
    }
    return ListView.separated(
      padding: pagePadding(context, top: 8, bottom: 24),
      itemCount: _resumes.length + items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        if (i < _resumes.length) return _resumeRow(_resumes[i]);
        return _historyRow(items[i - _resumes.length]);
      },
    );
  }

  /// 插件源一行：上次播放：线路名 · 章节名 进度时间 · 源标签
  Widget _resumeRow(PluginResume r) {
    final parts = <String>[];
    if (r.lineName.isNotEmpty) parts.add(r.lineName);
    parts.add(
        '${r.chapterName} ${PathUtils.formatDuration(r.positionMs)}');
    if (r.sourceName.isNotEmpty) parts.add(r.sourceName);
    return ListTile(
      leading: _resumeThumb(r),
      title: Text(r.bookTitle,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('上次播放：${parts.join(' · ')}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall),
      onTap: () => openResume(context, ref, r),
      onLongPress: () async {
        await PluginResumeStore.remove(r.key);
        if (mounted) setState(() {});
      },
    );
  }

  Widget _resumeThumb(PluginResume r) {
    final url = r.coverUrl;
    return Container(
      width: 44,
      height: 60,
      decoration: BoxDecoration(
        color: context.palette.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: url.startsWith('http')
          ? Image.network(url,
              fit: BoxFit.cover,
              cacheWidth: 88,
              cacheHeight: 120,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => _thumbIcon(r.isAudio))
          : _thumbIcon(r.isAudio),
    );
  }

  Widget _thumbIcon(bool isAudio) => Icon(
        isAudio ? Icons.headphones_outlined : Icons.movie_outlined,
        size: 20,
        color: Theme.of(context).colorScheme.primary.withOpacity(0.55),
      );

  /// 本地一行：上次播放：进度时间（没有时长就显示状态）
  Widget _historyRow(MediaItem item) {
    final p = item.progress > 1 ? item.progress / 100 : item.progress;
    String sub;
    if (item.durationMs != null && item.durationMs! > 0 && p > 0) {
      sub =
          '上次播放：${PathUtils.formatDuration((p * item.durationMs!).round())}';
    } else {
      sub = '上次播放：${item.statusLabel} · ${item.chapterCount} 章';
    }
    return ListTile(
      leading: SizedBox(
        width: 44,
        height: 60,
        child: CoverImage(
            path: item.coverPath,
            title: item.title,
            size: 44,
            isVideo: item.isVideo),
      ),
      title: Text(item.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall),
      onTap: () => _openItem(item),
      onLongPress: () => _menu(item),
    );
  }

  /// 清空历史：先弹确认框
  Future<void> _confirmClear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('是否清空历史记录？'),
        content: const Text('本地历史和最近播放的源记录都会清空，断点也会一起删掉。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (yes != true) return;
    await ref.read(libraryRepositoryProvider).clearHistory(_type);
    await PluginResumeStore.clearAll();
    if (mounted) setState(() {});
  }

  // ---------- 共用 ----------

  Future<void> _openItem(MediaItem item) async {
    // 插件源的收藏：id 里带源信息，直接进源详情页接着看/播
    if (item.id.startsWith('plugin|')) {
      final rest = item.id.substring('plugin|'.length);
      final sep = rest.indexOf('|');
      if (sep > 0) {
        final sourceId = rest.substring(0, sep);
        final bookUrl = rest.substring(sep + 1);
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SourceBookPage(
            sourceId: sourceId,
            bookUrl: bookUrl.isEmpty ? item.path : bookUrl,
            title: item.title,
            coverUrl: item.coverPath,
            author: item.author,
          ),
        ));
        return;
      }
    }
    final chapters =
        await ref.read(libraryRepositoryProvider).chapters(item.id);
    if (chapters.isEmpty) return;
    if (!mounted) return;
    if (item.isAudio) {
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AudioPlayerPage(item: item)));
    } else {
      final paths = chapters.map((c) => c.path!).toList();
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VideoPlayerPage(
              path: paths.first, playlist: paths, title: item.title)));
    }
  }

  Widget _card(MediaItem item) {
    final p = item.progress > 1 ? item.progress / 100 : item.progress;
    return GestureDetector(
      onTap: () => _openItem(item),
      onLongPress: () => _menu(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (ctx, c) => CoverImage(
                        path: item.coverPath,
                        title: item.title,
                        size: c.maxWidth,
                        isVideo: item.isVideo),
                  ),
                ),
                if (p > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(8)),
                      child: LinearProgressIndicator(
                        value: p,
                        minHeight: 4,
                        color: Theme.of(context).colorScheme.primary,
                        backgroundColor: Colors.black38,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            widget.kind == CollectionKind.favorite
                ? '${item.chapterCount} 章'
                : '${item.statusLabel} · ${item.chapterCount} 章',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }

  void _menu(MediaItem item) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  Text(PathUtils.formatSize(item.sizeBytes),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('查看路径'),
              subtitle: Text(item.path,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(ctx),
            ),
            if (widget.kind == CollectionKind.favorite)
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: const Text('移动到分组'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final groups = [
                    '默认',
                    ..._groups.where((g) => g != '默认'),
                  ];
                  final picked = await showDialog<String>(
                    context: context,
                    builder: (dctx) => SimpleDialog(
                      title: const Text('移动到分组'),
                      children: [
                        for (final g in groups)
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(dctx, g),
                            child: Text(g,
                                style: const TextStyle(fontSize: 15)),
                          ),
                      ],
                    ),
                  );
                  if (picked == null) return;
                  await ref
                      .read(libraryRepositoryProvider)
                      .moveFavorite(item.id, picked);
                  if (mounted) {
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('已移到 $picked 分组')));
                  }
                },
              ),
            ListTile(
              leading: Icon(Icons.favorite_border,
                  color: Theme.of(context).colorScheme.primary),
              title: Text(widget.kind == CollectionKind.favorite
                  ? '取消收藏'
                  : '加入收藏'),
              onTap: () async {
                Navigator.pop(ctx);
                final repo = ref.read(libraryRepositoryProvider);
                if (widget.kind == CollectionKind.favorite) {
                  await repo.removeFavorite(item.id);
                } else {
                  await repo.addFavorite(item.id, item.type);
                }
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 书签独立管理页（跨条目列出所有书签）
class BookmarkListPage extends ConsumerWidget {
  const BookmarkListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(libraryRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('书签')),
      body: FutureBuilder<List<dynamic>>(
        future: repo.bookmarks('').then((v) => v.cast<dynamic>()),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return const EmptyState(
                icon: Icons.bookmark_border,
                message: '还没有书签',
                hint: '播放时点书签按钮，会在当前位置留一个标记');
          }
          return ListView.separated(
            padding: pagePadding(context, top: 14, bottom: 24),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final b = rows[i];
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.palette.outline),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: context.palette.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.bookmark,
                          size: 17,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              PathUtils.formatDuration(
                                  (b.positionMs as int?) ?? 0),
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text((b.note as String?) ?? '书签',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
