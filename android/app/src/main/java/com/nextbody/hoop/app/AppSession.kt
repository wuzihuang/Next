package com.nextbody.hoop.app

import com.nextbody.hoop.data.SessionStore

/**
 * The one `SessionStore` (iOS `@StateObject private var session` on `NextBodyApp`). Created on
 * first touch, after `Defaults.init` and `DebugLaunch.read` have run in the activity.
 */
object AppSession {
    val session: SessionStore by lazy { SessionStore() }
}
