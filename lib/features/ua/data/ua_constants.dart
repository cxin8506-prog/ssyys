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

  /// 自动选择默认开启
  static const bool defaultAutoSelect = true;

  // ---------- 只认电脑 UA 的源（按名称/域名关键词匹配）----------
  /// 命中任一关键词即视为"PC-only 源"，自动选择开启时用电脑 UA。
  /// 二期插件可扩充此表；第一版内置常见几个。
  static const List<String> pcOnlyKeywords = [
    'bilibili',
    'b23.tv',
    '哔哩哔哩',
  ];

  /// 内置常用手机 UA（多条，可单独选用）
  static const List<String> builtinMobileUas = [
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (Linux; Android 12; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
    'Mozilla/5.0 (Linux; Android 11; Redmi Note 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (Linux; Android 10; HUAWEI P30 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (Linux; U; Android 12; zh-CN; VIVO X70) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/105.0.0.0 Mobile Safari/537.36',
    'Mozilla/5.0 (Linux; Android 13; OPPO Reno8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
  ];

  /// 内置常用电脑 UA（多条，可单独选用）
  static const List<String> builtinDesktopUas = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36 Edg/119.0.0.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  ];
}
