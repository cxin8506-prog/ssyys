import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/log/app_logger.dart';

/// 「我的听书」格式 JAR 源的原生桥。
///
/// 一个 JAR 包 = 一组源，安装时要先用 [scanEntryClasses] 找入口类，
/// 再用 [listSources] 把包里的每个源列出来。
class TingShuBridge {
  static const MethodChannel _channel = MethodChannel('suishou/tingshu');

  static Future<List<String>> scanEntryClasses(String jarPath) async {
    try {
      final r = await _channel
          .invokeMethod<List<dynamic>>('scanSources', {'path': jarPath});
      return (r ?? const []).map((e) => '$e').toList();
    } catch (e) {
      appLogger.warning('扫描 JAR 源包失败', detail: '$e');
      return const [];
    }
  }

  static Future<List<Map<String, dynamic>>> listSources(
      String jarPath, String entryClass) async {
    try {
      final r = await _channel.invokeMethod<String>(
          'listSources', {'path': jarPath, 'entryClass': entryClass});
      if (r == null) return const [];
      final data = jsonDecode(r);
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      appLogger.warning('列出 JAR 源包内容失败', detail: '$e');
      return const [];
    }
  }

  /// 调用包里第 [index] 个源的某个方法，返回 JSON 解出来的对象
  static Future<dynamic> call({
    required String jarPath,
    required String entryClass,
    required int index,
    required String method,
    Map<String, dynamic>? params,
  }) async {
    final raw = await _channel.invokeMethod<String>('callSource', {
      'path': jarPath,
      'entryClass': entryClass,
      'index': index,
      'method': method,
      'params': params ?? const <String, dynamic>{},
    });
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  /// 源的登录入口（ILogin）：没有返回 null，有返回 {url, desktop}
  static Future<Map<String, dynamic>?> loginInfo({
    required String jarPath,
    required String entryClass,
    required int index,
  }) async {
    try {
      final r = await _channel.invokeMethod<String>('loginInfo', {
        'path': jarPath,
        'entryClass': entryClass,
        'index': index,
      });
      if (r == null || r.isEmpty) return null;
      final d = jsonDecode(r);
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  /// 源的搜索验证（ISearchVerification）：没有返回 null，
  /// 有返回 {url, ua, delayMs, validated}
  static Future<Map<String, dynamic>?> verificationInfo({
    required String jarPath,
    required String entryClass,
    required int index,
    required String keyword,
  }) async {
    try {
      final r = await _channel.invokeMethod<String>('verificationInfo', {
        'path': jarPath,
        'entryClass': entryClass,
        'index': index,
        'params': {'keyword': keyword},
      });
      if (r == null || r.isEmpty) return null;
      final d = jsonDecode(r);
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  /// 搜索验证过没有（源自己读 Cookie 判断）
  static Future<bool> isSearchValidated({
    required String jarPath,
    required String entryClass,
    required int index,
  }) async {
    try {
      final r = await _channel.invokeMethod<String>('isSearchValidated', {
        'path': jarPath,
        'entryClass': entryClass,
        'index': index,
      });
      return r == 'true';
    } catch (_) {
      return false;
    }
  }
}
