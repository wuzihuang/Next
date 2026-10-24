package com.nextbody.hoop.features.onboarding

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandConnectionState
import com.nextbody.hoop.band.BandError
import com.nextbody.hoop.band.BandEvent
import com.nextbody.hoop.band.BodyCompositionReading
import com.nextbody.hoop.band.MeasurementProgress
import com.nextbody.hoop.band.MeasurementResult
import com.nextbody.hoop.band.PersonalInfo
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.data.Defaults
import com.nextbody.hoop.data.SessionStore
import com.nextbody.hoop.data.WeighIn
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.auth.AccountGate
import com.nextbody.hoop.features.auth.GText
import com.nextbody.hoop.features.auth.GateBackKey
import com.nextbody.hoop.features.auth.GatePage
import com.nextbody.hoop.features.auth.GateRepository
import com.nextbody.hoop.features.auth.GateSession
import com.nextbody.hoop.features.auth.OnboardingDraft
import com.nextbody.hoop.features.auth.lineSpacing
import com.nextbody.hoop.features.auth.plainTap
import com.nextbody.hoop.features.auth.startInstant
import com.nextbody.hoop.features.auth.track
import com.nextbody.hoop.features.connect.LimePillButton
import com.nextbody.hoop.features.consent.ConsentScreen
import com.nextbody.hoop.features.measure.BodyScanPrepareLayout
import com.nextbody.hoop.features.measure.BodyScanScanningLayout
import com.nextbody.hoop.features.measure.BodyScanState
import com.nextbody.hoop.features.measure.HoopFigure
import com.nextbody.hoop.features.measure.HoopFigureMode
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.Goal
import com.nextbody.hoop.model.MeasurementSource
import com.nextbody.hoop.services.ConsentStore
import com.nextbody.hoop.services.HealthService
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.ui.Chrome
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.Period
import java.util.UUID
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * 03 · Onboarding 建档与基线. Two counters, kept apart: ABOUT YOU 01–03 and BASELINE 01–03.
 * The back key works inside a 段 only; once the scan starts it disappears.
 * The whole BASELINE 段 is skippable.
 *
 * Android: the Health step reads height and weight from Health Connect. Health Connect has no
 * record for sex or date of birth, so those two are always typed — and when Health Connect is
 * missing, refused or empty (the usual case) all four are, on the same sheets.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnboardingFlow() {
    val session = GateSession.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var didEnter by remember { mutableStateOf(false) }

    // 补屏 A · Consent comes first: before Health Connect's dialog, before the first band read.
    var step by remember { mutableStateOf(initialStep()) }
    // 03 rule 02 · which of the four fields has a value at all, and where each came from.
    var filled by remember { mutableStateOf(if (DebugEdgeFlag.on("outofrange")) setOf("sex", "born", "height", "weight") else emptySet()) }
    var synced by remember { mutableStateOf(false) }
    var sheet by remember { mutableStateOf<OnbSheet?>(null) }
    var underage by remember { mutableStateOf(false) }

    var sex by remember { mutableStateOf("Female") }
    var born by remember { mutableStateOf(LocalDate.of(1998, 6, 12)) }
    var heightCm by remember { mutableDoubleStateOf(172.0) }
    var weightKg by remember { mutableDoubleStateOf(63.0) }
    var heightFromHealth by remember { mutableStateOf(false) }
    var weightFromHealth by remember { mutableStateOf(false) }
    var bornFromHealth by remember { mutableStateOf(false) }
    var sexFromHealth by remember { mutableStateOf(false) }
    var goal by remember { mutableStateOf(Goal.cut) }
    // 03 · what the band returned on the scanning screen; the baseline screen prints it.
    var baseline by remember { mutableStateOf<BodyCompositionReading?>(null) }
    var syncing by remember { mutableStateOf(false) }

    /** F2 §05 · the band's BIA multiplies by the weight we push down — the one just confirmed. */
    fun personalInfo() = PersonalInfo(heightCm = heightCm.roundToInt(), weightKg = weightKg.roundToInt(),
        birthYear = born.year, sexIsMale = sex == "Male", targetStep = DataStore.profile.stepGoal)

    /** 06 rule 09 · the baseline is stored like any other scan. */
    fun store(r: BodyCompositionReading) {
        DataStore.addWeighIn(WeighIn(id = UUID.randomUUID(), date = Instant.now(), weightKg = r.inputWeightKg,
            bodyFatPercent = r.bodyFatPercent, source = MeasurementSource.measured, origin = WeighIn.Origin.band))
        DataStore.today = DataStore.today.copy(fatKg = r.fatMassKg, leanKg = r.leanMassKg,
            fatSource = MeasurementSource.measured, scans7d = DataStore.today.scans7d + 1)
        DataStore.bodyFatPercent = r.bodyFatPercent
        scope.launch { GateRepository.recordBodyComposition(r) }
    }

    fun enter() {
        if (didEnter) return
        didEnter = true
        track("ONBOARD_DONE")
        DataStore.profile = DataStore.profile.copy(heightCm = heightCm, goal = goal, sexIsMale = sex == "Male",
            birthdate = born.startInstant())
        DataStore.today = DataStore.today.copy(weightKg = weightKg)
        // ⚠️ These four numbers only ever lived in memory; without this write a real account
        // stayed at "——" on every tile. What the user typed is marked `edit`; what Health
        // Connect gave is not, so a later sync may still refresh it (F3 §02.3).
        val edited = buildList {
            if (!sexFromHealth) add("sex")
            if (!bornFromHealth) add("birth_date")
            if (!heightFromHealth) add("height_cm")
        }
        val saved = DataStore.profile
        com.nextbody.hoop.app.AppLifecycle.scope.launch { GateRepository.saveProfile(saved, edited) }
        // The confirmed weight is the day's weigh-in when the scan was skipped.
        if (baseline == null) {
            DataStore.addWeighIn(WeighIn(id = UUID.randomUUID(), date = Instant.now(), weightKg = weightKg,
                bodyFatPercent = null, source = MeasurementSource.measured,
                origin = if (weightFromHealth) WeighIn.Origin.health else WeighIn.Origin.manual))
        }
        SupabaseClient.currentUserId?.let { OnboardingDraft.clear(it) }
        session.stage = SessionStore.Stage.root
    }

    fun apply(draft: OnboardingDraft) {
        sex = draft.sex
        born = runCatching { LocalDate.of(draft.year, draft.month, draft.day) }.getOrDefault(born)
        heightCm = draft.heightCm
        weightKg = draft.weightKg
        filled = draft.filled.toSet()
        synced = draft.synced
        sexFromHealth = draft.sexFromHealth
        bornFromHealth = draft.bornFromHealth
        heightFromHealth = draft.heightFromHealth
        weightFromHealth = draft.weightFromHealth
        Goal.entries.firstOrNull { it.raw == draft.goal }?.let { goal = it }
    }

    fun apply(facts: AccountGate) {
        facts.sex?.let { sex = if (it == "male") "Male" else "Female"; filled = filled + "sex" }
        facts.heightCm?.let { heightCm = it; filled = filled + "height" }
        facts.birthDate?.let { born = it; filled = filled + "born" }
        facts.weightKg?.let { weightKg = it; filled = filled + "weight" }
        facts.goal?.let { goal = it }
    }

    fun persistDraft() {
        val userId = SupabaseClient.currentUserId ?: return
        val persistStep = if (step == OnbStep.scanning) OnbStep.fingersOn else step
        OnboardingDraft(userId = userId, step = persistStep.name, sex = sex, year = born.year, month = born.monthValue,
            day = born.dayOfMonth, heightCm = heightCm, weightKg = weightKg, filled = filled.toList(), synced = synced,
            sexFromHealth = sexFromHealth, bornFromHealth = bornFromHealth, heightFromHealth = heightFromHealth,
            weightFromHealth = weightFromHealth, goal = goal.raw).save()
    }

    /**
     * F1 KILLED MID-GATE / PROFILE GAP. A draft on this account, or a partial profiles row,
     * lands on ABOUT YOU 02 with the values still in.
     */
    LaunchedEffect(Unit) {
        session.ensureSession()
        track("ONBOARD_ENTER")
        if (DebugEdgeFlag.name != null) return@LaunchedEffect
        if (DebugEnv["NB_DEBUG_ONB_STEP"] != null || DebugEnv["NB_DEBUG_SCAN_LEFT"] != null) return@LaunchedEffect
        if (Defaults.getBoolean(RESUME_KEY)) {
            Defaults.remove(RESUME_KEY)
            return@LaunchedEffect
        }
        val userId = SupabaseClient.currentUserId
        val draft = userId?.let { OnboardingDraft.load(it) }
        if (draft != null) {
            apply(draft)
            if (ConsentStore.decided) {
                val restored = OnbStep.entries.firstOrNull { it.name == draft.step } ?: OnbStep.confirm
                step = when (restored) {
                    OnbStep.scanning, OnbStep.baseline -> OnbStep.fingersOn
                    OnbStep.consent -> if (draft.filled.isEmpty()) OnbStep.healthSync else OnbStep.confirm
                    else -> restored
                }
            }
            return@LaunchedEffect
        }
        val facts = GateRepository.fetchAccountGate()
        if (facts.profileComplete) {
            SupabaseClient.currentUserId?.let { OnboardingDraft.clear(it) }
            session.stage = SessionStore.Stage.root
            return@LaunchedEffect
        }
        if (facts.hasAnyProfileField || facts.weightKg != null) {
            apply(facts)
            if (ConsentStore.decided) step = OnbStep.confirm
        }
    }
    // `.onChange(of:)` — not on the first composition, which would write the defaults over the
    // draft the restore above is about to read.
    var armed by remember { mutableStateOf(false) }
    LaunchedEffect(step, filled) {
        if (armed) persistDraft() else armed = true
    }

    /** 02 · the system sheet, then one read. Only the values that came back are marked as Health's. */
    suspend fun readFromHealth() {
        val b = HealthService.readBaseline()
        b.sexIsMale?.let { sex = if (it) "Male" else "Female"; sexFromHealth = true; filled = filled + "sex" }
        b.born?.let { born = it; bornFromHealth = true; filled = filled + "born" }
        b.heightCm?.let { heightCm = it; heightFromHealth = true; filled = filled + "height" }
        b.weightKg?.let { weightKg = it; weightFromHealth = true; filled = filled + "weight" }
        synced = !b.isEmpty
        if (synced) DataStore.profile = DataStore.profile.copy(appleHealthLinked = true)
        track("HEALTH_PROMPT", mapOf("GRANTED_FIELDS" to filled.size))
        syncing = false
        step = OnbStep.confirm
    }

    // Health Connect's own permission sheet (iOS: HealthKit's). Refused or empty is not an
    // error: the confirm screen opens with ADD on every field it could not fill.
    val healthLauncher = rememberLauncherForActivityResult(HealthService.permissionContract()) { granted ->
        HealthService.onPermissionResult(granted)
        scope.launch { readFromHealth() }
    }

    fun syncFromHealth() {
        if (syncing) return
        syncing = true
        scope.launch {
            if (!HealthService.requestRead()) {
                // Not on this phone. Where Play can install it, that is the one way forward;
                // otherwise the values are typed.
                syncing = false
                if (HealthService.installable) { HealthService.openInstallPage(context); return@launch }
                track("HEALTH_PROMPT", mapOf("GRANTED_FIELDS" to 0))
                step = OnbStep.confirm
                return@launch
            }
            if (HealthService.hasPermissions()) readFromHealth()
            else runCatching { healthLauncher.launch(HealthService.readPermissions) }.onFailure { readFromHealth() }
        }
    }

    fun age(of: LocalDate): Int = Period.between(of, LocalDate.now()).years

    // Android back = the screen's own back key, where it has one.
    BackHandler(enabled = sheet == null && !underage && step in setOf(OnbStep.confirm, OnbStep.goal, OnbStep.fingersOn)) {
        step = when (step) {
            OnbStep.confirm -> OnbStep.healthSync
            OnbStep.goal -> OnbStep.confirm
            else -> OnbStep.goal
        }
    }
    BackHandler(enabled = underage) { underage = false }

    // Declining (the chevron) is not a dead end — the rest of onboarding still runs. The consent
    // screen draws its own ground under the status bar, so it sits outside the safe-area page.
    if (step == OnbStep.consent) {
        ConsentScreen(onContinue = { step = OnbStep.healthSync }, onBack = { step = OnbStep.healthSync })
    } else GatePage {
        Box(Modifier.fillMaxSize()) {
            when (step) {
                OnbStep.consent -> {}
                OnbStep.healthSync -> HealthSync(syncing = syncing, onSync = { syncFromHealth() }, onManual = { step = OnbStep.confirm })
                OnbStep.confirm -> ConfirmScreen(
                    sex = sex, onSexToggle = { sex = if (sex == "Female") "Male" else "Female" },
                    born = born, heightCm = if (DebugEdgeFlag.on("outofrange")) 40.0 else heightCm, weightKg = weightKg,
                    heightFromHealth = heightFromHealth, weightFromHealth = weightFromHealth,
                    bornFromHealth = bornFromHealth, sexFromHealth = sexFromHealth,
                    filled = filled, nothingSynced = !synced,
                    onSexTap = { filled = filled + "sex" },
                    onBack = { step = OnbStep.healthSync },
                    onEdit = { sheet = it },
                    // F5 C5 · judged on 03/02 Looks right, not live on the birthday wheel.
                    onNext = { if (age(born) < 16) underage = true else step = OnbStep.goal },
                )
                OnbStep.goal -> GoalScreen(goal, { goal = it }, onBack = { step = OnbStep.confirm }, onNext = { step = OnbStep.fingersOn })
                OnbStep.fingersOn -> FingersOn(onBack = { step = OnbStep.goal }, onStart = { step = OnbStep.scanning }, onSkip = {
                    track("SCAN_SKIP", mapOf("REASON" to "USER"))
                    enter()
                })
                OnbStep.scanning -> ScanningScreen(
                    info = personalInfo(),
                    onDone = { r -> baseline = r; store(r); step = OnbStep.baseline },
                    onSkip = { track("SCAN_SKIP", mapOf("REASON" to "FAILED")); enter() },
                    onSkipEarly = { track("SCAN_SKIP", mapOf("REASON" to "USER")); enter() },
                    onReconnect = {
                        // 03 edge 3 · reuse the whole pairing chain, then come back to BASELINE 01.
                        Defaults.putBoolean(RESUME_KEY, true)
                        session.stage = SessionStore.Stage.gateConnect
                    },
                    // S1's back lands on the last interactive step — FingersOn would only re-arm
                    // the battery gate and bounce straight back here.
                    onBack = { step = OnbStep.goal },
                )
                OnbStep.baseline -> BaselineScreen(baseline) { enter() }
            }
            // F5 · D08 — the 16 gate is caught on the birthday screen, not buried in the terms.
            if (underage) AgeGate { underage = false }
        }
    }

    // The three value sheets: 62% of the screen, carbon2, the panel radius, a grabber.
    sheet?.let { route ->
        val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
        ModalBottomSheet(
            onDismissRequest = { sheet = null },
            sheetState = state,
            containerColor = NB.carbon2,
            contentColor = NB.text1,
            scrimColor = Color.Black.copy(alpha = 0.45f),
            shape = RoundedCornerShape(topStart = NB.R.panel, topEnd = NB.R.panel),
            dragHandle = { BottomSheetDefaults.DragHandle(color = NB.white.copy(alpha = 0.3f)) },
            contentWindowInsets = { WindowInsets(0) },
        ) {
            Box(Modifier.fillMaxWidth().height(ScreenMetrics.height * 0.62f)) {
                when (route) {
                    OnbSheet.weight -> WeightRulerSheet(weightKg) { v ->
                        weightKg = v; weightFromHealth = false; filled = filled + "weight"; sheet = null
                    }
                    OnbSheet.height -> HeightRulerSheet(heightCm) { v ->
                        heightCm = v; heightFromHealth = false; filled = filled + "height"; sheet = null
                    }
                    OnbSheet.birthday -> BirthdayWheelSheet(born, onSave = { d ->
                        born = d; bornFromHealth = false; filled = filled + "born"; sheet = null
                    }, onCancel = { sheet = null })
                }
            }
        }
    }
}

