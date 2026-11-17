package com.anytoany.converter.any_to_any

import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

/**
 * Rasmdagi matnni qurilmaning o'zida taniydi (Google ML Kit, internetsiz).
 * Skanerlangan PDF ni Word / Excel ga aylantirishda ishlatiladi: har bir so'z o'z joyi bilan qaytadi.
 */
object OcrRecognizer {
    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }

    /** Natija: har bir so'z uchun {text, left, top, right, bottom}. Xatoda ikkinchi qiymat matni bo'ladi. */
    fun recognize(path: String, done: (List<Map<String, Any>>?, String?) -> Unit) {
        val bitmap = BitmapFactory.decodeFile(path)
        if (bitmap == null) {
            done(null, "Rasmni o'qib bo'lmadi")
            return
        }
        recognizer.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { text ->
                val words = ArrayList<Map<String, Any>>()
                for (block in text.textBlocks) {
                    for (line in block.lines) {
                        for (element in line.elements) {
                            val box = element.boundingBox ?: continue
                            words.add(
                                mapOf(
                                    "text" to element.text,
                                    "left" to box.left,
                                    "top" to box.top,
                                    "right" to box.right,
                                    "bottom" to box.bottom,
                                )
                            )
                        }
                    }
                }
                bitmap.recycle()
                done(words, null)
            }
            .addOnFailureListener { e ->
                bitmap.recycle()
                done(null, e.message ?: "Matnni tanib bo'lmadi")
            }
    }
}
