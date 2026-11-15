package com.anytoany.converter.any_to_any

import android.content.Context
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager

/**
 * Fonda ijro uchun: MediaSession (bildirishnoma, qulflangan ekran va quloqchin tugmalari) hamda
 * ekran o'chganda protsessor va Wi-Fi uxlab qolmasligi uchun qulflar.
 */
object CoreMedia {
    private var session: MediaSession? = null
    private var wake: PowerManager.WakeLock? = null
    private var wifi: WifiManager.WifiLock? = null

    val token: MediaSession.Token?
        get() = session?.sessionToken

    @Synchronized
    fun ensureSession(ctx: Context): MediaSession {
        session?.let { return it }
        val s = MediaSession(ctx.applicationContext, "CORE")
        @Suppress("DEPRECATION")
        s.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
        s.setCallback(object : MediaSession.Callback() {
            override fun onPlay() = CoreBridge.send("mediaAction", "play")
            override fun onPause() = CoreBridge.send("mediaAction", "pause")
            override fun onSkipToNext() = CoreBridge.send("mediaAction", "next")
            override fun onSkipToPrevious() = CoreBridge.send("mediaAction", "previous")
            override fun onStop() = CoreBridge.send("mediaAction", "stop")
        })
        session = s
        return s
    }

    /** Bildirishnoma va qulflangan ekrandagi ma'lumotni yangilaydi */
    @Synchronized
    fun update(ctx: Context, title: String, text: String, playing: Boolean) {
        val s = ensureSession(ctx)
        s.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, text)
                .build()
        )
        val actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE or
            PlaybackState.ACTION_SKIP_TO_NEXT or PlaybackState.ACTION_SKIP_TO_PREVIOUS or PlaybackState.ACTION_STOP
        s.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(
                    if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                    PlaybackState.PLAYBACK_POSITION_UNKNOWN,
                    if (playing) 1f else 0f
                )
                .build()
        )
        if (!s.isActive) s.isActive = true
    }

    /** Ekran o'chganda ham protsessor va Wi-Fi ishlab turishi uchun */
    @Synchronized
    fun acquireLocks(ctx: Context) {
        try {
            if (wake == null) {
                val pm = ctx.applicationContext.getSystemService(Context.POWER_SERVICE) as PowerManager
                wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "core:media").apply { setReferenceCounted(false) }
            }
            if (wake?.isHeld == false) wake?.acquire(6 * 60 * 60 * 1000L)
        } catch (_: Exception) {
        }
        try {
            if (wifi == null) {
                val wm = ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val mode = if (Build.VERSION.SDK_INT >= 29) WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                else @Suppress("DEPRECATION") WifiManager.WIFI_MODE_FULL_HIGH_PERF
                wifi = wm.createWifiLock(mode, "core:media").apply { setReferenceCounted(false) }
            }
            if (wifi?.isHeld == false) wifi?.acquire()
        } catch (_: Exception) {
        }
    }

    @Synchronized
    fun release() {
        try {
            if (wake?.isHeld == true) wake?.release()
        } catch (_: Exception) {
        }
        try {
            if (wifi?.isHeld == true) wifi?.release()
        } catch (_: Exception) {
        }
        session?.let {
            try {
                it.isActive = false
                it.release()
            } catch (_: Exception) {
            }
        }
        session = null
    }
}
