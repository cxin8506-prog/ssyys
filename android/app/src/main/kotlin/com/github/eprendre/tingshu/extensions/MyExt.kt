package com.github.eprendre.tingshu.extensions

import android.os.Handler
import android.os.Looper
import com.github.eprendre.tingshu.utils.Book
import com.localreader.local_media_app.TingShuRuntime
import io.reactivex.disposables.Disposable
import io.reactivex.disposables.Disposables
import org.jsoup.Connection
import java.io.File
import java.net.URL
import java.net.URLDecoder
import java.util.concurrent.atomic.AtomicBoolean

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

/** 给 Jsoup 请求带上 UA（isDesktop=true 用 PC 版）。 */
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

/**
 * 获取当前正在播放的书籍。
 * 宿主现在播的是 Dart 侧书库条目（just_audio），不是 TingShu 的 Book 对象，
 * 没有能直接返回的 Book；原版 2.1.7 起这个返回值就是可空的，没在播就返回 null。
 */
fun getCurrentBook(): Book? = null

/**
 * 控制播放器：play, pause, skipToNext, skipToPrevious, rewind, fastForward, stop。
 * 播放器在 Dart 侧（audioHandler），这里经过 TingShuRuntime 的播放通道转过去；
 * 通道没接上就静默不做（源在没播东西的时候调它也不该崩）。
 */
fun playerControl(action: String) {
    TingShuRuntime.playerControl(action)
}

/**
 * 获取今天播放时长，单位毫秒。
 * Dart 侧 ListenStats 按自然日记着，问它要；问不到（通道没接上/超时）回 0。
 */
fun todayPlaybackTime(): Long = TingShuRuntime.todayPlaybackTime()

/**
 * 获取每个源自己的缓存目录：filesDir/tingshu_cache/<源id>/<子目录>。
 * 比如用来放 lrc 歌词；目录不存在就建出来。
 */
fun getSourceCacheDir(sourceId: String, subDir: String): File =
    TingShuRuntime.sourceCacheDir(sourceId, subDir)

private val myExtMainHandler = Handler(Looper.getMainLooper())

/**
 * 嵌套调用多个 AudioUrlXXXExtractor 时用：耗时部分放后台线程跑，
 * 跑完回主线程调 mainThreadCallback 决定用哪个 Extractor。
 * url/autoPlay/isCache/isDebug 是调用方传的上下文，宿主不解读，
 * 只负责“后台跑 backgroundTask → 主线程回 mainThreadCallback”这个流程。
 * 返回的 Disposable 调 dispose() 可以取消（后台任务跑完之前取消才有效）。
 */
fun extractorAsyncExecute(
    url: String,
    autoPlay: Boolean,
    isCache: Boolean,
    isDebug: Boolean,
    backgroundTask: () -> String,
    mainThreadCallback: (String) -> Unit
): Disposable {
    val cancelled = AtomicBoolean(false)
    Thread {
        try {
            val result = if (cancelled.get()) "" else backgroundTask()
            if (!cancelled.get()) {
                myExtMainHandler.post {
                    try {
                        if (!cancelled.get()) mainThreadCallback(result)
                    } catch (_: Throwable) {
                    }
                }
            }
        } catch (_: Throwable) {
            // 后台任务抛错：不回调，调用方按“没解析出来”处理
        }
    }.apply {
        isDaemon = true
        start()
    }
    return Disposables.fromAction { cancelled.set(true) }
}
