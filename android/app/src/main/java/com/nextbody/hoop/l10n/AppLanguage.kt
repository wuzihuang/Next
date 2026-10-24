package com.nextbody.hoop.l10n

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.Locale

/** In-app language. English is the default and the source of truth. */
enum class AppLocale(val raw: String) {
    English("en"),
    SimplifiedChinese("zh-Hans");

    /** BCP-47 sent to Edge Functions and written to `profiles.locale`. */
    val serverLocale: String
        get() = when (this) {
            English -> "en-US"
            SimplifiedChinese -> "zh-CN"
        }

    val javaLocale: Locale
        get() = when (this) {
            English -> Locale.US
            SimplifiedChinese -> Locale.SIMPLIFIED_CHINESE
        }

    /** Language names stay in their own language in the picker. */
    val nativeName: String
        get() = when (this) {
            English -> "English"
            SimplifiedChinese -> "简体中文"
        }

    /** Short label shown on the Profile row. */
    val rowLabel: String
        get() = when (this) {
            English -> "ENGLISH"
            SimplifiedChinese -> "简体中文"
        }

    val usesCJKFont: Boolean get() = this == SimplifiedChinese

    companion object {
        fun parse(raw: String?): AppLocale {
            val value = (raw ?: "").trim()
            return when (value) {
                "zh-Hans", "zh-CN", "zh", "简体中文" -> SimplifiedChinese
                "en", "en-US", "English" -> English
                else -> if (value.lowercase().startsWith("zh")) SimplifiedChinese else English
            }
        }
    }
}

/**
 * Stored as `en` / `zh-Hans` under `nb.language`. Compose readers observe [locale]; the root
 * keys its whole tree on it so a change in Settings redraws every screen.
 */
object AppLanguage {
    const val KEY = "nb.language"
    private var prefs: SharedPreferences? = null

    /** The profile row is the server's fallback for a client that sends no locale; the
     *  repository installs the writer. Written when the sheet changes, never on launch. */
    var onSync: ((String) -> Unit)? = null

    var locale: AppLocale by mutableStateOf(AppLocale.English)
        private set

    val isEnglish: Boolean get() = locale == AppLocale.English
    val serverLocale: String get() = locale.serverLocale
    val usesCJKFont: Boolean get() = locale.usesCJKFont

    fun init(context: Context, forced: String? = null) {
        val p = context.getSharedPreferences("nb", Context.MODE_PRIVATE)
        prefs = p
        locale = AppLocale.parse(forced ?: p.getString(KEY, null))
        p.edit().putString(KEY, locale.raw).apply()
    }

    fun set(next: AppLocale) {
        if (next != locale) {
            locale = next
            prefs?.edit()?.putString(KEY, next.raw)?.apply()
        }
        syncProfile()
    }

    fun syncProfile() {
        onSync?.invoke(serverLocale)
    }
}
