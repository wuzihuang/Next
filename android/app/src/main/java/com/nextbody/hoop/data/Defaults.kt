package com.nextbody.hoop.data

import android.content.Context
import android.content.SharedPreferences
import java.util.concurrent.ConcurrentHashMap

/**
 * `UserDefaults.standard` for the port. Backed by the same `nb` SharedPreferences file
 * `AppLanguage` uses once [init] has run (call it from `Application.onCreate`, before the
 * first touch of `DataStore` / `SessionStore`); an in-memory map before that, so pure
 * code and JVM tests still run.
 *
 * Every key the app stores starts with `nb.` — the account-delete sweep relies on it.
 */
object Defaults {
    @Volatile
    private var prefs: SharedPreferences? = null
    private val memory = ConcurrentHashMap<String, Any>()

    fun init(context: Context) {
        val p = context.applicationContext.getSharedPreferences("nb", Context.MODE_PRIVATE)
        prefs = p
        if (memory.isNotEmpty()) {
            val e = p.edit()
            for ((k, v) in memory) when (v) {
                is String -> e.putString(k, v)
                is Int -> e.putInt(k, v)
                is Boolean -> e.putBoolean(k, v)
                is Long -> e.putLong(k, v)
                is Double -> e.putLong(k, java.lang.Double.doubleToRawLongBits(v))
            }
            e.apply()
            memory.clear()
        }
    }

    fun contains(key: String): Boolean = prefs?.contains(key) ?: memory.containsKey(key)

    fun getString(key: String): String? =
        prefs?.let { runCatching { it.getString(key, null) }.getOrNull() } ?: memory[key] as? String

    fun putString(key: String, value: String?) {
        if (value == null) return remove(key)
        prefs?.edit()?.putString(key, value)?.apply() ?: run { memory[key] = value }
    }

    /** `integer(forKey:)` — 0 when absent. */
    fun getInt(key: String): Int =
        prefs?.let { runCatching { it.getInt(key, 0) }.getOrDefault(0) } ?: (memory[key] as? Int ?: 0)

    fun putInt(key: String, value: Int) {
        prefs?.edit()?.putInt(key, value)?.apply() ?: run { memory[key] = value }
    }

    /** `bool(forKey:)` — false when absent. */
    fun getBoolean(key: String): Boolean =
        prefs?.let { runCatching { it.getBoolean(key, false) }.getOrDefault(false) } ?: (memory[key] as? Boolean ?: false)

    fun putBoolean(key: String, value: Boolean) {
        prefs?.edit()?.putBoolean(key, value)?.apply() ?: run { memory[key] = value }
    }

    /** Stores a `Date` as epoch milliseconds. */
    fun getLong(key: String): Long? {
        val p = prefs
        if (p != null) return if (p.contains(key)) runCatching { p.getLong(key, 0) }.getOrNull() else null
        return memory[key] as? Long
    }

    fun putLong(key: String, value: Long) {
        prefs?.edit()?.putLong(key, value)?.apply() ?: run { memory[key] = value }
    }

    fun remove(key: String) {
        prefs?.edit()?.remove(key)?.apply() ?: run { memory.remove(key) }
    }

    /** `dictionaryRepresentation().keys`. */
    val keys: Set<String> get() = prefs?.all?.keys?.toSet() ?: memory.keys.toSet()
}