private const val RESUME_KEY = "nb.onboarding.resumeAtBaseline"

internal enum class OnbStep { consent, healthSync, confirm, goal, fingersOn, scanning, baseline }
internal enum class OnbSheet { height, weight, birthday }

/** 03 edge 3 · after the band dropped mid-scan and Connect ran again, resume at BASELINE 01. */
private fun initialStep(): OnbStep {
    DebugEnv["NB_DEBUG_ONB_STEP"]?.let { raw -> OnbStep.entries.firstOrNull { it.name == raw }?.let { return it } }
    if (Defaults.getBoolean(RESUME_KEY)) {
        Defaults.remove(RESUME_KEY)
        return OnbStep.fingersOn
    }
    if (DebugEdgeFlag.on("nothingsynced") || DebugEdgeFlag.on("outofrange")) return OnbStep.confirm
    if (DebugEdgeFlag.on("lowbattery")) return OnbStep.fingersOn
    if (DebugEdgeFlag.on("lifted") || DebugEdgeFlag.on("banddropped") || DebugEdgeFlag.on("nocontact")) return OnbStep.scanning
    return if (ConsentStore.decided) OnbStep.healthSync else OnbStep.consent
}

// MARK: shared

@Composable
private fun OnbHeader(counter: String, onBack: (() -> Unit)? = null) {
    Row(Modifier.width(NB.Layout.contentWidth).height(44.dp), verticalAlignment = Alignment.CenterVertically) {
        if (onBack != null) GateBackKey(onBack) else Spacer(Modifier.size(44.dp))
        Spacer(Modifier.width(16.dp)) // 8 + 0 + 8, as SwiftUI spaces around the Spacer
        Spacer(Modifier.weight(1f))
        GText(counter, NBFont.dot(600, 11f).tracking(0.3f), NB.text3Prod)
    }
}

