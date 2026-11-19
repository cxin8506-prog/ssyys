package com.github.eprendre.tingshu.utils

import com.localreader.local_media_app.TingShuRuntime

/** 源用来存少量数据的工具类，落到 App 的 SharedPreferences 里。 */
object ExternalSourcePrefs {
    fun putString(key: String, value: String?) {
        TingShuRuntime.prefs()?.edit()?.putString(key, value)?.apply()
    }

    fun getString(key: String, defValue: String?): String? =
        TingShuRuntime.prefs()?.getString(key, defValue) ?: defValue
}
