package com.localreader.local_media_app

import android.content.Context
import android.content.SharedPreferences
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.webkit.CookieManager
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import dalvik.system.DexClassLoader
import dalvik.system.DexFile
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.lang.reflect.Modifier
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.zip.GZIPInputStream

/**
 * 「我的听书」格式 JAR 源的运行时：
 *   - 提供源需要的 UA / 网络抓取 / 音频嗅探
 *   - 反射加载 JAR 里的 SourceEntry，列出它包含的每个源
 *   - 把源的 search / 分类 / 详情 / 章节 / 音频地址转成统一 JSON
 *
 * 关键点（1.0.2/1.0.3 的教训）：
 *   - 每个 JAR 一个 DexClassLoader（按路径缓存的 Map），重导时能单独清；
 *     以前只缓存一个加载器，两个包来回切会互相串。
 *   - 每个 JAR 一个 odex 子目录（名字按 JAR 路径算），重导不命中旧 odex。
 *   - 入口类缓存 entryCache 可失效；扫描/列出失败要把原始异常带出去，
 *     别吞成空列表，不然 Dart 侧分不清“扫不到”和“列不出”。
 *   - JAR 拷完要设只读（Android 14+ 拒绝加载可写的 dex）。
 */
object TingShuRuntime {

    @JvmStatic
    var mobileUA: String =
        "Mozilla/5.0 (Linux; Android 12; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/112.0.0.0 Mobile Safari/537.36"

    @JvmStatic
    var desktopUA: String =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " +
            "Chrome/112.0.0.0 Safari/537.36"

    /** Dart 侧解析出来的 UA（手机/电脑各一条），attach 时由引擎推过来。 */
    fun setUserAgents(mobile: String, desktop: String) {
        if (mobile.isNotEmpty()) mobileUA = mobile
        if (desktop.isNotEmpty()) desktopUA = desktop
    }

    private var appContext: Context? = null

    fun init(ctx: Context) {
        appContext = ctx.applicationContext
    }

    fun prefs(): SharedPreferences? =
        appContext?.getSharedPreferences("tingshu_ext", Context.MODE_PRIVATE)

    private val mainHandler = Handler(Looper.getMainLooper())

    // ------------------------------------------------------------ 播放控制（源调宿主）

    /**
     * Dart 侧播放器通道（MainActivity 在 configureFlutterEngine 里接上）。
     * 源代码跑在 JVM 里，调 MyExt.playerControl / todayPlaybackTime 时要
     * 经过这个通道转给 Dart 的 audioHandler；没接上就静默不做，不抛错。
     */
    @JvmStatic
    var playerChannel: MethodChannel? = null

    /** 源调 playerControl("play/pause/skipToNext/...")：转给 Dart 播放器 */
    fun playerControl(action: String) {
        val ch = playerChannel ?: return
        mainHandler.post {
            try {
                ch.invokeMethod(action, null)
            } catch (_: Throwable) {
            }
        }
    }

    /** 源调 todayPlaybackTime()：问 Dart 侧的收听统计（今日毫秒数），2 秒超时回 0 */
    fun todayPlaybackTime(): Long {
        val ch = playerChannel ?: return 0L
        val latch = CountDownLatch(1)
        var ms = 0L
        mainHandler.post {
            try {
                ch.invokeMethod("todayPlaybackTime", null,
                    object : MethodChannel.Result {
                        override fun success(result: Any?) {
                            ms = (result as? Number)?.toLong() ?: 0L
                            latch.countDown()
                        }

                        override fun error(code: String, msg: String?, details: Any?) {
                            latch.countDown()
                        }

                        override fun notImplemented() {
                            latch.countDown()
                        }
                    })
            } catch (_: Throwable) {
                latch.countDown()
            }
        }
        latch.await(2000, TimeUnit.MILLISECONDS)
        return ms
    }

    /** 源自己的缓存目录：filesDir/tingshu_cache/<源id>/<子目录>，不存在就建 */
    fun sourceCacheDir(sourceId: String, subDir: String): File {
        val ctx = appContext ?: throw IllegalStateException("TingShuRuntime 未初始化")
        val safeId = sourceId.replace(Regex("[^A-Za-z0-9._-]"), "_")
            .ifEmpty { "default" }
        val safeSub = subDir.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val dir = if (safeSub.isEmpty()) {
            File(File(ctx.filesDir, "tingshu_cache"), safeId)
        } else {
            File(File(ctx.filesDir, "tingshu_cache/$safeId"), safeSub)
        }
        dir.mkdirs()
        return dir
    }

