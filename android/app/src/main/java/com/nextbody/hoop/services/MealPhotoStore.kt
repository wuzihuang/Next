package com.nextbody.hoop.services

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File

/**
 * The plate's photo, on the phone. `photo_path` names an object in the private `meal-photos`
 * bucket; the bytes are fetched with the session's own token and kept in the cache dir. A
 * missing photo is not an error state: a plate with no photo simply has no thumbnail.
 *
 * Compose: observe [generation] so a thumbnail redraws when the bytes land.
 */
object MealPhotoStore {
    private val memory = HashMap<String, Bitmap>()
    private val inFlight = HashSet<String>()
    private val _generation = MutableStateFlow(0)
    val generation: StateFlow<Int> = _generation.asStateFlow()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var directory: File? = null

    fun init(context: Context) {
        directory = File(context.applicationContext.cacheDir, "meal-photos").also { it.mkdirs() }
    }

    @Synchronized
    fun image(path: String?): Bitmap? {
        if (path.isNullOrEmpty()) return null
        memory[path]?.let { return it }
        val file = directory?.let { File(it, filename(path)) }
        if (file != null && file.exists()) {
            BitmapFactory.decodeFile(file.path)?.let { memory[path] = it; return it }
        }
        load(path)
        return null
    }

    /** The photo of a plate the phone wrote itself, kept before the row was ever read back. */
    @Synchronized
    fun remember(image: Bitmap, path: String) {
        memory[path] = image
        directory?.let { dir ->
            runCatching { File(dir, filename(path)).outputStream().use { image.compress(Bitmap.CompressFormat.JPEG, 80, it) } }
        }
        _generation.value += 1
    }

    @Synchronized
    private fun load(path: String) {
        if (!inFlight.add(path)) return
        scope.launch {
            try {
                val data = runCatching { SupabaseClient.storageObject("meal-photos", path) }.getOrNull() ?: return@launch
                val image = BitmapFactory.decodeByteArray(data, 0, data.size) ?: return@launch
                synchronized(this@MealPhotoStore) {
                    memory[path] = image
                    directory?.let { runCatching { File(it, filename(path)).writeBytes(data) } }
                    _generation.value += 1
                }
            } finally {
                synchronized(this@MealPhotoStore) { inFlight.remove(path) }
            }
        }
    }

    /** Signing out clears the bytes with everything else this account could see. */
    @Synchronized
    fun clear() {
        memory.clear()
        directory?.let { it.deleteRecursively(); it.mkdirs() }
        _generation.value += 1
    }

    private fun filename(path: String) = path.replace("/", "_")
}