@Composable
private fun OnbTitle(title: String, sub: String, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(start = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        GText(title, NBFont.ui(500, 32f).tracking(0.01f), NB.text1)
        GText(sub, NBFont.ui(300, 15f).tracking(0.02f).lineSpacing(24f - 15f), NB.text2, Modifier.width(320.dp))
    }
}

@Composable
private fun OnbPage(
    counter: String,
    title: String,
    sub: String,
    onBack: (() -> Unit)? = null,
    cta: String,
    ctaEnabled: Boolean = true,
    onCTA: () -> Unit,
    footnote: String? = null,
    onFootnote: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(Chrome.gateTopInset))
        OnbHeader(counter, onBack)
        OnbTitle(title, sub, Modifier.padding(top = 24.dp))
        Column(Modifier.padding(top = 28.dp), horizontalAlignment = Alignment.CenterHorizontally, content = content)
        Spacer(Modifier.weight(1f))
        LimePillButton(cta, enabled = ctaEnabled, action = onCTA)
        if (footnote != null) {
            // Plain text on the board (no dot, no state) — but a real button underneath.
            GText(footnote, NBFont.ui(300, 13f).tracking(0.02f), NB.white.copy(alpha = 0.42f),
                Modifier.padding(top = 16.dp).plainTap { onFootnote?.invoke() })
        }
        Spacer(Modifier.height(10.dp))
    }
}

