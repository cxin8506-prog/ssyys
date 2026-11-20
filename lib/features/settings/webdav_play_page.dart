import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/database/app_database.dart';
import '../../core/database/library_repository.dart';
import '../../core/utils/path_utils.dart';
import '../audio/data/audio_handler.dart';
import '../sync/webdav_client.dart';

/// WebDAV 播放：浏览服务器上的文件夹，文件夹成书、音频文件按自然排序为章节，
/// 能选集、能连续播、不断点；播放时自动预取后面 2 章。
///
/// 浏览用共享的 WebDavClient.listDirectory（旧页自写 PROPFIND 的毛病已修，
/// 审计 B 第 12 项）。断点走 LibraryRepository：bookId 是
/// `webdav:<文件夹 URL 的 SHA-256 前 32 位>`；handler 每 5 秒 / 暂停 /
/// 切章 / 播完调 onPluginProgress 回来写断点。
class WebDavPlayPage extends ConsumerStatefulWidget {
  const WebDavPlayPage({super.key});

  @override
  ConsumerState<WebDavPlayPage> createState() => _WebDavPlayPageState();
}

class _WebDavPlayPageState extends ConsumerState<WebDavPlayPage> {
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;

  bool _connected = false;
  bool _loading = false;
  String _error = '';
  String _path = '';
  List<WebDavItem> _items = const [];

