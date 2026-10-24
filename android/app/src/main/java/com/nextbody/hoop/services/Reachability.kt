package com.nextbody.hoop.services

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * 05 edge 5 · a message never leaves the dock when there is no connection. One network
 * callback; [isOnline] is read anywhere, [online] is observed (Swift `$isOnline`).
 */
object Reachability {
    private val state = MutableStateFlow(true)
    val online: StateFlow<Boolean> = state.asStateFlow()
    val isOnline: Boolean get() = state.value
    private var started = false
    private val live = mutableSetOf<Network>()

    fun init(context: Context) {
        if (started) return
        started = true
        val cm = context.applicationContext.getSystemService(ConnectivityManager::class.java) ?: return
        state.value = cm.activeNetwork?.let { cm.getNetworkCapabilities(it) }
            ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) ?: false
        val request = NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build()
        cm.registerNetworkCallback(request, object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                synchronized(live) { live += network }
                state.value = true
            }
            override fun onLost(network: Network) {
                val empty = synchronized(live) { live -= network; live.isEmpty() }
                if (empty) state.value = cm.activeNetwork != null
            }
        })
    }
}
