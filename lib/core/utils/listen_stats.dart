import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';

/// 收听统计：从第一次播放开始记，关 App 再打开还在。
///
/// 今日：按自然日（yyyy-MM-dd）记；一共：累计秒数。
/// 播放页在播的时候每 5 秒记一次。
class ListenStats {
  static String _todayKey() {
    final now = DateTime.now();
    final m = '${now.month}'.padLeft(2, '0');
    final d = '${now.day}'.padLeft(2, '0');
    return '${now.year}-$m-$d';
  }

  /// 记 seconds 秒（播放页定时调用）
  static Future<void> record(int seconds) async {
    if (seconds <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final total = (prefs.getInt(AppConstants.keyListenTotalSecs) ?? 0) + seconds;
    await prefs.setInt(AppConstants.keyListenTotalSecs, total);
    final today = _todayKey();
    final savedDay = prefs.getString(AppConstants.keyListenDay) ?? '';
    var daySecs = prefs.getInt(AppConstants.keyListenDaySecs) ?? 0;
    if (savedDay != today) {
      daySecs = 0;
      await prefs.setString(AppConstants.keyListenDay, today);
    }
    await prefs.setInt(AppConstants.keyListenDaySecs, daySecs + seconds);
  }

  static Future<(int, int)> summary() async {
    final prefs = await SharedPreferences.getInstance();
    final total = prefs.getInt(AppConstants.keyListenTotalSecs) ?? 0;
    final today = _todayKey();
    final savedDay = prefs.getString(AppConstants.keyListenDay) ?? '';
    final daySecs =
        savedDay == today ? (prefs.getInt(AppConstants.keyListenDaySecs) ?? 0) : 0;
    return (daySecs, total);
  }

  static String format(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '$h 小时 $m 分钟';
    return '$m 分钟';
  }

  /// 弹出“今日收听了 X，一共收听了 X”
  static Future<void> showDialog(BuildContext context) async {
    final (today, total) = await summary();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('收听统计'),
        content: Text(
          '今日收听了 ${format(today)}，一共收听了 ${format(total)}',
          style: const TextStyle(fontSize: 15, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}
