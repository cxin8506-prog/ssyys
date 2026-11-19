package com.localreader.local_media_app

import android.app.PictureInPictureParams
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.WindowManager
import dalvik.system.DexClassLoader
import dalvik.system.DexFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Enumeration

class MainActivity : FlutterActivity() {

    private var dexLoader: DexClassLoader? = null
    private var loadedJar: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 全面屏：内容铺到状态栏/导航栏/刘海下面，由 Flutter 侧 SafeArea 避让。
        // 部分 ROM（MIUI/EMUI）会强制给透明系统栏加对比度遮罩，这里一起关掉。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val lp = window.attributes
            lp.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            window.attributes = lp
        }
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ---------- JAR 插件：DexClassLoader 反射调用 ----------
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "suishou/jar")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "load" -> {
                            val path = call.argument<String>("path") ?: ""
                            result.success(loadJar(path))
                        }
                        "listClasses" -> {
                            val path = call.argument<String>("path") ?: ""
                            result.success(listClasses(path))
                        }
                        "invoke" -> {
                            val path = call.argument<String>("path") ?: ""
                            val className = call.argument<String>("className") ?: ""
                            val method = call.argument<String>("method") ?: ""
                            val argsJson = call.argument<String>("argsJson") ?: "[]"
                            result.success(invokeJar(path, className, method, argsJson))
                        }
                        "hasMethod" -> {
                            val path = call.argument<String>("path") ?: ""
                            val className = call.argument<String>("className") ?: ""
                            val names = call.argument<List<String>>("names") ?: emptyList()
                            result.success(hasJarMethods(path, className, names))
                        }
                        "unload" -> {
                            dexLoader = null
                            loadedJar = null
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("JAR_ERROR", t.message ?: t.toString(), null)
                }
            }

        // ---------- 源登录：读写 WebView Cookie ----------
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "suishou/web")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "cookies" -> {
                            val url = call.argument<String>("url") ?: ""
                            if (url.isEmpty()) {
                                result.success("")
                            } else {
                                val cm = android.webkit.CookieManager.getInstance()
                                cm.setAcceptCookie(true)
                                result.success(cm.getCookie(url) ?: "")
                            }
                        }
                        "clearCookies" -> {
                            val cm = android.webkit.CookieManager.getInstance()
                            val url = call.argument<String>("url")
                            if (!url.isNullOrEmpty()) {
                                cm.setCookie(url, "")
                            }
                            cm.removeAllCookies(null)
                            cm.flush()
                            result.success(true)
                        }
                        "flush" -> {
                            android.webkit.CookieManager.getInstance().flush()
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (t: Throwable) {
                    result.error("WEB_ERROR", t.message ?: t.toString(), null)
                }
            }

        // ---------- 画中画 ----------
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "suishou/pip")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "available" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    "enter" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                            result.success(false)
                        } else {
                            val w = call.argument<Int>("width") ?: 16
                            val h = call.argument<Int>("height") ?: 9
                            try {
                                val params = PictureInPictureParams.Builder()
                                    .setAspectRatio(Rational(w, h))
                                    .build()
                                result.success(enterPictureInPictureMode(params))
                            } catch (t: Throwable) {
                                result.success(false)
                            }
                        }
                    }
                    "isIn" -> {
                        val inPip = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                            isInPictureInPictureMode
                        result.success(inPip)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ------------------------------------------------------------ JAR 支持

    private fun loadJar(path: String): Boolean {
        if (path.isEmpty()) throw IllegalArgumentException("path 为空")
        val jar = File(path)
        if (!jar.exists()) throw IllegalArgumentException("JAR 不存在: $path")
        if (loadedJar == path && dexLoader != null) return true

        val out = File(codeCacheDir, "plugin_dex")
        if (!out.exists()) out.mkdirs()
        val loader = DexClassLoader(path, out.absolutePath, null, classLoader)
        // 主动触发一次类扫描，dex 缺失会在这里暴露
        loader.loadClass("java.lang.Object")
        dexLoader = loader
        loadedJar = path
        return true
    }

    private fun listClasses(path: String): List<String> {
        val out = File(codeCacheDir, "plugin_dex")
        if (!out.exists()) out.mkdirs()
        val dex = DexFile.loadDex(path, File(out, "scan.dex").absolutePath, 0)
        val names = ArrayList<String>()
        val e: Enumeration<String> = dex.entries()
        while (e.hasMoreElements()) {
            val n = e.nextElement()
            if (!n.startsWith("android.") && !n.startsWith("java.") &&
                !n.startsWith("kotlin.") && !n.startsWith("dalvik.")
            ) {
                names.add(n)
            }
        }
        dex.close()
        names.sort()
        return names
    }

    /** 主类是否声明了这些方法中的任意一个（用于源能力判断） */
    private fun hasJarMethods(path: String, className: String, names: List<String>): Boolean {
        if (names.isEmpty()) return false
        if (dexLoader == null || loadedJar != path) loadJar(path)
        val loader = dexLoader ?: return false
        val cls = Class.forName(className, true, loader)
        return cls.methods.any { it.name in names }
    }

    /** 反射调用；优先静态方法，其次无参构造实例方法。参数按目标类型转换。 */
    private fun invokeJar(
        path: String,
        className: String,
        method: String,
        argsJson: String
    ): String {
        if (dexLoader == null || loadedJar != path) loadJar(path)
        val loader = dexLoader ?: throw IllegalStateException("类加载器未就绪")
        val cls = Class.forName(className, true, loader)
        val args = JSONArray(argsJson)

        var candidates = cls.methods.filter {
            it.name == method && it.parameterCount == args.length()
        }
        // 兼容无参方法：像 config() / getVoices() 这类我们拿不准签名，
        // 参数对不上时退一步按无参调。
        if (candidates.isEmpty() && args.length() > 0) {
            candidates = cls.methods.filter {
                it.name == method && it.parameterCount == 0
            }
        }
        if (candidates.isEmpty()) {
            throw NoSuchMethodException("$className.$method 不存在或参数个数不匹配")
        }

        var lastError: Throwable? = null
        for (m in candidates) {
            val converted = try {
                convertArgs(m.parameterTypes, args)
            } catch (t: Throwable) {
                lastError = t
                continue
            }
            // 静态优先
            val isStatic = java.lang.reflect.Modifier.isStatic(m.modifiers)
            try {
                val receiver = if (isStatic) null else newInstance(cls)
                val ret = m.invoke(receiver, *converted)
                return wrap(ret)
            } catch (t: Throwable) {
                lastError = t
            }
        }
        throw RuntimeException(lastError?.message ?: "调用失败")
    }

    private fun newInstance(cls: Class<*>): Any {
        val ctor = cls.getDeclaredConstructor()
        ctor.isAccessible = true
        return ctor.newInstance()
    }

    private fun convertArgs(types: Array<Class<*>>, args: JSONArray): Array<Any?> {
        return Array(types.size) { i ->
            val v = args.opt(i)
            val t = types[i]
            when {
                t == String::class.java -> if (v == null || v == JSONObject.NULL) null else v.toString()
                t == Int::class.javaPrimitiveType || t == Integer::class.java ->
                    if (v is Number) v.toInt() else v.toString().toInt()
                t == Long::class.javaPrimitiveType || t == Long::class.java ->
                    if (v is Number) v.toLong() else v.toString().toLong()
                t == Double::class.javaPrimitiveType || t == Double::class.java ->
                    if (v is Number) v.toDouble() else v.toString().toDouble()
                t == Boolean::class.javaPrimitiveType || t == Boolean::class.java ->
                    v is Boolean && v
                t == JSONObject::class.java -> JSONObject(v.toString())
                t == JSONArray::class.java -> JSONArray(v.toString())
                else -> v
            }
        }
    }

    private fun wrap(ret: Any?): String {
        val obj = JSONObject()
        obj.put("ok", true)
        when (ret) {
            null -> obj.put("data", JSONObject.NULL)
            is String -> obj.put("data", ret)
            is Number, is Boolean -> obj.put("data", ret)
            else -> obj.put("data", ret.toString())
        }
        return obj.toString()
    }
}
