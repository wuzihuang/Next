package com.nextbody.hoop.features.auth

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.nextbody.hoop.app.AppLifecycle
import com.nextbody.hoop.app.MainActivity
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.app.SheetRoute
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.data.Defaults
import com.nextbody.hoop.data.SessionStore
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.services.Analytics
import com.nextbody.hoop.services.DemoAccount
import com.nextbody.hoop.services.GoogleAuth
import com.nextbody.hoop.services.Reachability
import com.nextbody.hoop.services.ReviewAccount
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.services.SupabaseFailure
import com.nextbody.hoop.ui.ArrowGlyph
import com.nextbody.hoop.ui.BackspaceGlyph
import com.nextbody.hoop.ui.ChevronGlyph
import com.nextbody.hoop.ui.Chrome
import com.nextbody.hoop.ui.EnvelopeGlyph
import com.nextbody.hoop.ui.GoogleGlyph
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.Haptics
import com.nextbody.hoop.ui.NotificationFeedback
import com.nextbody.hoop.ui.swiftSpring
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.ceil

// MARK: - gate kit · shared by the four gate packages (auth · connect · consent · onboarding)

/** Fire-and-forget, the way Swift's `Task { await Analytics… }` outlives the view. */
internal fun track(name: String, props: Map<String, Any?> = emptyMap()) {
    AppLifecycle.scope.launch { Analytics.track(name, props) }
}

/** SwiftUI `.lineSpacing(x)` on top of the face's own line height (≈ 1.25 × size). */
internal fun TextStyle.lineSpacing(extra: Float): TextStyle {
    val size = fontSize.value
    return copy(lineHeight = (size * 1.25f + extra).sp)
}

/** One text, SwiftUI defaults: no ellipsis, wraps, colour separate from style. */
@Composable
internal fun GText(
    text: String,
    style: TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    align: TextAlign? = null,
    maxLines: Int = Int.MAX_VALUE,
) {
    Text(text = text, modifier = modifier, style = style, color = color, textAlign = align,
        maxLines = maxLines, softWrap = maxLines > 1)
}

/** `Button { } .buttonStyle(.plain)`: no ripple, the label dims while pressed. */
internal fun Modifier.plainTap(enabled: Boolean = true, onClick: () -> Unit): Modifier = composed {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    this
        // A disabled `.plain` SwiftUI button fades its label on top of whatever opacity the label
        // sets itself; measured off the simulator at ~0.46.
        .alpha(if (!enabled) 0.46f else if (pressed) 0.6f else 1f)
        .clickable(interactionSource = source, indication = null, enabled = enabled, onClick = onClick)
}

/** The 44pt round back key every gate header shares. */
@Composable
internal fun GateBackKey(onBack: () -> Unit) {
    Box(
        Modifier.size(44.dp).background(NB.carbon4, CircleShape).border(1.dp, NB.hairline, CircleShape)
            .plainTap(onClick = onBack),
        contentAlignment = Alignment.Center,
    ) { ChevronGlyph() }
}

/** The gate pages live inside the safe area; the ground reaches every edge. */
@Composable
internal fun GatePage(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize().background(NB.carbon)) {
        Box(Modifier.fillMaxSize().systemBarsPadding()) { content() }
    }
}

internal fun Context.findActivity(): Activity? {
    var c: Context? = this
    while (c is ContextWrapper) {
        if (c is Activity) return c
        c = c.baseContext
    }
    return null
}

// MARK: - 01 · 登录注册 Sign In

/**
 * 01 · 登录注册 Sign In. Gate → Email → Code → brand animation.
 * The word "sign up" appears nowhere: the server decides new vs returning, not the user.
 * Android has no Apple door: Google is the solid primary, email the outlined second.
 */