// MARK: 01 · 读档案 Health sync

/**
 * Health Connect gives height and weight only, so those are the two chips. Once granted they
 * never turn back — "Enter manually instead" is plain text with no dot and no state.
 */
@Composable
private fun HealthSync(syncing: Boolean, onSync: () -> Unit, onManual: () -> Unit) {
    val chips = listOf("HEIGHT", "WEIGHT")
    OnbPage(
        counter = L("ABOUT YOU 01 / 03"),
        title = L("First, about you"),
        sub = L("We can pull height and weight straight from Health Connect."),
        cta = L("Sync from Health Connect"), ctaEnabled = !syncing, onCTA = onSync,
        footnote = L("Enter manually instead"), onFootnote = onManual,
    ) {
        Column(Modifier.fillMaxWidth().padding(top = 40.dp), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(22.dp)) {
            HealthMark()
            GText(L("Health Connect"), NBFont.ui(400, 13f).tracking(0.02f), NB.text2)
            Row(Modifier.padding(top = 60.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (c in chips) {
                    Box(Modifier.height(26.dp).border(1.dp, NB.hairline, CircleShape).padding(horizontal = 12.dp),
                        contentAlignment = Alignment.Center) {
                        GText(L(c), NBFont.dot(600, 9f).tracking(0.16f), NB.text3Prod)
                    }
                }
            }
        }
    }
}

/** The health source's tile: a white rounded square and a heart, drawn rather than a brand asset. */
@Composable
private fun HealthMark() {
    Canvas(Modifier.size(92.dp)) {
        val s = size.width / 92f
        drawRoundRect(Color.White, Offset.Zero, size, CornerRadius(21f * s))
        val heart = Path().apply {
            moveTo(46f * s, 66f * s)
            cubicTo(30f * s, 55f * s, 22f * s, 46f * s, 22f * s, 37f * s)
            cubicTo(22f * s, 29f * s, 28f * s, 24f * s, 35f * s, 24f * s)
            cubicTo(40f * s, 24f * s, 44f * s, 27f * s, 46f * s, 31f * s)
            cubicTo(48f * s, 27f * s, 52f * s, 24f * s, 57f * s, 24f * s)
            cubicTo(64f * s, 24f * s, 70f * s, 29f * s, 70f * s, 37f * s)
            cubicTo(70f * s, 46f * s, 62f * s, 55f * s, 46f * s, 66f * s)
            close()
        }
        drawPath(heart, Brush.verticalGradient(listOf(hex(0xFF5F8A), hex(0xFF2D55)), 24f * s, 66f * s))
    }
}

// MARK: 02 · 对答案 Confirm

@Composable
private fun ConfirmScreen(
    sex: String,
    onSexToggle: () -> Unit,
    born: LocalDate,
    heightCm: Double,
    weightKg: Double,
    heightFromHealth: Boolean,
    weightFromHealth: Boolean,
    bornFromHealth: Boolean,
    sexFromHealth: Boolean,
    filled: Set<String>,
    nothingSynced: Boolean,
    onSexTap: () -> Unit,
    onBack: () -> Unit,
    onEdit: (OnbSheet) -> Unit,
    onNext: () -> Unit,
) {
    // 03 edge 5 · outside 90–230 cm / 25–250 kg is not an error, it is probably a slip.
    val heightOut = "height" in filled && heightCm !in 90.0..230.0
    val weightOut = "weight" in filled && weightKg !in 25.0..250.0
    fun tag(field: String, fromHealth: Boolean) = if (fromHealth) "HEALTH" else if (field in filled) "EDIT" else "ADD"
    fun shown(field: String, value: String) = if (field in filled) value else ""
    val bornText = Fmt.displayDate(born.startInstant(), "LLLL yyyy")

    OnbPage(
        counter = L("ABOUT YOU 02 / 03"),
        title = L("Does this look right?"),
        sub = L("Pulled from Health Connect. Tap any value to correct it before we calibrate."),
        onBack = onBack,
        // 03 edge 1 · NOTHING SYNCED: the same screen, values empty, ADD instead of HEALTH, and
        // the key is "Save and continue", dead until all four are in. No error line.
        cta = if (nothingSynced) L("Save and continue") else L("Looks right"),
        ctaEnabled = !nothingSynced || filled.size == 4,
        onCTA = onNext,
        footnote = L("Nothing synced? Just type it in"),
    ) {
        Column(Modifier.width(NB.Layout.contentWidth), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            // Sex has no sheet: two options are not worth a panel, so it toggles in place.
            ValueRow(L("Sex"), shown("sex", L(sex)), tag("sex", sexFromHealth)) {
                if ("sex" in filled) onSexToggle()
                onSexTap()
            }
            ValueRow(L("Born"), shown("born", bornText), tag("born", bornFromHealth)) { onEdit(OnbSheet.birthday) }
            ValueRow(L("Height"), shown("height", "${heightCm.toInt()} cm"), tag("height", heightFromHealth), warn = heightOut) {
                onEdit(OnbSheet.height)
            }
            ValueRow(L("Weight"), shown("weight", String.format(java.util.Locale.US, "%.0f kg", weightKg)),
                tag("weight", weightFromHealth), warn = weightOut) { onEdit(OnbSheet.weight) }
            if (heightOut || weightOut) {
                GText(L("That's outside what we can measure. Check it?"), NBFont.ui(400, 14f).tracking(0.01f), NB.emberPale,
                    Modifier.fillMaxWidth().padding(top = 2.dp))
            }
        }
    }
}

/** Once it has really been edited, the tag reads EDIT for good. */
@Composable
private fun ValueRow(label: String, value: String, tag: String, warn: Boolean = false, action: () -> Unit) {
    val tint = when (tag) { "HEALTH" -> NB.white.copy(alpha = 0.42f); "ADD" -> NB.ember1; else -> NB.lime1 }
    val shape = RoundedCornerShape(NB.R.chip)
    Row(
        Modifier.fillMaxWidth().height(66.dp).background(NB.carbon4, shape)
            .border(if (warn) 1.5.dp else 1.dp, if (warn) NB.ember1 else NB.hairline, shape)
            .plainTap(onClick = action).padding(horizontal = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            GText(label, NBFont.ui(400, 11f).tracking(0.06f), NB.white.copy(alpha = 0.38f))
            GText(value, NBFont.ui(400, 18f).tracking(0.01f), NB.text1, maxLines = 1)
        }
        Spacer(Modifier.width(16.dp))
        Box(
            Modifier.height(22.dp).background(NB.white.copy(alpha = 0.04f), CircleShape)
                .border(1.dp, if (tag == "HEALTH") NB.hairline else tint.copy(alpha = 0.4f), CircleShape)
                .padding(horizontal = 10.dp),
            contentAlignment = Alignment.Center,
        ) { GText(L(tag), NBFont.dot(600, 9f).tracking(0.18f), tint) }
    }
}

// MARK: 03 · 定目标 Goal

private val GOAL_OPTIONS = listOf(
    Triple(Goal.cut, "Lose fat", "Burn more than you take in"),
    Triple(Goal.bulk, "Build muscle", "Fuel the work, protect the gains"),
    Triple(Goal.recomp, "Lose fat + build muscle", "Recomposition — slower, but both"),
)

@Composable
private fun GoalScreen(goal: Goal, onGoal: (Goal) -> Unit, onBack: () -> Unit, onNext: () -> Unit) {
    OnbPage(
        counter = L("ABOUT YOU 03 / 03"),
        title = L("What brings you here?"),
        sub = L("Pick one focus. It sets your daily MOVE and FUEL targets — change it anytime."),
        onBack = onBack,
        cta = L("Continue"), onCTA = onNext,
        footnote = L("You can switch goals later in Profile"),
    ) {
        // The only real question in the whole of onboarding — and the first option is already
        // selected, so Continue is never grey.
        Column(Modifier.width(NB.Layout.contentWidth), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            for ((g, title, sub) in GOAL_OPTIONS) {
                val on = goal == g
                val shape = RoundedCornerShape(NB.R.spec)
                Row(
                    Modifier.fillMaxWidth().height(78.dp)
                        .background(if (on) NB.lime1.copy(alpha = 0.06f) else NB.carbon4, shape)
                        .border(if (on) 1.5.dp else 1.dp, if (on) NB.lime1.copy(alpha = 0.7f) else NB.hairline, shape)
                        .plainTap { onGoal(g) }.padding(horizontal = 18.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        GText(L(title), NBFont.ui(400, 16f).tracking(0.01f), NB.text1)
                        GText(L(sub), NBFont.ui(300, 12.5f).tracking(0.02f), NB.white.copy(alpha = 0.42f))
                    }
                    Spacer(Modifier.width(16.dp))
                    Box(Modifier.size(22.dp).border(1.5.dp, if (on) NB.lime1 else NB.white.copy(alpha = 0.22f), CircleShape),
                        contentAlignment = Alignment.Center) {
                        if (on) Box(Modifier.size(11.dp).background(NB.lime1, CircleShape))
                    }
                }
            }
        }
    }
}

// MARK: 04 · 上手 Fingers on

@Composable
private fun FingersOn(onBack: () -> Unit, onStart: () -> Unit, onSkip: () -> Unit) {
    // 03 edge 4 · gated before the scan starts, not discovered halfway through.
    var lowBattery by remember { mutableStateOf<Int?>(null) }
    LaunchedEffect(Unit) {
        if (DebugEdgeFlag.on("lowbattery")) { lowBattery = 8; return@LaunchedEffect }
        val b = runCatching { Band.live.readBattery() }.getOrNull()
        val p = b?.percent
        if (b != null && b.isPercent && p != null && p < 15) { lowBattery = p; return@LaunchedEffect }
        track("SCAN_START")
        onStart()
    }
    // Same S1 as the re-scan: the hoop waits for a finger, the battery check is the only thing
    // between this screen and the stream — no start button.
    val s = BodyScanState.Waiting
    BodyScanPrepareLayout(
        topInset = Chrome.gateTopInset, bottomInset = 24.dp,
        status = s.status, statusTint = s.statusTint, headline = s.headline, help = s.help,
        header = { OnbHeader(L("BASELINE 01 / 03"), onBack) },
        stage = {
            val lb = lowBattery
            if (lb != null) LowBatteryCard(lb, onSkip) else HoopFigure(HoopFigureMode.waiting, Modifier.fillMaxSize())
        },
        footer = { if (lowBattery == null) BodyScanSkipButton(onSkip) },
    )
}

@Composable
private fun LowBatteryCard(percent: Int, onSkip: () -> Unit) {
    ScanCard {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            BatteryGlyph()
            GText(L("BATTERY %d%%", percent), NBFont.dot(600, 12f).tracking(0.2f), NB.ember1)
        }
        GText(L("Charge the band before the first scan — it needs about 15%."),
            NBFont.ui(400, 14.5f).tracking(0.01f).lineSpacing(6f), NB.white.copy(alpha = 0.80f))
        GText(L("Skip for now, measure later →"), NBFont.ui(500, 14f).tracking(0.02f), NB.lime1,
            Modifier.plainTap {
                track("SCAN_SKIP", mapOf("REASON" to "LOW_BATTERY"))
                onSkip()
            })
    }
}

