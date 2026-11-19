import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart';
import '../data/web_session.dart';

/// 源登录页：内嵌 WebView 打开源给的登录地址，用户自己输账号、过验证码。
///
/// 登录完成后（点了「完成」或命中 successUrl）自动把该站点的 Cookie 读出来，
/// 通过 `Navigator.pop(cookie)` 交回给调用方保存。
class LoginWebPage extends StatefulWidget {
  final String title;
  final String url;
  final String successUrl;
  final String cookieUrl;

  /// true 用电脑版 UA 打开（有的站只认电脑版登录页）
  final bool desktop;

  const LoginWebPage({
    super.key,
    required this.title,
    required this.url,
    this.successUrl = '',
    this.cookieUrl = '',
    this.desktop = false,
  });

  @override
  State<LoginWebPage> createState() => _LoginWebPageState();
}

class _LoginWebPageState extends State<LoginWebPage> {
  static const _desktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36';

  WebViewController? _controller;
  int _progress = 0;
  String _currentUrl = '';
  bool _finishing = false;
  String? _error;

  final _session = WebSession();

  String get _readUrl {
    if (widget.cookieUrl.isNotEmpty) return widget.cookieUrl;
    final u = Uri.tryParse(widget.url);
    if (u == null || u.host.isEmpty) return widget.url;
    return '${u.scheme}://${u.host}/';
  }

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
  }

  bool _hitSuccess(String url) {
    final s = widget.successUrl.trim();
    if (s.isEmpty) return false;
    return url.startsWith(s);
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      await _session.flush();
      var cookie = await _session.cookieHeader(_readUrl);
      if (cookie.isEmpty) {
        // 有些站点 Cookie 只挂在当前页面的子路径下，再按当前地址取一次
        cookie = await _session.cookieHeader(_currentUrl);
      }
      if (!mounted) return;
      if (cookie.isEmpty) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('没有拿到 Cookie'),
            content: const Text(
              '可能是还没登录成功，或者这个站点的登录态不在 Cookie 里。\n'
              '可以返回页面确认已登录后再点完成；如果确实没有 Cookie，'
              '可以在源配置里手动填写。',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('继续登录')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('仍然返回')),
            ],
          ),
        );
        if (go != true) {
          if (mounted) setState(() => _finishing = false);
          return;
        }
      }
      if (mounted) Navigator.of(context).pop(cookie);
    } finally {
      if (mounted && _finishing) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text('登录 · ${widget.title}')),
        body: Padding(
          padding: pagePadding(context, top: 24, bottom: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off, size: 44),
              const SizedBox(height: 14),
              Text('登录页打不开：$_error', textAlign: TextAlign.center),
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: () {
                  setState(() => _error = null);
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
        title: Text('登录 · ${widget.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: _finishing ? null : _finish,
            child: _finishing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('完成'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 100)
            LinearProgressIndicator(
              value: _progress <= 0 ? null : _progress / 100,
              minHeight: 2,
            ),
          Expanded(
            child: WebView(
              initialUrl: widget.url,
              userAgent: widget.desktop ? _desktopUA : null,
              javascriptMode: JavascriptMode.unrestricted,
              onWebViewCreated: (c) => _controller = c,
              onProgress: (p) {
                if (mounted) setState(() => _progress = p);
              },
              onPageFinished: (url) {
                _currentUrl = url;
                if (mounted) setState(() {});
              },
              onWebResourceError: (e) {
                // 3.x 拿不到 isForMainFrame，主文档失败才提示；子资源失败忽略
                if (_progress <= 20) {
                  setState(() => _error = e.description);
                }
              },
              navigationDelegate: (req) {
                _currentUrl = req.url;
                if (_hitSuccess(req.url)) {
                  // 已经跳到登录后的页面，直接收工
                  scheduleMicrotask(_finish);
                  return NavigationDecision.prevent;
                }
                return NavigationDecision.navigate;
              },
            ),
          ),
          Container(
            width: double.infinity,
            color: context.palette.surfaceAlt,
            padding: EdgeInsets.fromLTRB(
                16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
            child: Text(
              '在这个页面里自己登录（账号密码、验证码都在网页里操作），'
              '登录成功后点右上角「完成」，App 会把 Cookie 同步给这个源。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