@Composable
fun SignInFlow() {
    val session = GateSession.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    var step by remember { mutableStateOf(Step.gate) }
    var email by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var resendIn by remember { mutableIntStateOf(60) }
    // Which door is waiting on the server. Nothing on the gate may look tappable while a
    // sign-in is in flight, and the door the finger chose is the one that has to say so.
    var busy by remember { mutableStateOf<Door?>(null) }
    // Eight seconds in, the copy stops implying it is nearly there. The request is *not*
    // abandoned: we keep waiting, we just stop pretending.
    var slow by remember { mutableStateOf(false) }
    var slowTimer by remember { mutableStateOf<Job?>(null) }
    var googleJob by remember { mutableStateOf<Job?>(null) }
    // The account facts, asked for exactly once and awaited by whichever arrives last.
    var gateTask by remember { mutableStateOf<Deferred<AccountGate>?>(null) }
    var playingWordmark by remember { mutableStateOf(false) }
    // 01 edges · 「出错的时候，不清屏」. The email and the digits are never cleared by an error.
    var codeError by remember { mutableStateOf<CodeError?>(null) }
    var sending by remember { mutableStateOf(false) }
    var authFailed by remember { mutableStateOf(DebugEdgeFlag.on("authfail")) }
    // 02M ◇5 · where the film hands the screen over.
    var nextStage by remember { mutableStateOf(SessionStore.Stage.gateConnect) }

    LaunchedEffect(Unit) {
        when (DebugEnv["NB_DEBUG_SIGN_STEP"]) {
            "email" -> {
                if (email.isEmpty()) email = DebugEnv["NB_DEBUG_EMAIL"] ?: "you@nextbody.app"
                if (DebugEdgeFlag.on("ratelimited")) codeError = CodeError.rateLimited
                if (DebugEdgeFlag.on("nonetwork")) codeError = CodeError.noNetwork
                if (DebugEdgeFlag.on("sending")) sending = true
                step = Step.email
            }
            "code" -> {
                if (email.isEmpty()) email = DebugEnv["NB_DEBUG_EMAIL"] ?: "you@nextbody.app"
                listOf("wrongcode" to CodeError.wrong, "locked" to CodeError.locked, "expired" to CodeError.expired,
                    "ratelimited" to CodeError.rateLimited, "nonetwork" to CodeError.noNetwork)
                    .forEach { (k, v) -> if (DebugEdgeFlag.on(k)) codeError = v }
                step = Step.code
            }
            "wordmark" -> playingWordmark = true
        }
    }

    fun beginWait(door: Door) {
        busy = door
        slow = false
        slowTimer?.cancel()
        slowTimer = scope.launch {
            delay(8_000)
            if (busy == door) slow = true
        }
    }

    fun endWait() {
        slowTimer?.cancel()
        slowTimer = null
        busy = null
        slow = false
    }

    fun finish() {
        session.email = email
        session.isSignedIn = true
        session.stage = nextStage
    }

    /** The one moment this product is handed a real name. A name already on the server wins. */
    fun adoptName(raw: String?, existingOnServer: String?) {
        val name = raw?.trim().orEmpty()
        if (name.isEmpty()) return
        if ((existingOnServer ?: "").trim().isNotEmpty()) return
        DataStore.profile = DataStore.profile.copy(name = name)
        AppLifecycle.scope.launch { GateRepository.saveDisplayName(name) }
    }

    /**
     * The one tail every door shares. The film starts *before* the facts arrive: a fresh
     * registration is knowable from the token itself, so 2.6 s of designed motion covers the fetch.
     */
    suspend fun completeSignIn(offeredName: String?) {
        val gate = AppLifecycle.scope.async { GateRepository.fetchAccountGate() }
        gateTask = gate
        if (SupabaseClient.isNewUser && claimFilmForToday()) playingWordmark = true
        val facts = gate.await()
        nextStage = facts.stage
        track("AUTH_SUCCESS", mapOf("IS_NEW_USER" to facts.isFirstRun))
        adoptName(offeredName, facts.displayName)
        // The film owns the hand-off when it is up; finishing here too would cut it short.
        if (!playingWordmark) finish()
    }

    fun signInWithGoogle() {
        if (DebugEdgeFlag.on("authfail")) { authFailed = true; return }
        if (busy != null) return
        val activity = context.findActivity() ?: MainActivity.current
        if (activity == null) { authFailed = true; return }
        beginWait(Door.google)
        googleJob = scope.launch {
            track("AUTH_METHOD_TAP", mapOf("METHOD" to "GOOGLE"))
            try {
                val name = GoogleAuth.signIn(activity)
                email = SupabaseClient.signedInEmail() ?: ""
                completeSignIn(name)
                endWait()
            } catch (e: GoogleAuth.Failure.Cancelled) {
                // 01 edge 5 · a cancel on the system sheet is silent.
                endWait()
            } catch (e: CancellationException) {
                endWait()
                throw e
            } catch (e: Exception) {
                android.util.Log.w("NBAuth", "Google sign-in failed: $e", e)
                endWait()
                authFailed = true
            }
        }
    }

    // The browser fallback has no cancel callback: coming back to the app with no redirect
    // on its way is the cancel, and it is as silent as the system sheet's.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val obs = LifecycleEventObserver { _, e ->
            if (e == Lifecycle.Event.ON_RESUME && busy == Door.google && !GoogleAuth.hasNativeClient) {
                scope.launch {
                    delay(3_000)
                    if (busy == Door.google && !SupabaseClient.isSignedIn) googleJob?.cancel()
                }
            }
        }
        lifecycle.addObserver(obs)
        onDispose { lifecycle.removeObserver(obs) }
    }

    fun sendCode() {
        codeError = null
        if (AuthLock.isLocked(email)) {
            codeError = CodeError.locked
            step = Step.code
            return
        }
        // 01 edge 3 · five a hour per email; the sixth sends nothing and explains nothing more.
        val key = "nb.auth.sends.${email.lowercase()}"
        val now = System.currentTimeMillis() / 1000.0
        val sends = (Defaults.getString(key) ?: "").split(',').mapNotNull { it.toDoubleOrNull() }
            .filter { now - it < 3600 }
        fun recordSend() = Defaults.putString(key, (sends + now).joinToString(","))
        if ((sends.size >= 5 && !hasNoMailbox(email)) || DebugEdgeFlag.on("ratelimited")) {
            codeError = CodeError.rateLimited; return
        }
        // 01 edge 4 · no network: the button turns to Sending in place, 8 s, then one line.
        if (!Reachability.isOnline || DebugEdgeFlag.on("nonetwork")) {
            sending = true
            scope.launch {
                delay(8_000)
                sending = false
                codeError = CodeError.noNetwork
            }
            return
        }
        // The seeded demo account and the App Review account have no mailbox: they skip the
        // mail and verify signs in with a password. Everyone else gets a real code.
        if (hasNoMailbox(email)) {
            recordSend()
            track("AUTH_CODE_SENT")
            step = Step.code; resendIn = 60
            if (DebugEdgeFlag.on("expired")) codeError = CodeError.expired
            return
        }
        sending = true
        scope.launch {
            try {
                SupabaseClient.requestCode(email)
                recordSend()
                sending = false
                track("AUTH_CODE_SENT")
                step = Step.code
                resendIn = 60
                if (DebugEdgeFlag.on("expired")) codeError = CodeError.expired
            } catch (e: CancellationException) {
                throw e
            } catch (e: SupabaseFailure.Http) {
                sending = false
                codeError = if (e.code == 429) CodeError.rateLimited else CodeError.noNetwork
            } catch (e: Exception) {
                sending = false
                codeError = CodeError.noNetwork
            }
        }
    }

    /** 01 edge 1 · red outline, a 6 px shake, one haptic, then back to the first cell. */
    fun rejectCode() {
        Haptics.notification(NotificationFeedback.Error)
        val locked = AuthLock.registerWrong(email)
        codeError = if (locked) CodeError.locked else CodeError.wrong
        track("AUTH_CODE_ERROR", mapOf("REASON" to if (locked) "LOCKED" else "WRONG"))
        scope.launch {
            delay(420)
            code = ""
        }
    }

    /** The second the code checks out there is no toast and no tick — the pixels just fall. */
    fun verify() {
        if (busy != null) return
        if (AuthLock.isLocked(email)) { codeError = CodeError.locked; return }
        if (DebugEdgeFlag.on("wrongcode")) { rejectCode(); return }
        beginWait(Door.email)
        scope.launch {
            try {
                when {
                    // The six digits are the review account's password.
                    ReviewAccount.matches(email) -> SupabaseClient.signIn(ReviewAccount.email, code)
                    isDemo(email) -> SupabaseClient.signIn(DemoAccount.email, DemoAccount.password)
                    else -> SupabaseClient.verifyCode(email, code)
                }
                AuthLock.clearWrongs(email)
                // The button stays in its verifying state across the one question the
                // returning path asks the server, so nothing sits dead on screen.
                completeSignIn(null)
                endWait()
            } catch (e: CancellationException) {
                throw e
            } catch (e: SupabaseFailure.Http) {
                endWait()
                // 01 edge 2 · a code past its ten minutes says so and offers a new one.
                when {
                    GateDecision.isExpiredCode(e.code, e.body) -> codeError = CodeError.expired
                    e.code == 429 -> codeError = CodeError.rateLimited
                    else -> rejectCode()
                }
            } catch (e: Exception) {
                endWait()
                codeError = CodeError.noNetwork
            }
        }
    }

    // The film ends on its own clock; it waits on the same task rather than starting a second.
    fun filmFinished() {
        scope.launch {
            gateTask?.let { nextStage = it.await().stage }
            finish()
        }
    }

    // Android back = the screen's own back key.
    BackHandler(enabled = step != Step.gate && !playingWordmark) {
        if (step == Step.code) { track("AUTH_DROP", mapOf("STEP" to "CODE")); step = Step.email }
        else { track("AUTH_DROP", mapOf("STEP" to "EMAIL")); step = Step.gate }
    }

    val waitPreview: Door? = if (DebugEdgeFlag.on("waitauth") || DebugEdgeFlag.on("slowauth")) Door.google else null

    Box(Modifier.fillMaxSize()) {
        GatePage {
            when (step) {
                Step.gate -> GateScreen(
                    failed = authFailed, busy = waitPreview ?: busy,
                    slow = if (waitPreview != null) DebugEdgeFlag.on("slowauth") else slow,
                    onEmail = {
                        if (busy == null) {
                            track("AUTH_METHOD_TAP", mapOf("METHOD" to "EMAIL"))
                            step = Step.email
                        }
                    },
                    onGoogle = { signInWithGoogle() },
                )
                Step.email -> EmailScreen(
                    email = email, onEmail = { email = it }, sending = sending, error = codeError,
                    onBack = { track("AUTH_DROP", mapOf("STEP" to "EMAIL")); step = Step.gate },
                    onSend = { sendCode() },
                )
                Step.code -> CodeScreen(
                    email = email, code = code, onCode = { code = it },
                    resendIn = resendIn, onTick = { if (resendIn > 0) resendIn -= 1 },
                    verifying = busy == Door.email, slow = slow, error = codeError,
                    onBack = { track("AUTH_DROP", mapOf("STEP" to "CODE")); step = Step.email },
                    onVerify = { verify() },
                    onNewCode = { codeError = null; code = ""; sendCode() },
                )
            }
        }
        // ◇1 · 「不是渐亮，是通电」. No transition on purpose: the flash *is* the cut.
        if (playingWordmark) {
            WordmarkAnimation(onFinish = { filmFinished() })
        }
    }
}

