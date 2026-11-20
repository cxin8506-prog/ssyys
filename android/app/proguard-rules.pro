# Release 构建的 R8 保留规则。
#
# 背景：v1.0.2 的发布包里一个 com.github.eprendre.tingshu.* 类都没有，
# 原因是这套「我的听书」兼容类只通过 DexClassLoader + 字符串反射被用到，
# App 自身代码没有任何静态引用，R8 把它们当死代码全删了，JAR 源加载时报
# Failed resolution of: [Lcom/github/eprendre/tingshu/sources/TingShu;。
# 这里把宿主类整批保留（类名 + 全部成员，JAR 是按原名链接的）。
-keep class com.github.eprendre.tingshu.** { *; }
# 兼容类内部用到的 Jsoup / Fuel，一起保留，免得 R8 顺着引用链再删。
-keep class org.jsoup.** { *; }
-keep class com.github.kittinunf.fuel.** { *; }
# 反射入口类本身也被桥直接点名，顺手保留。
-keep class com.localreader.local_media_app.TingShuRuntime { *; }
-keep class com.localreader.local_media_app.MainActivity { *; }
