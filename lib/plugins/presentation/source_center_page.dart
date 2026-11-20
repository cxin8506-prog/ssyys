import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../plugins/data/plugin_providers.dart';
import '../../plugins/model/plugin_source.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/login_web_page.dart';
import 'source_detail_page.dart';

/// 源管理：按插件折叠。
///
/// - 分组单位是包，不是个别源。一个插件包里的多个源折叠成一张卡，
///   点一下展开看里面的源，再点一下收起（用户要的新做法，两边
///   都没有现成实现，只能新做）。
/// - 卡片显示插件名 + 源数量 + 已启用数量；整包一键启用/停用开关
///   （包内任一源启用时整包开关显示开启）。
/// - 每张源卡：首字图标 + 名字 + 插件名徽章 + 版本号 + 简介 + 启用开关。
///   禁用的卡透明度 0.6；名字全名不截断（允许换行）。
/// - 排序：上移/下移按钮，顺序存为源 ID 列表。
/// - 筛选框（按名称包含匹配）、测试按钮、调试日志（最多保留 300 行）。
/// - 登录按钮只在源有登录地址时显示（卡片右上角“登录”）。
/// - 长按出设置/调试。删除删整包（源、目录、缓存、配置一起清）。
class SourceCenterPage extends ConsumerStatefulWidget {
  const SourceCenterPage({super.key});

  @override
  ConsumerState<SourceCenterPage> createState() => _SourceCenterPageState();
}

class _SourceCenterPageState extends ConsumerState<SourceCenterPage> {
  String _filter = '';
  final Set<String> _expanded = <String>{};
  bool _busy = false;
  String _stage = '';
  final List<String> _log = <String>[];
  final Map<String, Map<String, dynamic>?> _auth = {};
  String _authFingerprint = '';
  final _linkController = TextEditingController();

  @override
  void dispose() {
    _linkController.dispose();
    super.dispose();
  }

  void _logLine(String line) {
    setState(() {
      _log.add(line);
      if (_log.length > 300) {
        _log.removeRange(0, _log.length - 300);
      }
    });
  }

  String _pluginKey(PluginSource s) {
    final pid = s.pluginId ?? '';
    if (pid.isNotEmpty) return pid;
    if (s.group.isNotEmpty) return s.group;
    return s.id;
  }

  String _pluginName(PluginSource s) {
    final pid = s.pluginId ?? '';
    if (pid.isNotEmpty) return pid;
    if (s.group.isNotEmpty) return s.group;
    return s.name;
  }

  Map<String, List<PluginSource>> _grouped(List<PluginSource> list) {
    final map = <String, List<PluginSource>>{};
    for (final s in list) {
      final key = _pluginKey(s);
      map.putIfAbsent(key, () => <PluginSource>[]).add(s);
    }
    return map;
  }

  void _ensureAuth(List<PluginSource> list) {
    final fingerprint = list.map((s) => s.id).join(',');
    if (fingerprint == _authFingerprint) return;
    _authFingerprint = fingerprint;
    for (final s in list) {
      if (_auth.containsKey(s.id)) continue;
      _auth[s.id] = null;
      _loadAuth(s);
    }
  }

  Future<void> _loadAuth(PluginSource s) async {
    try {
      final engine = engineForSource(ref, s);
      await engine.attach(s);
      final info = await engine.loginInfo();
      if (!mounted) return;
      setState(() => _auth[s.id] = info);
    } catch (_) {
      // 没登录入口或查不到就当没有，不报错。
    }
  }

  String? _loginUrlOf(PluginSource s) {
    final info = _auth[s.id];
    if (info == null) return null;
    final url = info['loginUrl'] ?? info['url'] ?? info['login_url'];
    if (url == null) return null;
    final text = '$url';
    return text.isEmpty ? null : text;
  }

