import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/log/app_logger.dart';

/// 「我的听书」格式 JAR 源的原生桥。
///
/// 一个 JAR 包 = 一组源，安装时要先用 [scanEntryClasses] 找入口类，
/// 再用 [listSources] 把包里的每个源列出来。
///
/// 扫描失败与列出失败要区分报错、带原始异常，不许静默吞：
/// [lastScanError] / [lastListError] 记下最近一次原生报错，
/// 安装失败时拼进人话错误里，下次不用再猜是“扫不到”还是“列不出”。
class TingShuBridge {
  static const MethodChannel _channel = MethodChannel('suishou/tingshu');

  /// 最近一次扫描失败的原生报错（安装失败时拼进人话错误里）。
  /// 每次调用前先清掉，成功时保持 null。
  static String? lastScanError;

  /// 最近一次列出失败的原生报错。
  static String? lastListError;

  /// 拷完 JAR 后调：设只读（Android 14+ 拒绝加载可写的 dex）。
  /// 尽力而为，失败返回 false、不抛错（调用方记日志继续走）。
  static Future<bool> makeReadOnly(String jarPath) async {
    try {
      final r = await _channel.invokeMethod<String>(
          'makeReadOnly', <String, dynamic>{'path': jarPath});
      return r == 'true';
    } catch (_) {
      return false;
    }
  }

  /// 清掉这个 JAR 的加载器 / 入口缓存 / odex 子目录。
  /// 重导同一个包前必须调一次，否则同路径会命中旧加载器/旧 odex。
  static Future<void> clearJarCache(String jarPath) async {
    try {
      await _channel.invokeMethod<String>(
          'clearJarCache', <String, dynamic>{'path': jarPath});
    } catch (_) {}
  }

  /// 把解析出的手机/电脑 UA 推给原生侧：
  /// 源里调 getMobileUA() / getDesktopUA() / Connection.config() 拿到的
  /// 就是这两条。任一为 null 时原生侧保留内置默认，不覆盖。
  static Future<void> setUserAgents(String? mobile, String? desktop) async {
    try {
      await _channel.invokeMethod<String>('setUserAgents', <String, dynamic>{
        'mobile': mobile,
        'desktop': desktop,
      });
    } catch (e) {
      appLogger.warning('UA 下发到原生侧失败', detail: '$e');
    }
  }

  /// 原生返回的是 JSONArray 字符串（MainActivity 里 result.success(out)，
  /// out 是 JSONArray.toString()），不是 List——按 String 接再解 JSON。
  /// 失败返回空列表，但把原始异常记进 [lastScanError] 并写日志。
  static Future<List<String>> scanEntryClasses(String jarPath) async {
    lastScanError = null;
    try {
      final r = await _channel.invokeMethod<String>(
          'scanSources', <String, dynamic>{'path': jarPath});
      if (r == null || r.isEmpty) return const <String>[];
      final data = jsonDecode(r);
      if (data is! List) return const <String>[];
      return data.map((e) => '$e').toList();
    } catch (e) {
      lastScanError = '$e';
      appLogger.warning('扫描 JAR 源包失败', detail: '$e');
      return const <String>[];
    }
  }

  static Future<List<Map<String, dynamic>>> listSources(
      String jarPath, String entryClass) async {
    lastListError = null;
    try {
      final r = await _channel.invokeMethod<String>(
          'listSources', <String, dynamic>{
        'path': jarPath,
        'entryClass': entryClass,
      });
      if (r == null) return const <Map<String, dynamic>>[];
      final data = jsonDecode(r);
      if (data is! List) return const <Map<String, dynamic>>[];
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      lastListError = '$e';
      appLogger.warning('列出 JAR 源包内容失败', detail: '$e');
      return const <Map<String, dynamic>>[];
    }
  }

  /// 调用包里第 [index] 个源的某个方法，返回 JSON 解出来的对象。
  /// 原生侧抛错时直接往上抛（调用方转成人话），不吞成空。
  static Future<dynamic> call({
    required String jarPath,
    required String entryClass,
    required int index,
    required String method,
    Map<String, dynamic>? params,
  }) async {
    final raw = await _channel.invokeMethod<String>('callSource',
        <String, dynamic>{
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

  /// 源的登录入口（ILogin）：没有返回 null，有返回 {url, desktop}。
  static Future<Map<String, dynamic>?> loginInfo({
    required String jarPath,
    required String entryClass,
    required int index,
  }) async {
    try {
      final r = await _channel.invokeMethod<String>('loginInfo',
          <String, dynamic>{
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
  /// 有返回 {url, ua, delayMs, validated}。
  static Future<Map<String, dynamic>?> verificationInfo({
    required String jarPath,
    required String entryClass,
    required int index,
    required String keyword,
  }) async {
    try {
      final r = await _channel.invokeMethod<String>('verificationInfo',
          <String, dynamic>{
            'path': jarPath,
            'entryClass': entryClass,
            'index': index,
            'params': <String, dynamic>{'keyword': keyword},
          });
      if (r == null || r.isEmpty) return null;
      final d = jsonDecode(r);
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  /// 搜索验证过没有（源自己读 Cookie 判断）。
  static Future<bool> isSearchValidated({
    required String jarPath,
    required String entryClass,
    required int index,
  }) async {
    try {
      final r = await _channel.invokeMethod<String>('isSearchValidated',
          <String, dynamic>{
            'path': jarPath,
            'entryClass': entryClass,
            'index': index,
          });
      return r == 'true';
    } catch (_) {
      return false;
    }
  }

  /// 这个源能不能缓存（isCacheable）：默认 true，源明确返回 false 才不缓存。
  /// 所有视频源的 isCacheable() 都是 false，自动缓存问到 false 就不下。
  static Future<bool> isCacheable({
    required String jarPath,
    required String entryClass,
    required int index,
  }) async {
    try {
      final r = await _channel.invokeMethod<String>('isCacheable',
          <String, dynamic>{
            'path': jarPath,
            'entryClass': entryClass,
            'index': index,
          });
      return r != 'false';
    } catch (_) {
      return true;
    }
  }
}
