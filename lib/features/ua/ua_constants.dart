/// UA 设置相关常量与内置推荐列表。
///
/// 只存两条当前值（手机一条、电脑一条），两个文本框可改，带“恢复默认 UA”。
/// 内置推荐是筛过的（用户 2026-11-20 13:47 要求：多放一些，但是筛过的）：
/// 只留主流、真实、不容易被站方发现是伪造的、安全的，覆盖主流浏览器和真实机型
/// （Chrome、Safari、Edge、微信、QQ浏览器、华为、小米、vivo、OPPO 等）；
/// UA 字符串用真实流传的版本（Chrome 120+、Safari iOS 17、Edge、MicroMessenger 8.0.x），
/// 不编不存在的机型/版本；不要生僻、夸张、容易被识别拦截的。
/// 存储用 drift 的 kv_settings 表，自动随 database 目录进本地 zip 备份。
class UaConstants {
  UaConstants._();

  // ---------- kv_settings 中的 key ----------
  static const String keyAutoSelect = 'ua_auto_select';
  static const String keyMobileList = 'ua_mobile_list_json';
  static const String keyDesktopList = 'ua_desktop_list_json';
  static const String keyMobileCurrent = 'ua_mobile_current';
  static const String keyDesktopCurrent = 'ua_desktop_current';
  static const String keyRules = 'ua_rules_json';
  static const String keySiteMemory = 'ua_site_memory_json';
  static const String keySearchUaPrefix = 'ua_search_';

  /// 自动选择默认开启
  static const bool defaultAutoSelect = true;

  /// 默认手机 UA：Chrome · Pixel 8（Android 14）
  static String get defaultMobileUa => mobilePresets.first.ua;

  /// 默认电脑 UA：Chrome · Windows 11
  static String get defaultDesktopUa => desktopPresets.first.ua;

