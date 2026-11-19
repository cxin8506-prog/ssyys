package com.github.eprendre.tingshu.sources

/**
 * 「我的听书」搜索验证入口（与原版基类同签名，javap 自 tingshu-base-lib.jar 核对）。
 *
 * 影视聚合.jar 里 2 个源实现它：抖音、Hanime1。
 * 之前 App 的兼容层没提供这个接口，DexClassLoader 加载这 2 个源类时会报
 * NoClassDefFoundError，SourceEntry.getSources() 整个失败，包就装不上。
 * 注意：补接口只解决“类能加载、源能列出、能搜能播”；验证 WebView 本身
 * （搜索被拦时弹网页过验证）App 里还没接，搜到要验证时仍会按原逻辑报错。
 */
interface ISearchVerification {
    fun getSearchVerificationUrl(keywords: String): String
    fun isSearchValidated(): Boolean
    fun getSearchVerificationUA(): String
    fun getSearchDelayMs(): Long
}
