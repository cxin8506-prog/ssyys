import 'dart:convert';

import 'package:flutter/services.dart';

/// 与系统 WebView 共享的 Cookie 会话。
///
/// 登录流程：用内嵌 WebView 打开源的登录页 → 用户自己输账号密码/过验证码 →
/// 登录完成后把该站点的 Cookie 读出来 → 存进源配置 → 之后源请求自动带上。
class WebSession {
  static const MethodChannel _channel = MethodChannel('suishou/web');

  /// 读某个 URL 的 Cookie（系统 WebView 的 CookieJar，含登录写入的那些）
  Future<String> cookies(String url) async {
    if (url.isEmpty) return '';
    try {
      final r = await _channel.invokeMethod<String>('cookies', {'url': url});
      return r ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 登录完成后统一一下格式：`a=b; c=d`
  Future<String> cookieHeader(String url) async {
    final raw = await cookies(url);
    if (raw.isEmpty) return '';
    final parts = raw
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.join('; ');
  }

  Future<void> clear() async {
    try {
      await _channel.invokeMethod('clearCookies', {});
    } catch (_) {}
  }

  Future<void> flush() async {
    try {
      await _channel.invokeMethod('flush', {});
    } catch (_) {}
  }

  /// Cookie 字符串转成 map（源若想按 key 读）
  static Map<String, String> parse(String header) {
    final out = <String, String>{};
    for (final part in header.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      out[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    return out;
  }

  static bool looksLoggedIn(String? cookie) =>
      cookie != null && cookie.trim().isNotEmpty;

  static String mask(String? cookie) {
    final c = (cookie ?? '').trim();
    if (c.isEmpty) return '';
    if (c.length <= 12) return c;
    return '${c.substring(0, 8)}…${c.substring(c.length - 4)}';
  }

  static String encode(String header) => jsonEncode(header);
}
