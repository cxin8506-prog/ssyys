import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/path_utils.dart';
import '../data/plugin_providers.dart';
import '../model/plugin_source.dart';
import 'source_detail_page.dart';

/// 源管理：导入 JS/ZIP、JAR 插件，启用停用，进入配置
class SourceCenterPage extends ConsumerStatefulWidget {
  const SourceCenterPage({super.key});

  @override
  ConsumerState<SourceCenterPage> createState() => _SourceCenterPageState();
}

class _SourceCenterPageState extends ConsumerState<SourceCenterPage> {
  bool _busy = false;
  String _stage = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sourceListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('源管理'),
        actions: [
          TextButton.icon(
            onPressed: _busy ? null : () => _pickAndInstall(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('导入'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('读取源失败：$e')),
        data: (list) => Stack(
          children: [
            _buildBody(list),
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
        ),
      ),
    );
  }

  Widget _buildBody(List<PluginSource> list) {
    final audio = list.where((e) => e.type == AppConstants.typeAudio).toList();
    final video = list.where((e) => e.type == AppConstants.typeVideo).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _introCard(),
        const SizedBox(height: 18),
        if (list.isEmpty)
          _emptyCard()
        else ...[
          if (audio.isNotEmpty) ...[
            _groupTitle('听书源', audio.length),
            const SizedBox(height: 8),
            ...audio.map((s) => _sourceTile(s)),
            const SizedBox(height: 18),
          ],
          if (video.isNotEmpty) ...[
            _groupTitle('视频源', video.length),
            const SizedBox(height: 8),
            ...video.map((s) => _sourceTile(s)),
          ],
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _pickAndInstall(),
          icon: const Icon(Icons.file_open_outlined, size: 18),
          label: const Text('导入插件文件（.zip / .jar）'),
        ),
      ],
    );
  }

  Widget _introCard() {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withOpacity(0.18),
            Theme.of(context).colorScheme.secondary.withOpacity(0.10),
          ],
        ),
        border: Border.all(color: context.palette.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.extension, color: primary, size: 20),
              const SizedBox(width: 8),
              const Text('插件源',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '支持两种插件：\n'
            '• JS/ZIP：包内 manifest.json + JS（随身听书风格）\n'
            '• JAR：含 classes.dex 的安卓插件（我的听书风格）\n'
            '导入后在上方源列表里启用/配置，首页可切换当前源。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.outline),
      ),
      child: Column(
        children: [
          Icon(Icons.extension_outlined, size: 40, color: context.subtleColor),
          const SizedBox(height: 12),
          Text('还没有安装任何源',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text('点右上角「导入」，选择插件 .zip 或 .jar 文件',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _groupTitle(String title, int count) => Row(
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('$count 个', style: Theme.of(context).textTheme.bodySmall),
        ],
      );

  Widget _sourceTile(PluginSource s) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SourceDetailPage(sourceId: s.id)));
          ref.invalidate(sourceListProvider);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.palette.outline),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: context.palette.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  s.isJar ? Icons.archive_outlined : Icons.code,
                  size: 20,
                  color: primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(s.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 6),
                        _miniTag(s.formatLabel),
                        if (s.version.isNotEmpty && s.version != '1.0.0') ...[
                          const SizedBox(width: 4),
                          _miniTag('v${s.version}'),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${PathUtils.formatSize(s.sizeBytes)}'
                      '${s.description.isNotEmpty ? ' · ${s.description}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Switch(
                value: s.enabled,
                onChanged: (v) async {
                  await ref.read(sourceRepositoryProvider).setEnabled(s.id, v);
                  ref.invalidate(sourceListProvider);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniTag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: context.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 10, color: context.subtleColor)),
      );

  // ---------------------------------------------------------------- 导入

  Future<void> _pickAndInstall() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('这个源是哪一类？',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.headphones_outlined),
              title: const Text('听书源'),
              subtitle: const Text('搜索/目录/音频播放'),
              onTap: () => Navigator.pop(ctx, AppConstants.typeAudio),
            ),
            ListTile(
              leading: const Icon(Icons.movie_outlined),
              title: const Text('视频源'),
              subtitle: const Text('搜索/线路/视频播放'),
              onTap: () => Navigator.pop(ctx, AppConstants.typeVideo),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (type == null) return;

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip', 'jar'],
        withData: false,
      );
    } catch (e) {
      _toast('打开文件选择器失败：$e');
      return;
    }
    final path = picked?.files.single.path;
    if (path == null) return;

    setState(() {
      _busy = true;
      _stage = '正在解析插件包...';
    });
    try {
      final repo = ref.read(sourceRepositoryProvider);
      final ext = PathUtils.ext(path);
      final PluginSource s;
      if (ext == 'jar') {
        s = await repo.installJar(path, typeOverride: type);
      } else {
        s = await repo.installZip(path, typeOverride: type);
      }
      ref.invalidate(sourceListProvider);
      _toast('已安装「${s.name}」');
    } catch (e) {
      _toast('安装失败：$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = '';
        });
      }
    }
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
