import '../model/plugin_source.dart';

/// 插件引擎统一接口。三个引擎（JS / 通用 JAR / 我的听书格式 JAR）
/// 都继承这个类：format / attach / invoke / dispose 必须各自实现；
/// config / lines / voices / content / isCacheable 是具体方法，
/// 一律委托给 invoke()，引擎直接继承，不用逐个写（1.0.2 的教训是
/// 加方法不能只改基类不管实现——这 5 个是纯委托，继承即实现）。
abstract class PluginEngine {
  /// 引擎格式标识：`js` / `jar` / `tingshu`。
  String get format;

  /// 绑定一个源（加载脚本 / 准备类加载器 / 解析 UA）。
  /// 同一个源重复 attach 应该是便宜的（已加载就直接返回）。
  Future<void> attach(PluginSource source);

  /// 调用源方法。方法名统一用这一套：
  /// - `search`：params `{keyword, page}`，返回 `{books: [...], totalPage: int}`，
  ///   totalPage 不许丢（翻页按它判断有没有下一页）。
  /// - `categoryMenus`：返回分类菜单（大类 + 子类 tab）。
  /// - `categoryPage`：params `{menu, page}` 或 `{url, page}`，
  ///   返回 `{books/list, totalPage, nextUrl}`。
  /// - `bookDetail`：params `{url}`，返回 `{cover, author, artist, intro,
  ///   chapters: [{name, url}]}`。旧名 `detail` 是它的别名。
  /// - `chapters`：params `{url}`，返回章节列表（bookDetail 的章节部分）。
  /// - `content`：params `{url, voiceId, lineId}`，返回 `{url, headers}`。
  ///   **lineId 必须传进源，不许丢**——切线靠它，否则切线只是重复调同一个地址。
  /// - `lines`：params `{url}`，返回 `[{id, name}]`，由源暴露，App 只做归一化，
  ///   不许写死返回 `[]`。
  /// - `voices`：params `{url}`，返回 `[{id, name}]`，同样不许写死返回 `[]`。
  /// - `hot` / `hotSearch`：热门搜索，返回词列表（源没提供就抛错，
  ///   调用方按“源没提供”处理，不显示热门）。
  /// - `searchVerificationResult`：params `{html, url, keyword}`，
  ///   只解析当前验证页的 HTML，不发起网络请求；明确识别到结果返回
  ///   `{verified: true, books, totalPage}`，否则返回 null，
  ///   调用方走重搜那条路。
  /// - `config`：返回源声明的配置项（原始结构，由 ConfigSchemaLoader 解析）。
  /// - `isCacheable`：返回源能不能缓存（默认 true；视频源一律 false）。
  Future<dynamic> invoke(String method,
      {Map<String, dynamic> params = const <String, dynamic>{}});

  /// 源声明的配置项（原始结构，由 ConfigSchemaLoader 解析）。
  /// 具体方法：委托给 invoke('config')，三个引擎不用逐个实现。
  Future<dynamic> config() => invoke('config');

  /// 线路列表：invoke('lines', params: {url})，归一化成 [{value, label}]。
  Future<List<Map<String, String>>> lines({String url = ''}) async {
    final r = await invoke('lines', params: <String, dynamic>{'url': url});
    return _normalizeOptions(r);
  }

  /// 音色列表：invoke('voices', params: {url})，归一化成 [{value, label}]。
  Future<List<Map<String, String>>> voices({String url = ''}) async {
    final r = await invoke('voices', params: <String, dynamic>{'url': url});
    return _normalizeOptions(r);
  }

  /// 播放地址：invoke('content', params: {url, voiceId, lineId})。
  /// lineId 必须传进源，不许丢——切线靠它。
  /// 返回结果归一化成 Map（不是 Map 就包成 {'url': '$r'}）。
  Future<Map<String, dynamic>> content(
      {required String url, String? lineId, String? voiceId}) async {
    final r = await invoke('content', params: <String, dynamic>{
      'url': url,
      'lineId': lineId,
      'voiceId': voiceId,
    });
    if (r is Map) return Map<String, dynamic>.from(r);
    return <String, dynamic>{'url': '$r'};
  }

  /// 源能不能缓存：invoke('isCacheable')，返回 bool 就用它，否则默认 true。
  Future<bool> isCacheable() async {
    final r = await invoke('isCacheable');
    if (r is bool) return r;
    return true;
  }