/** The plain-text skip under the prepare screen's foot rule — gone once a finger is on the key. */
@Composable
private fun BodyScanSkipButton(action: () -> Unit) {
    GText(L("Skip for now, measure later →"), NBFont.ui(300, 13f).tracking(0.02f), NB.white.copy(alpha = 0.42f),
        Modifier.padding(top = 12.dp).plainTap {
            track("SCAN_SKIP", mapOf("REASON" to "USER"))
            action()
        })
}

/** 03 edge 4 · the board's 26 × 13 outline with one amber bar inside. */
@Composable
private fun BatteryGlyph() {
    Canvas(Modifier.size(26.dp, 13.dp)) {
        val u = density
        drawRoundRect(NB.ember1, Offset(0.75f * u, 0.75f * u), Size(size.width - 1.5f * u, size.height - 1.5f * u),
            CornerRadius(3f * u), style = Stroke(1.5f * u))
        drawRoundRect(NB.ember1, Offset(2f * u, (size.height - 7f * u) / 2), Size(4f * u, 7f * u), CornerRadius(1f * u))
    }
}

/** The 176pt card that sits in the stage where the hoop was. */
@Composable
private fun ScanCard(content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val shape = RoundedCornerShape(NB.R.spec)
        Column(
            Modifier.width(NB.Layout.contentWidth).height(176.dp).background(NB.carbon4, shape).border(1.dp, NB.hairline, shape)
                .padding(horizontal = 24.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically),
            content = content,
        )
    }
}

