import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart';
import '../data/web_session.dart';

/// 源登录页：内嵌 WebView 打开源给的登录地址，用户自己输账号、过验证码。
///
/// 登录完成后（点了「完成」或命中 successUrl）自动把该站点的 Cookie 读出来，
/// 通过 `Navigator.pop(cookie)` 交回给调用方保存。
///
/// 旧手机兜底：旧 Android WebView 跑不动现代站点 JS 时页面会黑在那，
/// 所以这里做了两层兜底——
/// 1) 页面长时间加载不完 / 加载完正文是空的，就显示一句人话提示 + 手动入口，
///    不让用户干等在一片黑屏上；
/// 2) 传了 [tokenKey] 的源（比如青空次元的 sorani_auth_token）可以在登录页里
///    点「手动输入 Token」，把在电脑浏览器上登录后拿到的 token 粘贴进来，
///    点确定就写进这个站点的 localStorage（源播放时就从这里读 token，
///    跟 WebView 登录拿到的 token 一个用法），同时以 `TOKEN:<token>` 的形式
///    返回给调用方存进源配置。
class LoginWebPage extends StatefulWidget {
  final String title;
  final String url;
  final String successUrl;
  final String cookieUrl;

  /// true 用电脑版 UA 打开（有的站只认电脑版登录页）
  final bool desktop;

  /// 手动粘贴 token 时写进 localStorage 的键（比如 sorani_auth_token）。
  /// 空表示这个源不提供手动 token 入口。
  final String tokenKey;

  /// 手动 token 输入框里的说明文字
  final String tokenHint;

  const LoginWebPage({
    super.key,
    required this.title,
    required this.url,
    this.successUrl = '',
    this.cookieUrl = '',
    this.desktop = false,
    this.tokenKey = '',
    this.tokenHint = '',
  });

  @override
  State<LoginWebPage> createState() => _LoginWebPageState();
}

class _LoginWebPageState extends State<LoginWebPage> {
  static const _desktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/112.0.0.0 Safari/537.36';

  /// 页面一直加载不出来，超过这个时间就提示兜底入口
  static const _loadTimeout = Duration(seconds: 20);

  /// 页面加载完后等一会再检查正文是不是空的（SPA 渲染需要一点时间）
  static const _blankCheckDelay = Duration(seconds: 4);

  WebViewController? _controller;
  int _progress = 0;
  String _currentUrl = '';
  bool _finishing = false;
  String? _error;

  /// 页面是否触发过 onPageFinished
  bool _pageLoaded = false;

  /// 是否显示“页面可能打不开”的兜底提示条
  bool _showFallbackHint = false;

  Timer? _loadTimer;
  Timer? _blankTimer;

  final _session = WebSession();

