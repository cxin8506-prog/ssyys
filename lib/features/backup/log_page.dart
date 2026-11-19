import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/database/app_database.dart' show Log;
import '../../core/di/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/path_utils.dart';

/// 日志页：查看 / 清空 / 导出
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
              icon: const Icon(Icons.ios_share),
              onPressed: _export,
              tooltip: '导出'),
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

  void _export() async {
    final rows = await _load();
    final logs = await PathUtils.logsDir;
    final file = File(p.join(
        logs.path, 'log_export_${DateTime.now().millisecondsSinceEpoch}.txt'));
    final buffer = StringBuffer();
    for (final r in rows) {
      buffer.writeln('[${r.createdAt}] [${r.level}] ${r.message}');
      if (r.detail != null) buffer.writeln('  ${r.detail}');
    }
    await file.writeAsString(buffer.toString());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已导出: ${file.path}')));
    }
  }
}

class EmptyLog extends StatelessWidget {
  const EmptyLog({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Text('暂无日志记录'));
}