// MARK: 05 · 测量 Scanning

/** The mutable scan state; every writer lands on the object the screen reads. */
@Stable
private class OnbScanModel {
    var remaining by mutableIntStateOf(30)
    /** 06 · body composition progress is the fields themselves (14 of them). */
    var fields by mutableIntStateOf(0)
    /** True once the band has reported the fingers. Until then the screen is S1. */
    var contact by mutableStateOf(false)
    /** Edge 1 · after 5 quiet seconds in waiting the prepare screen turns amber. */
    var nudged by mutableStateOf(false)
    /** 03 edge 2 · a lifted finger holds the count on screen; the band itself starts over. */
    var holding by mutableStateOf(false)
    /** 06 edge 2 · the resume grace, in seconds, counted down while `holding`. */
    var lostGrace by mutableDoubleStateOf(3.0)
    var restarts by mutableIntStateOf(0)
    /** 03 edge 3 · the one edge this screen cannot fix itself. */
    var dropped by mutableStateOf(false)
    /** The SDK ran and said no — its reason, in its words. Retry or skip; never a number. */
    var failure by mutableStateOf<String?>(null)
    var measuring by mutableStateOf(false)
    var halfway by mutableStateOf(false)
    var computing by mutableStateOf(false)
    var startedAt: Instant = Instant.now()
    /** When the band's count last moved — the figure hops from this instant. */
    var beatAt by mutableStateOf(Instant.now())

    val scanState: BodyScanState
        get() = when {
            computing -> BodyScanState.Computing
            holding -> BodyScanState.Lost(lostGrace.roundToInt())
            measuring -> if (halfway) BodyScanState.Halfway else BodyScanState.Counting(fields)
            contact -> BodyScanState.Contact
            nudged -> BodyScanState.Nudge
            else -> BodyScanState.Waiting
        }
}