  String? _loginStateOf(PluginSource s) {
    final info = _auth[s.id];
    if (info == null) return null;
    final nick = info['nickname'] ?? info['name'] ?? info['username'];
    if (nick != null && '$nick'.isNotEmpty) return '$nick';
    final logged = info['loggedIn'] ?? info['isLogin'] ?? info['isLoggedIn'];
    if (logged == true) return '已登录';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sourceListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('源管理'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : _showImport,
            icon: const Icon(Icons.add, size: 18, color: Colors.white),
            label: const Text('导入', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('读取源失败：$e')),
        data: (list) {
          _ensureAuth(list);
          final order = ref.watch(sourceOrderProvider);
          final sorted = sortSourcesByOrder<PluginSource>(
            list,
            order,
            (s) => s.id,
            (s) => s.name,
          );
          final filtered = _filter.isEmpty
              ? sorted
              : sorted
                  .where((s) => s.name
                      .toLowerCase()
                      .contains(_filter.toLowerCase()))
                  .toList();
          final groups = _grouped(filtered);
          final enabledCount = list.where((s) => s.enabled).length;
          return Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: '筛选源（按名称包含匹配）',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _filter.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () =>
                                    setState(() => _filter = ''),
                              ),
                      ),
                      onChanged: (v) => setState(() => _filter = v),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          '共 ${list.length} 个源，已启用 $enabledCount 个 · 来自 ${groups.length} 个插件',
                          style: TextStyle(
                              fontSize: 12, color: context.subtleColor),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(() {}),
                          child: const Text('重新加载'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? EmptyState(
                            icon: Icons.extension_outlined,
                            title: '还没有导入插件',
                            hint: '程序本身不带任何源，所有源都来自导入的插件。点右上角“导入”装一个 JS/ZIP 或 JAR 插件包。',
                            actionLabel: '导入',
                            onAction: _showImport,
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                            children: [
                              for (final entry in groups.entries)
                                _PluginCard(
                                  pluginKey: entry.key,
                                  pluginName: _pluginName(entry.value.first),
                                  sources: entry.value,
                                  expanded: _expanded.contains(entry.key),
                                  onToggleExpand: () {
                                    setState(() {
                                      if (_expanded.contains(entry.key)) {
                                        _expanded.remove(entry.key);
                                      } else {
                                        _expanded.add(entry.key);
                                      }
                                    });
                                  },
                                  loginUrlOf: _loginUrlOf,
                                  loginStateOf: _loginStateOf,
                                  onLogin: (s) => _openLogin(s),
                                  onToggleSource: (s, v) =>
                                      _setEnabled(s, v),
                                  onTogglePackage: (sources, v) =>
                                      _setPackageEnabled(sources, v),
                                  onMove: (s, delta) => _move(s, delta, sorted),
                                  onTest: (s) => _testSource(s),
                                  onLongPress: (s) => _sourceMenu(s),
                                  onDeletePackage: (sources) =>
                                      _deletePackage(sources),
                                ),
                              if (_log.isNotEmpty) _LogPanel(log: _log),
                              const SizedBox(height: 8),
                              Text(
                                '程序本身不带任何源，所有源都来自导入的插件包，一个插件可以包含多个源。删除一个源即删整个插件。',
                                style: TextStyle(
                                    fontSize: 12, color: context.subtleColor),
                              ),
                              const SizedBox(height: 24),
                            ],
                          ),
                  ),
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
                        Text(_stage,
                            style: const TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _setEnabled(PluginSource s, bool v) async {
    try {
      await ref.read(sourceRepositoryProvider).setEnabled(s.id, v);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切换失败：$e')),
      );
      return;
    }
    ref.invalidate(sourceListProvider);
  }

  Future<void> _setPackageEnabled(
      List<PluginSource> sources, bool v) async {
    final repo = ref.read(sourceRepositoryProvider);
    for (final s in sources) {
      try {
        await repo.setEnabled(s.id, v);
      } catch (_) {}
    }
    ref.invalidate(sourceListProvider);
  }

  Future<void> _move(
      PluginSource s, int delta, List<PluginSource> sorted) async {
    final order = List<String>.from(ref.read(sourceOrderProvider));
    // 当前顺序以 sorted 为准：先把 sorted 的 id 写进 order，再交换。
    final ids = sorted.map((e) => e.id).toList();
    for (final id in ids) {
      if (!order.contains(id)) order.add(id);
    }
    final i = ids.indexOf(s.id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= ids.length) return;
    final tmp = ids[i];
    ids[i] = ids[j];
    ids[j] = tmp;
    await saveSourceOrder(ref, ids);
  }

  Future<void> _openLogin(PluginSource s) async {
    final url = _loginUrlOf(s);
    if (url == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LoginWebPage(url: url)),
    );
    // 登录页关掉后重新查登录状态；没拿到登录态不报成功。
    await _loadAuth(s);
    if (!mounted) return;
    final state = _loginStateOf(s);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(state == null ? '已关闭登录页，未确认到登录状态' : '已登录：$state'),
      ),
    );
  }

  Future<void> _testSource(PluginSource s) async {
    _logLine('测试 ${s.name} …');
    try {
      final engine = engineForSource(ref, s);
      await engine.attach(s);
      dynamic firstBook;
      try {
        final menus = await engine.invoke('categoryMenus', params: {});
        _logLine('分类：${_countOf(menus)} 个大类');
        final tabs = _firstTabs(menus);
        if (tabs.isNotEmpty) {
          final page = await engine.invoke(
            'categoryPage',
            params: {'menu': tabs.first, 'page': 1},
          );
          firstBook = _firstBook(page);
        }
      } catch (e) {
        _logLine('分类失败：$e，改用搜索“我”');
      }
      firstBook ??= await _searchFirst(engine, s);
      if (firstBook == null) {
        _logLine('${s.name} 测试失败：分类和搜索都没拿到书');
        return;
      }
      final bookUrl = '${firstBook['bookUrl'] ?? firstBook['url'] ?? ''}';
      final detail = await engine.invoke(
        'bookDetail',
        params: {'url': bookUrl},
      );
      final chapters = _chaptersOf(detail);
      _logLine('详情：${firstBook['title'] ?? firstBook['name'] ?? ''}，${chapters.length} 集');
      if (chapters.isNotEmpty) {
        final first = chapters.first;
        final url = await engine.invoke(
          'content',
          params: {'url': '${first['url'] ?? ''}'},
        );
        final media = _mediaUrlOf(url);
        _logLine(media.isEmpty ? '第一集解析失败：源没有返回可播放地址' : '第一集音频地址已解析');
      }
      _logLine('${s.name} 测试完成');
    } catch (e) {
      _logLine('${s.name} 测试失败：$e');
    }
    if (!mounted) return;
    setState(() {});
  }

  int _countOf(dynamic v) {
    if (v is List) return v.length;
    if (v is Map) {
      final l = v['menus'] ?? v['categories'] ?? v['list'];
      if (l is List) return l.length;
    }
    return 0;
  }

  List<dynamic> _firstTabs(dynamic menus) {
    final list = menus is List
        ? menus
        : (menus is Map
            ? (menus['menus'] ?? menus['categories'] ?? menus['list'])
            : null);
    if (list is! List || list.isEmpty) return const [];
    final first = list.first;
    if (first is! Map) return const [];
    final tabs = first['tabs'] ?? first['children'];
    if (tabs is List) return tabs;
    return const [];
  }

  dynamic _firstBook(dynamic page) {
    final list = page is List
        ? page
        : (page is Map ? (page['books'] ?? page['list']) : null);
    if (list is List && list.isNotEmpty) return list.first;
    return null;
  }

  Future<dynamic> _searchFirst(dynamic engine, PluginSource s) async {
    try {
      final raw = await engine.invoke(
        'search',
        params: {'keyword': '我', 'page': 1},
      );
      return _firstBook(raw);
    } catch (_) {
      return null;
    }
  }

  List<dynamic> _chaptersOf(dynamic detail) {
    if (detail is! Map) return const [];
    final list = detail['episodes'] ?? detail['chapters'] ?? detail['list'];
    if (list is List) return list;
    return const [];
  }

  String _mediaUrlOf(dynamic raw) {
    if (raw is String) return raw;
    if (raw is Map) {
      final u = raw['url'] ?? raw['audioUrl'] ?? raw['src'];
      return u == null ? '' : '$u';
    }
    return '';
  }

  Future<void> _sourceMenu(PluginSource s) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('设置'),
              onTap: () => Navigator.pop(ctx, 'settings'),
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('调试（跑一次测试，结果写进调试日志）'),
              onTap: () => Navigator.pop(ctx, 'test'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'settings') {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SourceDetailPage(sourceId: s.id),
        ),
      );
    } else if (choice == 'test') {
      await _testSource(s);
    }
  }

  Future<void> _deletePackage(List<PluginSource> sources) async {
    final names = sources.map((s) => s.name).join('、');
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这个插件？'),
        content: Text(
          '会删除该插件的全部源：$names，以及它的目录、缓存和配置。\n只想停用某个源的话，关掉它的开关即可。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final repo = ref.read(sourceRepositoryProvider);
    for (final s in sources) {
      try {
        await repo.remove(s.id);
      } catch (_) {}
    }
    ref.invalidate(sourceListProvider);
  }

  Future<void> _showImport() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('从文件导入（.zip / .jar）'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('从链接导入'),
              onTap: () => Navigator.pop(ctx, 'link'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'file') {
      await _pickAndInstall();
    } else if (choice == 'link') {
      await _importFromLink();
    }
  }

  Future<void> _pickAndInstall() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'jar'],
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) return;
      await _installFile(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选文件失败：$e')),
      );
    }
  }

  Future<void> _importFromLink() async {
    _linkController.clear();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从链接导入'),
        content: TextField(
          controller: _linkController,
          decoration: const InputDecoration(
            hintText: '粘贴插件链接（.zip / .jar）',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _linkController.text.trim()),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    setState(() {
      _busy = true;
      _stage = '正在下载插件…';
    });
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) throw Exception('链接格式不对');
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('下载失败，服务器返回 ${resp.statusCode}');
      }
      final bytes = resp.bodyBytes;
      if (bytes.length < 2) throw Exception('下载到的文件是空的');
      // 先按扩展名判断，不对时按魔数判断（PK 是 zip、MZ 是 dll/jar）。
      var ext = '';
      final lower = url.toLowerCase().split('?').first;
      if (lower.endsWith('.zip')) ext = 'zip';
      if (lower.endsWith('.jar')) ext = 'jar';
      if (ext.isEmpty) {
        if (bytes[0] == 0x50 && bytes[1] == 0x4B) ext = 'zip';
        if (bytes[0] == 0x4D && bytes[1] == 0x5A) ext = 'jar';
      }
      if (ext.isEmpty) throw Exception('认不出这个链接是什么格式，只支持 .zip / .jar');
      final tmp = await getTemporaryDirectory();
      final file = File(
          '${tmp.path}/import_${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      setState(() => _stage = '正在安装插件…');
      await _installFile(file.path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  /// 安装一个本地插件文件。返回新装的源；失败报人话错，不只报异常名。
  Future<void> _installFile(String path) async {
    final repo = ref.read(sourceRepositoryProvider);
    final before = await repo.loadAll();
    final beforeIds = before.map((s) => s.id).toSet();
    setState(() {
      _busy = true;
      _stage = '正在安装插件…';
    });
    try {
      final lower = path.toLowerCase();
      List<PluginSource> installed;
      if (lower.endsWith('.jar')) {
        installed = await repo.installJar(path);
      } else if (lower.endsWith('.zip')) {
        installed = await repo.installZip(path);
      } else {
        throw Exception('只支持 .zip / .jar 插件包');
      }
      if (installed.isEmpty) {
        throw Exception('这个包里没有读出任何源，包可能不对或已损坏');
      }
      // 同名重导 = 升级：先清旧条目再装（引擎组 install 里做）。
      // 新装的源默认不在勾选里：先停用，在卡片上打勾才出现。
      final fresh = installed.where((s) => !beforeIds.contains(s.id)).toList();
      for (final s in fresh) {
        try {
          await repo.setEnabled(s.id, false);
        } catch (_) {}
      }
      ref.invalidate(sourceListProvider);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已导入 ${installed.length} 个源，默认未启用，在卡片上打勾即可使用。',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：${_humanError(e)}')),
      );
    }
  }

  String _humanError(Object e) {
    final text = '$e';
    if (text.contains('32MB') || text.contains('过大')) {
      return '插件包超过 32MB，拒收了';
    }
    if (text.contains('classes.dex') || text.contains('dex')) {
      return '这个 JAR 里没有 classes.dex，不是我的听书格式源包';
    }
    if (text.contains('manifest')) {
      return 'ZIP 里没有 manifest.json，也读不到注册信息，不装空壳';
    }
    return text.replaceFirst('Exception: ', '');
  }
}