  /// 手机推荐（15 条，筛过：主流浏览器 + 真实机型）
  static const List<UaPreset> mobilePresets = [
    UaPreset('Chrome · Pixel 8 (Android 14)',
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · 小米 13 (Android 13)',
        'Mozilla/5.0 (Linux; Android 13; 2211133C) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · 华为 Mate 60 Pro',
        'Mozilla/5.0 (Linux; Android 10; ALN-AL00) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · 三星 S23 Ultra',
        'Mozilla/5.0 (Linux; Android 13; SM-S9180) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · OPPO Find X6',
        'Mozilla/5.0 (Linux; Android 13; PGFM10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Chrome · vivo X90',
        'Mozilla/5.0 (Linux; Android 13; V2241A) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'mobile', 'Chrome'),
    UaPreset('Safari · iPhone iOS 17',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1',
        'mobile', 'Safari'),
    UaPreset('Safari · iPad iPadOS 17',
        'Mozilla/5.0 (iPad; CPU OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1',
        'mobile', 'Safari'),
    UaPreset('微信 · Android',
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/116.0.0.0 Mobile Safari/537.36 MicroMessenger/8.0.44.2460(0x28002C35) WeChat/arm64',
        'mobile', '微信'),
    UaPreset('微信 · iOS 17',
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.44(0x18002c2f) NetType/WIFI Language/zh_CN',
        'mobile', '微信'),
    UaPreset('QQ浏览器 · Android',
        'Mozilla/5.0 (Linux; U; Android 12; zh-cn; SM-G991B Build/SP1A.210812.016) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/109.0.5414.86 MQQBrowser/14.6 Mobile Safari/537.36',
        'mobile', 'QQ浏览器'),
    UaPreset('Edge · Android',
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 EdgA/120.0.2210.126',
        'mobile', 'Edge'),
    UaPreset('Firefox · Android',
        'Mozilla/5.0 (Android 13; Mobile; rv:121.0) Gecko/121.0 Firefox/121.0',
        'mobile', 'Firefox'),
    UaPreset('小米浏览器 · Android',
        'Mozilla/5.0 (Linux; U; Android 13; zh-cn; 2211133C Build/TKQ1.220905.001) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/109.0.5414.86 Mobile Safari/537.36 XiaoMi/MiuiBrowser/17.3.8',
        'mobile', '小米'),
    UaPreset('华为浏览器 · Android',
        'Mozilla/5.0 (Linux; Android 12; NOH-AN00) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/99.0.4844.88 HuaweiBrowser/13.0.0.303 Mobile Safari/537.36',
        'mobile', '华为'),
  ];

  /// 电脑推荐（12 条，筛过：主流浏览器）
  static const List<UaPreset> desktopPresets = [
    UaPreset('Chrome · Windows 11',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'desktop', 'Chrome'),
    UaPreset('Chrome · macOS',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'desktop', 'Chrome'),
    UaPreset('Chrome · Linux',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
        'desktop', 'Chrome'),
    UaPreset('Edge · Windows 11',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.2277.83',
        'desktop', 'Edge'),
    UaPreset('Edge · macOS',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.2277.83',
        'desktop', 'Edge'),
    UaPreset('Safari · macOS',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15',
        'desktop', 'Safari'),
    UaPreset('Firefox · Windows',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:122.0) Gecko/20100101 Firefox/122.0',
        'desktop', 'Firefox'),
    UaPreset('Firefox · macOS',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:122.0) Gecko/20100101 Firefox/122.0',
        'desktop', 'Firefox'),
    UaPreset('QQ浏览器 · Windows',
        'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/111.0.0.0 Safari/537.36 Core/1.70.3880.400 QQBrowser/10.8.4554.400',
        'desktop', 'QQ浏览器'),
    UaPreset('360极速浏览器 · Windows',
        'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 QIHU 360EE',
        'desktop', '360'),
    UaPreset('微信 · Windows',
        'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/107.0.0.0 Safari/537.36',
        'desktop', '微信'),
    UaPreset('Opera · Windows',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 OPR/106.0.0.0',
        'desktop', 'Opera'),
  ];

  /// 预设规则表：域名/关键词 → 电脑版还是手机版（常用视频站/网盘站）。
  /// 规则可增删改、每条可开关；按站记忆优先于规则表。
  static const List<UaRule> defaultRules = [
    UaRule(id: 'bilibili', pattern: 'bilibili', desktop: true),
    UaRule(id: 'b23', pattern: 'b23.tv', desktop: true),
    UaRule(id: 'baidupan', pattern: 'pan.baidu.com', desktop: true),
    UaRule(id: 'aliyundrive', pattern: 'aliyundrive.com', desktop: true),
    UaRule(id: '123pan', pattern: '123pan.com', desktop: true),
    UaRule(id: '189cloud', pattern: 'cloud.189.cn', desktop: true),
    UaRule(id: '115', pattern: '115.com', desktop: true),
    UaRule(id: 'youtube', pattern: 'youtube.com', desktop: true),
    UaRule(id: 'iqiyi', pattern: 'iqiyi.com', desktop: true),
    UaRule(id: 'youku', pattern: 'youku.com', desktop: true),
    UaRule(id: 'qqvideo', pattern: 'v.qq.com', desktop: true),
    UaRule(id: 'mgtv', pattern: 'mgtv.com', desktop: true),
  ];

  static List<String> get builtinMobileUas =>
      mobilePresets.map((e) => e.ua).toList(growable: false);

  static List<String> get builtinDesktopUas =>
      desktopPresets.map((e) => e.ua).toList(growable: false);

  /// 根据 UA 字符串猜一个友好名称（用于自定义项的展示）
  static String labelOf(String ua) {
    for (final p in [...mobilePresets, ...desktopPresets]) {
      if (p.ua == ua) return p.name;
    }
    final isMobile =
        ua.contains('Mobile') || ua.contains('Android') || ua.contains('iPhone');
    final platform = isMobile ? '手机' : '电脑';
    String browser = '自定义';
    final l = ua.toLowerCase();
    if (l.contains('micromessenger')) {
      browser = '微信';
    } else if (l.contains('mqqbrowser')) {
      browser = 'QQ浏览器';
    } else if (l.contains('ucbrowser')) {
      browser = 'UC';
    } else if (l.contains('quark')) {
      browser = '夸克';
    } else if (l.contains('edg')) {
      browser = 'Edge';
    } else if (l.contains('firefox')) {
      browser = 'Firefox';
    } else if (l.contains('safari') && !l.contains('chrome')) {
      browser = 'Safari';
    } else if (l.contains('chrome')) {
      browser = 'Chrome';
    }
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

/// 一条 UA 规则：域名或关键词 → 用电脑版还是手机版。
class UaRule {
  final String id;
  final String pattern;
  final bool desktop;
  final bool enabled;

  const UaRule({
    required this.id,
    required this.pattern,
    required this.desktop,
    this.enabled = true,
  });

  UaRule copyWith({String? pattern, bool? desktop, bool? enabled}) {
    return UaRule(
      id: id,
      pattern: pattern ?? this.pattern,
      desktop: desktop ?? this.desktop,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'pattern': pattern,
      'desktop': desktop,
      'enabled': enabled,
    };
  }

  factory UaRule.fromJson(Map<String, dynamic> json) {
    return UaRule(
      id: '${json['id'] ?? ''}',
      pattern: '${json['pattern'] ?? ''}',
      desktop: json['desktop'] == true,
      enabled: json['enabled'] != false,
    );
  }
}
