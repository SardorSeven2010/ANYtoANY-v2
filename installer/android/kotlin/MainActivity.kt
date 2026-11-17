package com.anytoany.converter.any_to_any

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.media.AudioManager
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

/** Flutter oynasi + "core/native" kanali: bildirishnoma, fon xizmati, PiP, yorliq, eslatma */
class MainActivity : FlutterActivity() {
    private var pipArmed = false
    private var pipRatio = 16.0 / 9.0
    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "core/native")
        CoreBridge.channel = channel
        channel.setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error("native", e.message, null)
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        CoreBridge.channel = null
        WebViewKeeper.stop()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT < 33 ||
                    checkSelfPermission("android.permission.POST_NOTIFICATIONS") == PackageManager.PERMISSION_GRANTED
                ) {
                    result.success(true)
                } else {
                    pendingPermission?.success(false)
                    pendingPermission = result
                    requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 7001)
                }
            }
            "notificationsEnabled" -> {
                val nm = getSystemService(NotificationManager::class.java)
                result.success(nm?.areNotificationsEnabled() ?: false)
            }
            "notify" -> {
                val nm = getSystemService(NotificationManager::class.java)
                val channel = call.argument<String>("channel") ?: CoreNotifications.CH_DOWNLOADS
                nm?.notify(
                    call.argument<Int>("id") ?: 1,
                    CoreNotifications.simple(
                        this, channel, call.argument<String>("title") ?: "CORE", call.argument<String>("body") ?: ""
                    )
                )
                result.success(true)
            }
            "scheduleReminder" -> {
                val id = call.argument<Int>("id") ?: 1
                val at = (call.argument<Number>("at") ?: 0).toLong()
                val am = getSystemService(AlarmManager::class.java)
                val intent = Intent(this, CoreReceiver::class.java)
                    .setAction(CoreNotifications.ACTION_REMIND)
                    .putExtra("id", id)
                    .putExtra("title", call.argument<String>("title"))
                    .putExtra("body", call.argument<String>("body"))
                val pi = PendingIntent.getBroadcast(
                    this, id, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                // Aniq vaqt ruxsatini talab qilmaydigan, tejamkor signal
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                result.success(true)
            }
            "cancelReminder" -> {
                val id = call.argument<Int>("id") ?: 1
                val am = getSystemService(AlarmManager::class.java)
                val intent = Intent(this, CoreReceiver::class.java).setAction(CoreNotifications.ACTION_REMIND)
                val pi = PendingIntent.getBroadcast(
                    this, id, intent, PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                )
                if (pi != null) {
                    am.cancel(pi)
                    pi.cancel()
                }
                result.success(true)
            }
            "startForeground", "updateForeground" -> result.success(foreground(call))
            "stopForeground" -> {
                stopService(Intent(this, CoreService::class.java))
                result.success(true)
            }
            "setPipArmed" -> {
                pipArmed = call.argument<Boolean>("armed") ?: false
                pipRatio = ratioOf(call)
                result.success(true)
            }
            "enterPip" -> {
                pipRatio = ratioOf(call)
                result.success(enterPip())
            }
            "pinShortcut" -> result.success(pinShortcut(call.argument<String>("label") ?: "CORE"))
            "saveToGallery" -> {
                val path = call.argument<String>("path") ?: ""
                val kind = call.argument<String>("kind") ?: "video"
                val name = call.argument<String>("name")
                // katta fayl nusxalanadi: asosiy oqimni band qilmaslik uchun alohida oqimda
                Thread {
                    val saved = try {
                        GallerySaver.save(applicationContext, path, kind, name)
                    } catch (e: Exception) {
                        null
                    }
                    runOnUiThread { result.success(saved) }
                }.start()
            }
            "getVolume" -> {
                val am = getSystemService(AudioManager::class.java)
                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                result.success(if (max > 0) am.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max else 0.0)
            }
            "ocrImage" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("ocr", "Rasm yo'li berilmadi", null)
                } else {
                    OcrRecognizer.recognize(path) { words, error ->
                        if (words != null) result.success(words) else result.error("ocr", error, null)
                    }
                }
            }
            "webviewKeepAlive" -> {
                if (call.argument<Boolean>("on") != true) {
                    WebViewKeeper.stop()
                    result.success(true)
                } else {
                    val id = (call.argument<Number>("id") ?: 0).toLong()
                    val engine = flutterEngine
                    val view = if (engine != null) WebViewFlutterAndroidExternalApi.getWebView(engine, id) else null
                    if (view != null) {
                        WebViewKeeper.start(view)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
            }
            "setVolume" -> {
                val am = getSystemService(AudioManager::class.java)
                val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                val v = (call.argument<Number>("value") ?: 0).toDouble().coerceIn(0.0, 1.0)
                am.setStreamVolume(AudioManager.STREAM_MUSIC, Math.round(v * max).toInt(), 0)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun ratioOf(call: MethodCall): Double {
        val w = (call.argument<Number>("width") ?: 16).toDouble()
        val h = (call.argument<Number>("height") ?: 9).toDouble()
        return if (w > 0 && h > 0) w / h else 16.0 / 9.0
    }

    /** Fon xizmatini ishga tushiradi yoki xabarini yangilaydi. Ishlamasa false qaytaradi. */
    private fun foreground(call: MethodCall): Boolean {
        val kind = call.argument<String>("kind") ?: "download"
        val title = call.argument<String>("title") ?: "CORE"
        val text = call.argument<String>("text") ?: ""
        val progress = call.argument<Int>("progress") ?: -1
        val playing = call.argument<Boolean>("playing") ?: false
        if (CoreService.running && CoreService.kind == kind) {
            val nm = getSystemService(NotificationManager::class.java)
            nm?.notify(
                CoreNotifications.FOREGROUND_ID,
                CoreNotifications.foreground(this, kind, title, text, progress, playing)
            )
            return true
        }
        val intent = Intent(this, CoreService::class.java)
            .putExtra("kind", kind).putExtra("title", title).putExtra("text", text)
            .putExtra("progress", progress).putExtra("playing", playing)
        return try {
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun pipParams(): PictureInPictureParams {
        // Android faqat 0.418 .. 2.39 oralig'idagi nisbatni qabul qiladi
        val r = pipRatio.coerceIn(0.5, 2.3)
        return PictureInPictureParams.Builder().setAspectRatio(Rational((r * 1000).toInt(), 1000)).build()
    }

    private fun enterPip(): Boolean {
        if (Build.VERSION.SDK_INT < 26) return false
        return try {
            enterPictureInPictureMode(pipParams())
        } catch (e: Exception) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipArmed) enterPip()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        CoreBridge.send("pipChanged", isInPictureInPictureMode)
    }

    /** PRO: asosiy ekranga o'zgartirilgan nomli yorliq qo'shish */
    private fun pinShortcut(label: String): Boolean {
        if (Build.VERSION.SDK_INT < 26) return false
        val sm = getSystemService(ShortcutManager::class.java) ?: return false
        if (!sm.isRequestPinShortcutSupported) return false
        val launch = Intent(this, MainActivity::class.java)
            .setAction(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_LAUNCHER)
        val info = ShortcutInfo.Builder(this, "core_custom_" + System.currentTimeMillis())
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
            .setIntent(launch)
            .build()
        return sm.requestPinShortcut(info, null)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 7001) {
            pendingPermission?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }
}
