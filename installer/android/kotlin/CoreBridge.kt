package com.anytoany.converter.any_to_any

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** Xizmat va qabul qilgich (Flutter'dan tashqari qismlar) Dart bilan shu orqali gaplashadi. */
object CoreBridge {
    @Volatile
    var channel: MethodChannel? = null

    private val main = Handler(Looper.getMainLooper())

    fun send(method: String, argument: Any?) {
        main.post { channel?.invokeMethod(method, argument) }
    }
}