private enum class Step { gate, email, code }
internal enum class Door { google, email }
internal enum class CodeError { wrong, locked, expired, rateLimited, noNetwork }

internal fun isDemo(email: String): Boolean = Band.allowsSeed && DemoAccount.matches(email)
internal fun hasNoMailbox(email: String): Boolean = isDemo(email) || ReviewAccount.matches(email)

/**
 * 02M · 「首次注册成功后」. The film plays once, for the session the server itself calls new,
 * and at most once in a day. 「不许倒放、不许循环、更不许当加载动画反复用」.
 */
private fun claimFilmForToday(): Boolean {
    val key = "nb.wordmark.playedOn"
    val today = LocalDate.now().atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
    if (Defaults.getLong(key) == today) return false
    Defaults.putLong(key, today)
    return true
}

// MARK: 01 · 授权入口 Gate

@Composable
private fun GateScreen(
    failed: Boolean,
    busy: Door?,
    slow: Boolean,
    onEmail: () -> Unit,
    onGoogle: () -> Unit,
) {
    LaunchedEffect(Unit) { track("AUTH_GATE_VIEW") }
    val label = NBFont.ui(500, 15f).tracking(0.02f)
    Box(Modifier.fillMaxSize()) {
        // The aurora is the page's ground, not a panel on it: it reaches the physical top edge.
        GateAurora(
            overhang = Chrome.statusBarBlock,
            modifier = Modifier.offset(y = -Chrome.statusBarBlock)
                .requiredSize(NB.Layout.screenWidth, 520.dp + Chrome.statusBarBlock)
                .align(Alignment.TopCenter),
        )
        Column(Modifier.fillMaxSize()) {
            Spacer(Modifier.height(Chrome.gateTopInset))
            Column(
                Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 246.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(9.dp), verticalAlignment = Alignment.Top) {
                    GText(L("NEXTBODY"), NBFont.brand(800, 46f).tracking(-0.045f), NB.text1, maxLines = 1)
                    Box(Modifier.padding(top = 6.dp).size(9.dp).background(NB.lime1, RoundedCornerShape(2.dp)))
                }
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    GText(L("Find your next body."), NBFont.ui(300, 21f).tracking(0.02f), NB.white.copy(alpha = 0.82f))
                    GText(L("SLEEP · LOAD · READINESS"), NBFont.dot(600, 11f).tracking(0.3f), NB.white.copy(alpha = 0.62f))
                }
            }
            Spacer(Modifier.weight(1f))
            Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                GateButton(solid = true, dimmed = busy != null && busy != Door.google, disabled = busy != null,
                    onClick = onGoogle) {
                    if (busy == Door.google) {
                        GateSpinner(NB.carbon.copy(alpha = 0.55f))
                        GText(L(if (slow) "Still connecting" else "Signing in"), label, NB.carbon.copy(alpha = 0.6f))
                    } else {
                        GoogleGlyph()
                        GText(L("Continue with Google"), label, NB.carbon)
                    }
                }
                GateButton(solid = false, dimmed = busy != null, disabled = busy != null, onClick = onEmail) {
                    if (busy == Door.email) {
                        GateSpinner(NB.text1.copy(alpha = 0.55f))
                        GText(L(if (slow) "Still connecting" else "Signing in"), label, NB.text1.copy(alpha = 0.7f))
                    } else {
                        EnvelopeGlyph()
                        GText(L("Continue with email"), label, NB.text1)
                    }
                }
                // 01 edge 5 · only a token that really failed says so; a cancel is silent.
                if (failed) {
                    Row(Modifier.padding(top = 4.dp).fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
                        verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(6.dp).background(NB.alert2, CircleShape))
                        GText(L("Sign-in failed. Try email instead."), NBFont.ui(400, 14f).tracking(0.01f), NB.white.copy(alpha = 0.78f))
                    }
                }
            }
            // Terms sit under the buttons: tapping one is the consent, there is no checkbox.
            LegalLine(Modifier.fillMaxWidth().padding(horizontal = 40.dp).padding(top = 22.dp))
            Spacer(Modifier.height(12.dp))
        }
    }
}

