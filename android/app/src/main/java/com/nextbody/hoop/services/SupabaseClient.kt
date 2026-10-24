package com.nextbody.hoop.services

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.util.Base64
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.Instant
import java.time.OffsetDateTime
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Thin REST/Edge-Function client. Everything server-side lives in Supabase (see supabase/). */
object SupabaseConfig {
    const val URL = "https://gkgzwcxivnffsecshvfs.supabase.co"
    const val PUBLISHABLE_KEY = "sb_publishable_FBRhpyBVNzlpBdjp4NOF4Q_1ZrVGWRt"

    /** Where the Edge Functions live. A release build always talks to the project. */
    val functionsBase: String get() = "$URL/functions/v1"

    /** The deep link the browser OAuth fallback returns to. */
    const val AUTH_REDIRECT = "nextbody://auth-callback"
}

/**
 * The mailbox-free account that carries `supabase/seed/demo.sql`. Simulator walk-through
 * only — a real phone must never land on it, even from a leftover stored session.
 */
object DemoAccount {
    const val email = "demo@nextbody.app"
    const val password = "nextbody-demo"
    fun matches(email: String): Boolean = email.trim().lowercase() == this.email
}

/**
 * The App Review account, reachable on a real phone. It has no mailbox: no code is mailed,
 * and the six digits typed on the code screen are its password. The app holds no secret for
 * it; a wrong code is refused by the server. Its data is synthetic and
 * `nb.reset_review_account()` rebuilds it every night.
 *
 * Gate usage (port of SignInFlow.verify): when [matches], call
 * `SupabaseClient.signIn(ReviewAccount.email, password = <the six digits>)` instead of
 * `verifyCode`, and skip `requestCode` (no mail is sent).
 */
object ReviewAccount {
    const val email = "demo@nextbody.ai"
    fun matches(email: String): Boolean = email.trim().lowercase() == this.email
}

/** Shared transport errors; read modules classify server conflicts without losing HTTP failures. */
sealed class SupabaseFailure(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class Http(val code: Int, val body: String) : SupabaseFailure("HTTP $code: $body")
    class Transport(val error: Throwable) : SupabaseFailure(error.localizedMessage ?: error.toString(), error)
}

/** Swift's `CancellationError` for a reply that belongs to a session that is gone. */
class SessionChangedException(message: String = "session changed") : CancellationException(message)

data class RequestSession(val owner: String?, val generation: String)

/** JWT payload helpers (port of HomeLaunchPolicy's token helpers). */
object Jwt {
    /** Access tokens this close to expiry are treated as gone. */
    const val ACCESS_TOKEN_LEEWAY_SECONDS = 15.0

    fun payload(token: String): JSONObject? {
        val parts = token.split(".")
        if (parts.size < 2) return null
        return runCatching {
            val bytes = Base64.decode(parts[1], Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
            JSONObject(String(bytes, Charsets.UTF_8))
        }.getOrNull()
    }

    fun subject(token: String): String? = payload(token)?.optString("sub")?.takeIf { it.isNotEmpty() }
    fun email(token: String): String? = payload(token)?.optString("email")?.takeIf { it.isNotEmpty() }
    fun expiry(token: String): Double? = payload(token)?.let { p ->
        if (p.has("exp")) p.optDouble("exp").takeIf { !it.isNaN() } else null
    }

    fun isAccessTokenUsable(token: String, nowSeconds: Double = System.currentTimeMillis() / 1000.0): Boolean {
        val exp = expiry(token) ?: return false
        return exp - nowSeconds > ACCESS_TOKEN_LEEWAY_SECONDS
    }
}

/** Session material in private SharedPreferences (the iOS Keychain's role). */
object SessionKeychain {
    private var prefs: SharedPreferences? = null
    fun init(context: Context) {
        if (prefs == null) prefs = context.applicationContext.getSharedPreferences("nb.supabase.session", Context.MODE_PRIVATE)
    }
    private fun get(k: String): String? = prefs?.getString(k, null)
    private fun set(k: String, v: String?) {
        val p = prefs ?: return
        if (v == null) p.edit().remove(k).apply() else p.edit().putString(k, v).apply()
    }
    var refreshToken: String? get() = get("refresh_token"); set(v) = set("refresh_token", v)
    var accessToken: String? get() = get("access_token"); set(v) = set("access_token", v)
    var userId: String? get() = get("user_id"); set(v) = set("user_id", v)
    var userEmail: String? get() = get("user_email"); set(v) = set("user_email", v)
    /** PKCE verifier for the browser OAuth fallback, kept across process death. */
    var pkceVerifier: String? get() = get("pkce_verifier"); set(v) = set("pkce_verifier", v)
}

/** PostgREST query items, in order. Same name may repeat (`ts=gte..&ts=lt..`). */
typealias Query = List<Pair<String, String>>

object SupabaseClient {
    private val lock = Any()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var appContext: Context? = null

