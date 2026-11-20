package com.github.eprendre.tingshu.sources

/**
 * 「我的听书」搜索验证入口（与原版基类同签名）。
 *
 * 影视聚合.jar 里有源实现它：抖音、Hanime1。
 * App 的兼容层必须提供这个接口，不然 DexClassLoader 加载这些源类时会报
 * NoClassDefFoundError，SourceEntry.getSources() 整个失败，包就装不上。
 *
 * 注意：补接口只解决“类能加载、源能列出、能搜能播”；
 * 验证 WebView 本身（搜索被拦时弹网页过验证）要 U 组在搜索页接，
 * 没接时搜到要验证的源仍会按原逻辑报错。
 */
interface ISearchVerification {
    /** 验证页地址（按搜索关键词生成）。 */
    fun getSearchVerificationUrl(keywords: String): String

    /** 验证过没有（源自己读 cf_clearance 之类的 Cookie 判断）。 */
    fun isSearchValidated(): Boolean

    /** 验证页用的 UA（空字符串表示用默认 UA）。 */
    fun getSearchVerificationUA(): String

    /** 验证通过后等多久再搜（毫秒）。 */
    fun getSearchDelayMs(): Long
}
