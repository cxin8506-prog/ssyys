package com.github.eprendre.tingshu.sources

/**
 * 「我的听书」源登录入口（与原版基类同签名）。
 *
 * 影视聚合.jar 里有源实现它：抖音、看剧、青空次元。
 * App 的兼容层必须提供这个接口，不然 DexClassLoader 加载这些源类时会报
 * NoClassDefFoundError，SourceEntry.getSources() 整个失败，包就装不上。
 *
 * 注意：getCookie 不是 ILogin 的成员——它是 MyExt.kt 里的独立扩展函数，
 * 源直接调 com.github.eprendre.tingshu.extensions.getCookie(url) 读 Cookie。
 */
interface ILogin {
    /** 登录页地址（源有登录入口才实现；没有就别实现这个接口）。 */
    fun getLoginUrl(): String

    /** 登录页用电脑版 UA 还是手机版 UA。 */
    fun isLoginDesktop(): Boolean
}