    private var sessionGeneration = UUID.randomUUID().toString()
    private var accessToken: String? = null
    private var refreshToken: String? = null
    private var refreshTask: Deferred<RefreshResult>? = null

    /** The signed-in user's id. RLS still checks it; convenience, never authority. */
    @Volatile var userId: String? = null
        private set
    @Volatile var userEmail: String? = null
        private set

    /** 01 · a session whose account was created in this very exchange is a first registration. */
    @Volatile var isNewUser: Boolean = false
        private set

    // Snapshot state (Swift's lock-guarded statics).
    @Volatile private var snapshotUserId: String? = null
    @Volatile private var snapshotSession = RequestSession(null, UUID.randomUUID().toString())

    private val _accountDidChange = MutableSharedFlow<Unit>(extraBufferCapacity = 16)
    /** Posted whenever the signed-in account changes (Swift `accountDidChange`). */
    val accountDidChange: SharedFlow<Unit> = _accountDidChange.asSharedFlow()
    private val _requestSessionDidChange = MutableSharedFlow<Unit>(extraBufferCapacity = 16)
    val requestSessionDidChange: SharedFlow<Unit> = _requestSessionDidChange.asSharedFlow()
    private val _currentUser = MutableStateFlow<String?>(null)
    /** Observable signed-in account id. */
    val currentUser: StateFlow<String?> = _currentUser.asStateFlow()
    /** Plain callbacks for non-coroutine listeners. */
    val accountListeners = java.util.concurrent.CopyOnWriteArrayList<() -> Unit>()

    private val http: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    /** SSE/long uploads: the timeout is the gap between two bytes, not the whole turn. */
    private val streamHttp: OkHttpClient = http.newBuilder()
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .build()

    private val JSON = "application/json".toMediaType()

    fun init(context: Context) {
        appContext = context.applicationContext
        SessionKeychain.init(context)
    }

    val context: Context? get() = appContext

    // region snapshots

    private val requestSession: RequestSession
        get() = synchronized(lock) { RequestSession(userId, sessionGeneration) }

    @JvmStatic fun currentUserIdSnapshot(): String? = snapshotUserId
    @JvmStatic fun currentRequestSessionSnapshot(): RequestSession = snapshotSession

    val isSignedIn: Boolean get() = accessToken != null
    val currentUserId: String? get() = userId
    fun signedInEmail(): String? = userEmail

    fun setAccessToken(token: String?) {
        synchronized(lock) {
            sessionGeneration = UUID.randomUUID().toString()
            accessToken = token
            userId = token?.let(Jwt::subject)
            refreshTask?.cancel(); refreshTask = null
        }
        storeSnapshot(userId, userEmail, sessionGeneration)
    }

    private fun storeSnapshot(userId: String?, userEmail: String?, generation: String) {
        // Bands are filed per account; the next reader of a binding must already see the new one.
        com.nextbody.hoop.band.DeviceSlots.owner = userId
        val changed: Boolean
        val sessionChanged: Boolean
        synchronized(lock) {
            changed = snapshotUserId != userId
            val next = RequestSession(userId, generation)
            sessionChanged = snapshotSession != next
            snapshotSession = next
            snapshotUserId = userId
        }
        if (changed) {
            _currentUser.value = userId
            _accountDidChange.tryEmit(Unit)
            accountListeners.forEach { runCatching { it() } }
        }
        if (sessionChanged) _requestSessionDidChange.tryEmit(Unit)
    }

    // endregion

    // region auth

    /** Email + password. Reaches the demo account and the App Review account (whose password is the typed code). */
    suspend fun signIn(email: String, password: String): String {
        val starting = sessionGeneration
        val out = grant("password", JSONObject().put("email", email).put("password", password))
        val token = out.optString("access_token")
        if (sessionGeneration != starting) throw SessionChangedException()
        adopt(out)
        return token
    }

    suspend fun signInWithGoogle(idToken: String, nonce: String): String =
        signInWithIdToken("google", idToken, nonce)