  // 当前打开的文件夹（成书的那一级）
  String _bookPath = '';
  String _bookTitle = '';
  String _bookId = '';
  List<WebDavItem> _chapters = const [];
  Map<String, BookProgress> _chapterProgress = const {};
  int _playingIndex = -1;
  bool _startingPlay = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _urlCtrl.text = prefs.getString(AppConstants.keyWebDavPlayUrl) ?? '';
      _userCtrl.text = prefs.getString(AppConstants.keyWebDavPlayUser) ?? '';
      _passCtrl.text = prefs.getString(AppConstants.keyWebDavPlayPass) ?? '';
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyWebDavPlayUrl, _urlCtrl.text.trim());
    await prefs.setString(
        AppConstants.keyWebDavPlayUser, _userCtrl.text.trim());
    await prefs.setString(
        AppConstants.keyWebDavPlayPass, _passCtrl.text);
  }

  WebDavClient get _client => WebDavClient(
        baseUrl: _urlCtrl.text.trim(),
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
      );

  Map<String, String> get _authHeaders => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${_userCtrl.text.trim()}:${_passCtrl.text}'))}',
      };

  String _joinPath(String base, String name) =>
      base.isEmpty ? name : '$base/$name';

  Uri _fileUri(String path) {
    var base = _urlCtrl.text.trim();
    if (!base.endsWith('/')) base = '$base/';
    final encoded = path
        .split('/')
        .map((s) => Uri.encodeComponent(s))
        .join('/');
    return Uri.parse('$base$encoded');
  }

  bool _isAudio(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return AppConstants.audioExtensions
        .contains(name.substring(dot + 1).toLowerCase());
  }

  /// 自然排序：第 2 集 < 第 10 集（纯字典序会排反）。
  int _naturalCompare(String a, String b) {
    final ra = RegExp(r'\d+|\D+').allMatches(a).map((m) => m.group(0)!);
    final rb = RegExp(r'\d+|\D+').allMatches(b).map((m) => m.group(0)!);
    final la = ra.toList();
    final lb = rb.toList();
    for (var i = 0; i < la.length && i < lb.length; i++) {
      final na = int.tryParse(la[i]);
      final nb = int.tryParse(lb[i]);
      if (na != null && nb != null) {
        if (na != nb) return na.compareTo(nb);
      } else {
        final c = la[i].toLowerCase().compareTo(lb[i].toLowerCase());
        if (c != 0) return c;
      }
    }
    return la.length.compareTo(lb.length);
  }

  Future<void> _connect() async {
    if (_urlCtrl.text.trim().isEmpty) {
      setState(() => _error = '先填服务器地址');
      return;
    }
    await _saveConfig();
    setState(() {
      _loading = true;
      _error = '';
      _bookPath = '';
    });
    try {
      final items = await _client.listDirectory('');
      if (!mounted) return;
      setState(() {
        _connected = true;
        _path = '';
        _items = items;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = WebDavClient.friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openDir(String path) async {
    setState(() {
      _loading = true;
      _error = '';
      _bookPath = '';
    });
    try {
      final items = await _client.listDirectory(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _items = items;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = WebDavClient.friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 打开一个文件夹当书：音频文件按自然排序为章节，读每章断点。
  Future<void> _openBook(String folderPath) async {
    final title = folderPath.split('/').last;
    final bookId =
        'webdav:${sha256.convert(utf8.encode(folderPath)).toString().substring(0, 32)}';
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final items = await _client.listDirectory(folderPath);
      final chapters = items.where((e) => !e.isDir && _isAudio(e.name)).toList();
      chapters.sort((a, b) => _naturalCompare(a.name, b.name));
      if (chapters.isEmpty) {
        if (mounted) {
          setState(() => _error = '这个文件夹里没有音频文件');
        }
        return;
      }
      final repo = ref.read(libraryRepositoryProvider);
      // 进书就登记：断点、章节表都落库
      await repo.upsertMediaItem(MediaItemsCompanion.insert(
        id: bookId,
        title: title,
        sourceId: 'webdav',
        sourceName: 'WebDAV',
        type: 'audio',
        createdAt: DateTime.now(),
      ));
      await repo.saveChapters(
        bookId,
        chapters
            .map((c) => <String, dynamic>{
                  'name': c.name,
                  'url': _fileUri(_joinPath(folderPath, c.name)).toString(),
                })
            .toList(),
      );
      final progress = <String, BookProgress>{};
      for (final c in chapters) {
        final url = _fileUri(_joinPath(folderPath, c.name)).toString();
        final p = await repo.getProgress(bookId, url);
        if (p != null) progress[url] = p;
      }
      if (!mounted) return;
      setState(() {
        _bookPath = folderPath;
        _bookTitle = title;
        _bookId = bookId;
        _chapters = chapters;
        _chapterProgress = progress;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = WebDavClient.friendlyError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _chapterUrl(int index) =>
      _fileUri(_joinPath(_bookPath, _chapters[index].name)).toString();

  Future<File> _prefetchFile(int index) async {
    final cache = await PathUtils.cacheDir;
    final dir = Directory(
        '${cache.path}${Platform.pathSeparator}webdav_prefetch'
        '${Platform.pathSeparator}${_bookId}');
    await dir.create(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$index'
        '_${_chapters[index].name}');
  }

  /// 播某章时用的地址：已预取到本地就用本地文件，否则用远程 URL。
  Future<String> _effectiveUrl(int index) async {
    try {
      final local = await _prefetchFile(index);
      if (await local.exists() && await local.length() > 0) {
        return local.path;
      }
    } catch (_) {}
    return _chapterUrl(index);
  }

  /// 播放时自动预取后面 2 章（后台下，不堵播放）。
  Future<void> _prefetchNext(int fromIndex) async {
    for (var i = fromIndex + 1;
        i <= fromIndex + 2 && i < _chapters.length;
        i++) {
      try {
        final local = await _prefetchFile(i);
        if (await local.exists() && await local.length() > 0) continue;
        final resp = await http
            .get(_fileUri(_joinPath(_bookPath, _chapters[i].name)),
                headers: _authHeaders)
            .timeout(const Duration(minutes: 5));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          await local.writeAsBytes(resp.bodyBytes);
        }
      } catch (_) {
        // 预取失败不影响播放，下次播这章时再走远程
      }
    }
  }

  Future<void> _play(int index) async {
    if (_startingPlay) return;
    setState(() {
      _startingPlay = true;
      _error = '';
    });
    try {
      final handler = ref.read(audioHandlerProvider);
      final repo = ref.read(libraryRepositoryProvider);
      final bookId = _bookId;
      final bookPath = _bookPath;
      final chapters = _chapters;
      final chapterMaps = List<Map<String, dynamic>>.generate(
        chapters.length,
        (i) => <String, dynamic>{
          'title': chapters[i].name,
          'url': _chapterUrl(i),
        },
      );
      handler.onResolveChapter = (i) async {
        if (i < 0 || i >= chapters.length) return null;
        return _effectiveUrl(i);
      };
      handler.onResolveHeaders = (_) => _authHeaders;
      handler.onPluginProgress =
          (chapterIndex, positionMs, durationMs, force) async {
        // setPluginBook 开头的 _flushProgress 会先触发一次旧书的回调，
        // 只认当前这本书、当前章节表里的下标
        if (handler.currentBookKey != bookId) return;
        if (chapterIndex < 0 || chapterIndex >= chapters.length) return;
        final finished =
            durationMs > 0 && positionMs >= durationMs - 2000;
        await repo.saveProgress(
          bookId: bookId,
          chapterUrl: _chapterUrl(chapterIndex),
          positionMs: positionMs,
          durationMs: durationMs,
          isFinished: finished,
        );
      };
      handler.onPluginSkipNext = () async {
        final next = handler.pluginChapterIndex + 1;
        if (next < chapters.length) await _play(next);
      };
      handler.onPluginSkipPrevious = () async {
        final prev = handler.pluginChapterIndex - 1;
        if (prev >= 0) await _play(prev);
      };
      await handler.setPluginBook(
        bookKey: bookId,
        sourceId: 'webdav',
        bookUrl: _fileUri(bookPath).toString(),
        title: _bookTitle,
        chapters: chapterMaps,
        initialIndex: index,
      );
      // 先把当前章的地址写进缓存，播起来不用再解析
      handler.cacheChapterUrl(index, await _effectiveUrl(index));
      // 断点续播：这章听到哪了，从那继续（快播完的从头播）
      var startAt = Duration.zero;
      final saved = _chapterProgress[_chapterUrl(index)];
      if (saved != null &&
          saved.durationMs > 0 &&
          saved.positionMs > 0 &&
          saved.positionMs < saved.durationMs - 5000) {
        startAt = Duration(milliseconds: saved.positionMs);
      }
      await handler.playPluginChapter(index, startAt: startAt);
      if (!mounted) return;
      setState(() => _playingIndex = index);
      // 播起来后在后台预取后面 2 章
      unawaited(_prefetchNext(index));
    } catch (e) {
      if (mounted) {
        setState(() => _error = '播放失败：${WebDavClient.friendlyError(e)}');
      }
    } finally {
      if (mounted) setState(() => _startingPlay = false);
    }
  }

  String _formatMs(int ms) {
    final total = ms ~/ 1000;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_bookPath.isEmpty ? 'WebDAV 播放' : _bookTitle),
        leading: _bookPath.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _bookPath = ''),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (_bookPath.isEmpty) ...[
            TextField(
              controller: _urlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://dav.jianguoyun.com/dav/',
              ),
              onChanged: (_) => _saveConfig(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: '账号'),
              onChanged: (_) => _saveConfig(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: _obscurePass,
              decoration: InputDecoration(
                labelText: '密码（应用密码）',
                suffixIcon: IconButton(
                  icon: Icon(_obscurePass
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () =>
                      setState(() => _obscurePass = !_obscurePass),
                ),
              ),
              onChanged: (_) => _saveConfig(),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.link_outlined),
              label: const Text('连接'),
              onPressed: _loading ? null : _connect,
            ),
            const SizedBox(height: 16),
            if (_connected) _breadcrumb(),
          ] else
            _bookView(),
          const SizedBox(height: 12),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error.isNotEmpty)
            Text(_error,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.red)),
          if (_bookPath.isEmpty && _connected && !_loading) ...[
            const SizedBox(height: 8),
            ..._items.map((item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(item.isDir
                      ? Icons.folder_outlined
                      : Icons.audiotrack_outlined),
                  title: Text(item.displayName),
                  subtitle: item.isDir
                      ? const Text('文件夹，点进去当书听')
                      : Text(PathUtils.formatSize(item.size)),
                  onTap: item.isDir
                      ? () => _openBook(_joinPath(_path, item.name))
                      : null,
                )),
            if (_items.isEmpty)
              const Text('这个目录是空的', style: TextStyle(fontSize: 13)),
          ],
        ],
      ),
    );
  }

  Widget _breadcrumb() {
    final segs = _path.isEmpty ? <String>[] : _path.split('/');
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ActionChip(
          label: const Text('根目录'),
          onPressed: () => _openDir(''),
        ),
        for (var i = 0; i < segs.length; i++) ...[
          const Text('/'),
          ActionChip(
            label: Text(segs[i]),
            onPressed: () =>
                _openDir(segs.sublist(0, i + 1).join('/')),
          ),
        ],
      ],
    );
  }

  Widget _bookView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('${_chapters.length} 集',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('播放全部'),
              onPressed: _startingPlay ? null : () => _play(_resumeIndex()),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(_chapters.length, (i) {
          final item = _chapters[i];
          final url = _chapterUrl(i);
          final saved = _chapterProgress[url];
          final playing = _playingIndex == i;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              playing ? Icons.volume_up : Icons.audiotrack_outlined,
              color: playing
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            title: Text(item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight:
                        playing ? FontWeight.w600 : FontWeight.normal)),
            subtitle: saved == null || saved.positionMs <= 0
                ? null
                : Text('听到 ${_formatMs(saved.positionMs)}',
                    style: const TextStyle(fontSize: 12)),
            onTap: _startingPlay ? null : () => _play(i),
          );
        }),
      ],
    );
  }

  /// “播放全部”从哪一集起：上次听到哪集、从那集继续；都没听过从第 1 集起。
  int _resumeIndex() {
    // 用已加载的断点表找最后一集
    var latest = -1;
    var latestMs = 0;
    for (var i = 0; i < _chapters.length; i++) {
      final saved = _chapterProgress[_chapterUrl(i)];
      if (saved != null &&
          saved.updatedAt.millisecondsSinceEpoch > latestMs) {
        latestMs = saved.updatedAt.millisecondsSinceEpoch;
        latest = i;
      }
    }
    if (latest < 0) return 0;
    final saved = _chapterProgress[_chapterUrl(latest)]!;
    // 最后一集快听完了，从下一集起
    if (saved.durationMs > 0 &&
        saved.positionMs >= saved.durationMs - 5000 &&
        latest + 1 < _chapters.length) {
      return latest + 1;
    }
    return latest;
  }
}