/** The 4×4 LED field with one lime bloom behind the wordmark, fading into carbon by y520. */
@Composable
fun GateAurora(overhang: Dp = 0.dp, modifier: Modifier = Modifier) {
    val dot = hex(0x15151B)
    Canvas(modifier.clipToBounds().drawWithCache {
        // ~15k LEDs: built once per size, not per frame.
        val u = density
        val step = 4f * u
        val side = 3.2f * u
        val field = androidx.compose.ui.graphics.Path()
        var y = 1f * u
        while (y < size.height) {
            var x = 1f * u
            while (x < size.width) {
                field.addRoundRect(androidx.compose.ui.geometry.RoundRect(x, y, x + side, y + side, CornerRadius(0.8f * u)))
                x += step
            }
            y += step
        }
        onDrawBehind { drawPath(field, dot) }
    }) {
        val u = density
        // Ellipse 460 × 360, centred 1pt right of the page centre, 188pt down (+ overhang).
        val cx = size.width / 2 + 1f * u
        // The ellipse is laid out centred in the ZStack, then offset.
        val ellipseCy = (360f * u) / 2 + (188f * u + overhang.toPx())
        val brush = Brush.radialGradient(
            0f to NB.lime1.copy(alpha = 0.16f), 0.55f to NB.lime1.copy(alpha = 0.05f), 1f to NB.lime1.copy(alpha = 0f),
            center = Offset(cx, ellipseCy), radius = 230f * u,
        )
        drawOval(brush, topLeft = Offset(cx - 230f * u, ellipseCy - 180f * u), size = Size(460f * u, 360f * u))
        val fadeTop = size.height - 220f * u
        drawRect(
            Brush.verticalGradient(
                0f to NB.carbon.copy(alpha = 0f), 0.5f to NB.carbon.copy(alpha = 0.75f), 1f to NB.carbon,
                startY = fadeTop, endY = size.height,
            ),
            topLeft = Offset(0f, fadeTop), size = Size(size.width, 220f * u),
        )
    }
}