    /**
     * 读 WebView 的 Cookie：登录态、cf_clearance 都存在这里，
     * 和登录页、验证页是同一份 CookieManager。
     */
    fun getCookie(url: String): String {
        return try {
            val cm = CookieManager.getInstance()
            cm.setAcceptCookie(true)
            cm.getCookie(url) ?: ""
        } catch (_: Throwable) {
            ""
        }
    }

    fun showToast(msg: String) {
        val ctx = appContext ?: return
        mainHandler.post {
            try {
                Toast.makeText(ctx, msg, Toast.LENGTH_SHORT).show()
            } catch (_: Throwable) {
            }
        }
    }

    // ------------------------------------------------------------ 音频地址回传

    private val resultHolder = ThreadLocal<String?>()

    @JvmStatic
    fun deliver(url: String?) {
        resultHolder.set(url)
    }

    fun takeDelivered(): String? {
        val v = resultHolder.get()
        resultHolder.remove()
        return v
    }

    // ------------------------------------------------------------ 网络

    fun fetch(url: String, isDesktop: Boolean = false, referer: String? = null): String {
        var current = url
        var redirects = 0
        while (redirects < 6) {
            val conn = (URL(current).openConnection() as HttpURLConnection).apply {
                connectTimeout = 20000
                readTimeout = 25000
                instanceFollowRedirects = false
                requestMethod = "GET"
                setRequestProperty("User-Agent", if (isDesktop) desktopUA else mobileUA)
                setRequestProperty("Accept", "*/*")
                setRequestProperty("Accept-Language", "zh-CN,zh;q=0.9")
                setRequestProperty("Accept-Encoding", "gzip")
                if (!referer.isNullOrEmpty()) setRequestProperty("Referer", referer)
                // 登录态 / cf_clearance 都在 WebView 的 Cookie 里，请求要带上
                val cookie = getCookie(current)
                if (cookie.isNotEmpty()) setRequestProperty("Cookie", cookie)
            }
            val code = conn.responseCode
            // 响应里带回的 Cookie 也写进 CookieManager，和 WebView 共用
            try {
                val cm = CookieManager.getInstance()
                conn.headerFields["Set-Cookie"]?.forEach { c ->
                    if (c.isNotEmpty()) cm.setCookie(current, c)
                }
                conn.headerFields["set-cookie"]?.forEach { c ->
                    if (c.isNotEmpty()) cm.setCookie(current, c)
                }
            } catch (_: Throwable) {
            }
            if (code in 300..399) {
                val loc = conn.getHeaderField("Location")
                conn.disconnect()
                if (loc.isNullOrEmpty()) throw RuntimeException("重定向缺少 Location")
                current = if (loc.startsWith("http")) loc else URL(URL(current), loc).toString()
                redirects++
                continue
            }
            if (code >= 400) {
                conn.disconnect()
                throw RuntimeException("HTTP $code")
            }
            val stream = if ("gzip".equals(conn.contentEncoding, true)) {
                GZIPInputStream(conn.inputStream)
            } else {
                conn.inputStream
            }
            val bytes = stream.use { input ->
                val out = ByteArrayOutputStream()
                input.copyTo(out, 8192)
                out.toByteArray()
            }
            conn.disconnect()
            return String(bytes, Charsets.UTF_8)
        }
        throw RuntimeException("重定向次数过多")
    }

    /** 从页面里找最可能的音频地址 */
    fun sniffAudio(html: String): String? {
        val re = Regex(
            "(https?:)?//[^\"'\\s<>\\\\]+\\.(m3u8|mp3|m4a|aac|mp4)(\\?[^\"'\\s<>\\\\]*)?",
            RegexOption.IGNORE_CASE
        )
        val hit = re.find(html)?.value ?: return null
        return if (hit.startsWith("//")) "https:$hit" else hit
    }

    // ------------------------------------------------------------ 真 WebView

