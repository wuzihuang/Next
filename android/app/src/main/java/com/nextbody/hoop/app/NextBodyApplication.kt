package com.nextbody.hoop.app

import android.app.Application
import android.content.Context
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.l10n.L10n

class NextBodyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        instance = this
        com.nextbody.hoop.data.Defaults.init(this)
        NBFont.init(this)
        L10n.load(this)
        com.nextbody.hoop.ui.HapticsSetting.init(this)
        com.nextbody.hoop.services.ServicesBootstrap.install(this)
        com.nextbody.hoop.features.sport.LiveSessionStore.install()
    }

    companion object {
        lateinit var instance: NextBodyApplication
            private set
        val context: Context get() = instance.applicationContext
    }
}
