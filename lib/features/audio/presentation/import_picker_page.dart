import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../data/repository_providers.dart';
import '../data/importer.dart';

/// 导入选择页：选择本地文件/文件夹/ZIP-JAR 包并导入
class ImportPickerPage extends ConsumerStatefulWidget {
  const ImportPickerPage({super.key});

  @override
  ConsumerState<ImportPickerPage> createState() => _ImportPickerPageState();
}

class _ImportPickerPageState extends ConsumerState<ImportPickerPage> {
  bool _busy = false;
  final List<String> _messages = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildButton(
              icon: Icons.audiotrack,
              label: '导入音频文件',
              hint: 'MP3 / M4A / M4B / FLAC / WAV 等',
              onTap: () =>
                  _pickFiles(isDirectory: false, type: AppConstants.typeAudio),
            ),
            const SizedBox(height: 12),
            _buildButton(
              icon: Icons.folder_open,
              label: '导入音频文件夹',
              hint: '每个子文件夹作为一本书，图片自动作封面',
              onTap: () =>
                  _pickFiles(isDirectory: true, type: AppConstants.typeAudio),
            ),
            const SizedBox(height: 12),
            _buildButton(
              icon: Icons.folder_zip_outlined,
              label: '导入 JAR / ZIP 音频包',
              hint: '当压缩包解析，内部音频按文件名自然排序',
              onTap: () => _pickArchive(),
            ),
            const SizedBox(height: 12),
            _buildButton(
              icon: Icons.movie,
              label: '导入视频文件',
              hint: 'MP4 / MKV / AVI 等',
              onTap: () =>
                  _pickFiles(isDirectory: false, type: AppConstants.typeVideo),
            ),
            const SizedBox(height: 12),
            _buildButton(
              icon: Icons.video_collection_outlined,
              label: '导入视频文件夹',
              hint: '文件夹内多个视频可连续播放',
              onTap: () =>
                  _pickFiles(isDirectory: true, type: AppConstants.typeVideo),
            ),
            const SizedBox(height: 20),
            if (_busy)
              const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary)),
            Expanded(
              child: ListView.builder(
                itemCount: _messages.length,
                itemBuilder: (context, i) => Text(_messages[i],
                    style: TextStyle(
                        color: _messages[i].contains('失败')
                            ? Colors.redAccent
                            : AppTheme.darkTextSub)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required String label,
    required String hint,
    required VoidCallback onTap,
  }) {
    return Card(
      color: AppTheme.darkSurface,
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primary),
        title: Text(label),
        subtitle: Text(hint, style: Theme.of(context).textTheme.bodySmall),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy ? null : onTap,
      ),
    );
  }

  Future<void> _pickFiles(
      {required bool isDirectory, required String type}) async {
    if (isDirectory) {
      final dir = await FilePicker.platform.getDirectoryPath();
      if (dir != null) await _doImport(dir);
    } else {
      final exts = type == AppConstants.typeAudio
          ? AppConstants.audioExtensions.toList()
          : AppConstants.videoExtensions.toList();
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: exts,
      );
      if (result != null) {
        for (final f in result.paths) {
          if (f != null) await _doImport(f);
        }
      }
    }
  }

  Future<void> _pickArchive() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['zip', 'jar', 'cbz'],
    );
    if (result != null && result.files.single.path != null) {
      await _doImport(result.files.single.path!);
    }
  }

  Future<void> _doImport(String path) async {
    setState(() {
      _busy = true;
      _messages.add('开始导入: $path');
    });
    try {
      final result = await MediaImporter().import(path);
      if (result.success) {
        await ref.read(libraryRepositoryProvider).saveImport(result);
        setState(() => _messages
            .add('成功导入「${result.item!.title}」，${result.item!.chapterCount} 章'));
      } else {
        setState(() => _messages.add('导入失败: ${result.errors.join('; ')}'));
      }
    } catch (e, st) {
      setState(() => _messages.add('导入失败: $e'));
      debugPrint('$e $st');
    } finally {
      setState(() => _busy = false);
    }
  }
}
