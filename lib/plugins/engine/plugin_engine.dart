import '../model/plugin_source.dart';

/// 插件引擎统一接口。三个引擎（JS / 通用 JAR / 我的听书格式 JAR）
/// 各自实现全部方法——基类加方法时，每个引擎必须自己实现，
/// 不能只改基类不管实现（1.0.2 的教训）。
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
  /// - `config`：返回源声明的配置项（原始结构，由 ConfigSchemaLoader 解析）。
  /// - `isCacheable`：返回源能不能缓存（默认 true；视频源一律 false）。
  Future<dynamic> invoke(String method,
      {Map<String, dynamic> params = const <String, dynamic>{}});

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
    'config': '配置声明',
    'isCacheable': '是否可缓存',
  };
}