    /**
     * Native id-token sign-in: Supabase verifies the signature, checks the audience against
     * the client ID configured for the provider, and hashes the raw nonce back to what the
     * token carries.
     */
    suspend fun signInWithIdToken(provider: String, idToken: String, nonce: String?): String {
        val starting = sessionGeneration
        val body = JSONObject().put("provider", provider).put("id_token", idToken)
        if (nonce != null) body.put("nonce", nonce)
        val out = grant("id_token", body)
        if (sessionGeneration != starting) throw SessionChangedException()
        adopt(out)
        return out.optString("access_token")
    }

    private suspend fun grant(type: String, body: JSONObject): JSONObject {
        val url = "${SupabaseConfig.URL}/auth/v1/token".toHttpUrl().newBuilder()
            .addQueryParameter("grant_type", type).build()
        val req = Request.Builder().url(url)
            .header("apikey", SupabaseConfig.PUBLISHABLE_KEY)
            .post(body.toString().toRequestBody(JSON)).build()
        val (code, data) = send(http, req)
        val out = runCatching { JSONObject(data) }.getOrNull()
        if (code !in 200..299 || out == null || !out.has("access_token")) throw SupabaseFailure.Http(code, data)
        return out
    }

    /**
     * Restore a session without waiting on the network when a still-valid access token is
     * already on this phone. Otherwise the refresh token is traded for a fresh grant.
     */
    suspend fun restoreSession(): Boolean {
        val restoring = sessionGeneration
        if (accessToken != null) return true
        val stored = SessionKeychain.accessToken
        if (stored != null && Jwt.isAccessTokenUsable(stored)) {
            val sub = Jwt.subject(stored)
            if (sub != null) {
                synchronized(lock) {
                    accessToken = stored
                    refreshToken = SessionKeychain.refreshToken
                    userId = sub
                    userEmail = Jwt.email(stored) ?: SessionKeychain.userEmail
                }
                SessionKeychain.userId = sub
                SessionKeychain.userEmail = userEmail
                storeSnapshot(userId, userEmail, sessionGeneration)
                return true
            }
        }
        val refresh = SessionKeychain.refreshToken ?: return false
        val url = "${SupabaseConfig.URL}/auth/v1/token".toHttpUrl().newBuilder()
            .addQueryParameter("grant_type", "refresh_token").build()
        val req = Request.Builder().url(url)
            .header("apikey", SupabaseConfig.PUBLISHABLE_KEY)
            .post(JSONObject().put("refresh_token", refresh).toString().toRequestBody(JSON)).build()
        val (code, data) = try { send(http, req) } catch (e: Exception) {
            if (e is CancellationException) throw e
            return false
        }
        if (sessionGeneration != restoring) return false
        val out = runCatching { JSONObject(data) }.getOrNull()
        if (code !in 200..299 || out == null || !out.has("access_token")) {
            // A refused refresh token is dead; a transport failure is not.
            if (code in 400..499) clearKeychain()
            return false
        }
        adopt(out)
        isNewUser = false
        return true
    }

    private fun clearKeychain() {
        SessionKeychain.refreshToken = null
        SessionKeychain.accessToken = null
        SessionKeychain.userId = null
        SessionKeychain.userEmail = null
    }

    private class RefreshResult(val payload: JSONObject?, val status: Int)

    private suspend fun refreshedToken(pinned: RequestSession): String? {
        if (requestSession != pinned) return null
        if (!refreshExpiredSession()) return null
        if (requestSession != pinned) return null
        return accessToken
    }

    /** Single-flight: parallel uploads cannot consume the rotating refresh token several times. */
    private suspend fun refreshExpiredSession(): Boolean {
        val pinned = requestSession
        val token = refreshToken ?: SessionKeychain.refreshToken ?: return false
        val task = synchronized(lock) {
            refreshTask ?: scope.async {
                val url = "${SupabaseConfig.URL}/auth/v1/token".toHttpUrl().newBuilder()
                    .addQueryParameter("grant_type", "refresh_token").build()
                val req = Request.Builder().url(url)
                    .header("apikey", SupabaseConfig.PUBLISHABLE_KEY)
                    .post(JSONObject().put("refresh_token", token).toString().toRequestBody(JSON)).build()
                try {
                    val (status, data) = send(http, req)
                    RefreshResult(runCatching { JSONObject(data) }.getOrNull(), status)
                } catch (e: Exception) {
                    RefreshResult(null, 0)
                }
            }.also { refreshTask = it }
        }
        val result = try { task.await() } catch (e: CancellationException) { RefreshResult(null, 0) }
        if (requestSession != pinned) return false
        // Another waiter may already have adopted this rotating refresh token.
        val current = refreshToken
        if (current != null && current != token) return accessToken != null
        synchronized(lock) { if (refreshTask === task) refreshTask = null }
        val payload = result.payload
        if (payload != null && payload.has("access_token")) {
            val user = payload.optJSONObject("user")
            if (user == null || user.optString("id") != pinned.owner) return false
            adopt(payload, preservingSession = true)
            isNewUser = false
            return true
        }
        if (result.status in 400..499) {
            synchronized(lock) {
                accessToken = null; refreshToken = null; userId = null; userEmail = null
            }
            clearKeychain()
            storeSnapshot(null, null, sessionGeneration)
        }
        return false
    }

