package com.nextbody.hoop.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import java.io.File

/**
 * Presents the system camera and hands back the full-resolution photo. The shutter is the
 * system's own capture activity (TakePicture into a cache file shared through a FileProvider),
 * so it can never be lost under a dismissing overlay. When the app declares CAMERA the
 * permission is asked for first; a refusal or a missing camera reads as a cancel.
 *
 * Requires in the manifest:
 * ```
 * <provider android:name="androidx.core.content.FileProvider"
 *     android:authorities="${applicationId}.fileprovider" android:exported="false"
 *     android:grantUriPermissions="true">
 *   <meta-data android:name="android.support.FILE_PROVIDER_PATHS"
 *       android:resource="@xml/nb_camera_paths" />
 * </provider>
 * ```
 */
class CameraGate internal constructor(private val start: () -> Unit) {
    fun present() = start()
}

@Composable
fun rememberCameraGate(onCapture: (Bitmap) -> Unit, onCancel: () -> Unit): CameraGate {
    val context = LocalContext.current
    val capture by rememberUpdatedState(onCapture)
    val cancel by rememberUpdatedState(onCancel)
    var pending by rememberSaveable { mutableStateOf<String?>(null) }

    val take = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val uri = pending?.let(Uri::parse)
        pending = null
        val image = if (ok && uri != null) decode(context, uri) else null
        uri?.let { runCatching { context.contentResolver.delete(it, null, null) } }
        if (image != null) capture(image) else cancel()
    }

    fun launchCamera() {
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)) {
            cancel(); return
        }
        val uri = runCatching { newPhotoUri(context) }.getOrNull() ?: run { cancel(); return }
        pending = uri.toString()
        runCatching { take.launch(uri) }.onFailure { pending = null; cancel() }
    }

    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) launchCamera() else cancel()
    }

    return remember(context) {
        CameraGate {
            val needsGrant = declaresCamera(context) &&
                ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED
            if (needsGrant) ask.launch(Manifest.permission.CAMERA) else launchCamera()
        }
    }
}

/** A declared-but-ungranted CAMERA permission blocks the capture intent; undeclared needs none. */
private fun declaresCamera(context: Context): Boolean = runCatching {
    context.packageManager
        .getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
        .requestedPermissions?.contains(Manifest.permission.CAMERA) == true
}.getOrDefault(false)

private fun newPhotoUri(context: Context): Uri {
    val dir = File(context.cacheDir, "camera").apply { mkdirs() }
    val file = File.createTempFile("capture", ".jpg", dir)
    return FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
}

private fun decode(context: Context, uri: Uri): Bitmap? = runCatching {
    ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, _, _ ->
        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
    }
}.getOrNull()
