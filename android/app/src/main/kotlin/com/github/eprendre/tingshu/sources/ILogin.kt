package com.github.eprendre.tingshu.sources

/**
 * 「我的听书」源登录入口（与原版基类同签名，javap 自 tingshu-base-lib.jar 核对）。
 *
 * 影视聚合.jar 里 3 个源实现它：抖音、看剧、青空次元。
 * 之前 App 的兼容层没提供这个接口，DexClassLoader 加载这 3 个源类时会报
 * NoClassDefFoundError，SourceEntry.getSources() 整个失败，包就装不上。
 */
interface ILogin {
    fun getLoginUrl(): String
    fun isLoginDesktop(): Boolean
}
