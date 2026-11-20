/// 源的登录入口声明。
///
/// manifest.json 支持三种写法：
/// ```json
/// "login": "https://example.com/login"
/// "login": { "url": "https://example.com/login",
///            "successUrl": "https://example.com/home",
///            "cookieUrl": "https://example.com" }
/// "loginUrl": "https://example.com/login"
/// ```
/// JAR 源没有 manifest，登录入口走引擎的 ILogin（见 TingShuBridge.loginInfo），
/// 不走这里。
class LoginEntry {
  final String url;

  /// 登录成功后 WebView 会跳到的地址（用于自动判定登录完成）。
  final String successUrl;

  /// 从这个地址读 Cookie（默认取 [url] 的 origin）。
  final String cookieUrl;

  const LoginEntry({
    required this.url,
    this.successUrl = '',
    this.cookieUrl = '',
  });

  bool get valid => url.isNotEmpty;

  /// 读 Cookie 用的地址。
  String get readCookieUrl {
    if (cookieUrl.isNotEmpty) return cookieUrl;
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return url;
    return '${u.scheme}://${u.host}/';
  }

  static LoginEntry? parse(Map<String, dynamic> manifest) {
    for (final k in const <String>[
      'login',
      'loginUrl',
      'login_url',
      'auth',
      'oauth',
    ]) {
      final v = manifest[k];
      if (v == null) continue;
      if (v is String && v.trim().isNotEmpty) {
        return LoginEntry(url: v.trim());
      }
      if (v is Map) {
        final m = Map<String, dynamic>.from(v);
        final url = '${m['url'] ?? m['href'] ?? m['loginUrl'] ?? ''}'.trim();
        if (url.isEmpty) continue;
        return LoginEntry(
          url: url,
          successUrl:
              '${m['successUrl'] ?? m['successURL'] ?? m['redirectUrl'] ?? ''}'
                  .trim(),
          cookieUrl:
              '${m['cookieUrl'] ?? m['cookieURL'] ?? m['domain'] ?? ''}'.trim(),
        );
      }
    }
    return null;
  }
}