@Composable
private fun GateButton(
    solid: Boolean,
    dimmed: Boolean,
    disabled: Boolean,
    onClick: () -> Unit,
    content: @Composable () -> Unit,
) {
    // The two doors not being used step back rather than disappear.
    val a by animateFloatAsState(if (dimmed) 0.45f else 1f, tween(180, easing = com.nextbody.hoop.ui.SwiftEaseOut), label = "dim")
    Row(
        Modifier.fillMaxWidth().height(56.dp).alpha(a)
            .background(if (solid) NB.white else NB.carbon4, CircleShape)
            .let { if (!solid) it.border(1.dp, NB.hairline, CircleShape) else it }
            .plainTap(enabled = !disabled, onClick = onClick),
        horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) { content() }
}

/** The one waiting mark on these screens: a quarter ring, 0.9 s a turn. */
@Composable
internal fun GateSpinner(color: Color) {
    val t = rememberInfiniteTransition(label = "spin")
    val deg by t.animateFloat(0f, 360f, infiniteRepeatable(tween(900, easing = LinearEasing), RepeatMode.Restart), label = "deg")
    Canvas(Modifier.size(14.dp)) {
        rotate(deg) {
            val w = 2.dp.toPx()
            drawArc(color, -90f, 90f, false, topLeft = Offset(w / 2, w / 2),
                size = Size(size.width - w, size.height - w), style = Stroke(w, cap = StrokeCap.Round))
        }
    }
}

/** The two lime words open the documents they name. */
@Composable
private fun LegalLine(modifier: Modifier = Modifier) {
    val text: AnnotatedString = buildAnnotatedString {
        withStyle(SpanStyle(color = NB.text3Prod)) { append(L("By continuing you agree to our ")) }
        withLink(LinkAnnotation.Clickable("terms") { Router.sheet = SheetRoute.About }) {
            withStyle(SpanStyle(color = NB.lime1)) { append(L("Terms")) }
        }
        withStyle(SpanStyle(color = NB.text3Prod)) { append(L(" and ")) }
        withLink(LinkAnnotation.Clickable("privacy") { Router.sheet = SheetRoute.Privacy }) {
            withStyle(SpanStyle(color = NB.lime1)) { append(L("Privacy Policy")) }
        }
    }
    Text(text, modifier, style = NBFont.ui(400, 12.5f).tracking(0.02f), textAlign = TextAlign.Center)
}

// MARK: 02 · 邮箱 Email

private val emailPattern = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")

