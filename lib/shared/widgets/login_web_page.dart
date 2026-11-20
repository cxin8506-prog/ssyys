import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// App 内 WebView 登录页（源登录、搜索验证共用）。
///
/// 用户自己在网页里输账号、过验证码；登录态留在 WebView Cookie /
/// localStorage，源用 getCookie 读。App 不自己画账号密码输入框。
///
/// 关闭时不报“登录成功”：调用方关掉页面后要重新查登录状态
///（引擎 loginInfo / checkLogin），没拿到登录态别报成功。
/// 旧坑：关掉登录页无条件 toast“Cookie 已同步”是错的。
///
/// 注意：pubspec 锁的是 webview_flutter 3.0.4，用 3.x 的 WebView 写法
///（initialUrl / JavascriptMode / navigationDelegate 回调），不要写成
/// 4.x 的 WebViewController / WebViewWidget。
class LoginWebPage extends StatefulWidget {
  final String url;
  final String title;
  final bool desktop;

  const LoginWebPage({
    super.key,
    required this.url,
    this.title = '登录',
    this.desktop = false,
  });

  @override
  State<LoginWebPage> createState() => _LoginWebPageState();
}

class _LoginWebPageState extends State<LoginWebPage> {
  bool _loading = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              '完成',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '在下方页面完成登录后点右上角“完成”，登录状态会保存下来。',
              style: TextStyle(fontSize: 13),
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: WebView(
              initialUrl: widget.url,
              javascriptMode: JavascriptMode.unrestricted,
              navigationDelegate: (request) =>
                  NavigationDecision.navigate,
              onPageFinished: (_) {
                if (mounted) setState(() => _loading = false);
              },
            ),
          ),
        ],
      ),
    );
  }
}
