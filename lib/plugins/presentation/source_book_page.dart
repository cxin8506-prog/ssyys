import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/plugin_providers.dart';
import '../model/plugin_source.dart';
import '../model/plugin_source.dart' show PluginSource;
import '../../features/video/presentation/video_player_page.dart';
import 'network_audio_page.dart';

/// 源里的书详情：简介 + 音色 + 章节，点章节直接播放
class SourceBookPage extends ConsumerStatefulWidget {
  final String sourceId;
  final String bookUrl;
  final String title;
  final String? coverUrl;
  final String? author;
  final String? intro;

  const SourceBookPage({
    super.key,
    required this.sourceId,
    required this.bookUrl,
    required this.title,
    this.coverUrl,
    this.author,
    this.intro,
  });

  @override
  ConsumerState<SourceBookPage> createState() => _SourceBookPageState();
}

class _SourceBookPageState extends ConsumerState<SourceBookPage> {
  PluginSource? _source;
  Map<String, dynamic> _detail = {};
  List<Map<String, dynamic>> _chapters = [];
  List<Map<String, dynamic>> _voices = [];
  String? _voiceId;
  List<Map<String, dynamic>> _lines = [];
  String? _lineId;
  bool _loading = true;
  String? _error;
  int _playingIndex = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(sourceRepositoryProvider);
    final s = await repo.byId(widget.sourceId);
    if (s == null) {
      setState(() {
        _loading = false;
        _error = '源已被删除';
      });
      return;
    }
    _source = s;
    // 音色 / 线路来自源配置
    final cfg =
        await ref.read(sourceConfigRepositoryProvider).load(s.id, s.type);
    _voices = cfg.voices;
    _voiceId = cfg.selectedVoiceId;
    _lines = cfg.lines;
    _lineId = cfg.selectedLineId;
    try {
      final engine = s.isJar
          ? ref.read(jarPluginEngineProvider)
          : ref.read(jsPluginEngineProvider);
      await engine.attach(s);

      dynamic detail;
      try {
        detail = await engine.invoke('detail', params: {'url': widget.bookUrl});
      } catch (_) {}
      if (detail is Map) _detail = Map<String, dynamic>.from(detail);

      dynamic chapters;
      try {
        chapters = await engine
            .invoke('chapters', params: {'url': widget.bookUrl});
      } catch (_) {}
      if (chapters == null && _detail['chapters'] != null) {
        chapters = _detail['chapters'];
      }
      _chapters = _normalizeChapters(chapters);

      if (_voices.isEmpty && s.isAudio) {
        try {
          final vs = await engine.invoke('voices', params: {'url': widget.bookUrl});
          _voices = _normalizeOptions(vs);
        } catch (_) {}
      }
      if (_lines.isEmpty && !s.isAudio) {
        try {
          final ls = await engine.invoke('lines', params: {'url': widget.bookUrl});
          _lines = _normalizeOptions(ls);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  List<Map<String, dynamic>> _normalizeChapters(dynamic raw) {
    if (raw == null) return [];
    final list = raw is List ? raw : (raw is Map ? [raw] : <dynamic>[]);
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (e is Map) {
        out.add({
          'name': '${e['name'] ?? e['title'] ?? e['chapterName'] ?? '第${i + 1}章'}',
          'url': '${e['url'] ?? e['chapterUrl'] ?? e['id'] ?? ''}',
        });
      } else if (e != null) {
        out.add({'name': '$e', 'url': '$e'});
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _normalizeOptions(dynamic raw) {
    if (raw == null) return [];
    final out = <Map<String, dynamic>>[];
    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final e = raw[i];
        if (e is Map) {
          out.add({
            'id': '${e['id'] ?? e['key'] ?? i}',
            'name': '${e['name'] ?? e['title'] ?? '选项${i + 1}'}',
          });
        } else if (e != null) {
          out.add({'id': '$i', 'name': '$e'});
        }
      }
    } else if (raw is Map) {
      raw.forEach((k, v) => out.add({'id': '$k', 'name': '$v'}));
    }
    return out;
  }

  String get _cover =>
      widget.coverUrl ??
      '${_detail['cover'] ?? _detail['img'] ?? _detail['coverUrl'] ?? ''}';
  String get _author =>
      widget.author ??
      '${_detail['author'] ?? _detail['writer'] ?? ''}';
  String get _intro =>
      widget.intro ??
      '${_detail['intro'] ?? _detail['desc'] ?? _detail['description'] ?? ''}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, overflow: TextOverflow.ellipsis)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _chapters.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 40,
                            color: Theme.of(context).colorScheme.error),
                        const SizedBox(height: 12),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 16),
                        OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _loading = true;
                                _error = null;
                              });
                              _load();
                            },
                            child: const Text('重试')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _header(),
                    if (_voices.isNotEmpty && _isAudio) ...[
                      const SizedBox(height: 16),
                      _voicePicker(),
                    ],
                    if (_lines.isNotEmpty && !_isAudio) ...[
                      const SizedBox(height: 16),
                      _linePicker(),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Text('目录',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Text('${_chapters.length} 章',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_chapters.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: context.cardColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.palette.outline),
                        ),
                        child: Text('这个源没有返回目录',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall),
                      )
                    else
                      ...List.generate(_chapters.length, (i) => _chapterTile(i)),
                  ],
                ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _cover.startsWith('http')
              ? Image.network(_cover,
                  width: 84,
                  height: 112,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _coverBox())
              : _coverBox(),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              if (_author.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(_author,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontSize: 12)),
              ],
              const SizedBox(height: 8),
              if (_intro.isNotEmpty)
                Text(_intro,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(height: 1.5)),
            ],
          ),
        ),
      ],
    );
  }

  bool get _isAudio => _source?.isAudio ?? true;

  Widget _linePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('播放线路',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _lines.map((l) {
            final id = '${l['id']}';
            final selected = _lineId == id;
            final primary = Theme.of(context).colorScheme.primary;
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                setState(() => _lineId = id);
                _saveLine(id);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? context.palette.primarySoft
                      : context.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: selected ? primary : context.palette.outline),
                ),
                child: Text('${l['name']}',
                    style: TextStyle(
                        fontSize: 12,
                        color: selected ? primary : null,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _saveLine(String id) async {
    final s = _source;
    if (s == null) return;
    final repo = ref.read(sourceConfigRepositoryProvider);
    final cfg = await repo.load(s.id, s.type);
    cfg.lines = _lines;
    cfg.selectedLineId = id;
    await repo.save(cfg);
  }

  Widget _coverBox() => Container(
        width: 84,
        height: 112,
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
            widget.title.isEmpty ? '?' : widget.title.substring(0, 1),
            style: TextStyle(color: context.subtleColor, fontSize: 24)),
      );

  Widget _voicePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('音色',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _voices.map((v) {
            final id = '${v['id']}';
            final selected = _voiceId == id;
            final primary = Theme.of(context).colorScheme.primary;
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                setState(() => _voiceId = id);
                _saveVoice(id);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? context.palette.primarySoft
                      : context.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: selected ? primary : context.palette.outline),
                ),
                child: Text('${v['name']}',
                    style: TextStyle(
                        fontSize: 12,
                        color: selected ? primary : null,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _saveVoice(String id) async {
    final s = _source;
    if (s == null) return;
    final repo = ref.read(sourceConfigRepositoryProvider);
    final cfg = await repo.load(s.id, s.type);
    cfg.voices = _voices;
    cfg.selectedVoiceId = id;
    await repo.save(cfg);
  }

  Widget _chapterTile(int i) {
    final ch = _chapters[i];
    final playing = _playingIndex == i;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _play(i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: context.palette.outline, width: 0.6),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text('${i + 1}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 11)),
            ),
            Expanded(
              child: Text('${ch['name']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      color: playing
                          ? Theme.of(context).colorScheme.primary
                          : null)),
            ),
            Icon(playing ? Icons.graphic_eq : Icons.play_arrow,
                size: 18,
                color: playing
                    ? Theme.of(context).colorScheme.primary
                    : context.subtleColor),
          ],
        ),
      ),
    );
  }

  Future<void> _play(int index) async {
    final s = _source;
    if (s == null) return;
    final ch = _chapters[index];
    final url = '${ch['url']}';
    if (url.isEmpty) {
      _toast('这一章没有地址');
      return;
    }
    setState(() => _playingIndex = index);
    try {
      final engine = s.isJar
          ? ref.read(jarPluginEngineProvider)
          : ref.read(jsPluginEngineProvider);
      await engine.attach(s);
      final r = await engine.invoke('content', params: {
        'url': url,
        'voiceId': _voiceId,
        'lineId': _lineId,
      });
      final mediaUrl = _extractUrl(r);
      if (mediaUrl.isEmpty) {
        throw Exception('源没有返回可播放地址');
      }
      if (!mounted) return;
      if (_isAudio) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => NetworkAudioPage(
            url: mediaUrl,
            title: '${ch['name']}',
            subtitle: widget.title,
            sourceId: _source?.id ?? '',
            bookName: widget.title,
            playlist: _chapters.map((e) => '${e['name']}').toList(),
            startIndex: index,
            onNext: (i) => _play(i),
          ),
        ));
      } else {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VideoPlayerPage(
            path: mediaUrl,
            network: true,
            title: '${widget.title} · ${ch['name']}',
          ),
        ));
      }
    } catch (e) {
      _toast('拿播放地址失败：$e');
    } finally {
      if (mounted) setState(() => _playingIndex = -1);
    }
  }

  String _extractUrl(dynamic r) {
    if (r == null) return '';
    if (r is String) {
      return r.startsWith('http') ? r : '';
    }
    if (r is Map) {
      for (final k in ['url', 'audioUrl', 'playUrl', 'src', 'mp3']) {
        final v = r[k];
        if (v != null && '$v'.startsWith('http')) return '$v';
      }
      // 有些源把地址放在 data/result 里
      for (final k in ['data', 'result', 'content']) {
        final v = r[k];
        if (v is Map) {
          final inner = _extractUrl(v);
          if (inner.isNotEmpty) return inner;
        }
      }
    }
    return '';
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }
}
