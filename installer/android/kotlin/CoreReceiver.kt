package com.anytoany.converter.any_to_any

import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Eslatma signallari va bildirishnomadagi tugmalar (pleyer, yuklashni to'xtatish) */
class CoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        when {
            action == CoreNotifications.ACTION_REMIND -> {
                val nm = context.getSystemService(NotificationManager::class.java) ?: return
                val id = intent.getIntExtra("id", 1)
                nm.notify(
                    id,
                    CoreNotifications.simple(
                        context,
                        CoreNotifications.CH_REMIND,
                        intent.getStringExtra("title") ?: "CORE",
                        intent.getStringExtra("body") ?: ""
                    )
                )
            }
            action.startsWith(CoreNotifications.ACTION_MEDIA_PREFIX) ->
                CoreBridge.send("mediaAction", action.removePrefix(CoreNotifications.ACTION_MEDIA_PREFIX))
            action == CoreNotifications.ACTION_STOP_DOWNLOADS ->
                CoreBridge.send("downloadsStop", null)
        }
    }
}
