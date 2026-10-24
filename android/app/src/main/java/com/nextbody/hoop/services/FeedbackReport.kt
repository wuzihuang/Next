package com.nextbody.hoop.services

import android.graphics.Bitmap
import android.os.Build
import android.util.Base64
import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.l10n.AppLanguage
import java.io.ByteArrayOutputStream
import java.util.TimeZone
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Profile › REPORT A PROBLEM. One POST to the `feedback` Edge Function, which files a GitHub
 * issue. The phone never sees the GitHub token.
 */
object FeedbackReport {
    const val maxImages = 3

    data class Filed(val number: Int, val url: String)

    sealed class Outcome {
        data class Filed(val filed: FeedbackReport.Filed) : Outcome()
        /** The server has no GitHub token yet — a deploy problem, not the user's. */
        object Unconfigured : Outcome()
        /** Five a minute is the budget; the sixth waits. */
        object RateLimited : Outcome()
        /** Anything else: offline, 5xx, GitHub down. The form stays filled. */
        object Failed : Outcome()
    }

    /** A screenshot ready for the wire: 1280 px long side, ≤ 600 KB where it can be. */
    class Image private constructor(val preview: Bitmap, val jpeg: ByteArray) {
        companion object {
            const val targetBytes = 600 * 1024

            fun prepare(raw: Bitmap): Image? {
                val attempts = listOf(1280 to listOf(72, 60, 50), 960 to listOf(55, 45), 720 to listOf(45))
                var smallest: Pair<Bitmap, ByteArray>? = null
                for ((side, qualities) in attempts) {
                    val image = resized(raw, side)
                    for (q in qualities) {
                        val out = ByteArrayOutputStream()
                        if (!image.compress(Bitmap.CompressFormat.JPEG, q, out)) continue
                        val data = out.toByteArray()
                        if (smallest == null || data.size < smallest.second.size) smallest = image to data
                        if (data.size <= targetBytes) return Image(image, data)
                    }
                }
                return smallest?.let { Image(it.first, it.second) }
            }

            private fun resized(raw: Bitmap, maxSide: Int): Bitmap {
                val longest = max(raw.width, raw.height)
                if (longest <= maxSide) return raw
                val scale = maxSide.toDouble() / longest
                return Bitmap.createScaledBitmap(raw, (raw.width * scale).roundToInt(), (raw.height * scale).roundToInt(), true)
            }
        }
    }

    /** What the issue's facts table gets. No health data — the build, the phone, the band. */
    fun context(bandConnected: Boolean, firmware: String, batteryPercent: Int?): Map<String, String> {
        val c = mutableMapOf(
            "app" to BuildConfig.VERSION_NAME,
            "build" to BuildConfig.VERSION_CODE.toString(),
            "android" to Build.VERSION.RELEASE,
            "device" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "language" to AppLanguage.locale.raw,
            "timezone" to TimeZone.getDefault().id,
        )
        if (bandConnected || firmware.isNotEmpty()) {
            val parts = mutableListOf("NEXTBODY")
            if (firmware.isNotEmpty()) parts += "fw $firmware"
            parts += if (bandConnected) "connected" else "not connected"
            if (batteryPercent != null) parts += "$batteryPercent%"
            c["band"] = parts.joinToString(" · ")
        }
        return c
    }

    suspend fun send(title: String, body: String, images: List<Image>, bandConnected: Boolean,
                     firmware: String, batteryPercent: Int?): Outcome {
        val payload = mapOf(
            "title" to title,
            "body" to body,
            "images" to images.take(maxImages).map {
                mapOf("mime" to "image/jpeg", "base64" to Base64.encodeToString(it.jpeg, Base64.NO_WRAP))
            },
            "context" to context(bandConnected, firmware, batteryPercent),
        )
        return try {
            val row = SupabaseClient.callFunction("feedback", payload)
            val number = (row.opt("number") as? Number)?.toInt()
            val url = row.optStringOrNull("url")
            if (number == null || url == null) return Outcome.Failed
            Analytics.track("FEEDBACK_FILED", mapOf("NUMBER" to number, "IMAGES" to images.size))
            Outcome.Filed(Filed(number, url))
        } catch (e: SupabaseFailure.Http) {
            when {
                e.code == 429 -> Outcome.RateLimited
                e.code == 503 && e.body.contains("FEEDBACK_UNCONFIGURED") -> Outcome.Unconfigured
                else -> Outcome.Failed
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            Outcome.Failed
        }
    }
}
