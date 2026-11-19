/// UA 设置相关常量与内置 UserAgent 库。
///
/// 存储使用 drift 的 kv_settings 表（key -> value），因此 UA 配置会随
/// database 目录一起被 zip 备份，跟"设置项 kv"的既有设计保持一致。
class UaConstants {
  UaConstants._();

  // ---------- kv_settings 中的 key ----------
  static const String keyAutoSelect = 'ua_auto_select';
  static const String keyMobileList = 'ua_mobile_list_json';
  static const String keyDesktopList = 'ua_desktop_list_json';
  static const String keyMobileCurrent = 'ua_mobile_current';
  static const String keyDesktopCurrent = 'ua_desktop_current';

  /// 自动选择默认开启
  static const bool defaultAutoSelect = true;

  // ---------- 只认电脑 UA 的源（按名称/域名关键词匹配）----------
  static const List<String> pcOnlyKeywords = [
    'bilibili',
    'b23.tv',
    '哔哩哔哩',
    'b站',
  ];

  /// 内置推荐（带名称，便于在界面上点选）
  static const List<UaPreset> mobilePresets = [
    UaPreset('微信 · Android 13',
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/116.0.0.0 Mobile Safari/537.36 MicroMessenger/8.0.42.2460(0x28002A35) WeChat/arm64',
        'mobile', '微信'),
    UaPreset('微信 · iOS 17',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.42(0x18002a2f) NetType/WIFI Language/zh_CN',
        'mobile', '微信'),
    UaPreset('QQ浏览器 · Android',
        'Mozilla/5.0 (Linux; U; Android 12; zh-cn; SM-G991B Build/SP1A.210812.016) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/109.0.5414.86 MQQBrowser/14.6 Mobile Safari/537.36',
        'mobile', 'QQ浏览器'),
    UaPreset('Chrome · Pixel 8 (Android 14)',
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · 小米 13 (Android 13)',
        'Mozilla/5.0 (Linux; Android 13; 2211133C) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · 华为 Mate 40 (Android 12)',
        'Mozilla/5.0 (Linux; Android 12; NOH-AN00) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · Redmi Note 10 (Android 11)',
        'Mozilla/5.0 (Linux; Android 11; Redmi Note 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Safari · iPhone iOS 17',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
        'mobile', 'Safari'),
    UaPreset('Safari · iPhone iOS 16',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
        'mobile', 'Safari'),
    UaPreset('Safari · iPad iPadOS 17',
        'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
        'mobile', 'Safari'),
    UaPreset('UC浏览器 · Android',
        'Mozilla/5.0 (Linux; U; Android 12; zh-CN; V2118A Build/SP1A.210812.003) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/100.0.4896.58 UCBrowser/15.5.8.1229 Mobile Safari/537.36',
        'mobile', 'UC'),
    UaPreset('夸克 · Android',
        'Mozilla/5.0 (Linux; U; Android 13; zh-CN; PGT-AN20 Build/TP1A.220905.001) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/111.0.5563.116 Quark/6.9.0.360 Mobile Safari/537.36',
        'mobile', '夸克'),
    UaPreset('华为浏览器 · Android',
        'Mozilla/5.0 (Linux; Android 12; NOH-AN00) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/99.0.4844.88 HuaweiBrowser/13.0.0.303 Mobile Safari/537.36',
        'mobile', '华为'),
    UaPreset('三星浏览器 · Android',
        'Mozilla/5.0 (Linux; Android 13; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/23.0 Chrome/115.0.0.0 Mobile Safari/537.36',
        'mobile', '三星'),
    UaPreset('vivo浏览器 · Android',
        'Mozilla/5.0 (Linux; U; Android 12; zh-CN; V2171A Build/SP1A.210812.003) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/105.0.0.0 Mobile Safari/537.36 VivoBrowser/16.0.0.0',
        'mobile', 'vivo'),
    UaPreset('Firefox · Android',
        'Mozilla/5.0 (Android 13; Mobile; rv:121.0) Gecko/121.0 Firefox/121.0',
        'mobile', 'Firefox'),
    UaPreset('Edge · Android',
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 EdgA/120.0.2210.126',
        'mobile', 'Edge'),
    UaPreset('百度App · Android',
        'Mozilla/5.0 (Linux; Android 12; M2102K1AC) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/109.0.5414.86 Mobile Safari/537.36 baiduboxapp/13.30.0.10',
        'mobile', '百度'),
    UaPreset('抖音 · Android',
        'Mozilla/5.0 (Linux; Android 12; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/99.0.4844.88 Mobile Safari/537.36 Aweme/26.5.0',
        'mobile', '抖音'),
    UaPreset('通用 · Android 10 兼容版',
        'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
        'mobile', '通用'),
    UaPreset('Chrome · 一加 11 (Android 13)',
        'Mozilla/5.0 (Linux; Android 13; PHB110) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · OPPO Find X6 (Android 13)',
        'Mozilla/5.0 (Linux; Android 13; PGFM10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · vivo X90 (Android 13)',
        'Mozilla/5.0 (Linux; Android 13; V2241A) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · 荣耀 Magic5 (Android 13)',
        'Mozilla/5.0 (Linux; Android 13; PGT-AN00) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · 魅族 20 (Android 13)',
        'Mozilla/5.0 (Linux; Android 13; M2381) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · 三星 S23 Ultra',
        'Mozilla/5.0 (Linux; Android 13; SM-S9180) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · 索尼 Xperia 1 V',
        'Mozilla/5.0 (Linux; Android 13; XQ-DQ72) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · Android 9 兼容',
        'Mozilla/5.0 (Linux; Android 9; Redmi Note 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.104 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Safari · iPhone iOS 15',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 15_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1',
        'mobile', 'Safari'),
    UaPreset('Safari · iPhone iOS 14',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 14_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.2 Mobile/15E148 Safari/604.1',
        'mobile', 'Safari'),
    UaPreset('Safari · iPad iPadOS 16',
        'Mozilla/5.0 (iPad; CPU OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
        'mobile', 'Safari'),
    UaPreset('Edge · iOS',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 EdgiOS/120.0.2210.126 Mobile/15E148 Safari/604.1',
        'mobile', 'Edge'),
    UaPreset('小米浏览器 · Android',
        'Mozilla/5.0 (Linux; U; Android 13; zh-cn; 2211133C Build/TKQ1.220905.001) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/109.0.5414.86 Mobile Safari/537.36 XiaoMi/MiuiBrowser/17.3.8',
        'mobile', '小米'),
    UaPreset('OPPO 浏览器 · Android',
        'Mozilla/5.0 (Linux; U; Android 13; zh-CN; PGFM10 Build/TP1A.220905.001) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/110.0.5481.154 Mobile Safari/537.36',
        'mobile', 'OPPO'),
    UaPreset('荣耀浏览器 · Android',
        'Mozilla/5.0 (Linux; Android 13; PGT-AN00) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Mobile Safari/537.36 HonorBrowser/7.0.2.301',
        'mobile', '荣耀'),
    UaPreset('搜狗浏览器 · Android',
        'Mozilla/5.0 (Linux; U; Android 12; zh-cn; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/98.0.4758.102 Mobile Safari/537.36 SogouMobileBrowser/6.2.8',
        'mobile', '搜狗'),
    UaPreset('2345 浏览器 · Android',
        'Mozilla/5.0 (Linux; U; Android 11; zh-CN; Redmi Note 10) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/90.0.4430.210 Mobile Safari/537.36 Mb2345Browser/15.0',
        'mobile', '2345'),
    UaPreset('猎豹浏览器 · Android',
        'Mozilla/5.0 (Linux; U; Android 10; zh-CN; HUAWEI P30 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/88.0.4324.93 Mobile Safari/537.36 LieBaoFast/5.26.2',
        'mobile', '猎豹'),
    UaPreset('遨游浏览器 · Android',
        'Mozilla/5.0 (Linux; U; Android 11; zh-CN) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/95.0.4638.74 Mobile Safari/537.36 Maxthon/7.0.1',
        'mobile', '遨游'),
  ];

