package com.github.eprendre.tingshu.utils

import com.localreader.local_media_app.TingShuRuntime

/** 插件自定义配置读写：落盘到 App 自己的 SharedPreferences。 */
object ExternalSourcePrefs {
    fun putString(key: String, value: String?) {
        val p = TingShuRuntime.prefs() ?: return
        p.edit().putString(key, value).apply()
    }

    fun getString(key: String, defValue: String?): String? {
        val p = TingShuRuntime.prefs() ?: return defValue
        return p.getString(key, defValue)
    }
}
