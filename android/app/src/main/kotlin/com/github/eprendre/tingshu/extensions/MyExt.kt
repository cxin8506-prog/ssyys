package com.github.eprendre.tingshu.extensions

import com.localreader.local_media_app.TingShuRuntime
import org.jsoup.Connection
import java.net.URL
import java.net.URLDecoder

fun splitQuery(url: URL): LinkedHashMap<String, String> {
    val queryPairs = LinkedHashMap<String, String>()
    val query = url.query ?: return queryPairs
    val pairs = query.split("&")
    for (pair in pairs) {
        val idx = pair.indexOf("=")
        if (idx < 0) continue
        queryPairs[URLDecoder.decode(pair.substring(0, idx), "UTF-8")] =
            URLDecoder.decode(pair.substring(idx + 1), "UTF-8")
    }
    return queryPairs
}

/** 给 Jsoup 请求带上 UA（isDesktop=true 用 PC 版） */
fun Connection.config(isDesktop: Boolean = false): Connection =
    this.userAgent(if (isDesktop) getDesktopUA() else getMobileUA())

fun getDesktopUA(): String = TingShuRuntime.desktopUA

fun getMobileUA(): String = TingShuRuntime.mobileUA

/** 加载多页章节时用来给宿主报进度，这里不需要，留空实现。 */
fun notifyLoadingEpisodes(pageInfo: String?) {}

/**
 * 读宿主 WebView 的 Cookie（登录态 / cf_clearance 都在这里）。
 * 没有时返回空串，不抛错。
 */
fun getCookie(url: String): String = TingShuRuntime.getCookie(url)

/** 在主线程弹一个短提示。 */
fun showToast(msg: String) {
    TingShuRuntime.showToast(msg)
}
