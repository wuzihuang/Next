package com.nextbody.hoop.l10n

import android.content.Context
import org.json.JSONObject
import java.util.Locale

/**
 * English-as-key lookup. The English string in source is the catalog key.
 *
 * Adding a language: drop `assets/l10n/<code>.json` mapping English → that language,
 * then add a case on [AppLocale]. Missing keys fall back to English.
 *
 * Interpolation: `L("%@ LEFT", Fmt.kcal(n))` with `"%@ LEFT"` / `"还剩 %@"` in the table.
 * The tables are the iOS ones verbatim, so Foundation placeholders are translated to
 * java.util.Formatter ones on the way out (`%@` → `%s`, `%ld` → `%d`).
 */
object L10n {
    private val tables = mutableMapOf<AppLocale, Map<String, String>>()

    fun load(context: Context) {
        if (tables.isNotEmpty()) return
        runCatching {
            val raw = context.assets.open("l10n/zh-Hans.json").bufferedReader().use { it.readText() }
            val json = JSONObject(raw)
            val out = HashMap<String, String>(json.length())
            json.keys().forEach { k -> out[k] = json.getString(k) }
            tables[AppLocale.SimplifiedChinese] = out
        }
    }

    fun t(key: String): String = lookup(key)

    fun t(key: String, args: Array<out Any?>): String {
        val template = lookup(key)
        if (args.isEmpty()) return template
        return format(template, AppLanguage.locale.javaLocale, args)
    }

    fun hasTranslation(key: String, locale: AppLocale = AppLanguage.locale): Boolean =
        locale == AppLocale.English || tables[locale]?.containsKey(key) == true

    private fun lookup(key: String): String {
        val locale = AppLanguage.locale
        if (locale == AppLocale.English) return key
        return tables[locale]?.get(key) ?: key
    }

    private val placeholder =
        Regex("%(\\d+\\$)?([-+ 0#,']*)(\\d+)?(\\.\\d+)?(hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfFeEgGcCsSaA%])")

    /** Foundation format → java.util.Formatter. Never throws: a bad pairing prints the template. */
    fun format(template: String, locale: Locale, args: Array<out Any?>): String {
        var auto = 0
        val converted = placeholder.replace(template) { m ->
            val conv = m.groupValues[6]
            if (conv == "%") return@replace "%%"
            val explicit = m.groupValues[1]
            val index = if (explicit.isNotEmpty()) explicit.dropLast(1).toInt() - 1 else auto++
            val flags = m.groupValues[2].replace("'", "")
            val width = m.groupValues[3]
            val precision = m.groupValues[4]
            val arg = args.getOrNull(index)
            val pos = "${index + 1}\$"
            when (conv) {
                "@", "s", "S" -> "%$pos${flags.replace(",", "")}${width}s"
                "d", "D", "i", "u", "U" ->
                    if (arg is Double || arg is Float) "%$pos$flags$width.0f" else "%$pos$flags${width}d"
                "c", "C" -> "%$pos${width}c"
                else -> "%$pos$flags$width$precision$conv"
            }
        }
        val fixed = args.map {
            when (it) {
                null, is Int, is Long, is Double, is Float, is String -> it
                else -> it.toString()
            }
        }
        return runCatching { String.format(locale, converted, *fixed.toTypedArray()) }.getOrElse { template }
    }
}

fun L(key: String): String = keepLastWordCompany(L10n.t(key))

fun L(key: String, vararg args: Any?): String = keepLastWordCompany(L10n.t(key, args))

/**
 * iOS breaks lines with the `.standard` strategy: a paragraph never ends on a line holding a
 * single word, the word before it comes down too ("…pulling everything / into place.").
 * Android breaks greedily, so a sentence's last two words are joined with a no-break space,
 * which gives the same lines. Labels (fewer than three spaces) and Chinese copy are left alone.
 */
internal fun keepLastWordCompany(s: String): String {
    if (s.count { it == ' ' } < 3 || s.any { it.code in 0x3000..0x9FFF }) return s
    return s.split('\n').joinToString("\n") { para ->
        val body = para.trimEnd()
        val last = body.lastIndexOf(' ')
        if (body.count { it == ' ' } < 3 || last <= 0) para
        else para.substring(0, last) + "\u00A0" + para.substring(last + 1)
    }
}