class _PluginCard extends StatelessWidget {
  final String pluginKey;
  final String pluginName;
  final List<PluginSource> sources;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final String? Function(PluginSource) loginUrlOf;
  final String? Function(PluginSource) loginStateOf;
  final ValueChanged<PluginSource> onLogin;
  final void Function(PluginSource, bool) onToggleSource;
  final void Function(List<PluginSource>, bool) onTogglePackage;
  final void Function(PluginSource, int) onMove;
  final ValueChanged<PluginSource> onTest;
  final ValueChanged<PluginSource> onLongPress;
  final ValueChanged<List<PluginSource>> onDeletePackage;

  const _PluginCard({
    required this.pluginKey,
    required this.pluginName,
    required this.sources,
    required this.expanded,
    required this.onToggleExpand,
    required this.loginUrlOf,
    required this.loginStateOf,
    required this.onLogin,
    required this.onToggleSource,
    required this.onTogglePackage,
    required this.onMove,
    required this.onTest,
    required this.onLongPress,
    required this.onDeletePackage,
  });

  @override
  Widget build(BuildContext context) {
    final enabledCount = sources.where((s) => s.enabled).length;
    final anyEnabled = enabledCount > 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  SourceAvatar(name: pluginName, size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pluginName,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '共 ${sources.length} 个源，已启用 $enabledCount 个',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.subtleColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 整包一键启用/停用：包内任一源启用时显示开启。
                  Switch(
                    value: anyEnabled,
                    onChanged: (v) => onTogglePackage(sources, v),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: context.subtleColor,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            for (final s in sources)
              _SourceRow(
                source: s,
                loginUrl: loginUrlOf(s),
                loginState: loginStateOf(s),
                onLogin: () => onLogin(s),
                onToggle: (v) => onToggleSource(s, v),
                onMoveUp: () => onMove(s, -1),
                onMoveDown: () => onMove(s, 1),
                onTest: () => onTest(s),
                onLongPress: () => onLongPress(s),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => onDeletePackage(sources),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('删除整个插件'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final PluginSource source;
  final String? loginUrl;
  final String? loginState;
  final VoidCallback onLogin;
  final ValueChanged<bool> onToggle;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onTest;
  final VoidCallback onLongPress;

  const _SourceRow({
    required this.source,
    required this.loginUrl,
    required this.loginState,
    required this.onLogin,
    required this.onToggle,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onTest,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final desc = source.description ?? '';
    final row = InkWell(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SourceAvatar(name: source.name, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          source.name,
                          maxLines: 2,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // 登录按钮只在源有登录地址时显示（右上角“登录”）。
                      if (loginUrl != null)
                        TextButton(
                          onPressed: onLogin,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            loginState ?? '登录',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    children: [
                      _Badge(
                          source.isAudio ? '听书' : (source.isVideo ? '视频' : source.type)),
                      _Badge('v${source.version}'),
                      _Badge(source.format),
                    ],
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.subtleColor,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _MiniButton(
                          icon: Icons.bug_report_outlined,
                          label: '测试',
                          onTap: onTest),
                      const SizedBox(width: 4),
                      _MiniButton(
                          icon: Icons.arrow_upward,
                          label: '上移',
                          onTap: onMoveUp),
                      const SizedBox(width: 4),
                      _MiniButton(
                          icon: Icons.arrow_downward,
                          label: '下移',
                          onTap: onMoveDown),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Switch(value: source.enabled, onChanged: onToggle),
          ],
        ),
      ),
    );
    // 禁用的卡透明度 0.6。
    return Opacity(opacity: source.enabled ? 1.0 : 0.6, child: row);
  }
}

class _Badge extends StatelessWidget {
  final String text;

  const _Badge(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MiniButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: context.subtleColor),
            const SizedBox(width: 2),
            Text(label,
                style: TextStyle(fontSize: 12, color: context.subtleColor)),
          ],
        ),
      ),
    );
  }
}

class _LogPanel extends StatelessWidget {
  final List<String> log;

  const _LogPanel({required this.log});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '调试日志（最多保留 300 行）',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              height: 220,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.palette.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView(
                children: [
                  for (final line in log)
                    Text(
                      line,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