    /**
     * 主线程起一个隐藏 WebView 加载 url，页面跑完后执行 script，
     * 返回脚本返回值解码后的字符串；超时或失败返回 null。
     * evaluateJavascript 的返回值是 JSON 编码的，字符串要先解一层。
     */
    fun webViewEval(
        url: String,
        isDesktop: Boolean = false,
        script: String,
        timeoutMs: Long = 30000
    ): String? {
        val ctx = appContext ?: return null
        val latch = CountDownLatch(1)
        var result: String? = null
        var webView: WebView? = null
        mainHandler.post {
            try {
                val wv = WebView(ctx)
                webView = wv
                val settings = wv.settings
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.userAgentString = if (isDesktop) desktopUA else mobileUA
                CookieManager.getInstance().setAcceptCookie(true)
                var done = false
                wv.webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView, finishedUrl: String) {
                        if (done) return
                        done = true
                        try {
                            view.evaluateJavascript(script) { value ->
                                result = decodeJsString(value)
                                latch.countDown()
                            }
                        } catch (_: Throwable) {
                            latch.countDown()
                        }
                    }
                }
                wv.loadUrl(url)
                mainHandler.postDelayed({
                    if (latch.count > 0) latch.countDown()
                }, timeoutMs)
            } catch (_: Throwable) {
                latch.countDown()
            }
        }
        latch.await(timeoutMs + 5000, TimeUnit.MILLISECONDS)
        mainHandler.post {
            try {
                webView?.stopLoading()
                webView?.destroy()
            } catch (_: Throwable) {
            }
        }
        return result
    }

    /** evaluateJavascript 返回的 JSON 编码字符串解一层；"null" 返回 null。 */
    private fun decodeJsString(value: String?): String? {
        if (value == null || value == "null" || value.isEmpty()) return null
        return try {
            JSONArray("[$value]").optString(0).takeIf { it.isNotEmpty() }
        } catch (_: Throwable) {
            value.trim('"')
        }
    }

    /**
     * 真 WebView 加载页面，拦截资源请求，抓第一个音频/视频地址。
     * 页面加载完再等几秒，让播放器请求发出来。
     */
    fun webViewSniff(
        url: String,
        isDesktop: Boolean = false,
        timeoutMs: Long = 30000
    ): String? {
        val ctx = appContext ?: return null
        val mediaRe = Regex("\\.(m3u8|mp4|mp3|m4a)([?#]|$)", RegexOption.IGNORE_CASE)
        val found = ArrayList<String>()
        val pageDone = CountDownLatch(1)
        var webView: WebView? = null
        mainHandler.post {
            try {
                val wv = WebView(ctx)
                webView = wv
                val settings = wv.settings
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.userAgentString = if (isDesktop) desktopUA else mobileUA
                CookieManager.getInstance().setAcceptCookie(true)
                wv.webViewClient = object : WebViewClient() {
                    override fun shouldInterceptRequest(
                        view: WebView,
                        request: WebResourceRequest
                    ): WebResourceResponse? {
                        val u = request.url.toString()
                        if (mediaRe.containsMatchIn(u)) {
                            synchronized(found) {
                                if (u !in found) found.add(u)
                            }
                        }
                        return super.shouldInterceptRequest(view, request)
                    }

                    override fun onPageFinished(view: WebView, finishedUrl: String) {
                        pageDone.countDown()
                    }
                }
                wv.loadUrl(url)
            } catch (_: Throwable) {
                pageDone.countDown()
            }
        }
        pageDone.await(timeoutMs, TimeUnit.MILLISECONDS)
        val deadline = System.currentTimeMillis() + 5000
        while (found.isEmpty() && System.currentTimeMillis() < deadline) {
            Thread.sleep(300)
        }
        mainHandler.post {
            try {
                webView?.stopLoading()
                webView?.destroy()
            } catch (_: Throwable) {
            }
        }
        return found.firstOrNull()
    }

    // ------------------------------------------------------------ JAR / 源

    // 每个 JAR 一个加载器（按路径缓存的 Map），重导时能单独清；
    // 以前只缓存一个加载器，两个包来回切会互相串。
    private val loaders = HashMap<String, DexClassLoader>()
    private val instanceCache = HashMap<String, Any>()

    /**
     * 每个 JAR 一个 odex 子目录（名字按 JAR 路径算）。
     * 以前所有 JAR 共用 codeCacheDir/plugin_dex + 写死的 scan.dex，
     * 重导同一个包会拿到旧的优化 dex；现在一包一目录，互不干扰。
     */
    private fun odexDirFor(path: String): File {
        val ctx = appContext ?: throw IllegalStateException("TingShuRuntime 未初始化")
        val base = File(path).name.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val tag = Integer.toUnsignedString(path.hashCode(), 36)
        val out = File(File(ctx.codeCacheDir, "plugin_dex"), "${base}_$tag")
        if (!out.exists()) out.mkdirs()
        return out
    }

    @Synchronized
    private fun loaderFor(path: String): DexClassLoader {
        loaders[path]?.let { return it }
        val out = odexDirFor(path)
        val loader = DexClassLoader(path, out.absolutePath, null, javaClass.classLoader)
        loaders[path] = loader
        return loader
    }

    /**
     * 清掉某个 JAR 的全部缓存：加载器、入口缓存、源实例缓存、odex 目录。
     * 重导同一个包前必须调一次，否则同路径会命中旧加载器/旧 odex，
     * 新包导进来还是旧的源（1.0.3 失败的怀疑点 b）。
     */
    @Synchronized
    fun clearCacheFor(path: String) {
        loaders.remove(path)
        entryCache.remove(path)
        val it = instanceCache.keys.iterator()
        while (it.hasNext()) {
            if (it.next().startsWith("$path#")) it.remove()
        }
        try {
            odexDirFor(path).deleteRecursively()
        } catch (_: Throwable) {
        }
    }

    /**
     * 把 JAR 设成只读（chmod 444）。
     * Android 14+ 拒绝加载可写的 dex/jar，拷出来的 plugin.jar 默认可写，
     * 不设只读 DexFile.loadDex / DexClassLoader 直接抛错（1.0.3 失败的
     * 怀疑点 a，随心听书专门做了 makeReadOnly + 专门报错）。
     * 返回是否成功，失败也不抛错（调用方记日志继续走）。
     */
    fun makeReadOnly(path: String): Boolean {
        return try {
            val f = File(path)
            if (!f.exists()) return false
            f.setReadOnly()
        } catch (_: Throwable) {
            false
        }
    }

    private fun listClassNames(path: String): List<String> {
        val out = odexDirFor(path)
        val dex = DexFile.loadDex(path, File(out, "scan.dex").absolutePath, 0)
        val names = ArrayList<String>()
        val e = dex.entries()
        while (e.hasMoreElements()) {
            val n = e.nextElement()
            if (n.startsWith("android.") || n.startsWith("java.") ||
                n.startsWith("kotlin.") || n.startsWith("dalvik.") ||
                n.startsWith("kotlinx.")
            ) continue
            names.add(n)
        }
        dex.close()
        names.sort()
        return names
    }

    private val entryCache = HashMap<String, List<String>>()

    /** 找 JAR 里的源入口类（含 getSources 的类）。 */
    @Synchronized
    fun findEntryClasses(path: String): List<String> {
        entryCache[path]?.let { return it }
        val found = try {
            scanEntryClasses(path)
        } catch (t: Throwable) {
            // dex 本身加载失败（比如文件可写被 Android 14+ 拒绝）：
            // 别吞成空列表，带上原因抛出去，Dart 侧才能区分“扫不到”和“列不出”
            throw RuntimeException("扫描 JAR 入口失败：${t.message ?: t}", t)
        }
        entryCache[path] = found
        return found
    }

    private fun scanEntryClasses(path: String): List<String> {
        val loader = loaderFor(path)
        val names = listClassNames(path)
        val hits = ArrayList<String>()
        // 优先认 SourceEntry
        val preferred = names.filter { it.endsWith("SourceEntry") || it.endsWith("SourceList") }
        val ordered = preferred + names.filter { it !in preferred }
        for (n in ordered) {
            try {
                val cls = Class.forName(n, false, loader)
                val hasStatic = cls.methods.any {
                    it.name == "getSources" && Modifier.isStatic(it.modifiers) && it.parameterCount == 0
                }
                val hasInstance = cls.methods.any {
                    it.name == "getSources" && !Modifier.isStatic(it.modifiers) && it.parameterCount == 0
                }
                if (hasStatic || hasInstance) hits.add(n)
                if (hits.isNotEmpty() && n.endsWith("SourceEntry")) break
            } catch (t: Throwable) {
                // 只有入口候选类加载失败才记日志：普通类加载失败是正常的
                // （引用了宿主没有的类型），记了也没用，只会刷屏
                if (n.endsWith("SourceEntry") || n.endsWith("SourceList")) {
                    Log.w("TingShuRuntime", "入口候选类加载失败 $n: ${t.message}")
                }
            }
        }
        return hits
    }

    private fun sourcesOf(path: String, entryClass: String): List<Any> {
        val loader = loaderFor(path)
        val cls = Class.forName(entryClass, true, loader)
        val m = cls.methods.firstOrNull {
            it.name == "getSources" && it.parameterCount == 0
        } ?: throw RuntimeException("$entryClass 没有 getSources()")
        val receiver = if (Modifier.isStatic(m.modifiers)) {
            null
        } else {
            cls.getField("INSTANCE").get(null)
        }
        // getSources() 要实例化全部源对象，任何一个源的构造器抛错，
        // 整个调用就失败——带上入口类名抛出去，别和“扫不到”混成同一句报错
        val raw = try {
            m.invoke(receiver) as? List<*> ?: emptyList<Any>()
        } catch (t: Throwable) {
            val cause = (t.cause ?: t).message ?: t.toString()
            throw RuntimeException("调用 $entryClass.getSources() 失败：$cause", t)
        }
        return raw.filterNotNull()
    }

    @Synchronized
    private fun sourceInstance(path: String, entryClass: String, index: Int): Any {
        val key = "$path#$entryClass#$index"
        instanceCache[key]?.let { return it }
        val list = sourcesOf(path, entryClass)
        if (index < 0 || index >= list.size) throw RuntimeException("源下标越界：$index/${list.size}")
        val s = list[index]
        instanceCache[key] = s
        return s
    }

    /** 列出 JAR 内所有源的基本信息 */
    fun listSources(path: String, entryClass: String): List<Map<String, Any?>> {
        val list = sourcesOf(path, entryClass)
        val out = ArrayList<Map<String, Any?>>()
        for ((i, s) in list.withIndex()) {
            fun call(name: String): String = try {
                (s.javaClass.getMethod(name).invoke(s) as? String) ?: ""
            } catch (_: Throwable) {
                ""
            }
            out.add(
                mapOf(
                    "index" to i,
                    "name" to call("getName"),
                    "id" to call("getSourceId"),
                    "url" to call("getUrl"),
                    "desc" to call("getDesc"),
                    "class" to s.javaClass.name
                )
            )
        }
        return out
    }

    /** 源有没有登录入口（ILogin），有就返回登录地址和是否用电脑版 UA */
    fun loginInfo(path: String, entryClass: String, index: Int): Map<String, Any?>? {
        val s = sourceInstance(path, entryClass, index)
        return try {
            val m = s.javaClass.getMethod("getLoginUrl")
            val url = m.invoke(s) as? String ?: ""
            if (url.isEmpty()) return null
            val desktop = try {
                s.javaClass.getMethod("isLoginDesktop").invoke(s) as? Boolean ?: false
            } catch (_: Throwable) {
                false
            }
            mapOf("url" to url, "desktop" to desktop)
        } catch (_: Throwable) {
            null
        }
    }

    /** 源有没有搜索验证（ISearchVerification），有就返回验证地址等 */
    fun verificationInfo(
        path: String,
        entryClass: String,
        index: Int,
        keywords: String
    ): Map<String, Any?>? {
        val s = sourceInstance(path, entryClass, index)
        return try {
            val m = s.javaClass.getMethod("getSearchVerificationUrl", String::class.java)
            val url = m.invoke(s, keywords) as? String ?: ""
            if (url.isEmpty()) return null
            val ua = try {
                s.javaClass.getMethod("getSearchVerificationUA").invoke(s) as? String ?: ""
            } catch (_: Throwable) {
                ""
            }
            val delay = try {
                s.javaClass.getMethod("getSearchDelayMs").invoke(s) as? Long ?: 0L
            } catch (_: Throwable) {
                0L
            }
            val validated = try {
                s.javaClass.getMethod("isSearchValidated").invoke(s) as? Boolean ?: false
            } catch (_: Throwable) {
                false
            }
            mapOf("url" to url, "ua" to ua, "delayMs" to delay, "validated" to validated)
        } catch (_: Throwable) {
            null
        }
    }

    /** 搜索验证过没有（源自己读 cf_clearance 之类的 Cookie 判断） */
    fun isSearchValidated(path: String, entryClass: String, index: Int): Boolean {
        val s = sourceInstance(path, entryClass, index)
        return try {
            s.javaClass.getMethod("isSearchValidated").invoke(s) as? Boolean ?: false
        } catch (_: Throwable) {
            false
        }
    }

    /** 这个源能不能缓存（isCacheable）：默认 true，源明确返回 false 才不缓存 */
    fun isCacheable(path: String, entryClass: String, index: Int): Boolean {
        val s = sourceInstance(path, entryClass, index)
        return try {
            s.javaClass.getMethod("isCacheable").invoke(s) as? Boolean ?: true
        } catch (_: Throwable) {
            true
        }
    }

    // ------------------------------------------------------------ 线路 / 音色 / 配置

    /**
     * 把当前线路/音色推给源（播放前调）。
     * 先试源的线路方法 setLineId / setCurrentLine / setLine；
     * 再把 "<源id>.lineId" 写进 ExternalSourcePrefs，供源自己读；
     * 最后试 setConfig / applyConfig（传 {"lineId":..,"voiceId":..} 的 JSON）。
     * 三种方式都没有时如实记一笔日志，不静默丢掉。
     */
    fun pushLine(source: Any, sourceId: String, lineId: String?, voiceId: String?) {
        if (lineId.isNullOrEmpty() && voiceId.isNullOrEmpty()) return
        var pushed = false
        if (!lineId.isNullOrEmpty()) {
            for (name in listOf("setLineId", "setCurrentLine", "setLine")) {
                try {
                    source.javaClass.getMethod(name, String::class.java)
                        .invoke(source, lineId)
                    pushed = true
                    break
                } catch (_: Throwable) {
                }
            }
            try {
                prefs()?.edit()?.putString("$sourceId.lineId", lineId)?.apply()
            } catch (_: Throwable) {
            }
        }
        if (!pushed) {
            val cfg = JSONObject()
            if (!lineId.isNullOrEmpty()) cfg.put("lineId", lineId)
            if (!voiceId.isNullOrEmpty()) cfg.put("voiceId", voiceId)
            for (name in listOf("setConfig", "applyConfig")) {
                try {
                    source.javaClass.getMethod(name, String::class.java)
                        .invoke(source, cfg.toString())
                    pushed = true
                    break
                } catch (_: Throwable) {
                }
            }
        }
        if (!pushed) {
            Log.i("TingShuRuntime", "源 $sourceId 没有线路接口，lineId=$lineId 未推给源")
        }
    }

    /** 探源的线路/音色方法：lines()/lineList()/getLines()/videoLines() 等。 */
    private fun probeList(
        source: Any,
        names: List<String>,
        url: String?
    ): List<Map<String, String>> {
        for (name in names) {
            val result = try {
                val m = source.javaClass.methods.firstOrNull {
                    it.name == name && (it.parameterCount == 0 ||
                        (it.parameterCount == 1 && it.parameterTypes[0] == String::class.java))
                } ?: continue
                if (m.parameterCount == 0) m.invoke(source) else m.invoke(source, url ?: "")
            } catch (_: Throwable) {
                continue
            } ?: continue
            val items = when (result) {
                is List<*> -> result.filterNotNull()
                is Array<*> -> result.filterNotNull()
                else -> continue
            }
            val out = ArrayList<Map<String, String>>()
            for (e in items) {
                out.add(normalizeLineItem(e))
            }
            if (out.isNotEmpty()) return out
            // 方法存在但返回空列表：这是源的真实答案（没有线路/音色），
            // 别再试下一个别名，直接返回空。
            return emptyList()
        }
        return emptyList()
    }

    /** 线路/音色条目归一化：String / Map / Pair / 有 getId/getName 的对象。 */
    private fun normalizeLineItem(e: Any): Map<String, String> {
        when (e) {
            is String -> return mapOf("id" to e, "name" to e)
            is Map<*, *> -> {
                val id = (e["id"] ?: e["key"] ?: e["value"] ?: "").toString()
                val name = (e["name"] ?: e["label"] ?: e["title"] ?: id).toString()
                return mapOf("id" to id, "name" to name)
            }
            is Pair<*, *> -> {
                val id = e.first?.toString() ?: ""
                val name = e.second?.toString() ?: id
                return mapOf("id" to id, "name" to name)
            }
        }
        val id = try {
            e.javaClass.getMethod("getId").invoke(e)?.toString() ?: ""
        } catch (_: Throwable) {
            ""
        }
        val name = try {
            e.javaClass.getMethod("getName").invoke(e)?.toString() ?: ""
        } catch (_: Throwable) {
            ""
        }
        val text = if (name.isNotEmpty()) name else e.toString()
        return mapOf("id" to if (id.isNotEmpty()) id else text, "name" to text)
    }

    /** 源声明的配置项（ConfigurableSource），或 getConfig() 返回的 Map/List。 */
    private fun probeConfig(source: Any): JSONObject {
        try {
            val m = source.javaClass.getMethod("getCustomConfigItems")
            @Suppress("UNCHECKED_CAST")
            val items = m.invoke(source) as? List<*> ?: emptyList<Any>()
            val arr = JSONArray()
            for (item in items) {
                if (item == null) continue
                fun str(name: String): String = try {
                    item.javaClass.getMethod(name).invoke(item)?.toString() ?: ""
                } catch (_: Throwable) {
                    ""
                }
                val options = try {
                    val raw = item.javaClass.getMethod("getOptions").invoke(item)
                    val o = JSONArray()
                    if (raw is List<*>) {
                        for (v in raw) if (v != null) o.put(v.toString())
                    }
                    o
                } catch (_: Throwable) {
                    JSONArray()
                }
                arr.put(
                    JSONObject()
                        .put("type", str("getType"))
                        .put("key", str("getKey"))
                        .put("title", str("getTitle"))
                        .put("defaultValue", str("getDefaultValue"))
                        .put("options", options)
                        .put("hint", str("getHint"))
                )
            }
            return JSONObject().put("fields", arr)
        } catch (_: Throwable) {
        }
        try {
            val m = source.javaClass.getMethod("getConfig")
            val raw = m.invoke(source)
            return when (raw) {
                is Map<*, *> -> JSONObject(raw as Map<*, *>)
                is List<*> -> JSONObject().put("fields", JSONArray(raw))
                is String -> try {
                    JSONObject(raw)
                } catch (_: Throwable) {
                    JSONObject().put("fields", JSONArray())
                }
                else -> JSONObject().put("fields", JSONArray())
            }
        } catch (_: Throwable) {
        }
        return JSONObject().put("fields", JSONArray())
    }

    // ------------------------------------------------------------ 调用

    fun call(
        path: String,
        entryClass: String,
        index: Int,
        method: String,
        params: Map<String, Any?>
    ): String {
        val s = sourceInstance(path, entryClass, index)
        return when (method) {
            "search" -> {
                val kw = params["keyword"] as? String ?: ""
                val page = (params["page"] as? Number)?.toInt() ?: 1
                val m = s.javaClass.getMethod(
                    "search", String::class.java, Int::class.javaPrimitiveType
                )
                @Suppress("UNCHECKED_CAST")
                val pair = m.invoke(s, kw, page) as Pair<List<Any>, Int>
                JSONObject()
                    .put("books", booksJson(pair.first))
                    .put("totalPage", pair.second)
                    .toString()
            }
            "categories" -> {
                val m = s.javaClass.getMethod("getCategoryMenus")
                val menus = m.invoke(s) as? List<*> ?: emptyList<Any>()
                val arr = JSONArray()
                for (menu in menus) {
                    if (menu == null) continue
                    val title = runCatching {
                        menu.javaClass.getMethod("getTitle").invoke(menu) as String
                    }.getOrNull() ?: ""
                    val tabs = runCatching {
                        menu.javaClass.getMethod("getTabs").invoke(menu) as List<*>
                    }.getOrNull() ?: emptyList<Any>()
                    val tabArr = JSONArray()
                    for (t in tabs) {
                        if (t == null) continue
                        tabArr.put(
                            JSONObject()
                                .put(
                                    "title",
                                    runCatching {
                                        t.javaClass.getMethod("getTitle").invoke(t) as String
                                    }.getOrNull() ?: ""
                                )
                                .put(
                                    "url",
                                    runCatching {
                                        t.javaClass.getMethod("getUrl").invoke(t) as String
                                    }.getOrNull() ?: ""
                                )
                        )
                    }
                    arr.put(JSONObject().put("title", title).put("tabs", tabArr))
                }
                JSONObject().put("menus", arr).toString()
            }
            "browse" -> {
                val url = params["category"] as? String ?: params["url"] as? String ?: ""
                val m = s.javaClass.getMethod("getCategoryList", String::class.java)
                val c = m.invoke(s, url)
                val books = runCatching {
                    c.javaClass.getMethod("getList").invoke(c) as List<*>
                }.getOrNull() ?: emptyList<Any>()
                JSONObject()
                    .put("books", booksJson(books))
                    .put(
                        "nextUrl",
                        runCatching {
                            c.javaClass.getMethod("getNextUrl").invoke(c) as String
                        }.getOrNull() ?: ""
                    )
                    .put(
                        "totalPage",
                        runCatching {
                            c.javaClass.getMethod("getTotalPage").invoke(c) as Int
                        }.getOrNull() ?: 0
                    )
                    .toString()
            }
            "detail" -> {
                val url = params["url"] as? String ?: params["bookUrl"] as? String ?: ""
                val m = s.javaClass.getMethod(
                    "getBookDetailInfo",
                    String::class.java,
                    Boolean::class.javaPrimitiveType,
                    Boolean::class.javaPrimitiveType
                )
                val d = m.invoke(s, url, true, true)
                val playList = runCatching {
                    d.javaClass.getMethod("getPlayList").invoke(d) as List<*>
                }.getOrNull() ?: emptyList<Any>()
                val chapters = JSONArray()
                for (ep in playList) {
                    if (ep == null) continue
                    chapters.put(
                        JSONObject()
                            .put(
                                "title",
                                runCatching {
                                    ep.javaClass.getMethod("getTitle").invoke(ep) as String
                                }.getOrNull() ?: ""
                            )
                            .put(
                                "url",
                                runCatching {
                                    ep.javaClass.getMethod("getUrl").invoke(ep) as String
                                }.getOrNull() ?: ""
                            )
                    )
                }
                JSONObject()
                    .put("chapters", chapters)
                    .put(
                        "intro",
                        runCatching {
                            d.javaClass.getMethod("getIntro").invoke(d) as String
                        }.getOrNull() ?: ""
                    )
                    .put(
                        "artist",
                        runCatching {
                            d.javaClass.getMethod("getArtist").invoke(d) as String
                        }.getOrNull() ?: ""
                    )
                    .put(
                        "author",
                        runCatching {
                            d.javaClass.getMethod("getAuthor").invoke(d) as String
                        }.getOrNull() ?: ""
                    )
                    .put(
                        "cover",
                        runCatching {
                            d.javaClass.getMethod("getCoverUrl").invoke(d) as String
                        }.getOrNull() ?: ""
                    )
                    .toString()
            }
            "audio" -> {
                val url = params["url"] as? String ?: params["chapterUrl"] as? String ?: ""
                // 先把线路/音色推给源，再解析地址（以前只传 URL 是断层）。
                val sourceId = try {
                    s.javaClass.getMethod("getSourceId").invoke(s) as? String ?: ""
                } catch (_: Throwable) {
                    ""
                }
                pushLine(
                    s,
                    sourceId,
                    params["lineId"] as? String,
                    params["voiceId"] as? String
                )
                val em = s.javaClass.getMethod("getAudioUrlExtractor")
                val extractor = em.invoke(s)
                    ?: throw RuntimeException("源没有返回 AudioUrlExtractor")
                val xm = extractor.javaClass.getMethod(
                    "extract",
                    String::class.java,
                    Boolean::class.javaPrimitiveType,
                    Boolean::class.javaPrimitiveType
                )
                deliver(null)
                xm.invoke(extractor, url, false, false)
                val audio = takeDelivered()
                    ?: throw RuntimeException("未能解析出音频地址")
                val out = JSONObject().put("url", audio)
                // 有的源要带请求头播（Referer/UA），一起回给播放器
                try {
                    val hm = s.javaClass.getMethod("headers", String::class.java)
                    @Suppress("UNCHECKED_CAST")
                    val headers = hm.invoke(s, audio) as? Map<String, String>
                    if (!headers.isNullOrEmpty()) {
                        out.put("headers", JSONObject(headers as Map<*, *>))
                    }
                } catch (_: Throwable) {
                }
                out.toString()
            }
            "lines" -> {
                val url = params["url"] as? String ?: ""
                val items = probeList(
                    s,
                    listOf("lines", "lineList", "getLines", "videoLines"),
                    url
                )
                val arr = JSONArray()
                for (item in items) {
                    arr.put(JSONObject(item as Map<*, *>))
                }
                JSONObject().put("lines", arr).toString()
            }
            "voices" -> {
                val url = params["url"] as? String ?: ""
                val items = probeList(
                    s,
                    listOf("voices", "voiceList", "getVoices", "tones"),
                    url
                )
                val arr = JSONArray()
                for (item in items) {
                    arr.put(JSONObject(item as Map<*, *>))
                }
                JSONObject().put("voices", arr).toString()
            }
            "config" -> probeConfig(s).toString()
            else -> throw RuntimeException("不支持的调用：$method")
        }
    }

    private fun booksJson(books: List<*>): JSONArray {
        val arr = JSONArray()
        for (b in books) {
            if (b == null) continue
            fun str(name: String): String = runCatching {
                b.javaClass.getMethod(name).invoke(b) as? String ?: ""
            }.getOrDefault("")
            arr.put(
                JSONObject()
                    .put("url", str("getBookUrl"))
                    .put("title", str("getTitle"))
                    .put("author", str("getAuthor"))
                    .put("artist", str("getArtist"))
                    .put("cover", str("getCoverUrl"))
                    .put("intro", str("getIntro"))
            )
        }
        return arr
    }
}
