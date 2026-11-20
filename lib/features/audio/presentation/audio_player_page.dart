import 'dart:async';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:local_media_app/core/database/library_repository.dart';
import 'package:local_media_app/features/ua/ua_resolver.dart';
import '../data/audio_handler.dart';

String _fmt(Duration d) {
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

String _fmtMs(int ms) => _fmt(Duration(milliseconds: ms));

/// 听书播放页：从上到下照我的听书 2.8.x——
/// ← 返回 + 书名 + 日志 + ♡ 收藏 + ⋮；源名；模糊背景 + 圆形封面；
/// 简介/集数行；⏰定时关闭 | 书签 | 倍速 | 播放列表；
/// |◀ ◀◀ ▶ ▶▶ ▶|。
///
/// 页面只是遥控器：播放住在 [MyAudioHandler]（前台服务）里，
/// 返回/切 App 不停播。尺寸照 Voice：左右边距 24dp、播放键 104dp、
/// 封面最小 120dp；横屏（宽 ≥600dp 且高 ≥360dp）改左右分栏。
///
/// [bookId] 只用来做收藏/书签的 key（播放页不自建队列）：
/// 进 /player 前调用方必须先让 handler 播起来（source_book_page 调
/// setPluginBook + playPluginChapter），本页只遥控 handler 正在播的内容。
class AudioPlayerPage extends ConsumerStatefulWidget {
  final String? bookId;
  final String? bookTitle;
  final String? coverUrl;
  final String? author;
  final String? sourceName;

  /// 源网页地址（日志按钮用）：有就打开 WebView，没有就不显示网页入口。
  final String? sourceUrl;

  /// 可切换的音色：[{id, name}]，没有就不显示音色按钮。
  final List<Map<String, dynamic>> voices;
  final String? currentVoiceId;

  /// 切音色时向源要新地址（参数：音色 id），返回新播放地址。
  final Future<String> Function(String voiceId)? onSwitchVoice;

  const AudioPlayerPage({
    super.key,
    this.bookId,
    this.bookTitle,
    this.coverUrl,
    this.author,
    this.sourceName,
    this.sourceUrl,
    this.voices = const [],
    this.currentVoiceId,
    this.onSwitchVoice,
  });

  @override
  ConsumerState<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends ConsumerState<AudioPlayerPage> {
  MyAudioHandler get _handler => ref.read(audioHandlerProvider);

  bool _favorite = false;
  StreamSubscription<String>? _errorSub;

  /// 当前音色 id（来自 widget.currentVoiceId，切换后更新）。
  String? _voiceId;

  /// 当前在播的章下标（插件书走 handler.pluginChapterIndex，
  /// 本地书走 handler.currentIndex）。
  int get _currentIndex => _handler.currentIndex;

  String get _favBookId =>
      widget.bookId ?? _handler.currentBookKey ?? '';

  String get _bookmarkBookId => _favBookId;

  @override
  void initState() {
    super.initState();
    _voiceId = widget.currentVoiceId;
    _errorSub = _handler.errorStream.listen((msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    });
    _loadFavorite();
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    super.dispose();
  }

  Future<void> _loadFavorite() async {
    final id = _favBookId;
    if (id.isEmpty) return;
    try {
      final repo = ref.read(libraryRepositoryProvider);
      final fav = await repo.isFavorite(id);
      if (mounted) setState(() => _favorite = fav);
    } catch (_) {}
  }

  Future<void> _toggleFavorite() async {
    final id = _favBookId;
    if (id.isEmpty) return;
    try {
      final repo = ref.read(libraryRepositoryProvider);
      if (_favorite) {
        await repo.removeFavorite(id);
      } else {
        await repo.addFavorite(id);
      }
      if (mounted) {
        setState(() => _favorite = !_favorite);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_favorite ? '已加入收藏' : '已取消收藏')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('收藏失败：$e')),
        );
      }
    }
  }

  /// 日志按钮：打开源网页确认能不能播（我的听书的做法）。
  void _openSourcePage() {
    final url = widget.sourceUrl;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这本书没有源网页')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(widget.sourceName ?? '源网页')),
        body: WebView(
          initialUrl: url,
          javascriptMode: JavascriptMode.unrestricted,
        ),
      ),
    ));
  }

  /// 右上角 UA 切换入口：调 UA 解析器换 UA 后重播当前集。
  /// 只在插件书（有 sourceId）时显示。
  /// 注意：只调 resolve() 不够——按站记忆优先于 desktop 标志，
  /// 必须把换到的 UA 用 rememberSiteUa() 记下来再重播，否则还是旧 UA。
  Future<void> _switchUa(bool desktop) async {
    final sourceId = _handler.currentSourceId;
    if (sourceId == null || sourceId.isEmpty) return;
    try {
      final resolver = ref.read(uaResolverProvider);
      final ua = await resolver.resolve(
        sourceId: sourceId,
        sourceName: widget.sourceName ?? '',
        desktop: desktop,
      );
      await resolver.rememberSiteUa(sourceId, ua);
      resolver.notifyUaChanged();
      await _handler.playPluginChapter(_handler.pluginChapterIndex);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(desktop ? '已切换到电脑版 UA，正在重播' : '已切换到手机版 UA，正在重播')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('换 UA 失败：$e')),
        );
      }
    }
  }

  void _showUaSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ListTile(title: Text('切换 UA 后重播当前集')),
            ListTile(
              leading: const Icon(Icons.smartphone),
              title: const Text('手机版 UA'),
              onTap: () {
                Navigator.pop(ctx);
                _switchUa(false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.computer),
              title: const Text('电脑版 UA'),
              onTap: () {
                Navigator.pop(ctx);
                _switchUa(true);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showSleepSheet() {
    final handler = _handler;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ListTile(title: Text('定时关闭')),
            for (final m in <int>[5, 15, 30, 60])
              ListTile(
                title: Text('$m 分钟后停止'),
                trailing: handler.sleepRemaining != null &&
                        handler.sleepRemaining!.inMinutes == m
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  handler.setSleepTimer(minutes: m);
                  setState(() {});
                },
              ),
            ListTile(
              title: const Text('自定义分钟数…'),
              onTap: () async {
                Navigator.pop(ctx);
                final min = await _pickCustomSleepMinutes();
                if (min != null) {
                  handler.setSleepTimer(minutes: min);
                  setState(() {});
                }
              },
            ),
            ListTile(
              title: const Text('播到本集末停'),
              trailing: handler.sleepUntilChapterEnd
                  ? const Icon(Icons.check)
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                handler.setSleepTimer(untilChapterEnd: true);
                setState(() {});
              },
            ),
            ListTile(
              title: const Text('播完 3 集停'),
              onTap: () {
                Navigator.pop(ctx);
                handler.setSleepTimer(episodes: 3);
                setState(() {});
              },
            ),
            ListTile(
              title: const Text('取消定时'),
              onTap: () {
                Navigator.pop(ctx);
                handler.cancelSleepTimer();
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<int?> _pickCustomSleepMinutes() async {
    final controller = TextEditingController();
    final last = await _handler.lastSleepMinutes();
    if (last != null) controller.text = '$last';
    final min = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义定时'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入分钟数（1–240）',
            suffixText: '分钟',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v != null && v >= 1 && v <= 240) Navigator.pop(ctx, v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return min;
  }

  /// 书签：点一下看列表，长按新建。
  Future<void> _showBookmarks() async {
    final repo = ref.read(libraryRepositoryProvider);
    List<dynamic> list = <dynamic>[];
    try {
      list = await repo.getBookmarks(_bookmarkBookId) as List<dynamic>;
    } catch (_) {}
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.6,
            child: Column(
              children: <Widget>[
                ListTile(
                  title: const Text('书签'),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.bookmark_add, size: 18),
                    label: const Text('加书签'),
                    onPressed: () async {
                      await _addBookmarkHere();
                      try {
                        final fresh = await repo
                            .getBookmarks(_bookmarkBookId) as List<dynamic>;
                        setSheet(() {
                          list.clear();
                          list.addAll(fresh);
                        });
                      } catch (_) {}
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: list.isEmpty
                      ? const Center(
                          child: Text('还没有书签，听到想留的地方长按书签按钮新建'))
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (_, i) {
                            final dynamic b = list[i];
                            String note = '';
                            int posMs = 0;
                            try {
                              note = '${b.note ?? ''}';
                              posMs = (b.positionMs as int?) ?? 0;
                            } catch (_) {}
                            return ListTile(
                              leading:
                                  const Icon(Icons.bookmark, size: 20),
                              title: Text(
                                  note.isEmpty ? '书签 ${i + 1}' : note,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(_fmtMs(posMs)),
                              onTap: () {
                                Navigator.pop(context);
                                _handler.seek(
                                    Duration(milliseconds: posMs));
                              },
                              onLongPress: () async {
                                try {
                                  await repo.deleteBookmark(b.id);
                                  final fresh = await repo.getBookmarks(
                                      _bookmarkBookId) as List<dynamic>;
                                  setSheet(() {
                                    list.clear();
                                    list.addAll(fresh);
                                  });
                                } catch (_) {}
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addBookmarkHere() async {
    final pos = _handler.player.position.inMilliseconds;
    try {
      final repo = ref.read(libraryRepositoryProvider);
      await repo.saveBookmark(
        bookId: _bookmarkBookId,
        chapterUrl: _currentChapterUrl(),
        positionMs: pos,
        note: _currentChapterTitle(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('书签已保存（${_fmtMs(pos)}）')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存书签失败：$e')),
        );
      }
    }
  }

  String _currentChapterUrl() {
    final items = _handler.queue.value;
    final idx = _currentIndex;
    if (idx >= 0 && idx < items.length) return items[idx].id;
    return '';
  }

  String _currentChapterTitle() {
    final items = _handler.queue.value;
    final idx = _currentIndex;
    if (idx >= 0 && idx < items.length) return items[idx].title;
    return widget.bookTitle ?? '';
  }

  /// 播放列表：独立入口，点一行切章。
  void _showPlaylist() {
    final items = _handler.queue.value;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有播放列表')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: <Widget>[
              const ListTile(title: Text('播放列表')),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final current = i == _currentIndex;
                    return ListTile(
                      title: Text(items[i].title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: current
                          ? const Icon(Icons.play_arrow, size: 20)
                          : null,
                      selected: current,
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          await _handler.jumpToChapter(i);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('切章失败：$e')),
                            );
                          }
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 音色切换：选完从当前进度接着播。
  void _showVoiceSheet() {
    if (widget.voices.isEmpty) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ListTile(title: Text('音色')),
            for (final v in widget.voices)
              ListTile(
                title: Text('${v['name'] ?? v['id']}'),
                trailing: '${v['id']}' == _voiceId
                    ? const Icon(Icons.check)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  await _switchVoice('${v['id']}');
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _switchVoice(String id) async {
    final resolver = widget.onSwitchVoice;
    if (resolver == null || id == _voiceId) return;
    final pos = _handler.player.position;
    try {
      final url = await resolver(id);
      if (url.isEmpty || !mounted) return;
      final idx = _currentIndex;
      _handler.cacheChapterUrl(idx, url);
      await _handler.playPluginChapter(idx, startAt: pos);
      if (mounted) setState(() => _voiceId = id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换音色失败：$e')),
        );
      }
    }
  }

  /// 单书设置：跳过静音、音量增强、跳过片头/片尾（按书单独存）。
  void _showBookSettings() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('这本书的播放设置')),
                SwitchListTile(
                  title: const Text('跳过静音'),
                  value: _handler.skipSilenceEnabled,
                  onChanged: (v) async {
                    await _handler.setSkipSilence(v);
                    setSheet(() {});
                    setState(() {});
                  },
                ),
                ListTile(
                  title: Text(
                      '音量增强：${(_handler.volumeBoost * 100).round()}%'),
                  subtitle: Slider(
                    value: _handler.volumeBoost,
                    min: 0,
                    max: 1.5,
                    divisions: 15,
                    label: '${(_handler.volumeBoost * 100).round()}%',
                    onChanged: (v) async {
                      await _handler.setVolumeBoost(v);
                      setSheet(() {});
                      setState(() {});
                    },
                  ),
                ),
                ListTile(
                  title: const Text('跳过片头'),
                  trailing: DropdownButton<int>(
                    value: <int>[0, 5, 10, 15, 30, 60]
                            .contains(_handler.skipIntroSeconds)
                        ? _handler.skipIntroSeconds
                        : 0,
                    items: const <int>[0, 5, 10, 15, 30, 60]
                        .map((s) => DropdownMenuItem<int>(
                              value: s,
                              child: Text(s == 0 ? '不跳' : '$s 秒'),
                            ))
                        .toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      await _handler.setSkipIntroSeconds(v);
                      setSheet(() {});
                      setState(() {});
                    },
                  ),
                ),
                ListTile(
                  title: const Text('跳过片尾'),
                  trailing: DropdownButton<int>(
                    value: <int>[0, 5, 10, 15, 30, 60]
                            .contains(_handler.skipOutroSeconds)
                        ? _handler.skipOutroSeconds
                        : 0,
                    items: const <int>[0, 5, 10, 15, 30, 60]
                        .map((s) => DropdownMenuItem<int>(
                              value: s,
                              child: Text(s == 0 ? '不跳' : '$s 秒'),
                            ))
                        .toList(),
                    onChanged: (v) async {
                      if (v == null) return;
                      await _handler.setSkipOutroSeconds(v);
                      setSheet(() {});
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showLogs() async {
    List<dynamic> logs = <dynamic>[];
    try {
      final repo = ref.read(libraryRepositoryProvider);
      logs = await repo.getLogs(limit: 100) as List<dynamic>;
    } catch (_) {}
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: <Widget>[
              const ListTile(title: Text('日志')),
              const Divider(height: 1),
              Expanded(
                child: logs.isEmpty
                    ? const Center(child: Text('暂无日志'))
                    : ListView.builder(
                        itemCount: logs.length,
                        itemBuilder: (_, i) {
                          final dynamic l = logs[i];
                          String msg = '';
                          try {
                            msg = '${l.message ?? l}';
                          } catch (_) {
                            msg = '$l';
                          }
                          return ListTile(
                            dense: true,
                            title: Text(msg,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('查看日志'),
              onTap: () {
                Navigator.pop(ctx);
                _showLogs();
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('这本书的播放设置'),
              subtitle: const Text('跳过静音 / 音量增强 / 跳过片头片尾'),
              onTap: () {
                Navigator.pop(ctx);
                _showBookSettings();
              },
            ),
            if (_handler.currentSourceId != null &&
                _handler.currentSourceId!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.public),
                title: const Text('换个 UA 再试'),
                subtitle: const Text('播不出来时换 UA 重播当前集'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showUaSheet();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, Color primary, String? coverUrl) {
    const double size = 220;
    final Widget placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            primary.withOpacity(0.75),
            Theme.of(context).colorScheme.secondary.withOpacity(0.55),
          ],
        ),
      ),
      child: const Icon(Icons.graphic_eq, size: 72, color: Colors.white),
    );
    if (coverUrl == null || !coverUrl.startsWith('http')) {
      return placeholder;
    }
    return ClipOval(
      child: Image.network(
        coverUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }

  Widget _blurredBackground(String? coverUrl) {
    if (coverUrl == null || !coverUrl.startsWith('http')) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Image.network(
          coverUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final primary = Theme.of(context).colorScheme.primary;
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 600 && size.height >= 360;

    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      initialData: handler.mediaItem.value,
      builder: (context, mediaSnap) {
        final mediaItem = mediaSnap.data;
        final title = mediaItem?.title ??
            widget.bookTitle ??
            _handler.currentBookTitle;
        final coverUrl = mediaItem?.artUri?.toString() ?? widget.coverUrl;
        if (mediaItem == null &&
            widget.bookId == null &&
            title.isEmpty) {
          return _buildEmpty(context);
        }
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回',
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              title.isEmpty ? '正在播放' : title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.article_outlined),
                tooltip: '日志',
                onPressed: _openSourcePage,
              ),
              IconButton(
                icon: Icon(
                    _favorite ? Icons.favorite : Icons.favorite_border),
                tooltip: '收藏',
                onPressed: _toggleFavorite,
              ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                tooltip: '更多',
                onPressed: _showMoreMenu,
              ),
            ],
          ),
          body: SafeArea(
            child: Stack(
              children: <Widget>[
                _blurredBackground(coverUrl),
                Container(color: Theme.of(context)
                    .colorScheme
                    .background
                    .withOpacity(0.55)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: isWide
                      ? _buildWideBody(context, handler, primary, coverUrl)
                      : _buildNarrowBody(
                          context, handler, primary, coverUrl),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('播放器')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.play_circle_outline,
                  size: 72,
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withOpacity(0.6)),
              const SizedBox(height: 18),
              const Text('还没有在播的内容',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('搜一部喜欢的书或视频，播一半退出后会记在这里',
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => context.go('/search'),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('去找'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 窄屏：从上到下——源名、圆形封面、简介/集数行、工具行、进度条、控制行。
  Widget _buildNarrowBody(BuildContext context, MyAudioHandler handler,
      Color primary, String? coverUrl) {
    return SingleChildScrollView(
      child: Column(
        children: <Widget>[
          const SizedBox(height: 12),
          if ((widget.sourceName ?? '').isNotEmpty)
            Text(widget.sourceName!,
                style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          _cover(context, primary, coverUrl),
          const SizedBox(height: 20),
          _buildTitleRows(context, handler),
          const SizedBox(height: 12),
          _buildToolRow(context, handler),
          const SizedBox(height: 8),
          _buildSleepChip(context, handler),
          const SizedBox(height: 8),
          _buildProgress(context, handler, primary),
          const SizedBox(height: 12),
          _buildControls(context, handler, primary),
          const SizedBox(height: 12),
          _buildSpeedRow(context, handler, primary),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 宽屏（横屏）：左栏封面 + 标题，右栏控制区。
  Widget _buildWideBody(BuildContext context, MyAudioHandler handler,
      Color primary, String? coverUrl) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _cover(context, primary, coverUrl),
              const SizedBox(height: 16),
              _buildTitleRows(context, handler),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _buildToolRow(context, handler),
                const SizedBox(height: 8),
                _buildSleepChip(context, handler),
                const SizedBox(height: 8),
                _buildProgress(context, handler, primary),
                const SizedBox(height: 12),
                _buildControls(context, handler, primary),
                const SizedBox(height: 12),
                _buildSpeedRow(context, handler, primary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleRows(BuildContext context, MyAudioHandler handler) {
    final items = handler.queue.value;
    final idx = _currentIndex;
    final chapter = idx >= 0 && idx < items.length ? items[idx].title : '';
    final total = items.length;
    return Column(
      children: <Widget>[
        if ((widget.author ?? '').isNotEmpty)
          Text(widget.author!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        if (chapter.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            total > 0 ? '$chapter（${idx + 1} / $total）' : chapter,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );
  }

  /// 工具行：⏰定时关闭 | 书签（长按新建） | 倍速 | 播放列表。
  Widget _buildToolRow(BuildContext context, MyAudioHandler handler) {
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      initialData: handler.playbackState.valueOrNull,
      builder: (context, snap) {
        final speed = snap.data?.speed ?? handler.currentSpeed;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            TextButton.icon(
              icon: const Icon(Icons.timer_outlined, size: 18),
              label: const Text('定时关闭'),
              onPressed: _showSleepSheet,
            ),
            GestureDetector(
              onLongPress: _addBookmarkHere,
              child: TextButton.icon(
                icon: const Icon(Icons.bookmark_border, size: 18),
                label: const Text('书签'),
                onPressed: _showBookmarks,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.speed, size: 18),
              label: Text('倍速: ${speed.toStringAsFixed(1)}'),
              onPressed: () => _showSpeedSheet(handler),
            ),
            TextButton.icon(
              icon: const Icon(Icons.playlist_play, size: 18),
              label: const Text('播放列表'),
              onPressed: _showPlaylist,
            ),
          ],
        );
      },
    );
  }

  void _showSpeedSheet(MyAudioHandler handler) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ListTile(title: Text('倍速')),
            Wrap(
              spacing: 8,
              children: <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5, 3.0]
                  .map((v) => ChoiceChip(
                        label: Text('${v}x'),
                        selected: handler.currentSpeed == v,
                        onSelected: (_) {
                          Navigator.pop(ctx);
                          handler.setSpeed(v);
                          setState(() {});
                        },
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSleepChip(BuildContext context, MyAudioHandler handler) {
    return StreamBuilder<Duration?>(
      stream: handler.sleepRemainingStream,
      builder: (context, snap) {
        final left = snap.data;
        if (left == null && !handler.sleepUntilChapterEnd) {
          return const SizedBox.shrink();
        }
        final text = handler.sleepUntilChapterEnd
            ? '播到本集末停（点一下取消）'
            : '定时：还剩 ${_fmt(left ?? Duration.zero)}（点一下取消）';
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            handler.cancelSleepTimer();
            setState(() {});
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(text,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary)),
          ),
        );
      },
    );
  }

  Widget _buildProgress(
      BuildContext context, MyAudioHandler handler, Color primary) {
    return StreamBuilder<Duration?>(
      stream: handler.durationStream,
      builder: (context, durSnap) {
        final totalMs = (durSnap.data ?? Duration.zero).inMilliseconds;
        return StreamBuilder<Duration>(
          stream: handler.position,
          initialData: handler.player.position,
          builder: (context, posSnap) {
            final posMs = posSnap.data?.inMilliseconds ?? 0;
            final clamped =
                totalMs == 0 ? 0 : posMs.clamp(0, totalMs);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Slider(
                  value: clamped.toDouble(),
                  max: totalMs == 0 ? 1 : totalMs.toDouble(),
                  onChanged: (v) =>
                      handler.seek(Duration(milliseconds: v.toInt())),
                  activeColor: primary,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(_fmtMs(clamped),
                          style: Theme.of(context).textTheme.bodySmall),
                      Text(_fmtMs(totalMs),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 控制行：|◀ ◀◀ ▶ ▶▶ ▶|（上一集 / 快退 / 播放暂停 / 快进 / 下一集）。
  /// 播放键 104dp。
  Widget _buildControls(
      BuildContext context, MyAudioHandler handler, Color primary) {
    return StreamBuilder<PlaybackState>(
      stream: handler.playbackState,
      initialData: handler.playbackState.valueOrNull,
      builder: (context, snap) {
        final playing = snap.data?.playing ?? handler.player.playing;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            IconButton(
              iconSize: 32,
              icon: const Icon(Icons.skip_previous),
              tooltip: '上一集',
              onPressed: () => _skipPrevious(handler),
            ),
            IconButton(
              iconSize: 32,
              icon: const Icon(Icons.replay_10),
              tooltip: '后退 15 秒',
              onPressed: () => handler.seekBackward(),
            ),
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primary,
              ),
              child: IconButton(
                iconSize: 52,
                icon: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    color: Colors.white),
                tooltip: playing ? '暂停' : '播放',
                onPressed: () async {
                  try {
                    if (playing) {
                      await handler.pause();
                    } else {
                      await handler.play();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e')),
                      );
                    }
                  }
                },
              ),
            ),
            IconButton(
              iconSize: 32,
              icon: const Icon(Icons.forward_10),
              tooltip: '前进 15 秒',
              onPressed: () => handler.seekForward(),
            ),
            IconButton(
              iconSize: 32,
              icon: const Icon(Icons.skip_next),
              tooltip: '下一集',
              onPressed: () => _skipNext(handler),
            ),
          ],
        );
      },
    );
  }

  Future<void> _skipNext(MyAudioHandler handler) async {
    try {
      await handler.skipToNext();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切下一集失败：$e')),
        );
      }
    }
  }

  Future<void> _skipPrevious(MyAudioHandler handler) async {
    try {
      await handler.skipToPrevious();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切上一集失败：$e')),
        );
      }
    }
  }

  Widget _buildSpeedRow(
      BuildContext context, MyAudioHandler handler, Color primary) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (widget.voices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.record_voice_over_outlined, size: 16),
              label: const Text('音色'),
              onPressed: _showVoiceSheet,
            ),
          ),
        for (final v in <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                handler.setSpeed(v);
                setState(() {});
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: handler.currentSpeed == v
                      ? primary.withOpacity(0.15)
                      : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: handler.currentSpeed == v
                          ? primary
                          : Theme.of(context).dividerColor),
                ),
                child: Text('${v}x',
                    style: TextStyle(
                        fontSize: 12,
                        color:
                            handler.currentSpeed == v ? primary : null,
                        fontWeight: handler.currentSpeed == v
                            ? FontWeight.w600
                            : FontWeight.w400)),
              ),
            ),
          ),
      ],
    );
  }
}