@Composable
private fun ScanningScreen(
    info: PersonalInfo,
    onDone: (BodyCompositionReading) -> Unit,
    onSkip: () -> Unit,
    onSkipEarly: () -> Unit,
    onReconnect: () -> Unit,
    onBack: () -> Unit,
) {
    val model = remember { OnbScanModel() }
    var attempt by remember { mutableIntStateOf(0) }
    val scope = rememberCoroutineScope()
    var nudgeTask by remember { mutableStateOf<Job?>(null) }
    var graceTask by remember { mutableStateOf<Job?>(null) }

    fun armNudge(after: Long) {
        nudgeTask?.cancel()
        nudgeTask = scope.launch {
            delay(after)
            if (model.failure != null || model.dropped) return@launch
            if (!model.measuring && !model.contact && !model.holding) model.nudged = true
        }
    }
    fun disarmNudge() {
        nudgeTask?.cancel(); nudgeTask = null
        if (model.nudged) model.nudged = false
    }
    /** 06 edge 2 · three seconds of grace, shown as PAUSED, then back at waiting for a finger. */
    fun startGrace() {
        graceTask?.cancel()
        graceTask = scope.launch {
            while (model.lostGrace > 0) {
                delay(1_000)
                if (!model.holding) return@launch
                model.lostGrace -= 1
            }
            if (!model.holding) return@launch
            model.holding = false; model.contact = false; model.halfway = false; model.measuring = false
            model.remaining = 30; model.fields = 0; model.lostGrace = 3.0
            armNudge(5_000)
        }
    }

    /** The scan is the band's. Weight first (F2 §05), then every state is one the SDK reported. */
    suspend fun runScan() {
        model.remaining = 30; model.fields = 0; model.contact = false; model.holding = false; model.halfway = false
        model.computing = false; model.failure = null; model.dropped = false; model.measuring = false; model.lostGrace = 3.0
        model.startedAt = Instant.now()
        disarmNudge()
        try {
            if (Band.live.state != BandConnectionState.connected) Band.live.reconnectIfBound()
            Band.live.syncPersonalInfo(info)
            armNudge(5_000)
            Band.live.measureBodyComposition().collect { s ->
                when (s) {
                    MeasurementProgress.WaitingForContact -> {}
                    MeasurementProgress.Contact -> {
                        graceTask?.cancel(); disarmNudge()
                        model.contact = true; model.holding = false
                    }
                    is MeasurementProgress.Measuring -> {
                        graceTask?.cancel(); disarmNudge()
                        model.fields = min(14, (14 * s.fraction).toInt())
                        val left = s.secondsLeft ?: max(0, 30 - (30 * s.fraction).roundToInt())
                        if (model.remaining != left) model.beatAt = Instant.now()
                        model.contact = true; model.measuring = true; model.holding = false
                        model.halfway = s.fraction >= 0.5
                        model.remaining = left
                    }
                    MeasurementProgress.LostContact -> {
                        // 03 edge 2 · the count holds where it was; the band starts over on contact.
                        disarmNudge(); graceTask?.cancel()
                        model.lostGrace = 3.0
                        model.holding = true; model.restarts += 1
                        startGrace()
                    }
                    is MeasurementProgress.Finished -> {
                        disarmNudge(); graceTask?.cancel()
                        val r = (s.result as? MeasurementResult.BodyComposition)?.reading
                        if (r != null) {
                            model.measuring = false; model.computing = true
                            track("SCAN_DONE", mapOf("MS" to (Instant.now().toEpochMilli() - model.startedAt.toEpochMilli()).toInt(),
                                "RESTARTS" to model.restarts))
                            delay(650)
                            onDone(r)
                        }
                        throw StopScan()
                    }
                    is MeasurementProgress.Failed -> {
                        disarmNudge(); graceTask?.cancel()
                        model.failure = s.reason
                        throw StopScan()
                    }
                }
            }
        } catch (e: StopScan) {
            return
        } catch (e: BandError.NotConnected) {
            disarmNudge(); graceTask?.cancel()
            model.dropped = true
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            disarmNudge(); graceTask?.cancel()
            model.failure = (e as? BandError)?.message ?: "BAND OFFLINE"
        }
    }

    // Leaving the screen cancels this, which ends the stream, which stops the band's test
    // (F1 rule 05). `attempt` re-runs it from the failure card.
    LaunchedEffect(attempt) {
        if (applyDebugScanPin(model)) return@LaunchedEffect
        if (DebugEdgeFlag.on("lifted")) {
            model.remaining = 30; model.contact = true; model.measuring = true
            repeat(3) { delay(1_000); model.remaining -= 1 }
            model.holding = true; delay(3_000); model.holding = false
            repeat(3) { delay(1_000); model.remaining -= 1 }
            model.holding = true; delay(2_000); model.holding = false; model.restarts += 1; model.remaining = 30
            while (model.remaining > 0) { delay(1_000); model.remaining -= 1 }
            return@LaunchedEffect
        }
        if (DebugEdgeFlag.on("banddropped")) {
            delay(2_000); model.dropped = true
            return@LaunchedEffect
        }
        coroutineScope {
            val watch = launch {
                Band.live.events.collect { e ->
                    if (e is BandEvent.State && e.state == BandConnectionState.disconnected) {
                        model.dropped = true
                        throw StopScan()
                    }
                }
            }
            runScan()
            watch.cancel()
        }
    }

    BackHandler(enabled = !(model.contact || model.failure != null || model.dropped || model.measuring || model.holding || model.computing)) {
        onBack()
    }

    val s = model.scanState
    // S1 covers every pre-measure state and the failure / dropped cards; S2 is measuring, held
    // or computing. Both stay mounted; opacity is the swap.
    val showsPrepare = !(model.measuring || model.holding || model.computing)
    Box(Modifier.fillMaxSize()) {
        if (showsPrepare) {
            BodyScanPrepareLayout(
                topInset = Chrome.gateTopInset, bottomInset = 24.dp,
                status = s.status, statusTint = s.statusTint, headline = s.headline, help = s.help,
                header = {
                    // Once the scan starts the back key is gone — you cannot half-measure a body.
                    OnbHeader(L("BASELINE 01 / 03"),
                        if (model.contact || model.failure != null || model.dropped) null else onBack)
                },
                stage = {
                    val failure = model.failure
                    when {
                        failure != null -> ScanCard {
                            GText(failure, NBFont.dot(600, 12f).tracking(0.2f), NB.ember1)
                            GText(L("The band ran the scan and could not finish it.\nNothing you filled in is lost."),
                                NBFont.ui(400, 14.5f).tracking(0.01f).lineSpacing(6f), NB.white.copy(alpha = 0.80f))
                            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                                GText(L("Try again →"), NBFont.ui(500, 14f).tracking(0.02f), NB.lime1,
                                    Modifier.plainTap { attempt += 1 })
                                GText(L("Skip for now"), NBFont.ui(400, 14f).tracking(0.02f), NB.white.copy(alpha = 0.42f),
                                    Modifier.plainTap(onClick = onSkip))
                            }
                        }
                        model.dropped -> ScanCard {
                            GText(L("BAND DISCONNECTED"), NBFont.dot(600, 12f).tracking(0.2f), NB.ember1)
                            GText(L("The band went quiet mid-scan.\nNothing you filled in is lost."),
                                NBFont.ui(400, 14.5f).tracking(0.01f).lineSpacing(6f), NB.white.copy(alpha = 0.80f))
                            GText(L("Reconnect →"), NBFont.ui(500, 14f).tracking(0.02f), NB.lime1, Modifier.plainTap(onClick = onReconnect))
                        }
                        else -> HoopFigure(
                            if (model.nudged) HoopFigureMode.nudge else if (model.contact) HoopFigureMode.contact else HoopFigureMode.waiting,
                            Modifier.fillMaxSize())
                    }
                },
                footer = {
                    if (!model.contact && model.failure == null && !model.dropped) BodyScanSkipButton(onSkipEarly)
                },
            )
        } else {
            BodyScanScanningLayout(
                topInset = Chrome.gateTopInset, bottomInset = 24.dp, headerHeight = 44.dp,
                remaining = model.remaining, held = model.holding,
                status = s.status, statusTint = s.statusTint, headline = s.headline, help = s.help,
                beat = if (model.computing) 30 else 30 - model.remaining,
                total = 30, beatAt = model.beatAt, complete = model.computing,
                header = { OnbHeader(L("BASELINE 02 / 03")) },
            )
        }
    }
}

private class StopScan : CancellationException("scan finished")

/** `NB_DEBUG_SCAN_LEFT=24` freezes the body-fill figure at that remaining second. */
private fun applyDebugScanPin(model: OnbScanModel): Boolean {
    val left = DebugEnv["NB_DEBUG_SCAN_LEFT"]?.toIntOrNull() ?: return false
    model.remaining = left.coerceIn(0, 30)
    model.fields = min(14, (14 * (30 - model.remaining) / 30.0).toInt())
    model.halfway = model.remaining <= 15
    model.contact = true
    model.beatAt = Instant.now()
    val hold = DebugEnv["NB_DEBUG_SCAN_HOLD"] == "1"
    model.measuring = !hold && !DebugEdgeFlag.on("nocontact") && !DebugEdgeFlag.on("banddropped")
    model.holding = hold || DebugEdgeFlag.on("lifted")
    if (model.holding) model.measuring = true
    if (DebugEdgeFlag.on("nocontact")) {
        model.measuring = false; model.holding = false; model.contact = false; model.nudged = true
    }
    if (DebugEdgeFlag.on("banddropped")) {
        model.dropped = true; model.measuring = false; model.holding = false
    }
    return true
}

