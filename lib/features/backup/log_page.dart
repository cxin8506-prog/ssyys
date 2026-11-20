import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/library_repository.dart';

/// 运行日志页：查看 / 清空 / 复制。
/// 日志存在数据库 Logs 表（最新 500 条），不写本地文件；重启后还在。
class LogPage extends ConsumerStatefulWidget {
  const LogPage({super.key});

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage> {
  @override
  Widget build(BuildContext context) {
    final repo = ref.read(libraryRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: '复制全部',
            onPressed: () => _copyAll(repo),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空日志',
            onPressed: () => _confirmClear(repo),
          ),
        ],
      ),
      body: FutureBuilder(
        future: repo.getLogs(limit: 500),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final logs = snapshot.data ?? const [];
          if (logs.isEmpty) {
            return const Center(child: Text('暂无日志'));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: logs.length,
            itemBuilder: (context, i) {
              final r = logs[i];
              return InkWell(
                onLongPress: () => _copyOne(r),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _levelChip(r.level),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _formatTime(r.createdAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(r.message,
                          style: const TextStyle(fontSize: 13.5)),
                      if (r.detail != null && r.detail!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(r.detail!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontSize: 11.5)),
                        ),
                      const Divider(height: 12),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _levelChip(String level) {
    final color = level == 'error'
        ? Colors.red
        : level == 'warning'
            ? Colors.orange
            : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(level,
          style: TextStyle(fontSize: 11, color: color)),
    );
  }

  String _formatTime(DateTime t) {
    final m = '${t.month}'.padLeft(2, '0');
    final d = '${t.day}'.padLeft(2, '0');
    final h = '${t.hour}'.padLeft(2, '0');
    final min = '${t.minute}'.padLeft(2, '0');
    final s = '${t.second}'.padLeft(2, '0');
    return '${t.year}-$m-$d $h:$min:$s';
  }

  Future<void> _copyAll(LibraryRepository repo) async {
    final logs = await repo.getLogs(limit: 500);
    final buffer = StringBuffer();
    for (final r in logs) {
      buffer.writeln('[${_formatTime(r.createdAt)}] [${r.level}] ${r.message}');
      if (r.detail != null && r.detail!.isNotEmpty) {
        buffer.writeln(r.detail);
      }
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制全部日志')));
  }

  Future<void> _copyOne(dynamic r) async {
    await Clipboard.setData(ClipboardData(
        text: '[${_formatTime(r.createdAt)}] [${r.level}] ${r.message}'
            '${r.detail == null || (r.detail as String).isEmpty ? '' : '\n${r.detail}'}'));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制这条日志')));
  }

  Future<void> _confirmClear(LibraryRepository repo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空日志'),
        content: const Text('会删掉全部运行日志，确定吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok != true) return;
    await repo.clearLogs();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('日志已清空')));
  }
}