  static const List<UaPreset> desktopPresets = [
    UaPreset('Chrome · Windows 10/11',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'desktop', 'Chrome'),
    UaPreset('Chrome · macOS',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'desktop', 'Chrome'),
    UaPreset('Chrome · Linux',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'desktop', 'Chrome'),
    UaPreset('Chrome · Windows 旧版',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36',
        'desktop', 'Chrome'),
    UaPreset('Edge · Windows 11',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.2277.83',
        'desktop', 'Edge'),
    UaPreset('Firefox · Windows',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:122.0) Gecko/20100101 Firefox/122.0',
        'desktop', 'Firefox'),
    UaPreset('Firefox · macOS',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:122.0) Gecko/20100101 Firefox/122.0',
        'desktop', 'Firefox'),
    UaPreset('Safari · macOS',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15',
        'desktop', 'Safari'),
    UaPreset('360极速浏览器 · Windows',
        'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 QIHU 360EE',
        'desktop', '360'),
    UaPreset('QQ浏览器 · Windows',
        'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36 Core/1.70.3880.400 QQBrowser/10.8.4554.400',
        'desktop', 'QQ浏览器'),
    UaPreset('Opera · Windows',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 OPR/106.0.0.0',
        'desktop', 'Opera'),
    UaPreset('通用 · Windows 兼容版',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/108.0.0.0 Safari/537.36',
        'desktop', '通用'),
    UaPreset('Edge · macOS',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.2277.83',
        'desktop', 'Edge'),
    UaPreset('Edge · Windows 10',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36 Edg/118.0.2088.76',
        'desktop', 'Edge'),
    UaPreset('Chrome · ChromeOS',
        'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'desktop', 'Chrome'),
    UaPreset('Chrome · Windows 7 兼容',
        'Mozilla/5.0 (Windows NT 6.1; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36',
        'desktop', 'Chrome'),
    UaPreset('Safari · macOS 旧版',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Safari/605.1.15',
        'desktop', 'Safari'),
    UaPreset('Firefox · Linux',
        'Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0',
        'desktop', 'Firefox'),
    UaPreset('Opera · macOS',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 OPR/106.0.0.0',
        'desktop', 'Opera'),
    UaPreset('Vivaldi · Windows',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Vivaldi/6.5',
        'desktop', 'Vivaldi'),
    UaPreset('搜狗浏览器 · Windows',
        'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.198 Safari/537.36 SE 2.X MetaSr 1.0',
        'desktop', '搜狗'),
    UaPreset('猎豹浏览器 · Windows',
        'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/79.0.3945.130 Safari/537.36 LBBROWSER',
        'desktop', '猎豹'),
  ];

  /// 兼容旧代码：由 presets 派生纯 UA 列表
  static List<String> get builtinMobileUas =>
      mobilePresets.map((e) => e.ua).toList(growable: false);

  static List<String> get builtinDesktopUas =>
      desktopPresets.map((e) => e.ua).toList(growable: false);

  /// 根据 UA 字符串猜一个友好名称（用于自定义项的展示）
  static String labelOf(String ua) {
    for (final p in [...mobilePresets, ...desktopPresets]) {
      if (p.ua == ua) return p.name;
    }
    final isMobile = ua.contains('Mobile') || ua.contains('Android') || ua.contains('iPhone');
    final platform = isMobile ? '手机' : '电脑';
    String browser = '自定义';
    final l = ua.toLowerCase();
    if (l.contains('micromessenger')) browser = '微信';
    else if (l.contains('mqqbrowser')) browser = 'QQ浏览器';
    else if (l.contains('ucbrowser')) browser = 'UC';
    else if (l.contains('quark')) browser = '夸克';
    else if (l.contains('edg')) browser = 'Edge';
    else if (l.contains('firefox')) browser = 'Firefox';
    else if (l.contains('safari') && !l.contains('chrome')) browser = 'Safari';
    else if (l.contains('chrome')) browser = 'Chrome';
    return '$platform · $browser';
  }
}

/// 一条内置 UA 预设
class UaPreset {
  final String name;
  final String ua;

  /// mobile | desktop
  final String platform;

  /// 浏览器/App 标签
  final String tag;

  const UaPreset(this.name, this.ua, this.platform, this.tag);

  bool get isMobile => platform == 'mobile';
}
