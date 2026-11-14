package com.anytoany.converter.any_to_any

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Ilova fonda bo'lganda yuklash va musiqa to'xtab qolmasligi uchun xizmat.
 * Faqat foydalanuvchi yuklashni yoki ijroni boshlaganda ishga tushadi va ish tugagach o'chadi.
 */
class CoreService : Service() {
    companion object {
        @Volatile
        var running = false

        @Volatile
        var kind = ""
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val k = intent?.getStringExtra("kind") ?: "download"
        val notification = CoreNotifications.foreground(
            this,
            k,
            intent?.getStringExtra("title") ?: "CORE",
            intent?.getStringExtra("text") ?: "",
            intent?.getIntExtra("progress", -1) ?: -1,
            intent?.getBooleanExtra("playing", false) ?: false
        )
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                val type = if (k == "media") ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                else ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                startForeground(CoreNotifications.FOREGROUND_ID, notification, type)
            } else {
                startForeground(CoreNotifications.FOREGROUND_ID, notification)
            }
            running = true
            kind = k
        } catch (e: Exception) {
            running = false
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        kind = ""
        super.onDestroy()
    }
}
