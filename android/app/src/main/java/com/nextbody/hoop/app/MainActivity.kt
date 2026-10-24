package com.nextbody.hoop.app

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.nextbody.hoop.l10n.AppLanguage

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        DebugLaunch.read(intent)
        AppLanguage.init(this, DebugLaunch["NB_DEBUG_LANG"])
        super.onCreate(savedInstanceState)
        // The app is dark only (`.preferredColorScheme(.dark)` on iOS): light bar content.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
        )
        current = this
        AppLifecycle.onCreate(this)
        setContent { RootView() }
        handleIncoming(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncoming(intent)
    }

    override fun onResume() {
        super.onResume()
        current = this
        AppLifecycle.onForeground(this)
    }

    override fun onPause() {
        super.onPause()
        AppLifecycle.onBackground(this)
    }

    override fun onDestroy() {
        if (current === this) current = null
        super.onDestroy()
    }

    /** 01 · the OAuth return and F1 · notification deep links both arrive as `nextbody://`. */
    private fun handleIncoming(intent: Intent?) {
        val uri = intent?.data ?: return
        AppLifecycle.openIncoming(this, uri)
    }

    companion object {
        /** The activity on screen, for APIs that need one (Credential Manager, permissions). */
        var current: MainActivity? = null
            private set
    }
}
