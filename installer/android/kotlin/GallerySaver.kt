package com.anytoany.converter.any_to_any

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

/**
 * Faylni galereyaga (MediaStore) qo'shadi: video -> Movies/CORE, audio -> Music/CORE, rasm -> Pictures/CORE.
 * Android 10+ da ruxsat so'ralmaydi; eski Android'da yozish ruxsati kerak.
 * Qaytaradi: galereyadagi fayl yo'li (aniqlab bo'lmasa content manzili) yoki null.
 */
object GallerySaver {
    private fun mimeFor(name: String, kind: String): String {
        val ext = name.substringAfterLast('.', "").lowercase()
        return when (kind) {
            "audio" -> when (ext) {
                "mp3" -> "audio/mpeg"
                "m4a", "aac" -> "audio/mp4"
                "flac" -> "audio/flac"
                "ogg", "opus" -> "audio/ogg"
                "wav" -> "audio/x-wav"
                else -> "audio/*"
            }
            "image" -> when (ext) {
                "png" -> "image/png"
                "gif" -> "image/gif"
                "webp" -> "image/webp"
                else -> "image/jpeg"
            }
            else -> when (ext) {
                "webm" -> "video/webm"
                "mkv" -> "video/x-matroska"
                "mov" -> "video/quicktime"
                "avi" -> "video/x-msvideo"
                else -> "video/mp4"
            }
        }
    }

    fun save(ctx: Context, path: String, kind: String, displayName: String?): String? {
        val src = File(path)
        if (!src.exists()) return null
        val name = displayName?.takeIf { it.isNotBlank() } ?: src.name
        val mime = mimeFor(name, kind)
        val folder = when (kind) {
            "audio" -> Environment.DIRECTORY_MUSIC
            "image" -> Environment.DIRECTORY_PICTURES
            else -> Environment.DIRECTORY_MOVIES
        }
        if (Build.VERSION.SDK_INT >= 29) {
            val collection = when (kind) {
                "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                else -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "$folder/CORE")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = ctx.contentResolver
            val uri = resolver.insert(collection, values) ?: return null
            try {
                resolver.openOutputStream(uri)?.use { out ->
                    src.inputStream().use { it.copyTo(out, 1 shl 16) }
                } ?: throw IllegalStateException("yozib bo'lmadi")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                try {
                    resolver.delete(uri, null, null)
                } catch (_: Exception) {
                }
                throw e
            }
            // Ilova ichida ijro etish uchun haqiqiy yo'l (o'z faylimiz bo'lgani uchun o'qiladi)
            return try {
                resolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)?.use { c ->
                    if (c.moveToFirst()) c.getString(0) else null
                } ?: uri.toString()
            } catch (_: Exception) {
                uri.toString()
            }
        }
        // Android 9 va undan eski: umumiy papkaga nusxalab, galereyani yangilaymiz
        @Suppress("DEPRECATION")
        val dir = File(Environment.getExternalStoragePublicDirectory(folder), "CORE")
        if (!dir.exists() && !dir.mkdirs()) return null
        var dest = File(dir, name)
        var n = 1
        while (dest.exists()) {
            dest = File(dir, name.substringBeforeLast('.') + "_$n." + name.substringAfterLast('.', ""))
            n++
        }
        src.copyTo(dest)
        MediaScannerConnection.scanFile(ctx, arrayOf(dest.absolutePath), arrayOf(mime), null)
        return dest.absolutePath
    }
}
