package com.localreader.local_media_app

import android.content.Context
import android.content.SharedPreferences
import dalvik.system.DexClassLoader
import dalvik.system.DexFile
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.lang.reflect.Modifier
import java.net.HttpURLConnection
import java.net.URL
import java.util.zip.GZIPInputStream

/**
 * 「我的听书」格式 JAR 源的运行时：
 *   - 提供源需要的 UA / 网络抓取 / 音频嗅探
 *   - 反射加载 JAR 里的 SourceEntry，列出它包含的每个源
 *   - 把源的 search / 分类 / 详情 / 章节 / 音频地址转成统一 JSON
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

    private var appContext: Context? = null

    fun init(ctx: Context) {
        appContext = ctx.applicationContext
    }

    fun prefs(): SharedPreferences? =
        appContext?.getSharedPreferences("tingshu_ext", Context.MODE_PRIVATE)

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
            }
            val code = conn.responseCode
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

    // ------------------------------------------------------------ JAR / 源

    private class Loaded(val path: String, val loader: DexClassLoader)

    private var loaded: Loaded? = null
    private val instanceCache = HashMap<String, Any>()

    private fun loaderFor(path: String): DexClassLoader {
        val cached = loaded
        if (cached != null && cached.path == path) return cached.loader
        val ctx = appContext ?: throw IllegalStateException("TingShuRuntime 未初始化")
        val out = File(ctx.codeCacheDir, "plugin_dex")
        if (!out.exists()) out.mkdirs()
        val loader = DexClassLoader(path, out.absolutePath, null, javaClass.classLoader)
        loaded = Loaded(path, loader)
        instanceCache.clear()
        return loader
    }

    private fun listClassNames(path: String): List<String> {
        val ctx = appContext ?: return emptyList()
        val out = File(ctx.codeCacheDir, "plugin_dex")
        if (!out.exists()) out.mkdirs()
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

    /** 找 JAR 里的源入口类（含 getSources 的类） */
    @Synchronized
    fun findEntryClasses(path: String): List<String> {
        entryCache[path]?.let { return it }
        val found = scanEntryClasses(path)
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
            } catch (_: Throwable) {
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
        val raw = m.invoke(receiver) as? List<*> ?: emptyList<Any>()
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
                JSONObject().put("url", audio).toString()
            }
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