// MARK: 06 · 交底 Baseline

@Composable
private fun BaselineScreen(reading: BodyCompositionReading?, onEnter: () -> Unit) {
    fun f(v: Double?, decimals: Int = 1): String = v?.let { String.format(java.util.Locale.US, "%.${decimals}f", it) } ?: Fmt.dash
    val r = reading
    // The full twelve the SDK returns, laid out flat — this screen collects, it does not judge.
    val tiles = listOf(
        listOf("FAT MASS", f(r?.fatMassKg), "kg", NB.lime1),
        listOf("LEAN MASS", f(r?.leanMassKg), "kg", NB.lime1),
        listOf("MUSCLE", f(r?.muscleKg), "kg", NB.lime1),
        listOf("MUSCLE RATE", f(r?.muscleRatePercent), "%", NB.lime1),
        listOf("SKELETAL", f(r?.skeletalMusclePercent), "%", NB.lime1),
        listOf("BONE", f(r?.boneKg), "kg", NB.lime1),
        listOf("BODY WATER", f(r?.bodyWaterPercent), "%", NB.cyan1),
        listOf("WATER", f(r?.waterKg), "kg", NB.cyan1),
        listOf("PROTEIN", f(r?.proteinPercent), "%", NB.cyan1),
        listOf("PROTEIN MASS", f(r?.proteinKg), "kg", NB.cyan1),
        listOf("SUBCUT FAT", f(r?.subcutaneousFatPercent), "%", NB.cyan1),
        listOf("BMR ESTIMATE", r?.bmrKcal?.toString() ?: Fmt.dash, "kcal/day", NB.ember1),
    )
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(Chrome.gateTopInset))
        OnbHeader(L("BASELINE 03 / 03"))
        OnbTitle(L("Your baseline"), L("First scan complete — this is day zero."), Modifier.padding(top = 24.dp))
        val cardShape = RoundedCornerShape(NB.R.card)
        Row(
            Modifier.padding(top = 16.dp).width(NB.Layout.contentWidth).height(116.dp).background(NB.carbon4, cardShape)
                .border(1.dp, NB.white.copy(alpha = 0.08f), cardShape),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            HeadlineStat(f(reading?.bodyFatPercent), "%", L("BODY FAT"), NB.lime1, Modifier.weight(1f))
            Box(Modifier.size(1.dp, 72.dp).background(NB.white.copy(alpha = 0.08f)))
            HeadlineStat(f(reading?.bmi), null, L("BMI"), NB.white.copy(alpha = 0.42f), Modifier.weight(1f))
        }
        // Three 114pt columns are exactly the 358 column on the board; on a wider phone they
        // share the content width so the grid still lines up with the card above it.
        Column(Modifier.padding(top = 16.dp).width(NB.Layout.contentWidth), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (row in tiles.chunked(3)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (t in row) BaselineTile(t[0] as String, t[1] as String, t[2] as String, t[3] as Color, Modifier.weight(1f))
                }
            }
        }
        Spacer(Modifier.weight(1f))
        // "Enter NEXTBODY", never "Done" — the end point is the product, not the form.
        LimePillButton(L("Enter NEXTBODY"), action = onEnter)
        GText(L("Scan again anytime from the Device page"), NBFont.ui(300, 13f).tracking(0.02f), NB.white.copy(alpha = 0.42f),
            Modifier.padding(top = 16.dp))
        Spacer(Modifier.height(10.dp))
    }
}

@Composable
private fun HeadlineStat(value: String, unit: String?, label: String, labelTint: Color, modifier: Modifier) {
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            GText(value, NBFont.brand(700, 46f).tracking(-0.045f), NB.white, Modifier.alignByBaseline(), maxLines = 1)
            if (unit != null) GText(unit, NBFont.brand(500, 18f).tracking(-0.01f), NB.white.copy(alpha = 0.42f), Modifier.alignByBaseline())
        }
        GText(L(label), NBFont.dot(600, 10f).tracking(0.24f), labelTint)
    }
}

@Composable
private fun BaselineTile(label: String, value: String, unit: String, tint: Color, modifier: Modifier) {
    val shape = RoundedCornerShape(NB.R.chip)
    Column(
        modifier.height(78.dp).background(NB.carbon4, shape).border(1.dp, NB.white.copy(alpha = 0.06f), shape)
            .padding(start = 14.dp, top = 14.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        GText(L(label), NBFont.dot(600, 9f).tracking(0.16f), tint, maxLines = 1)
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            GText(value, NBFont.brand(600, 21f).tracking(-0.02f), NB.white, Modifier.alignByBaseline(), maxLines = 1)
            GText(unit, NBFont.ui(300, 11f), NB.white.copy(alpha = 0.42f), Modifier.alignByBaseline(), maxLines = 1)
        }
    }
}

/** F5 · D08 — the 16 threshold is enforced on the birthday screen itself. */
@Composable
private fun AgeGate(onBack: () -> Unit) {
    Box(Modifier.fillMaxSize().background(NB.carbon.copy(alpha = 0.94f)).plainTap(enabled = true) {}, contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
            GText(L("NEXTBODY IS 16+"), NBFont.dot(700, 13f).tracking(0.3f), NB.alert2)
            GText(L("We can't create an account for someone under 16."), NBFont.ui(400, 17f).tracking(0.01f), NB.text1,
                Modifier.width(280.dp), align = TextAlign.Center)
            Box(Modifier.size(280.dp, 52.dp).border(1.dp, NB.hairline, CircleShape).plainTap(onClick = onBack),
                contentAlignment = Alignment.Center) {
                GText(L("Change date of birth"), NBFont.ui(500, 15f).tracking(0.06f), NB.text1)
            }
        }
    }
}
