package com.github.eprendre.tingshu.extensions

import com.localreader.local_media_app.TingShuRuntime

/** 宿主 UA：JAR 插件里 getMobileUA() 直接走我们存的手机 UA。 */
fun getMobileUA(): String = TingShuRuntime.mobileUA

fun getDesktopUA(): String = TingShuRuntime.desktopUA
