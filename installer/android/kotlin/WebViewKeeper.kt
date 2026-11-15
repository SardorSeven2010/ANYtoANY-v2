package com.anytoany.converter.any_to_any

import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View
import android.webkit.WebView
import java.lang.ref.WeakReference

/**
 * Mini-brauzerdagi WebView ekran o'chganda "yashirin" holatga o'tib, video ovozini to'xtatib qo'ymasligi uchun:
 *  - render jarayoni muhim deb belgilanadi (ko'rinmaganda ham past ustuvorlikka tushmaydi)
 *  - WebView davriy ravishda "ko'rinadi / davom etmoqda" holatiga qaytariladi
 * Faqat sahifada video o'ynayotganda ishlaydi; Dart tomoni to'xtatganda yoki ekran yopilganda o'chadi.
 */
object WebViewKeeper {
    private val handler = Handler(Looper.getMainLooper())
    private var ref: WeakReference<WebView>? = null
    private var active = false

    private val tick = object : Runnable {
        override fun run() {
            val view = ref?.get()
            if (!active || view == null) {
                active = false
                return
            }
            keepAlive(view)
            handler.postDelayed(this, 1500)
        }
    }

    fun start(view: WebView) {
        ref = WeakReference(view)
        if (Build.VERSION.SDK_INT >= 26) {
            try {
                view.setRendererPriorityPolicy(WebView.RENDERER_PRIORITY_IMPORTANT, false)
            } catch (e: Exception) {
            }
        }
        if (!active) {
            active = true
            handler.post(tick)
        }
    }

    fun stop() {
        active = false
        handler.removeCallbacks(tick)
        ref = null
    }

    private fun keepAlive(view: WebView) {
        try {
            view.onResume()
            view.resumeTimers()
            view.dispatchWindowVisibilityChanged(View.VISIBLE)
        } catch (e: Exception) {
        }
    }
}
