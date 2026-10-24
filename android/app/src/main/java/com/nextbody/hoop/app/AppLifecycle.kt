package com.nextbody.hoop.app

import android.app.Activity
import android.net.Uri
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * The scene-phase half of `NextBodyApp.swift`: launch, foreground, background, incoming
 * links. The service layer installs the actual work through the hooks below so the shell
 * stays free of networking.
 */
object AppLifecycle {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    var launchHook: (suspend () -> Unit)? = null
    var foregroundHook: ((reason: String) -> Unit)? = null
    var backgroundHook: (() -> Unit)? = null
    /** Returns true when the URI was an auth redirect and has been consumed. */
    var authRedirectHook: ((Uri) -> Boolean)? = { uri ->
        if (uri.host == "auth-callback") { scope.launch { com.nextbody.hoop.services.SupabaseClient.handleAuthRedirect(uri) }; true } else false
    }
    /** Only a signed-in root accepts a notification deep link. */
    var acceptsDeepLinks: (() -> Boolean) = { AppSession.session.stage == com.nextbody.hoop.data.SessionStore.Stage.root }

    private var launched = false

    fun onCreate(activity: Activity) {}

    fun onForeground(activity: Activity) {
        if (!launched) {
            launched = true
            return
        }
        foregroundHook?.invoke("foreground")
    }

    fun onBackground(activity: Activity) {
        backgroundHook?.invoke()
    }

    fun openIncoming(activity: Activity, uri: Uri) {
        if (authRedirectHook?.invoke(uri) == true) return
        if (!acceptsDeepLinks()) return
        val link = NotificationDeepLink.parse(uri) ?: return
        Router.receive(link)
    }
}