    /**
     * Forget the session on this device. The server's row is revoked when it can be reached;
     * the stored copy goes either way, so the next launch starts at the gate.
     */
    suspend fun signOut() {
        val departing = accessToken
        synchronized(lock) {
            sessionGeneration = UUID.randomUUID().toString()
            refreshTask?.cancel(); refreshTask = null
            accessToken = null; refreshToken = null; userId = null; userEmail = null
        }
        clearKeychain()
        storeSnapshot(null, null, sessionGeneration)
        // After the local session is gone, not before: the credential manager is an IPC, and
        // an account that signed in while it was answering must not be signed out by it.
        appContext?.let { runCatching { GoogleAuth.signOut(it) } }
        if (departing != null) {
            val req = Request.Builder().url("${SupabaseConfig.URL}/auth/v1/logout")
                .header("apikey", SupabaseConfig.PUBLISHABLE_KEY)
                .header("Authorization", "Bearer $departing")
                .post(ByteArray(0).toRequestBody(null)).build()
            runCatching { send(http, req) }
        }
    }

    /** One place that reads a session reply, whichever grant produced it. */
    private fun adopt(out: JSONObject, preservingSession: Boolean = false) {
        synchronized(lock) {
            if (!preservingSession) {
                sessionGeneration = UUID.randomUUID().toString()
                refreshTask?.cancel(); refreshTask = null
            }
            accessToken = out.optString("access_token").takeIf { it.isNotEmpty() }
            refreshToken = out.optString("refresh_token").takeIf { it.isNotEmpty() }
            val user = out.optJSONObject("user")
            userId = user?.optString("id")?.takeIf { it.isNotEmpty() }
            userEmail = user?.optString("email")?.takeIf { it.isNotEmpty() }
            isNewUser = looksLikeFirstRegistration(user)
        }
        SessionKeychain.refreshToken = refreshToken
        SessionKeychain.accessToken = accessToken
        SessionKeychain.userId = userId
        SessionKeychain.userEmail = userEmail
        storeSnapshot(userId, userEmail, sessionGeneration)
    }

    /** GoTrue stamps `last_sign_in_at` with this very grant; on a first registration it lands within a breath of `created_at`. */
    private fun looksLikeFirstRegistration(user: JSONObject?): Boolean {
        val created = user?.optString("created_at")?.let(::timestamp) ?: return false
        val last = user.optString("last_sign_in_at").let(::timestamp) ?: return true
        return kotlin.math.abs(last.epochSecond - created.epochSecond) < 5
    }

    private fun timestamp(raw: String?): Instant? {
        if (raw.isNullOrEmpty()) return null
        return runCatching { OffsetDateTime.parse(raw).toInstant() }.getOrNull()
            ?: runCatching { Instant.parse(raw) }.getOrNull()
    }

    /** The gate's real path: ask for a six-digit code. */
    suspend fun requestCode(email: String) {
        val req = Request.Builder().url("${SupabaseConfig.URL}/auth/v1/otp")
            .header("apikey", SupabaseConfig.PUBLISHABLE_KEY)
            .post(JSONObject().put("email", email).put("create_user", true).toString().toRequestBody(JSON)).build()
        val (code, data) = send(http, req)
        if (code !in 200..299) throw SupabaseFailure.Http(code, data)
    }

    suspend fun verifyCode(email: String, token: String): String {
        val starting = sessionGeneration
        val req = Request.Builder().url("${SupabaseConfig.URL}/auth/v1/verify")
            .header("apikey", SupabaseConfig.PUBLISHABLE_KEY)
            .post(JSONObject().put("email", email).put("token", token).put("type", "email").toString().toRequestBody(JSON))
            .build()
        val (code, data) = send(http, req)
        val out = runCatching { JSONObject(data) }.getOrNull()
        if (code !in 200..299 || out == null || !out.has("access_token")) throw SupabaseFailure.Http(code, data)
        if (sessionGeneration != starting) throw SessionChangedException()
        adopt(out)
        return out.optString("access_token")
    }

