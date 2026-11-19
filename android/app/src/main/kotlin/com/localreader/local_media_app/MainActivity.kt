package com.localreader.local_media_app

import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
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

        val candidates = cls.methods.filter {
            it.name == method && it.parameterCount == args.length()
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