  /// 源是否实现了某个方法：true / false，null 表示无法判断。
  /// 默认返回 null；引擎有能力判断时重写。
  Future<bool?> hasMethod(String method) async => null;

  /// 源有没有登录入口，没有返回 null，
  /// 有返回 `{url, desktop}`（url 是登录页地址，desktop 是不是用电脑版 UA 打开）。
  /// 注意：返回 null 必须是真的探过（源确实没有登录方法），
  /// 不能是没接就写死 null。
  Future<Map<String, dynamic>?> loginInfo() async => null;

  /// 搜索验证（人机验证）：没有返回 null，
  /// 有返回 `{url, ua, delayMs, validated}`。
  Future<Map<String, dynamic>?> verificationInfo(String keyword) async =>
      null;

  /// 释放引擎持有的会话/加载器。App 退出或源被删时调。
  Future<void> dispose();
}

/// 把 invoke('lines' / 'voices') 的返回归一化成 [{value, label}]。
/// value 取 id/value/key，label 取 name/label/title；
/// 元素不是 Map 时 value 和 label 都用它本身的字符串。
/// 注意：这里不能 import config_schema_loader.dart 用它那份
/// normalizeOptions，会循环依赖，所以本地写一份小的。
List<Map<String, String>> _normalizeOptions(dynamic raw) {
  final out = <Map<String, String>>[];
  if (raw is List) {
    for (final e in raw) {
      if (e is Map) {
        final v = e['value'] ?? e['id'] ?? e['key'];
        final l = e['label'] ?? e['name'] ?? e['title'] ?? v;
        if (v != null) {
          out.add(<String, String>{'value': '$v', 'label': '$l'});
        }
      } else if (e != null) {
        out.add(<String, String>{'value': '$e', 'label': '$e'});
      }
    }
  } else if (raw is Map) {
    raw.forEach((k, v) {
      out.add(<String, String>{'value': '$k', 'label': '$v'});
    });
  }
  return out;
}

/// 源方法名兼容映射：不同插件作者用的函数名不一样，
/// 引擎按这张表依次尝试，别只认一个名字。
class PluginMethods {
  PluginMethods._();

  static const Map<String, List<String>> aliases = {
    'search': <String>['search', 'bookSearch', 'searchBook', 'searchBooks'],
    'categoryMenus': <String>[
      'categoryMenus',
      'categories',
      'categoryList',
      'getCategories',
      'classify',
      'kinds',
      'types',
      'category',
    ],
    'categoryPage': <String>[
      'categoryPage',
      'categoryItems',
      'categoryBrowse',
      'getCategoryList',
      'listByCategory',
      'getList',
      'browse',
    ],
    'bookDetail': <String>[
      'bookDetail',
      'detail',
      'bookInfo',
      'getBookInfo',
      'getBookDetailInfo',
    ],
    'chapters': <String>[
      'chapters',
      'chapterList',
      'getChapterList',
      'catalog',
    ],
    'content': <String>[
      'content',
      'audio',
      'bookContent',
      'getContent',
      'chapterContent',
    ],
    'lines': <String>['lines', 'lineList', 'getLines', 'videoLines'],
    'voices': <String>['voices', 'voiceList', 'getVoices', 'tones'],
    'hot': <String>['hotSearch', 'hot', 'hotWords', 'hotKeywords'],
    'hotSearch': <String>['hotSearch', 'hot', 'hotWords', 'hotKeywords'],
    'searchVerificationResult': <String>['searchVerificationResult'],
    'config': <String>[
      'config',
      'getConfig',
      'configForm',
      'getConfigForm',
      'settings',
      'getSettings',
      'configSchema',
      'getConfigSchema',
      'getCustomConfigItems',
    ],
  };

  static const Map<String, String> labels = {
    'search': '搜索',
    'categoryMenus': '分类列表',
    'categoryPage': '分类内容',
    'bookDetail': '详情',
    'chapters': '目录',
    'content': '正文/播放地址',
    'lines': '线路列表',
    'voices': '音色列表',
    'hot': '热门搜索',
    'hotSearch': '热门搜索',
    'searchVerificationResult': '验证结果解析',
    'config': '配置声明',
    'isCacheable': '是否可缓存',
  };
}
