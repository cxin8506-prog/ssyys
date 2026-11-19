import '../model/plugin_source.dart';

/// 插件引擎统一接口。
///
/// 两套写法互不兼容，各自实现：
/// - JS/ZIP（随身听书风格）：manifest.json + JS，QuickJS 执行，宿主桥提供网络
/// - JAR（我的听书风格）：Android DexClassLoader 反射调用
abstract class PluginEngine {
  /// 引擎格式标识：jsZip | jar
  String get format;

  /// 绑定一个源（加载脚本 / 准备类加载器）
  Future<void> attach(PluginSource source);

  /// 调用源方法：recommend / search / detail / chapters / content / lines / voices
  Future<dynamic> invoke(String method, {Map<String, dynamic>? params});

  Future<void> dispose();
}

/// 源方法名兼容映射：不同插件作者用的函数名不一样
class PluginMethods {
  PluginMethods._();

  static const Map<String, List<String>> aliases = {
    'recommend': [
      'recommend',
      'home',
      'homeList',
      'homeFeed',
      'indexList',
      'discover',
      'recommendList',
      'getRecommend',
      'hot',
    ],
    'search': ['search', 'bookSearch', 'searchBook', 'searchBooks'],
    'detail': ['detail', 'bookInfo', 'getBookInfo', 'bookDetail'],
    'chapters': ['chapters', 'chapterList', 'getChapterList', 'catalog'],
    'content': ['content', 'bookContent', 'getContent', 'chapterContent'],
    'lines': ['lines', 'lineList', 'getLines', 'videoLines'],
    'voices': ['voices', 'voiceList', 'getVoices', 'tones'],
  };

  static const Map<String, String> labels = {
    'recommend': '首页推荐',
    'search': '搜索',
    'detail': '详情',
    'chapters': '目录',
    'content': '正文/播放地址',
    'lines': '线路列表',
    'voices': '音色列表',
  };
}
