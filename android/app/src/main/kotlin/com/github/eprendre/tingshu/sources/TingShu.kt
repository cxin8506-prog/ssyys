package com.github.eprendre.tingshu.sources

import com.github.eprendre.tingshu.utils.Book
import com.github.eprendre.tingshu.utils.BookDetail
import com.github.eprendre.tingshu.utils.Category
import com.github.eprendre.tingshu.utils.CategoryMenu
import com.localreader.local_media_app.TingShuRuntime
import com.github.kittinunf.fuel.json.FuelJson
import org.jsoup.Jsoup
import org.jsoup.nodes.Document

/**
 * 「我的听书」自定义源 SDK 的兼容实现。
 *
 * 第三方 JAR 源里的源类都继承这个类，App 提供同一份类定义，
 * 它们在 DexClassLoader 里就能正常链接，不用改源本身。
 */
abstract class TingShu {
    abstract fun getSourceId(): String
    abstract fun getUrl(): String
    abstract fun getName(): String
    open fun getDesc() = ""
    abstract fun search(keywords: String, page: Int): Pair<List<Book>, Int>
    abstract fun getAudioUrlExtractor(): AudioUrlExtractor
    abstract fun getCategoryMenus(): List<CategoryMenu>
    abstract fun getCategoryList(url: String): Category
    open fun isMultipleEpisodePages() = false
    abstract fun getBookDetailInfo(
        bookUrl: String,
        loadEpisodes: Boolean = true,
        loadFullPages: Boolean = true
    ): BookDetail

    open fun reset() {}
    open fun isSearchable() = true
    open fun isDiscoverable() = true
    open fun isCacheable() = true
    open fun isWebViewNotRequired() = false
}

interface AudioUrlExtractor {
    fun extract(url: String, autoPlay: Boolean, isCache: Boolean)
}

interface IAd {
    fun adUrl(): String = ""
    fun showAdByDefault(): Boolean = false
}

interface AudioUrlExtraHeaders {
    fun headers(audioUrl: String): Map<String, String>
}

/** 章节地址就是最终音频地址 */
object AudioUrlDirectExtractor : AudioUrlExtractor {
    override fun extract(url: String, autoPlay: Boolean, isCache: Boolean) {
        TingShuRuntime.deliver(url)
    }
}

/** 用 Jsoup 抓页面再解析 */
object AudioUrlJsoupExtractor : AudioUrlExtractor {
    private var isDesktop = false
    private var parse: ((Document) -> String)? = null

    @JvmOverloads
    fun setUp(isDesktop: Boolean = false, parse: (Document) -> String) {
        this.isDesktop = isDesktop
        this.parse = parse
    }

    override fun extract(url: String, autoPlay: Boolean, isCache: Boolean) {
        val p = parse ?: throw IllegalStateException("AudioUrlJsoupExtractor 未 setUp")
        val html = TingShuRuntime.fetch(url, isDesktop)
        TingShuRuntime.deliver(p(Jsoup.parse(html, url)))
    }
}

/** 返回 JSON 的接口 */
object AudioUrlJsonExtractor : AudioUrlExtractor {
    private var isDesktop = false
    private var parse: ((FuelJson) -> String)? = null

    @JvmOverloads
    fun setUp(isDesktop: Boolean = false, parse: (FuelJson) -> String) {
        this.isDesktop = isDesktop
        this.parse = parse
    }

    override fun extract(url: String, autoPlay: Boolean, isCache: Boolean) {
        val p = parse ?: throw IllegalStateException("AudioUrlJsonExtractor 未 setUp")
        val body = TingShuRuntime.fetch(url, isDesktop)
        TingShuRuntime.deliver(p(FuelJson(body)))
    }
}

/** 自己写逻辑，入参是章节地址 */
object AudioUrlCustomExtractor : AudioUrlExtractor {
    private var parse: ((String) -> String)? = null

    fun setUp(parse: (String) -> String) {
        this.parse = parse
    }

    override fun extract(url: String, autoPlay: Boolean, isCache: Boolean) {
        val p = parse ?: throw IllegalStateException("AudioUrlCustomExtractor 未 setUp")
        TingShuRuntime.deliver(p(url))
    }
}

/**
 * 原本要走 WebView 渲染再执行脚本取 HTML。
 * 这里退化成直接抓页面源码交给 parse，绝大多数源都是解析 HTML 找 audio 标签，
 * 结果一致且更快。
 */
object AudioUrlWebViewExtractor : AudioUrlExtractor {
    private var isDesktop = false
    private var script: String = ""
    private var parse: ((String) -> String?)? = null

    @JvmOverloads
    fun setUp(
        isDeskTop: Boolean = false,
        script: String = "(function() { return ('<html>'+document.getElementsByTagName('html')[0].innerHTML+'</html>'); })();",
        parse: (String) -> String?
    ) {
        this.isDesktop = isDeskTop
        this.script = script
        this.parse = parse
    }

    override fun extract(url: String, autoPlay: Boolean, isCache: Boolean) {
        val p = parse ?: throw IllegalStateException("AudioUrlWebViewExtractor 未 setUp")
        val html = TingShuRuntime.fetch(url, isDesktop)
        TingShuRuntime.deliver(p(html))
    }
}

/** 嗅探页面里的音频地址 */
object AudioUrlWebViewSniffExtractor : AudioUrlExtractor {
    private var isDesktop = false
    private var validate: ((String) -> Boolean)? = null

    @JvmOverloads
    fun setUp(isDeskTop: Boolean = false, validateUrl: ((String) -> Boolean)? = null) {
        this.isDesktop = isDeskTop
        this.validate = validateUrl
    }

    override fun extract(url: String, autoPlay: Boolean, isCache: Boolean) {
        val html = TingShuRuntime.fetch(url, isDesktop)
        val found = TingShuRuntime.sniffAudio(html)
        val ok = found != null && (validate?.invoke(found) ?: true)
        TingShuRuntime.deliver(if (ok) found else null)
    }
}
