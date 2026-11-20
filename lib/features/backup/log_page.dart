import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart' show Log;
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';

/// 日志页：查看 / 清空 / 复制（不写本地文件）
class LogPage extends ConsumerStatefulWidget {
  const LogPage({super.key});

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage> {
  Future<List<Log>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Log>> _load() async {
    final db = ref.read(databaseProvider);
    final query = db.select(db.logs)
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)])
      ..limit(500);
    return query.get();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          IconButton(
              icon: const Icon(Icons.copy),
              onPressed: _copyAll,
              tooltip: '复制'),
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clear,
              tooltip: '清空'),
        ],
      ),
      body: FutureBuilder<List<Log>>(
        future: _future,
        builder: (context, snap) {
          final rows = snap.data ?? [];
          if (rows.isEmpty) {
            return const EmptyLog();
          }
          return ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final r = rows[i];
              final color = r.level == 'error'
                  ? Colors.redAccent
                  : r.level == 'warning'
                      ? Colors.orange
                      : context.subtleColor;
              return ListTile(
                leading: Icon(Icons.circle, size: 10, color: color),
                title: Text(r.message, style: TextStyle(color: color)),
                subtitle: Text('${r.createdAt} ${r.detail ?? ''}', maxLines: 2),
                onLongPress: () => _copyOne(r),
              );
            },
          );
        },
      ),
    );
  }

  void _clear() async {
    final db = ref.read(databaseProvider);
    await db.delete(db.logs).go();
    setState(() => _future = _load());
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('日志已清空')));
  }

  /// 复制全部日志
  void _copyAll() async {
    final rows = await _load();
    if (rows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('暂无日志可复制')));
      }
      return;
    }
    final buffer = StringBuffer();
    for (final r in rows) {
      buffer.write(_formatLogRow(r));
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制')));
    }
  }

  /// 长按某一行：复制该条日志（时间 + 级别 + 内容 + 详情）
  void _copyOne(Log r) async {
    await Clipboard.setData(ClipboardData(text: _formatLogRow(r).trimRight()));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制该条日志')));
    }
  }

  /// 单条日志的文本格式，复制全部和复制单条共用
  static String _formatLogRow(Log r) {
    final buffer = StringBuffer();
    buffer.writeln('[${r.createdAt}] [${r.level}] ${r.message}');
    if (r.detail != null) buffer.writeln('  ${r.detail}');
    return buffer.toString();
  }
}

class EmptyLog extends StatelessWidget {
  const EmptyLog({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('暂无日志记录'));
}