@Composable
private fun EmailScreen(
    email: String,
    onEmail: (String) -> Unit,
    sending: Boolean,
    error: CodeError?,
    onBack: () -> Unit,
    onSend: () -> Unit,
) {
    val valid = emailPattern.matches(email)
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    // The keyboard rises with the screen (board: 「键盘随屏起」): the Send pill rides above the
    // IME, and the two reason rows are what give up their room (clipped, never the pill).
    Column(Modifier.fillMaxSize().imePadding()) {
        Spacer(Modifier.height(Chrome.gateTopInset))
        StepBar(L("STEP 01 / 02"), onBack)
        Column(Modifier.fillMaxWidth().weight(1f).clipToBounds()) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 44.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            GText(L("Your email"), NBFont.ui(500, 32f).tracking(0.01f), NB.text1)
            GText(L("We'll send a 6-digit code.\nNo password to set."),
                NBFont.ui(300, 15f).tracking(0.02f).lineSpacing(24f - 15f), NB.text2)
        }
        Column(Modifier.padding(horizontal = 24.dp).padding(top = 38.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            GText(L("EMAIL ADDRESS"), NBFont.ui(500, 11f).tracking(0.24f), NB.text3Prod)
            val shape = RoundedCornerShape(NB.R.chip)
            // The caret opens at the end of what is already there, as UITextField does.
            var field by remember { mutableStateOf(TextFieldValue(email, TextRange(email.length))) }
            if (field.text != email) field = TextFieldValue(email, TextRange(email.length))
            BasicTextField(
                value = field,
                onValueChange = { field = it; onEmail(it.text) },
                singleLine = true,
                textStyle = NBFont.ui(400, 17f).tracking(0.01f).copy(color = NB.text1),
                cursorBrush = SolidColor(NB.lime1),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false,
                    keyboardType = KeyboardType.Email, imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = { if (valid) onSend() }),
                modifier = Modifier.fillMaxWidth().height(62.dp).focusRequester(focus)
                    .background(NB.carbon4, shape).border(1.dp, NB.lime1.copy(alpha = 0.42f), shape),
                decorationBox = { inner ->
                    Box(Modifier.fillMaxSize().padding(horizontal = 20.dp), contentAlignment = Alignment.CenterStart) { inner() }
                },
            )
            // Not selling points — an answer to "why should I give you my email".
            Column(Modifier.padding(top = 22.dp)) {
                Box {
                    ReasonRow(lit = true, text = L("A code signs you in — nothing to remember"))
                    Hairline(modifier = Modifier.align(Alignment.BottomStart))
                }
                ReasonRow(lit = false, text = L("Used only for sign-in and your weekly report"))
            }
        }
        }
        Spacer(Modifier.height(12.dp))
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(18.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            // 01 edge 3 · the sixth send in an hour: one sentence, nothing about the address.
            if (error == CodeError.rateLimited) {
                Column(Modifier.fillMaxWidth().padding(horizontal = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(6.dp).background(NB.caution2, CircleShape))
                        GText(L("5 SENT · 1H WINDOW"), NBFont.dot(600, 11f).tracking(0.24f), NB.caution2)
                    }
                    GText(L("You've hit the limit. Try again in an hour."), NBFont.ui(400, 14.5f).tracking(0.01f), NB.white.copy(alpha = 0.78f))
                }
            }
            Row(
                Modifier.fillMaxWidth().height(56.dp).alpha(if (valid) 1f else 0.55f)
                    .background(if (valid) NB.lime1.copy(alpha = if (sending) 0.28f else 1f) else NB.carbon4, CircleShape)
                    .let { if (!valid) it.border(1.dp, NB.hairline, CircleShape) else it }
                    .plainTap(enabled = valid && !sending, onClick = onSend),
                horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (sending) {
                    // 01 edge 4 · Sending, in place, 8 s; the address is not touched.
                    Canvas(Modifier.size(14.dp)) {
                        val w = 2.dp.toPx()
                        drawCircle(NB.carbon.copy(alpha = 0.55f), radius = size.width / 2 - w / 2, style = Stroke(w))
                        drawArc(NB.carbon, -90f, 90f, false, topLeft = Offset(w / 2, w / 2),
                            size = Size(size.width - w, size.height - w), style = Stroke(w))
                    }
                    GText(L("Sending"), NBFont.ui(500, 15f).tracking(0.01f), NB.carbon.copy(alpha = 0.6f))
                } else {
                    GText(L("Send code"), NBFont.ui(500, 15f).tracking(0.06f), NB.carbon)
                    ArrowGlyph(color = NB.carbon)
                }
            }
            if (error == CodeError.noNetwork) {
                GText(L("No connection. Your code wasn't sent."), NBFont.ui(400, 13.5f).tracking(0.01f), NB.alert1,
                    Modifier.fillMaxWidth().padding(horizontal = 8.dp))
            }
            GText(L("Use Google instead"), NBFont.ui(400, 13f).tracking(0.02f), NB.text3Prod,
                Modifier.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onBack))
        }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun ReasonRow(lit: Boolean, text: String) {
    Row(Modifier.fillMaxWidth().height(52.dp), horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(6.dp).background(if (lit) NB.lime1 else NB.white.copy(alpha = 0.22f), RoundedCornerShape(2.dp)))
        GText(text, NBFont.ui(300, 14f).tracking(0.02f), NB.text2, Modifier.weight(1f))
        Spacer(Modifier.width(0.dp)) // 12 + 0, as SwiftUI spaces before the trailing Spacer
    }
}

