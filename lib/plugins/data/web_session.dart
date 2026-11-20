import 'dart:convert';

import 'package:flutter/services.dart';

/// 与系统 WebView 共享的 Cookie 会话。
///
/// 登录流程：用内嵌 WebView 打开源的登录页 → 用户自己输账号密码/过验证码 →
/// 登录完成后把该站点的 Cookie 读出来 → 存进源配置 → 之后源请求自动带上。
///
/// 共享是双向的：
/// - 读：JS 引擎每次请求前调 [cookies] 读 WebView 的 CookieJar，
///   登录页写进去的 Cookie，源请求自动带上；
/// - 写：JS 引擎收到响应里的 Set-Cookie 后调 [setCookie] 写回 WebView，
///   登录页和别的请求都能用上。
/// 原生侧是同一个 android.webkit.CookieManager，不存在两份 Cookie。
class WebSession {
  static const MethodChannel _channel = MethodChannel('suishou/web');

  /// 读某个 URL 的 Cookie（系统 WebView 的 CookieJar，含登录写入的那些）。
  Future<String> cookies(String url) async {
    if (url.isEmpty) return '';
    try {
      final r =
          await _channel.invokeMethod<String>('cookies', {'url': url});
      return r ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 登录完成后统一一下格式：`a=b; c=d`。
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

  /// 把一条 Set-Cookie 写进 WebView 的 CookieJar（供登录页和后续请求共用）。
  /// [cookie] 是响应里 `Set-Cookie` 头的原始值（如 `a=b; Path=/`）。
  Future<void> setCookie(String url, String cookie) async {
    if (url.isEmpty || cookie.isEmpty) return;
    try {
      await _channel.invokeMethod<void>(
          'setCookie', {'url': url, 'cookie': cookie});
    } catch (_) {}
  }

  /// 清掉全部 Cookie（退出登录用）。指定 [url] 时只清该站点的。
  Future<void> clear([String? url]) async {
    try {
      await _channel.invokeMethod('clearCookies', {'url': url});
    } catch (_) {}
  }

  Future<void> flush() async {
    try {
      await _channel.invokeMethod('flush', {});
    } catch (_) {}
  }

  /// Cookie 字符串转成 map（源若想按 key 读）。
  static Map<String, String> parse(String header) {
    final out = <String, String>{};
    for (final part in header.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      out[part.substring(0, i).trim()] = part.substring(i + 1).trim();
    }
    return out;
  }

  /// 只看 Cookie 字符串非空不能算“已登录”（见登录有效性要求），
  /// 这里只是“有没有 Cookie 可读”的粗判断，真正的登录态要调源的 checkLogin。
  static bool looksLoggedIn(String? cookie) =>
      cookie != null && cookie.trim().isNotEmpty;

  /// 打码显示 Cookie（日志/调试用，别把完整 Cookie 贴进日志）。
  static String mask(String? cookie) {
    final c = (cookie ?? '').trim();
    if (c.isEmpty) return '';
    if (c.length <= 12) return c;
    return '${c.substring(0, 8)}…${c.substring(c.length - 4)}';
  }
}