  bool get _hasTokenEntry => widget.tokenKey.trim().isNotEmpty;

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
    // 一直加载不出来：提示兜底入口，别让用户干等
    _loadTimer = Timer(_loadTimeout, () {
      if (!mounted) return;
      if (!_pageLoaded && _error == null) {
        setState(() => _showFallbackHint = true);
      }
    });
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    _blankTimer?.cancel();
    super.dispose();
  }

  bool _hitSuccess(String url) {
    final s = widget.successUrl.trim();
    if (s.isEmpty) return false;
    return url.startsWith(s);
  }

  /// 页面加载完后检查正文是不是空的：旧手机 WebView 跑不动现代站点 JS 时，
  /// 页面能加载完但渲染出来是黑的，正文基本是空的。
  Future<void> _checkBlank() async {
    final c = _controller;
    if (c == null || !mounted) return;
    try {
      final r = await c.evaluateJavascript(
          'document.body ? document.body.innerText.length : 0');
      if (!mounted) return;
      if (r.trim() == '0') {
        setState(() => _showFallbackHint = true);
      }
    } catch (_) {
      // JS 求值失败就不提示，别误报
    }
  }

  void _onPageFinished(String url) {
    _currentUrl = url;
    if (!_pageLoaded) {
      _pageLoaded = true;
      _loadTimer?.cancel();
      // 等一会再检查空白，给 SPA 一点渲染时间
      _blankTimer?.cancel();
      _blankTimer = Timer(_blankCheckDelay, _checkBlank);
    }
    if (mounted) setState(() {});
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

  /// 手动输入 Token：粘贴进来后写进这个站点的 localStorage，
  /// 再以 `TOKEN:<token>` 返回给调用方存进源配置。
  Future<void> _showTokenDialog() async {
    final ctrl = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动输入 Token'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.tokenHint.isNotEmpty
                  ? widget.tokenHint
                  : '在电脑浏览器上登录这个站点后，把 ${widget.tokenKey} 的值复制过来粘贴进来。',
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: 4,
              minLines: 3,
              decoration: InputDecoration(
                hintText: widget.tokenKey,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
    if (token == null || token.isEmpty) return;
    // 写进这个站点的 localStorage：源播放时就从这里读 token。
    // 旧手机上站点 JS 跑不动也不影响这一行，localStorage 本身能写就行。
    final c = _controller;
    if (c != null && _hasTokenEntry) {
      try {
        await c.evaluateJavascript(
            'localStorage.setItem(${jsonEncode(widget.tokenKey)}, ${jsonEncode(token)})');
      } catch (_) {
        // 写不进去也没关系，调用方还会把 token 存进源配置
      }
    }
    if (mounted) Navigator.of(context).pop('TOKEN:$token');
  }

  void _retry() {
    setState(() {
      _error = null;
      _pageLoaded = false;
      _showFallbackHint = false;
      _progress = 0;
    });
    _loadTimer?.cancel();
    _loadTimer = Timer(_loadTimeout, () {
      if (!mounted) return;
      if (!_pageLoaded && _error == null) {
        setState(() => _showFallbackHint = true);
      }
    });
    _controller?.reload();
  }

  /// “页面可能打不开”的兜底提示条：旧手机 WebView 黑屏/白屏时显示
  Widget _fallbackBanner() {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: context.palette.primarySoft,
        border: Border(
          bottom: BorderSide(color: context.palette.outline),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '这个登录页在旧手机上可能打不开（一直加载或一片空白），'
                  '可以试试手动输入 Token 登录。',
                  style: TextStyle(fontSize: 12.5, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              if (_hasTokenEntry)
                OutlinedButton(
                  onPressed: _showTokenDialog,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('手动输入 Token',
                      style: TextStyle(fontSize: 12)),
                ),
              OutlinedButton(
                onPressed: _retry,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child:
                    const Text('重新加载', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
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
              const SizedBox(height: 8),
              Text(
                '旧手机 WebView 可能打不开这个站点的登录页，'
                '可以试试手动输入 Token 登录。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  if (_hasTokenEntry)
                    OutlinedButton(
                      onPressed: _showTokenDialog,
                      child: const Text('手动输入 Token'),
                    ),
                  OutlinedButton(
                    onPressed: _retry,
                    child: const Text('重试'),
                  ),
                ],
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
          if (_hasTokenEntry)
            TextButton(
              onPressed: _showTokenDialog,
              child: const Text('手动输入 Token',
                  style: TextStyle(fontSize: 13)),
            ),
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
          if (_showFallbackHint) _fallbackBanner(),
          Expanded(
            child: WebView(
              initialUrl: widget.url,
              userAgent: widget.desktop ? _desktopUA : null,
              javascriptMode: JavascriptMode.unrestricted,
              onWebViewCreated: (c) => _controller = c,
              onProgress: (p) {
                if (mounted) setState(() => _progress = p);
              },
              onPageFinished: _onPageFinished,
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
              '登录成功后点右上角「完成」，App 会把 Cookie 同步给这个源。'
              '${_hasTokenEntry ? '如果页面打不开，点右上角「手动输入 Token」。' : ''}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
