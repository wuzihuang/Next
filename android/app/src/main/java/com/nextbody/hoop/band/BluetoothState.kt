package com.nextbody.hoop.band

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/**
 * 02 edge 2 · BLUETOOTH IS OFF is a state of the phone, not of the band, so it is read from
 * the system adapter directly rather than inferred from a scan that finds nothing. One
 * receiver, registered the first time 02 needs it.
 *
 * (iOS wraps CBCentralManager; Android reads BluetoothAdapter and listens to
 * ACTION_STATE_CHANGED. Without a context — unit tests, previews — it stays a no-op.)
 */
class BluetoothState private constructor() {
    companion object {
        val shared: BluetoothState by lazy { BluetoothState() }
    }

    var poweredOff by mutableStateOf(false)
        private set
    /** Bluetooth permission denied (Android 12+ BLUETOOTH_SCAN / BLUETOOTH_CONNECT). A 15 s
     *  empty scan would otherwise look like NOTHING FOUND. */
    var permissionDenied by mutableStateOf(false)
        private set
    private var started = false
    private var context: Context? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) update()
        }
    }

    fun start() {
        if (started) { update(); return }
        val ctx = runCatching { com.nextbody.hoop.app.NextBodyApplication.context }.getOrNull() ?: return
        started = true
        context = ctx
        runCatching { ctx.registerReceiver(receiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)) }
        update()
    }

    /** The adapter answers synchronously on Android; this keeps the Swift call shape and
     *  re-reads the permission, which the user may have just granted. */
    suspend fun waitForState() {
        start()
    }

    private fun update() {
        val ctx = context ?: return
        val adapter = runCatching {
            (ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
        }.getOrNull()
        val denied = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && listOf(
            Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT,
        ).any { ctx.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        val off = adapter != null && runCatching {
            adapter.state == BluetoothAdapter.STATE_OFF || adapter.state == BluetoothAdapter.STATE_TURNING_OFF
        }.getOrDefault(false)
        val apply = {
            poweredOff = off
            permissionDenied = denied
        }
        apply()
    }
}
