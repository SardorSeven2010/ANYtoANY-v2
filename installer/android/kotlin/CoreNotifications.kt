package com.anytoany.converter.any_to_any

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build

/** Bildirishnomalar: faqat Android'ning o'z sinflari (qo'shimcha kutubxonasiz). */
object CoreNotifications {
    const val CH_DOWNLOADS = "core_downloads"
    const val CH_MEDIA = "core_media"
    const val CH_REMIND = "core_reminders"

    const val FOREGROUND_ID = 4101

    const val ACTION_REMIND = "com.anytoany.converter.REMIND"
    const val ACTION_STOP_DOWNLOADS = "com.anytoany.converter.STOP_DOWNLOADS"
    const val ACTION_MEDIA_PREFIX = "com.anytoany.converter.MEDIA_"

    fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(
            NotificationChannel(CH_DOWNLOADS, "Yuklashlar", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Video yuklash jarayoni va natijasi"
                setShowBadge(false)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_MEDIA, "Pleyer", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Fonda ijro etilayotgan musiqa va video"
                setShowBadge(false)
            }
        )
        nm.createNotificationChannel(
            NotificationChannel(CH_REMIND, "Eslatmalar", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Bepul sinov va obuna muddati haqida"
            }
        )
    }

    @Suppress("DEPRECATION")
    private fun builder(ctx: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, channel) else Notification.Builder(ctx)

    /** Bildirishnomani bosganda ilova ochiladi */
    fun openApp(ctx: Context): PendingIntent {
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: Intent()
        launch.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        return PendingIntent.getActivity(
            ctx, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun broadcast(ctx: Context, action: String, code: Int): PendingIntent {
        val intent = Intent(ctx, CoreReceiver::class.java).setAction(action)
        return PendingIntent.getBroadcast(
            ctx, code, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun action(ctx: Context, icon: Int, label: String, pi: PendingIntent): Notification.Action =
        Notification.Action.Builder(Icon.createWithResource(ctx, icon), label, pi).build()

    /** Oddiy xabar (yuklash tugadi, eslatma) */
    fun simple(ctx: Context, channel: String, title: String, body: String): Notification {
        ensureChannels(ctx)
        return builder(ctx, channel)
            .setSmallIcon(R.drawable.ic_stat_core)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(openApp(ctx))
            .setAutoCancel(true)
            .build()
    }

    /**
     * Fon xizmatining doimiy xabari.
     * kind = "media": pleyer boshqaruvi; boshqa holda: yuklash jarayoni (progress < 0 bo'lsa noaniq).
     */
    fun foreground(
        ctx: Context, kind: String, title: String, text: String, progress: Int, playing: Boolean
    ): Notification {
        ensureChannels(ctx)
        val media = kind == "media"
        val b = builder(ctx, if (media) CH_MEDIA else CH_DOWNLOADS)
            .setSmallIcon(R.drawable.ic_stat_core)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openApp(ctx))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
        if (media) {
            b.addAction(action(ctx, android.R.drawable.ic_media_previous, "Oldingi", broadcast(ctx, ACTION_MEDIA_PREFIX + "previous", 11)))
            b.addAction(
                if (playing) action(ctx, android.R.drawable.ic_media_pause, "Pauza", broadcast(ctx, ACTION_MEDIA_PREFIX + "playpause", 12))
                else action(ctx, android.R.drawable.ic_media_play, "Ijro", broadcast(ctx, ACTION_MEDIA_PREFIX + "playpause", 12))
            )
            b.addAction(action(ctx, android.R.drawable.ic_media_next, "Keyingi", broadcast(ctx, ACTION_MEDIA_PREFIX + "next", 13)))
            b.setStyle(Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2))
        } else {
            if (progress in 0..100) b.setProgress(100, progress, false) else b.setProgress(0, 0, true)
            b.addAction(action(ctx, android.R.drawable.ic_menu_close_clear_cancel, "To'xtatish", broadcast(ctx, ACTION_STOP_DOWNLOADS, 14)))
        }
        return b.build()
    }
}