    // Browser OAuth (PKCE) fallback for Google when no web client id is configured.

    private var pendingRedirect: CompletableDeferred<Unit>? = null

    /** Builds the `/auth/v1/authorize` URL and stores the verifier. */
    fun beginOAuth(provider: String): Uri {
        val verifier = Nonce.random(64)
        SessionKeychain.pkceVerifier = verifier
        val challenge = Base64.encodeToString(
            MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray()),
            Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
        pendingRedirect?.cancel()
        pendingRedirect = CompletableDeferred()
        return Uri.parse("${SupabaseConfig.URL}/auth/v1/authorize").buildUpon()
            .appendQueryParameter("provider", provider)
            .appendQueryParameter("redirect_to", SupabaseConfig.AUTH_REDIRECT)
            .appendQueryParameter("code_challenge", challenge)
            .appendQueryParameter("code_challenge_method", "s256")
            .build()
    }

    /** Suspends until [handleAuthRedirect] finishes the browser round trip. */
    suspend fun awaitOAuthRedirect() {
        (pendingRedirect ?: CompletableDeferred<Unit>().also { pendingRedirect = it }).await()
    }

    /**
     * The activity hands every `nextbody://auth-callback…` deep link here. Exchanges the PKCE
     * code at `/auth/v1/token?grant_type=pkce`. Returns true when a session was adopted.
     */
    suspend fun handleAuthRedirect(uri: Uri): Boolean {
        if (uri.scheme != "nextbody" || uri.host != "auth-callback") return false
        val waiter = pendingRedirect
        val error = uri.getQueryParameter("error_description") ?: uri.getQueryParameter("error")
            ?: uri.fragment?.let { Uri.parse("x://x?$it").getQueryParameter("error_description") }
        val code = uri.getQueryParameter("code")
        val verifier = SessionKeychain.pkceVerifier
        if (error != null || code == null || verifier == null) {
            waiter?.completeExceptionally(
                if (error?.contains("cancel", ignoreCase = true) == true) GoogleAuth.Failure.Cancelled()
                else SupabaseFailure.Http(400, error ?: "missing code"))
            pendingRedirect = null
            return false
        }
        return try {
            val starting = sessionGeneration
            val out = grant("pkce", JSONObject().put("auth_code", code).put("code_verifier", verifier))
            SessionKeychain.pkceVerifier = null
            if (sessionGeneration != starting) throw SessionChangedException()
            adopt(out)
            waiter?.complete(Unit)
            pendingRedirect = null
            true
        } catch (e: Exception) {
            waiter?.completeExceptionally(e)
            pendingRedirect = null
            false
        }
    }

    // endregion

    // region transport

    private suspend fun send(client: OkHttpClient, request: Request): Pair<Int, String> {
        val (code, bytes) = sendBytes(client, request)
        return code to String(bytes, Charsets.UTF_8)
    }