// MARK: 03 · 验证码 Code

@Composable
private fun CodeScreen(
    email: String,
    code: String,
    onCode: (String) -> Unit,
    resendIn: Int,
    onTick: () -> Unit,
    verifying: Boolean,
    slow: Boolean,
    error: CodeError?,
    onBack: () -> Unit,
    onVerify: () -> Unit,
    onNewCode: () -> Unit,
) {
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    // The code step has its own keypad: the email step's system keyboard must not linger over it.
    val keyboard = LocalSoftwareKeyboardController.current
    val focusManager = LocalFocusManager.current
    LaunchedEffect(Unit) { focusManager.clearFocus(); keyboard?.hide() }
    LaunchedEffect(Unit) {
        while (isActive) {
            delay(1_000)
            onTick()
            now = System.currentTimeMillis()
        }
    }
    val shake = remember { Animatable(0f) }
    LaunchedEffect(error) {
        if (error == CodeError.wrong || error == CodeError.locked) {
            // 01 edge 1 · a 6 px horizontal shake, once.
            repeat(5) { i -> shake.animateTo(if (i % 2 == 0) 6f else 0f, tween(60, easing = LinearEasing)) }
            delay(20)
            shake.snapTo(0f)
        }
    }
    val lockLine: String = run {
        @Suppress("UNUSED_EXPRESSION") now
        val left = AuthLock.remaining(email) ?: return@run L("Too many tries. Try again in 15:00.")
        val seconds = ceil(left).toInt()
        L("Too many tries. Try again in %02d:%02d.", seconds / 60, seconds % 60)
    }
    val clipboard = LocalClipboardManager.current
    val full = code.length == 6

    Column(Modifier.fillMaxSize()) {
        Spacer(Modifier.height(Chrome.gateTopInset))
        StepBar(L("STEP 02 / 02"), onBack)
        Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 44.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)) {
            GText(L("Enter the code"), NBFont.ui(500, 32f).tracking(0.01f), NB.text1)
            Row {
                GText(L("Sent to "), NBFont.ui(300, 15f).tracking(0.02f), NB.text2)
                GText(email, NBFont.ui(400, 15f).tracking(0.02f), NB.lime1, maxLines = 1)
            }
        }
        CodeBoxes(code, error == CodeError.wrong || error == CodeError.locked,
            Modifier.padding(horizontal = 24.dp).padding(top = 40.dp)
                .offset { IntOffset((shake.value * density).toInt(), 0) }
                // Paste: the custom keypad stays on screen, so a long press takes the code
                // off the clipboard instead of the system keyboard.
                .pointerInputLongPress {
                    val digits = clipboard.getText()?.text.orEmpty().filter { it.isDigit() }.take(6)
                    if (digits.isNotEmpty()) {
                        onCode(digits)
                        if (digits.length == 6) onVerify()
                    }
                })
        // 01 edges 1 / 2 · the line under the cells. Expired is not red — it is not an error.
        if (error != null) {
            val expired = error == CodeError.expired
            val line = when (error) {
                CodeError.wrong -> L("That code didn't work.")
                CodeError.locked -> lockLine
                CodeError.expired -> L("That code has expired.")
                else -> ""
            }
            GText(line, NBFont.ui(if (expired) 300 else 400, if (expired) 13.5f else 14f).copy(letterSpacing = (0.01f * 14f).sp),
                if (expired) NB.white.copy(alpha = 0.50f) else NB.alert1,
                Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 14.dp))
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 26.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            val s = NBFont.ui(400, 13.5f).tracking(0.02f)
            GText(L("Didn't get it?"), s, NB.text3Prod)
            if (resendIn > 0) {
                GText(L("Resend in"), s, NB.white.copy(alpha = 0.34f))
                GText(String.format(java.util.Locale.US, "%02d:%02d", resendIn / 60, resendIn % 60),
                    NBFont.dot(700, 13.5f).tracking(0.14f), NB.lime1)
            } else {
                GText(L("Resend"), NBFont.ui(500, 13.5f), NB.lime1, Modifier.plainTap(onClick = onNewCode))
            }
        }
        Spacer(Modifier.weight(1f))
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(18.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            // The button only reports state and catches the edge case — the sixth box submits.
            if (error == CodeError.expired) {
                // 01 edge 2 · the primary becomes the one step that fixes it; the address stays.
                Box(Modifier.fillMaxWidth().height(56.dp).background(NB.lime1, CircleShape).plainTap(onClick = onNewCode),
                    contentAlignment = Alignment.Center) {
                    GText(L("Get a new code"), NBFont.ui(500, 15f).tracking(0.01f), NB.carbon)
                }
            } else {
                Row(
                    Modifier.fillMaxWidth().height(56.dp)
                        .background(if (full) NB.lime1 else NB.carbon4, CircleShape)
                        .let { if (!full) it.border(1.dp, NB.hairline, CircleShape) else it },
                    horizontalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterHorizontally),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (verifying) GateSpinner(NB.carbon.copy(alpha = 0.55f))
                    GText(if (verifying) L(if (slow) "Still connecting" else "Verifying") else L("Verify and continue"),
                        NBFont.ui(500, 15f).tracking(0.06f), if (full) NB.carbon else NB.white.copy(alpha = 0.38f))
                }
            }
            GText(L("Use a different email"), NBFont.ui(400, 13f).tracking(0.02f), NB.text3Prod,
                Modifier.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onBack))
        }
        Keypad(
            onDigit = { d ->
                if (code.length < 6) {
                    val next = code + d
                    onCode(next)
                    if (next.length == 6) onVerify()
                }
            },
            onDelete = { if (code.isNotEmpty()) onCode(code.dropLast(1)) },
            modifier = Modifier.padding(horizontal = 6.dp).padding(top = 26.dp),
        )
        Spacer(Modifier.height(16.dp))
    }
}

