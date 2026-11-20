import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/path_utils.dart';
import '../../shared/widgets/common.dart';

/// 缓存设置页。
///
/// 缓存只自动缓存后续章节，不做手动下载；isCacheable() 返回 false
/// 的源一集都不下；集数上不出现感叹号。
/// 默认值：自动缓存关、每本书 3 集、标准 30%、仅 Wi-Fi 开、自动清理 40。
class CacheSettingsPage extends ConsumerStatefulWidget {
  const CacheSettingsPage({super.key});

  @override
  ConsumerState<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends ConsumerState<CacheSettingsPage> {
  int? _cacheBytes;
  String? _cachePath;
  String? _dataPath;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _refreshSize();
  }

  Future<void> _refreshSize() async {
    try {
      final dir = await PathUtils.cacheDir;
      _cachePath = dir.path;
      var total = 0;
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
      final appDir = await PathUtils.appFilesDir;
      if (!mounted) return;
      setState(() {
        _cacheBytes = total;
        _dataPath = appDir.path;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cacheBytes = 0);
    }
  }

  String _sizeText(int? bytes) {
    if (bytes == null) return '正在计算…';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _clearCache() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除所有音频缓存？'),
        content: const Text('已缓存的后续章节会被删掉，下次播放时重新缓存。书架、断点、收藏不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _clearing = true);
    try {
      final dir = await PathUtils.cacheDir;
      if (await dir.exists()) {
        await for (final e in dir.list(followLinks: false)) {
          try {
            await e.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _clearing = false);
    await _refreshSize();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('缓存已清除')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final freq = ref.watch(autoCacheFreqProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('缓存设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          InfoRow(
            title: '自动缓存后续章节',
            subtitle: ref.watch(autoCacheProvider) ? '开' : '关',
            info: '默认关：播放时自动预缓存后面几集。isCacheable() 返回 false 的源一集都不下；集数上不出现感叹号。',
            trailing: Switch(
              value: ref.watch(autoCacheProvider),
              onChanged: (v) =>
                  saveBoolSetting(ref, autoCacheProvider, 'auto_cache', v),
            ),
          ),
          InfoRow(
            title: '每本书最大缓存集数',
            subtitle: '${ref.watch(autoCacheCountProvider)} 集',
            info: '默认 3 集。播完的集会按自动清理规则删掉。',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${ref.watch(autoCacheCountProvider)} 集',
                    style: TextStyle(fontSize: 13, color: context.subtleColor)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    size: 20, color: context.subtleColor),
              ],
            ),
            onTap: () => _pickCount(context),
          ),
          InfoRow(
            title: '缓存频率',
            subtitle: _freqLabel(freq),
            info: '标准 = 播到 30% 开始缓存后面几集；较快 15%；较慢 50%。',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_freqLabel(freq),
                    style: TextStyle(fontSize: 13, color: context.subtleColor)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    size: 20, color: context.subtleColor),
              ],
            ),
            onTap: () => _pickFreq(context, freq),
          ),
          InfoRow(
            title: '只在 Wi-Fi 下缓存',
            subtitle: ref.watch(autoCacheWifiOnlyProvider) ? '开' : '关',
            info: '默认开：流量下不自动缓存，免得偷跑流量。',
            trailing: Switch(
              value: ref.watch(autoCacheWifiOnlyProvider),
              onChanged: (v) => saveBoolSetting(
                  ref, autoCacheWifiOnlyProvider, 'auto_cache_wifi_only', v),
            ),
          ),
          InfoRow(
            title: '自动清理缓存文件',
            subtitle: '${ref.watch(autoCleanLimitProvider)} 个',
            info: '缓存文件超过这个数就自动清理最旧的，默认 40 个。',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${ref.watch(autoCleanLimitProvider)} 个',
                    style: TextStyle(fontSize: 13, color: context.subtleColor)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    size: 20, color: context.subtleColor),
              ],
            ),
            onTap: () => _pickCleanLimit(context),
          ),
          const Divider(),
          InfoRow(
            title: '缓存占用',
            subtitle: _sizeText(_cacheBytes),
            info: '当前音频缓存占用的空间。',
            trailing: TextButton(
              onPressed: _clearing ? null : _clearCache,
              child: Text(_clearing ? '清除中…' : '清除全部'),
            ),
          ),
          InfoRow(
            title: '数据目录',
            subtitle: _dataPath ?? '正在读取…',
            info: '书架、进度、收藏、书签、设置、日志都存在这里。',
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: '复制路径',
              onPressed: _dataPath == null
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: _dataPath!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('路径已复制')),
                      );
                    },
            ),
          ),
          if (_cachePath != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                '缓存目录：$_cachePath',
                style: TextStyle(fontSize: 12, color: context.subtleColor),
              ),
            ),
        ],
      ),
    );
  }

  String _freqLabel(String freq) {
    switch (freq) {
      case 'fast':
        return '较快 15%';
      case 'slow':
        return '较慢 50%';
      default:
        return '标准 30%';
    }
  }

  Future<void> _pickCount(BuildContext context) async {
    final current = ref.read(autoCacheCountProvider);
    final controller = TextEditingController(text: '$current');
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('每本书最大缓存集数'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(hintText: '1–20'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim()) ?? current;
              Navigator.pop(ctx, v.clamp(1, 20));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (picked != null) {
      await saveIntSetting(
          ref, autoCacheCountProvider, 'auto_cache_count', picked);
    }
  }

  Future<void> _pickFreq(BuildContext context, String current) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('缓存频率'),
        children: [
          for (final e in const [
            ['standard', '标准 30%'],
            ['fast', '较快 15%'],
            ['slow', '较慢 50%'],
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e[0]),
              child: Row(
                children: [
                  Text(e[1]),
                  const Spacer(),
                  if (current == e[0]) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked != null) {
      await saveStringSetting(
          ref, autoCacheFreqProvider, 'auto_cache_freq', picked);
    }
  }

  Future<void> _pickCleanLimit(BuildContext context) async {
    final current = ref.read(autoCleanLimitProvider);
    final controller = TextEditingController(text: '$current');
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自动清理缓存文件数'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(hintText: '0–500'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim()) ?? current;
              Navigator.pop(ctx, v.clamp(0, 500));
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (picked != null) {
      await saveIntSetting(
          ref, autoCleanLimitProvider, 'auto_clean_limit', picked);
    }
  }
}