    private suspend fun sendBytes(client: OkHttpClient, request: Request): Pair<Int, ByteArray> =
        suspendCancellableCoroutine { cont ->
            val call = client.newCall(request)
            cont.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (cont.isActive) cont.resumeWithException(e)
                }
                override fun onResponse(call: Call, response: Response) {
                    val result = runCatching { response.use { it.code to (it.body?.bytes() ?: ByteArray(0)) } }
                    result.fold({ if (cont.isActive) cont.resume(it) },
                        { if (cont.isActive) cont.resumeWithException(it) })
                }
            })
        }

    private class Reply(val code: Int, val body: ByteArray, val headers: okhttp3.Headers) {
        val text: String get() = String(body, Charsets.UTF_8)
    }

    private suspend fun sendReply(client: OkHttpClient, request: Request): Reply =
        suspendCancellableCoroutine { cont ->
            val call = client.newCall(request)
            cont.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    if (cont.isActive) cont.resumeWithException(e)
                }
                override fun onResponse(call: Call, response: Response) {
                    val result = runCatching {
                        response.use { Reply(it.code, it.body?.bytes() ?: ByteArray(0), it.headers) }
                    }
                    result.fold({ if (cont.isActive) cont.resume(it) },
                        { if (cont.isActive) cont.resumeWithException(it) })
                }
            })
        }

    /**
     * Every authenticated request gets one bounded recovery from an expired access token
     * (SessionBoundTransport.perform): a refresh may change credentials, never the account.
     */
    private suspend fun authenticated(build: (String) -> Request, expectedOwner: String? = null,
                                      longRunning: Boolean = false): Reply {
        if (expectedOwner != null && userId != expectedOwner) throw SessionChangedException()
        val pinned = requestSession
        val client = if (longRunning) streamHttp else http
        currentCoroutineContext().ensureActive()
        if (requestSession != pinned) throw SessionChangedException()
        val first = sendReply(client, build(bearer()))
        currentCoroutineContext().ensureActive()
        if (requestSession != pinned) throw SessionChangedException()
        if (first.code != 401) return first
        val token = refreshedToken(pinned) ?: return first
        currentCoroutineContext().ensureActive()
        if (requestSession != pinned) throw SessionChangedException()
        val retry = sendReply(client, build("Bearer $token"))
        currentCoroutineContext().ensureActive()
        if (requestSession != pinned) throw SessionChangedException()
        return retry
    }

    private fun bearer(): String = "Bearer ${accessToken ?: SupabaseConfig.PUBLISHABLE_KEY}"

    private fun rest(table: String, query: Query = emptyList()): HttpUrl {
        val b = "${SupabaseConfig.URL}/rest/v1/$table".toHttpUrl().newBuilder()
        query.forEach { (k, v) -> b.addQueryParameter(k, v) }
        return b.build()
    }

    private fun Request.Builder.auth(bearer: String): Request.Builder =
        header("apikey", SupabaseConfig.PUBLISHABLE_KEY).header("Authorization", bearer)

    private fun validateOwner(owner: String?) {
        if (owner != null && owner != userId) throw SessionChangedException()
    }

    private fun check(reply: Reply) {
        if (reply.code !in 200..299) throw SupabaseFailure.Http(reply.code, reply.text)
    }

    private fun rows(reply: Reply): List<JSONObject> = Json.rows(Json.parse(reply.text)) ?: emptyList()

    // endregion

    // region PostgREST

    /** A PostgREST select. RLS does the filtering; we never send a user id. */
    suspend fun select(table: String, query: Query): List<JSONObject> {
        val url = rest(table, query)
        val reply = authenticated({ Request.Builder().url(url).auth(it).get().build() })
        check(reply)
        return rows(reply)
    }

    /** ADR 0032 · the AI assistants this account authorized through Supabase Auth's OAuth server. */
    suspend fun oauthGrants(): List<JSONObject> {
        val url = "${SupabaseConfig.URL}/auth/v1/user/oauth/grants".toHttpUrl()
        val reply = authenticated({ Request.Builder().url(url).auth(it).get().build() })
        check(reply)
        return rows(reply)
    }

    suspend fun revokeOAuthGrant(clientId: String) {
        val url = "${SupabaseConfig.URL}/auth/v1/user/oauth/grants".toHttpUrl().newBuilder()
            .addQueryParameter("client_id", clientId).build()
        val reply = authenticated({ Request.Builder().url(url).auth(it).delete().build() })
        if (reply.code !in 200..299 && reply.code != 404) throw SupabaseFailure.Http(reply.code, reply.text)
    }

    /** One object out of a private bucket, with this session's own token. */
    suspend fun storageObject(bucket: String, path: String): ByteArray {
        val b = "${SupabaseConfig.URL}/storage/v1/object".toHttpUrl().newBuilder().addPathSegment(bucket)
        path.split("/").filter { it.isNotEmpty() }.forEach { b.addPathSegment(it) }
        val url = b.build()
        val reply = authenticated({ Request.Builder().url(url).auth(it).get().build() })
        check(reply)
        return reply.body
    }

    /**
     * ⚠️ `returning` is not a convenience: RETURNING has to pass a *select* policy, so on a
     * write-only table a legal insert comes back as an RLS violation.
     */
    suspend fun insert(table: String, rows: List<Any>, returning: Boolean = true,
                       expectedOwner: String? = null): List<JSONObject> {
        validateOwner(expectedOwner)
        val array = Json.array(rows)
        for (i in 0 until array.length()) validateOwner(array.optJSONObject(i)?.optStringOrNull("user_id"))
        val url = rest(table)
        val body = array.toString()
        val reply = authenticated({
            Request.Builder().url(url).auth(it)
                .header("Prefer", if (returning) "return=representation" else "return=minimal")
                .post(body.toRequestBody(JSON)).build()
        })
        check(reply)
        return rows(reply)
    }

    suspend fun insert(table: String, row: Any): List<JSONObject> = insert(table, listOf(row))

    /** An insert that leaves rows already there alone. `onConflict` names the key's columns. */
    suspend fun insertIgnoringDuplicates(table: String, rows: List<Any>, onConflict: String,
                                         expectedOwner: String? = null): List<JSONObject> {
        validateOwner(expectedOwner)
        val array = Json.array(rows)
        for (i in 0 until array.length()) validateOwner(array.optJSONObject(i)?.optStringOrNull("user_id"))
        val url = rest(table, listOf("on_conflict" to onConflict))
        val body = array.toString()
        val reply = authenticated({
            Request.Builder().url(url).auth(it)
                .header("Prefer", "resolution=ignore-duplicates,return=minimal")
                .post(body.toRequestBody(JSON)).build()
        })
        check(reply)
        return emptyList()
    }

    /** An upsert. PostgREST wants the conflict target named. */
    suspend fun upsert(table: String, row: Any, onConflict: String, expectedOwner: String? = null): List<JSONObject> {
        val obj = Json.obj(row)
        validateOwner(expectedOwner ?: obj.optStringOrNull("user_id"))
        val url = rest(table, listOf("on_conflict" to onConflict))
        val body = JSONArray().put(obj).toString()
        val reply = authenticated({
            Request.Builder().url(url).auth(it)
                .header("Prefer", "resolution=merge-duplicates,return=representation")
                .post(body.toRequestBody(JSON)).build()
        })
        check(reply)
        return rows(reply)
    }

    /** A PATCH by primary key. */
    suspend fun patch(table: String, id: String, row: Any, expectedOwner: String? = null): List<JSONObject> =
        patchWhere(table, "id", id, row, expectedOwner)

    /** A PATCH filtered on any column, for tables whose primary key is not `id`. */
    suspend fun patchWhere(table: String, column: String, equals: String, row: Any,
                           expectedOwner: String? = null): List<JSONObject> {
        val obj = Json.obj(row)
        validateOwner(expectedOwner ?: obj.optStringOrNull("user_id"))
        val url = rest(table, listOf(column to "eq.$equals"))
        val body = obj.toString()
        val reply = authenticated({
            Request.Builder().url(url).auth(it).header("Prefer", "return=representation")
                .patch(body.toRequestBody(JSON)).build()
        })
        check(reply)
        return rows(reply)
    }

    /** A DELETE filtered on one column. RLS keeps it to the caller's own rows. */
    suspend fun deleteWhere(table: String, column: String, equals: String, expectedOwner: String? = null) {
        validateOwner(expectedOwner)
        val url = rest(table, listOf(column to "eq.$equals"))
        val reply = authenticated({ Request.Builder().url(url).auth(it).delete().build() })
        check(reply)
    }

    /** An exact row count, from the Content-Range header rather than by pulling the rows. */
    suspend fun count(table: String, query: Query = emptyList()): Int? {
        val url = rest(table, query + ("select" to "user_id"))
        val reply = try {
            authenticated({
                Request.Builder().url(url).auth(it).header("Prefer", "count=exact").header("Range", "0-0").get().build()
            })
        } catch (e: Exception) {
            if (e is CancellationException && e !is SessionChangedException) throw e
            return null
        }
        val range = reply.headers["content-range"] ?: return null
        return range.substringAfterLast('/').toIntOrNull()
    }

    /**
     * A PostgREST RPC. Returns the parsed JSON: JSONObject, JSONArray, Number, String,
     * Boolean, or an empty JSONObject when the body is not JSON (Swift returned `[:]`).
     */
    suspend fun rpc(name: String, args: Map<String, Any?> = emptyMap(), expectedOwner: String? = null,
                    timeoutSeconds: Long = 30): Any {
        if (expectedOwner != null && userId != expectedOwner) throw SessionChangedException()
        val url = "${SupabaseConfig.URL}/rest/v1/rpc/$name".toHttpUrl()
        val body = Json.obj(args).toString()
        val client = if (timeoutSeconds == 30L) http else http.newBuilder()
            .callTimeout(timeoutSeconds, TimeUnit.SECONDS).build()
        val pinned = requestSession
        val build: (String) -> Request = { Request.Builder().url(url).auth(it).post(body.toRequestBody(JSON)).build() }
        var reply = sendReply(client, build(bearer()))
        if (requestSession != pinned) throw SessionChangedException()
        if (reply.code == 401) {
            val token = refreshedToken(pinned)
            if (token != null) {
                if (requestSession != pinned) throw SessionChangedException()
                reply = sendReply(client, build("Bearer $token"))
                if (requestSession != pinned) throw SessionChangedException()
            }
        }
        check(reply)
        return Json.parse(reply.text) ?: JSONObject()
    }

    // endregion

    // region Edge Functions

    private fun functionUrl(path: String): HttpUrl {
        val b = "${SupabaseConfig.functionsBase}/$path".toHttpUrl().newBuilder()
        // 2026-09-21 · the asr route is pinned to Singapore (docs/STATUS.md).
        if (path == "asr" && SupabaseConfig.functionsBase.toHttpUrl().host.endsWith(".supabase.co")) {
            b.addQueryParameter("forceFunctionRegion", "ap-southeast-1")
        }
        return b.build()
    }

    private fun Request.Builder.functionHeaders(path: String, bearer: String): Request.Builder {
        auth(bearer)
        if (path == "asr") header("x-region", "ap-southeast-1")
        return this
    }

    suspend fun callFunction(name: String, payload: Any, expectedOwner: String? = null): JSONObject {
        if (expectedOwner != null && userId != expectedOwner) throw SessionChangedException()
        val body = Json.obj(payload).toString()
        val url = functionUrl(name)
        val reply = try {
            authenticated({
                Request.Builder().url(url).functionHeaders(name, it).post(body.toRequestBody(JSON)).build()
            })
        } catch (e: CancellationException) {
            throw e
        } catch (e: SupabaseFailure) {
            throw e
        } catch (e: Exception) {
            throw SupabaseFailure.Transport(e)
        }
        check(reply)
        return Json.parse(reply.text) as? JSONObject ?: JSONObject()
    }

    /** A multipart POST to an Edge Function. */
    suspend fun uploadFunction(name: String, file: File, field: String, filename: String, mime: String,
                               requestId: String = UUID.randomUUID().toString()): JSONObject {
        val url = functionUrl(name)
        val boundary = "nb-${UUID.randomUUID()}"
        val reply = authenticated({ bearer ->
            val multipart = MultipartBody.Builder(boundary).setType(MultipartBody.FORM)
                .addFormDataPart(field, filename, file.asRequestBody(mime.toMediaType()))
                .build()
            Request.Builder().url(url).functionHeaders(name, bearer)
                .header("Idempotency-Key", requestId.lowercase())
                .post(multipart).build()
        }, longRunning = true)
        check(reply)
        return Json.parse(reply.text) as? JSONObject ?: JSONObject()
    }

    /**
     * Streams an Edge Function's SSE response. Each frame is yielded as "<event>\n<data>".
     */
    fun streamFunction(name: String, payload: Any, expectedOwner: String? = null,
                       requestId: String = UUID.randomUUID().toString()): Flow<String> = callbackFlow {
        validateOwner(expectedOwner)
        val pinned = requestSession
        val body = Json.obj(payload).toString()
        val url = functionUrl(name)
        fun build(bearer: String) = Request.Builder().url(url).functionHeaders(name, bearer)
            .header("Idempotency-Key", requestId.lowercase())
            .post(body.toRequestBody(JSON)).build()
        val job = launch(Dispatchers.IO) {
            try {
                var call = streamHttp.newCall(build(bearer()))
                var response = call.execute()
                if (response.code == 401) {
                    response.close()
                    val token = refreshedToken(pinned) ?: throw SupabaseFailure.Http(401, "")
                    call = streamHttp.newCall(build("Bearer $token"))
                    response = call.execute()
                }
                response.use { r ->
                    if (r.code !in 200..299) {
                        throw SupabaseFailure.Http(r.code, r.body?.string()?.take(16_384) ?: "")
                    }
                    val source = r.body?.source() ?: return@use
                    var event = "message"
                    while (true) {
                        val line = source.readUtf8Line() ?: break
                        if (requestSession != pinned) throw SessionChangedException()
                        if (line.startsWith("event:")) { event = line.drop(6).trim(); continue }
                        if (!line.startsWith("data:")) continue
                        val data = line.drop(5).trim()
                        if (data == "[DONE]") break
                        send("$event\n$data")
                        event = "message"
                    }
                }
                close()
            } catch (e: Throwable) {
                close(e)
            }
        }
        awaitClose { job.cancel() }
    }

    // endregion
}

/** Random nonces (port of AppleSignIn.swift's `Nonce`). */
object Nonce {
    private const val CHARSET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._"
    fun random(length: Int = 32): String {
        val bytes = ByteArray(length)
        SecureRandom().nextBytes(bytes)
        return String(CharArray(length) { CHARSET[(bytes[it].toInt() and 0xff) % CHARSET.length] })
    }

    fun sha256(input: String): String =
        MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
}