private fun Modifier.pointerInputLongPress(onLong: () -> Unit): Modifier =
    this.pointerInput(Unit) { detectTapGestures(onLongPress = { onLong() }) }

@Composable
private fun CodeBoxes(code: String, error: Boolean, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        for (i in 0 until 6) {
            val filled = i < code.length
            val isCursor = i == code.length
            val shape = RoundedCornerShape(16.dp)
            val fill = when {
                error -> NB.alert2.copy(alpha = 0.06f)
                isCursor -> NB.lime1.copy(alpha = 0.07f)
                i > code.length -> NB.carbon2
                else -> NB.carbon4
            }
            val stroke = when {
                error -> NB.alert2
                isCursor -> NB.lime1.copy(alpha = 0.70f)
                else -> NB.hairline
            }
            Box(
                Modifier.size(50.dp, 64.dp).background(fill, shape)
                    .border(if (error || isCursor) 1.5.dp else 1.dp, stroke, shape),
                contentAlignment = Alignment.Center,
            ) {
                when {
                    filled -> GText(code[i].toString(), NBFont.dot(800, 32f).tracking(0.02f), NB.text1)
                    isCursor -> BlinkingCaret(26.dp)
                    else -> Box(Modifier.size(8.dp, 2.dp).background(NB.white.copy(alpha = 0.18f), RoundedCornerShape(1.dp)))
                }
            }
        }
    }
}

@Composable
fun BlinkingCaret(height: Dp = 22.dp) {
    val t = rememberInfiniteTransition(label = "caret")
    val a by t.animateFloat(1f, 0f, infiniteRepeatable(tween(550, easing = com.nextbody.hoop.ui.SwiftEaseInOut), RepeatMode.Reverse), label = "a")
    Box(Modifier.size(2.dp, height).alpha(a).background(NB.lime1))
}

@Composable
private fun Keypad(onDigit: (String) -> Unit, onDelete: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for (row in listOf(listOf("1", "2", "3"), listOf("4", "5", "6"), listOf("7", "8", "9"))) {
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (d in row) Key(d, Modifier.weight(1f)) { onDigit(d) }
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Spacer(Modifier.weight(1f).height(46.dp))
            Key(L("0"), Modifier.weight(1f)) { onDigit("0") }
            Box(Modifier.weight(1f).height(46.dp).plainTap(onClick = onDelete), contentAlignment = Alignment.Center) {
                BackspaceGlyph()
            }
        }
    }
}

@Composable
private fun Key(label: String, modifier: Modifier, action: () -> Unit) {
    Box(modifier.height(46.dp).background(NB.smokeKey, RoundedCornerShape(NB.R.key)).plainTap(onClick = action),
        contentAlignment = Alignment.Center) {
        GText(label, NBFont.ui(400, 24f).tracking(0.01f), NB.text1)
    }
}

@Composable
fun StepBar(step: String, onBack: () -> Unit) {
    Row(Modifier.fillMaxWidth().height(46.dp).padding(horizontal = 16.dp).padding(top = 2.dp),
        verticalAlignment = Alignment.CenterVertically) {
        GateBackKey(onBack)
        Spacer(Modifier.width(16.dp)) // 8 + 0 + 8, as SwiftUI spaces around the Spacer
        Spacer(Modifier.weight(1f))
        GText(step, NBFont.dot(600, 11f).tracking(0.3f), NB.text3Prod)
    }
}
