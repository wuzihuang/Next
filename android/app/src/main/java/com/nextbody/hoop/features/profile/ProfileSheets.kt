package com.nextbody.hoop.features.profile

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Intent
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.ui.text.drawText
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.health.connect.client.HealthConnectClient
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.nextbody.hoop.app.AppSession
import com.nextbody.hoop.app.Router
import com.nextbody.hoop.app.SheetRoute
import com.nextbody.hoop.app.Takeover
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.PersonalInfo
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.data.Defaults
import com.nextbody.hoop.data.Ports
import com.nextbody.hoop.data.WeighIn
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.measurements.MeasurementSheet
import com.nextbody.hoop.features.weighin.WeighInDialSheet
import com.nextbody.hoop.features.weighin.WeighInSheet
import com.nextbody.hoop.l10n.AppLanguage
import com.nextbody.hoop.l10n.AppLocale
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.Goal
import com.nextbody.hoop.model.MeasurementSource
import com.nextbody.hoop.data.Profile
import com.nextbody.hoop.services.Analytics
import com.nextbody.hoop.services.HealthService
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.services.saveProfile
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.HapticsSetting
import com.nextbody.hoop.ui.HoldHaptics
import com.nextbody.hoop.ui.cardSkin
import com.nextbody.hoop.ui.hotZoneTap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import kotlin.math.roundToInt

/** Work that has to outlive the sheet that started it (the band's personal-info push). */
private val detached = CoroutineScope(SupervisorJob() + Dispatchers.Main)

/**
 * 11 · the thirteen sheets. New settings default to a sheet; making one a page has to be argued
 * for first. None of them is more than 78% of the screen tall.
 */
@Composable
fun ProfileSheet(route: SheetRoute, close: () -> Unit) {
    Box(Modifier.fillMaxSize().background(NB.carbon2)) {
        when (route) {
            SheetRoute.ProfileEdit -> PersonalInfoSheet(close)
            SheetRoute.Goal -> TrainingGoalSheet(close)
            SheetRoute.Notifications -> NotificationsSheet()
            SheetRoute.Units -> UnitsSheet()
            SheetRoute.Language -> LanguageSheet(close)
            SheetRoute.HealthConnect -> HealthConnectSheet(close)
            SheetRoute.Feedback -> FeedbackSheet(close)
            SheetRoute.Privacy -> LegalSheet(LegalText.Kind.privacy)
            SheetRoute.About -> LegalSheet(LegalText.Kind.terms)
            SheetRoute.DeleteAccount -> DeleteAccountSheet(close)
            SheetRoute.SignOut -> SignOutSheet(close)
            SheetRoute.Widgets -> WidgetsSheet(close)
            SheetRoute.Assistants -> AssistantsSheet(close)
            // The same three the profile reaches; hosted here too so one dispatcher covers them.
            SheetRoute.WeighIn -> WeighInSheet(close)
            SheetRoute.ScanWeighIn -> WeighInDialSheet(close)
            is SheetRoute.Measurement -> MeasurementSheet(route.id, close)
            else -> Unit
        }
    }
}

// MARK: Your details

/**
 * Body inputs remain editable without Health Connect. Profile writes must succeed before
 * closing; manual weights use the durable weigh-in queue and the existing server settlement.
 * Sex and birthday are always typed here — Health Connect has neither.
 */
@Composable
fun PersonalInfoSheet(close: () -> Unit) {
    val data = DataStore
    val scope = rememberCoroutineScope()
    val metric = data.profile.usesMetric

    // `.onAppear` — the sheet opens on what the profile says now.
    val initialWeight = remember {
        data.today.weightKg?.let { kg -> String.format(Locale.US, "%.1f", if (metric) kg else kg * 2.2046226) } ?: ""
    }
    var name by remember { mutableStateOf(data.profile.name) }
    val email = remember { data.profile.email }
    var birthdate by remember { mutableStateOf(data.profile.birthdate) }
    var sexIsMale by remember { mutableStateOf(data.profile.sexIsMale) }
    var saving by remember { mutableStateOf(false) }
    var saveError by remember { mutableStateOf(false) }
    var heightCm by remember { mutableStateOf(data.profile.heightCm) }
    var weightText by remember { mutableStateOf(initialWeight) }
    var stepGoalText by remember { mutableStateOf(data.profile.stepGoal.toString()) }
    var heightSheet by remember { mutableStateOf(false) }
    var heightError by remember { mutableStateOf(false) }
    var weightError by remember { mutableStateOf(false) }
    var stepGoalError by remember { mutableStateOf(false) }

    fun parsedKg(): Double? {
        val raw = weightText.trim().replace("。", ".").replace("．", ".").replace(",", ".")
        val v = raw.toDoubleOrNull() ?: return null
        val kg = if (metric) v else v / 2.2046226
        return if (kg in 20.0..300.0) kg else null
    }

    val heightLabel = if (metric) "${heightCm.roundToInt()} cm" else {
        val inches = (heightCm / 2.54).toInt()
        "${inches / 12}'${inches % 12}\""
    }

    fun save() {
        if (saving) return
        heightError = heightCm !in 120.0..220.0
        val kg = parsedKg()
        weightError = kg == null && weightText.isNotBlank()
        val steps = stepGoalText.trim().toIntOrNull()
        stepGoalError = steps == null || steps !in 1_000..60_000
        if (heightError || weightError || stepGoalError || steps == null) return
        val owner = SupabaseClient.currentUserIdSnapshot()
        val before = data.profile
        val saved = before.copy(name = name, heightCm = heightCm, birthdate = birthdate,
            sexIsMale = sexIsMale, stepGoal = steps)
        val edited = mutableListOf("display_name")
        if (before.heightCm != heightCm) edited += "height_cm"
        if (before.birthdate != birthdate) edited += "birth_date"
        if (before.sexIsMale != sexIsMale) edited += "sex"
        val weightChanged = weightText != initialWeight && kg != null
        if (weightChanged) edited += "weight_kg"
        saving = true
        saveError = false
        scope.launch {
            try {
                if (!ProfileWrites.save(saved, edited) || owner != SupabaseClient.currentUserIdSnapshot()) {
                    saveError = true
                    return@launch
                }
                data.profile = saved
                if (weightChanged && kg != null) {
                    val ok = data.addWeighIn(WeighIn(id = UUID.randomUUID(), date = Instant.now(), weightKg = kg,
                        bodyFatPercent = null, source = MeasurementSource.measured, origin = WeighIn.Origin.manual))
                    if (!ok) { saveError = true; return@launch }
                }
                // Same publication and settlement path as a completed measurement. Pending
                // manual weights remain durable if connectivity drops after saving.
                ProfileWrites.flushPendingEvidence()
                if (owner != SupabaseClient.currentUserIdSnapshot()) return@launch
                val w = kg ?: data.today.weightKg
                if (w != null) {
                    val info = PersonalInfo(heightCm = saved.heightCm.roundToInt(), weightKg = w.roundToInt(),
                        birthYear = saved.birthdate.atZone(ZoneId.systemDefault()).year,
                        sexIsMale = saved.sexIsMale, targetStep = saved.stepGoal)
                    detached.launch { runCatching { Band.live.syncPersonalInfo(info) } }
                }
                close()
            } finally {
                saving = false
            }
        }
    }

    SheetFrame(title = L("Your details"), footer = {
        LimePill(if (saving) L("Saving…") else L("Save"), enabled = !saving) { save() }
    }) {
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            FieldBox(L("Name"), name, { name = it })
            FieldBox(L("Email"), email, {}, badge = L("VERIFIED"), enabled = false)
            BirthdayRow(L("Birthday"), birthdate) { birthdate = it }
            SegmentedPicker(listOf(L("Female"), L("Male")), selected = if (sexIsMale) 1 else 0) { sexIsMale = it == 1 }
            ChipBox(Modifier.hotZoneTap(pressedScale = 1f) { heightSheet = true }) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(L("Height"), style = NBFont.ui(400, 11f).tracking(0.06f), color = NB.white.copy(alpha = 0.38f))
                    Text(heightLabel, style = NBFont.ui(400, 16f), color = NB.text1, maxLines = 1)
                }
            }
            FieldBox(L("Weight") + if (metric) " · KG" else " · LB", weightText, { weightText = it },
                keyboard = KeyboardType.Decimal)
            // The band's own daily step ring. It is pushed to the firmware, so this is the one
            // number on this sheet the wrist reads back to you.
            FieldBox(L("Daily step goal"), stepGoalText, { stepGoalText = it }, keyboard = KeyboardType.Number)
        }
        when {
            saveError -> Text(L("Could not save your details. Please try again."),
                style = NBFont.ui(400, 12f), color = NB.ember1)
            heightError -> FootNote(L("Height is out of range."), NB.ember1.copy(alpha = 0.85f))
            stepGoalError -> FootNote(L("Step goal is out of range."), NB.ember1.copy(alpha = 0.85f))
            weightError -> FootNote(L("Weight is out of range."), NB.ember1.copy(alpha = 0.85f))
            else -> FootNote(L("Tap any field to change it"), NB.white.copy(alpha = 0.38f))
        }
    }

    if (heightSheet) {
        ProfileHeightSheet(
            value = heightCm,
            onDismiss = { heightSheet = false },
            onSave = {
                heightCm = it
                heightError = heightCm !in 120.0..220.0
                if (!heightError) heightSheet = false
            },
        )
    }
}

@Composable
private fun FootNote(text: String, color: Color) {
    Text(
        text, style = NBFont.ui(300, 12.5f).tracking(0.02f), color = color, textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
    )
}

/** iOS's compact DatePicker row: the label, and the date in a grey lozenge that opens the picker. */
@Composable
private fun BirthdayRow(label: String, date: Instant, onChange: (Instant) -> Unit) {
    val context = LocalContext.current
    val zone = ZoneId.systemDefault()
    val local = date.atZone(zone).toLocalDate()
    val shown = DateTimeFormatter.ofPattern(if (AppLanguage.isEnglish) "MMM d, yyyy" else "yyyy年M月d日",
        AppLanguage.locale.javaLocale).format(local)
    Row(Modifier.fillMaxWidth().height(44.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = systemStyle(17f), color = NB.text1)
        Spacer(Modifier.weight(1f))
        Box(
            Modifier
                .background(NB.white.copy(alpha = 0.12f), RoundedCornerShape(8.dp))
                .hotZoneTap(pressedScale = 1f) {
                    val dialog = DatePickerDialog(context, android.R.style.Theme_DeviceDefault_Dialog_Alert, { _, y, m, d ->
                        onChange(LocalDate.of(y, m + 1, d).atStartOfDay(zone).toInstant())
                    }, local.year, local.monthValue - 1, local.dayOfMonth)
                    dialog.datePicker.maxDate = System.currentTimeMillis()
                    dialog.show()
                }
                .padding(horizontal = 12.dp, vertical = 6.dp),
        ) {
            Text(shown, style = systemStyle(17f), color = NB.text1, maxLines = 1)
        }
    }
}

/** UIKit's segmented control: a grey track and a lighter lozenge under the choice. */
@Composable
private fun SegmentedPicker(options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(32.dp)
            .background(Color(0x3D767680), RoundedCornerShape(9.dp))
            .padding(2.dp),
    ) {
        options.forEachIndexed { i, o ->
            val on = i == selected
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .let { if (on) it.shadow(2.dp, RoundedCornerShape(7.dp)).background(Color(0xFF636366), RoundedCornerShape(7.dp)) else it }
                    .hotZoneTap(pressedScale = 1f) { onSelect(i) },
                contentAlignment = Alignment.Center,
            ) {
                Text(o, style = systemStyle(13f, if (on) FontWeight.SemiBold else FontWeight.Medium), color = NB.text1, maxLines = 1)
            }
        }
    }
}

private fun systemStyle(size: Float, weight: FontWeight = FontWeight.Normal) =
    androidx.compose.ui.text.TextStyle(fontFamily = FontFamily.Default, fontSize = size.sp, fontWeight = weight)

// MARK: Training goal

/** 04 · the options, tapping one is the commit. There is no Save — choosing is the action. */
@Composable
fun TrainingGoalSheet(close: () -> Unit) {
    val data = DataStore
    val options = listOf(
        Goal.bulk to "Lean mass first, the scale second",
        Goal.cut to "Aerobic base and recovery lead",
        Goal.recomp to "Trade fat for muscle, same weight",
    )
    SheetFrame(title = L("Training goal"), footer = {
        // Today's numbers are already spent; changing the goal cannot rewrite them.
        Text(L("Takes effect with tomorrow's numbers"), style = NBFont.ui(300, 12.5f).tracking(0.02f),
            color = NB.white.copy(alpha = 0.38f))
    }) {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            options.forEach { (g, sub) ->
                val on = data.profile.goal == g
                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(66.dp)
                        .background(if (on) NB.lime1.copy(alpha = 0.06f) else NB.carbon4, RoundedCornerShape(NB.R.chip))
                        .border(1.dp, if (on) NB.lime1.copy(alpha = 0.6f) else NB.hairline, RoundedCornerShape(NB.R.chip))
                        .hotZoneTap(pressedScale = 1f) {
                            if (data.profile.goal != g) {
                                Defaults.putString("nb.goal.changedDay", UserDay.containing(Instant.now()).key)
                            }
                            val saved = data.profile.copy(goal = g)
                            data.profile = saved
                            detached.launch { ProfileWrites.save(saved, listOf("goal")) }
                            close()
                        }
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(L(g.raw), style = NBFont.ui(500, 16f).tracking(0.01f), color = NB.text1)
                        Text(L(sub), style = NBFont.ui(300, 12f).tracking(0.02f), color = NB.white.copy(alpha = 0.38f))
                    }
                    Spacer(Modifier.width(16.dp)) // 8 + 0 + 8, as SwiftUI spaces around the Spacer
                    Box(
                        Modifier
                            .size(10.dp)
                            .background(if (on) NB.lime1 else Color.Transparent, CircleShape)
                            .let { if (on) it else it.border(1.dp, NB.white.copy(alpha = 0.2f), CircleShape) },
                    )
                }
            }
        }
    }
}

// MARK: Notifications

/** ADR 0019 · seven edge switches. Move and drink buzzes live on the band, not here. */
@Composable
fun NotificationsSheet() {
    val context = LocalContext.current
    var lamp by remember { mutableStateOf(NotificationAccess.lamp(context)) }
    val systemDenied = lamp == NotificationAccess.Lamp.Denied

    fun pref(key: String) = mutableStateOf(if (Defaults.contains(key)) Defaults.getBoolean(key) else true)
    val switches = remember {
        listOf(
            Triple("nb.notif.morning", "Morning report", "WHEN LAST NIGHT LANDS"),
            Triple("nb.notif.training", "Training nudge", "UNDER TARGET · RESERVE DROPS"),
            Triple("nb.notif.meals", "Meals", "NEXT SLOT EMPTY · YOU MOVED"),
            Triple("nb.notif.wrap", "Daily wrap", "WHEN THE DAY FILLS IN"),
            Triple("nb.notif.energy", "Energy", "READINESS AT OR BELOW 35"),
            Triple("nb.notif.band", "Band", "AWAY 4 H / CHARGE 15"),
            Triple("nb.notif.quiet", "Quiet hours", "22:30 → 07:00"),
        ).map { (k, t, d) -> Triple(k, t to d, pref(k)) }
    }

    fun refreshReach() = Ports.notificationReach.evaluate(DataStore)

    // F5 · D08 — the notification permission gets a primer before the system prompt. Nothing
    // in the product has ever asked for it before. Asked once per opening, so a primer
    // dismissed with Not now does not come straight back.
    LaunchedEffect(Unit) {
        lamp = NotificationAccess.lamp(context)
        if (NotificationAccess.notDetermined(context)) {
            Router.setTakeover(Takeover.NotificationPrimer)
        } else if (lamp == NotificationAccess.Lamp.On) {
            refreshReach()
        }
    }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) {
        lamp = NotificationAccess.lamp(context)
        if (lamp == NotificationAccess.Lamp.On) refreshReach()
    }

    SheetFrame(title = L("Notifications"), footer = {
        Text(L("Move and drink buzzes live on the NEXTBODY."), style = NBFont.ui(300, 12.5f).tracking(0.02f),
            color = NB.white.copy(alpha = 0.38f))
    }) {
        Column(Modifier.weight(1f, fill = false), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (systemDenied) {
                Row(
                    Modifier
                        .width(NB.Layout.contentWidth)
                        .height(62.dp)
                        .cardSkin()
                        .hotZoneTap(pressedScale = 1f) {
                            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            runCatching { context.startActivity(intent) }
                        }
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(L("Notifications are off in Settings"), style = NBFont.ui(500, 14f).tracking(0.02f), color = NB.text1)
                        Text(L("ACCESS OFF"), style = NBFont.dot(500, 10f).tracking(0.14f), color = NB.ember1)
                    }
                    Spacer(Modifier.width(16.dp))
                    Text(L("Open Settings"), style = NBFont.ui(500, 13f), color = NB.lime1)
                }
            }
            Column(
                Modifier
                    .verticalScroll(rememberScrollState())
                    .width(NB.Layout.contentWidth)
                    .cardSkin()
                    .alpha(if (systemDenied) 0.38f else 1f),
            ) {
                switches.forEachIndexed { i, (key, copy, state) ->
                    SwitchRow(L(copy.first), L(copy.second), state.value, enabled = !systemDenied,
                        last = i == switches.size - 1) {
                        state.value = it
                        Defaults.putBoolean(key, it)
                        refreshReach()
                    }
                }
            }
        }
    }
}

@Composable
fun SwitchRow(
    title: String,
    detail: String,
    isOn: Boolean,
    enabled: Boolean = true,
    last: Boolean = false,
    onChange: (Boolean) -> Unit,
) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(62.dp)
            .drawBehind {
                if (!last) {
                    val inset = 16.dp.toPx()
                    drawRect(NB.hairline, Offset(inset, size.height - 1.dp.toPx()), Size(size.width - inset, 1.dp.toPx()))
                }
            }
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = NBFont.ui(500, 14f).tracking(0.02f), color = NB.text1)
            Text(detail, style = NBFont.dot(500, 10f).tracking(0.14f), color = NB.white.copy(alpha = 0.34f))
        }
        Spacer(Modifier.width(16.dp))
        NBSwitch(isOn, enabled = enabled, onChange = onChange)
    }
}

/** The iOS switch: 51 × 31, lime when on, a white 27 knob. */
@Composable
fun NBSwitch(isOn: Boolean, modifier: Modifier = Modifier, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    val x by animateDpAsState(if (isOn) 22.dp else 2.dp, com.nextbody.hoop.ui.swiftSpring(0.3f, 0.8f), label = "switch.x")
    val track by animateColorAsState(if (isOn) NB.lime1 else Color(0x52787880), label = "switch.track")
    Box(
        modifier
            .size(51.dp, 31.dp)
            .background(track, CircleShape)
            .hotZoneTap(enabled = enabled, pressedOpacity = 1f, pressedScale = 1f) { onChange(!isOn) },
    ) {
        Box(
            Modifier
                .offset(x = x, y = 2.dp)
                .size(27.dp)
                .shadow(2.dp, CircleShape)
                .background(Color.White, CircleShape),
        )
    }
}

// MARK: Units

/**
 * 06 · two segmented rows plus a language row. Instant, no Save.
 * ⚠️ The unit is a display preference only: the SDK's own unit flag is never written to the band.
 */
@Composable
fun UnitsSheet() {
    val data = DataStore
    var weightUnit by remember { mutableStateOf(if (data.profile.usesMetric) "KG" else "LB") }
    var heightUnit by remember { mutableStateOf(if (data.profile.usesMetric) "CM" else "FT") }

    SheetFrame(title = L("Units & language"), footer = {
        Text(L("Changes everywhere, straight away"), style = NBFont.ui(300, 12.5f).tracking(0.02f),
            color = NB.white.copy(alpha = 0.38f))
    }) {
        Column(Modifier.width(NB.Layout.contentWidth).cardSkin()) {
            UnitRow(L("Weight")) {
                ProfileUnitToggle(listOf("KG", "LB"), weightUnit) {
                    if (it != weightUnit) {
                        weightUnit = it
                        val saved = data.profile.copy(usesMetric = it == "KG")
                        data.profile = saved
                        detached.launch { ProfileWrites.save(saved, listOf("units_metric")) }
                    }
                }
            }
            UnitRow(L("Height")) { ProfileUnitToggle(listOf("CM", "FT"), heightUnit) { heightUnit = it } }
            UnitRow(L("HAPTICS")) {
                NBSwitch(HapticsSetting.enabled) { on ->
                    HapticsSetting.enabled = on
                    if (on) HoldHaptics.release()
                }
            }
            UnitRow(L("Language"), last = true) {
                Text(AppLanguage.locale.nativeName, style = NBFont.ui(400, 13f), color = NB.text3Prod)
                Spacer(Modifier.width(8.dp))
                Chevron()
            }
        }
    }
}

@Composable
private fun UnitRow(title: String, last: Boolean = false, trailing: @Composable () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(62.dp)
            .drawBehind {
                if (!last) {
                    val inset = 16.dp.toPx()
                    drawRect(NB.hairline, Offset(inset, size.height - 1.dp.toPx()), Size(size.width - inset, 1.dp.toPx()))
                }
            }
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, style = NBFont.ui(500, 14f), color = NB.text1, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(16.dp))
        trailing()
    }
}

// MARK: Language

@Composable
fun LanguageSheet(close: () -> Unit) {
    SheetFrame(title = L("Language"), footer = {
        Text(L("The screen answers in this language, including metric names."),
            style = NBFont.ui(300, 12.5f).tracking(0.02f), color = NB.white.copy(alpha = 0.38f),
            textAlign = TextAlign.Center)
    }) {
        Column(Modifier.width(NB.Layout.contentWidth).cardSkin()) {
            AppLocale.entries.forEach { loc ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(58.dp)
                        .drawBehind {
                            val inset = 16.dp.toPx()
                            drawRect(NB.hairline, Offset(inset, size.height - 1.dp.toPx()), Size(size.width - inset, 1.dp.toPx()))
                        }
                        .hotZoneTap(pressedScale = 1f) { AppLanguage.set(loc); close() }
                        .padding(horizontal = 16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(loc.nativeName, style = NBFont.ui(500, 15f), color = NB.text1, modifier = Modifier.weight(1f))
                    Spacer(Modifier.width(16.dp))
                    if (AppLanguage.locale == loc) Box(Modifier.size(10.dp).background(NB.lime1, CircleShape))
                }
            }
            Row(
                Modifier
                    .fillMaxWidth()
                    .height(58.dp)
                    .hotZoneTap(pressedScale = 1f) { Router.sheet = SheetRoute.Widgets }
                    .padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(L("WIDGETS"), style = NBFont.ui(500, 15f), color = NB.text1, modifier = Modifier.weight(1f))
                Spacer(Modifier.width(16.dp))
                Text(L("HOW TO ADD"), style = NBFont.dot(500, 11f).tracking(0.08f), color = NB.text3Prod)
                Spacer(Modifier.width(8.dp))
                Chevron()
            }
        }
    }
}

// MARK: Health Connect

/**
 * Was the Apple Health sheet. Health Connect, read only: height and weight. Unlike HealthKit,
 * Health Connect says whether read access is held, so this sheet can tell "not granted" from
 * "granted, but nothing there" — and in both cases, and when Health Connect is missing, it
 * points at the manual entries. Sex and date of birth are never in Health Connect: they are
 * always typed in Your details.
 */
@Composable
fun HealthConnectSheet(close: () -> Unit) {
    val data = DataStore
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var available by remember { mutableStateOf(HealthService.available) }
    var installable by remember { mutableStateOf(HealthService.installable) }
    var granted by remember { mutableStateOf<Boolean?>(null) }
    var reading by remember { mutableStateOf(false) }
    var baseline by remember { mutableStateOf<HealthService.Baseline?>(null) }
    val linked = data.profile.appleHealthLinked

    suspend fun check() {
        reading = true
        val b = HealthService.readBaseline()
        baseline = b
        granted = HealthService.hasPermissions()
        // An empty re-check cannot undo a completed import or prove revocation.
        var p = data.profile
        if (!b.isEmpty) p = p.copy(appleHealthLinked = true)
        data.profile = p.restoringHealthSync()
        reading = false
        Analytics.track("HEALTH_CONNECT_CHECK", mapOf("EMPTY" to b.isEmpty))
    }

    val launcher = rememberLauncherForActivityResult(HealthService.permissionContract()) { result ->
        HealthService.onPermissionResult(result)
        scope.launch { check() }
    }

    suspend fun refresh() {
        available = HealthService.available
        installable = HealthService.installable
        granted = if (available) HealthService.hasPermissions() else false
        if (granted == true && baseline == null) check()
    }
    LaunchedEffect(Unit) { refresh() }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { scope.launch { refresh() } }

    fun connect() {
        when {
            !available && installable -> HealthService.openInstallPage(context)
            !available -> Router.sheet = SheetRoute.ProfileEdit
            else -> scope.launch {
                if (HealthService.hasPermissions()) check() else launcher.launch(HealthService.readPermissions)
            }
        }
    }

    fun unlink() {
        data.profile = data.profile.copy(appleHealthLinked = false)
        Defaults.remove("nb.health.lastRead")
        baseline = null
        scope.launch {
            runCatching {
                HealthConnectClient.getOrCreate(context).permissionController.revokeAllPermissions()
            }
            granted = if (available) HealthService.hasPermissions() else false
            Analytics.track("HEALTH_CONNECT_UNLINK")
        }
    }

    val status: Pair<String, Color> = when {
        linked -> L("SYNCED") to NB.optimal2
        !available -> L("NOT AVAILABLE") to NB.ember1
        else -> L("NOT CONNECTED") to NB.ember1
    }
    val b = baseline
    val empty = b != null && b.heightCm == null && b.weightKg == null

    SheetFrame(title = L("Health Connect"), footer = {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            val title = when {
                reading -> L("Reading…")
                !available && installable -> L("Get Health Connect")
                !available -> L("Enter by hand")
                linked -> L("Re-check now")
                else -> L("Connect Health Connect")
            }
            LimePill(title, enabled = !reading) { connect() }
            if (linked && available) {
                Text(L("Unlink"), style = NBFont.ui(400, 13f).tracking(0.02f), color = NB.text3Prod,
                    modifier = Modifier.hotZoneTap(pressedScale = 1f) { unlink() })
            }
        }
    }) {
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Column(
                Modifier.width(NB.Layout.contentWidth).cardSkin().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.size(8.dp).background(status.second, CircleShape))
                    Text(status.first, style = NBFont.dot(700, 12f).tracking(0.16f), color = status.second)
                }
                // The consent screen says nothing is ever written back, and the app does not.
                Text(
                    if (available) L("We read your height and weight. Nothing is ever written back.")
                    else L("Health Connect isn't on this phone. Your height and weight are entered by hand."),
                    style = NBFont.brand(400, 14f).copy(lineHeight = spaced(14f, 7f)), color = NB.text2,
                )
                if (available && b != null) {
                    if (empty) {
                        Text(L("Health Connect has no height or weight for you yet."),
                            style = NBFont.ui(400, 12f).tracking(0.02f), color = NB.ember1)
                    } else {
                        Column {
                            HealthFact(L("HEIGHT"), b.heightCm?.let { heightText(it) })
                            HealthFact(L("WEIGHT"), b.weightKg?.let { weightText(it, b.weightAt) }, last = true)
                        }
                    }
                } else if (available && granted == false && !reading && !linked) {
                    Text(L("Read access is off. Connect to allow height and weight."),
                        style = NBFont.ui(400, 11f).tracking(0.04f), color = NB.text3Prod)
                }
                Text(L("Sex and date of birth are always entered by hand."),
                    style = NBFont.ui(400, 11f).tracking(0.04f), color = NB.text3Prod)
            }
            if (!available || empty || (granted == false && !linked)) {
                // The way round Health Connect: the same two entries the rest of the app uses.
                Row(Modifier.width(NB.Layout.contentWidth), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ManualLink(L("YOUR DETAILS ›"), Modifier.weight(1f)) { Router.sheet = SheetRoute.ProfileEdit }
                    ManualLink(L("ADD A WEIGH-IN ›"), Modifier.weight(1f)) { Router.sheet = SheetRoute.WeighIn }
                }
            }
        }
    }
}

@Composable
private fun HealthFact(label: String, value: String?, last: Boolean = false) {
    Row(
        Modifier
            .fillMaxWidth()
            .height(34.dp)
            .drawBehind { if (!last) drawRect(NB.hairline, Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx())) },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = NBFont.ui(500, 12f).tracking(0.08f), color = NB.text2)
        Spacer(Modifier.weight(1f))
        Text(value ?: Fmt.dash, style = NBFont.dot(600, 13f), color = NB.text1, maxLines = 1)
    }
}

@Composable
private fun ManualLink(text: String, modifier: Modifier, onTap: () -> Unit) {
    Box(
        modifier.height(44.dp).cardSkin().hotZoneTap(pressedScale = 1f, onClick = onTap),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = NBFont.dot(700, 10f).tracking(0.12f), color = NB.lime1, maxLines = 1)
    }
}

private fun heightText(cm: Double): String {
    if (DataStore.profile.usesMetric) return "${cm.roundToInt()} CM"
    val inches = (cm / 2.54).roundToInt()
    return "${inches / 12}'${inches % 12}\" FT"
}

private fun weightText(kg: Double, at: Instant?): String {
    val metric = DataStore.profile.usesMetric
    val v = if (metric) "${Fmt.kg(kg)} KG" else "${Fmt.kg(kg * 2.2046226)} LB"
    if (at == null) return v
    val format = if (AppLanguage.isEnglish) "MMM d" else "M月d日"
    return "$v · ${Fmt.displayDate(at, format).uppercase()}"
}

// MARK: Legal

/** Terms or Privacy, in the app's language. The text lives in `LegalText`. */
@Composable
fun LegalSheet(kind: LegalText.Kind) {
    val doc = LegalText.document(kind)
    SheetFrame(title = doc.title) {
        Column(
            Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(22.dp),
        ) {
            Text(doc.updated, style = NBFont.ui(400, 12f).tracking(0.02f), color = NB.text3Prod)
            doc.sections.forEach { section ->
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(section.heading, style = NBFont.ui(500, 15f), color = NB.text1)
                    section.paragraphs.forEach { p ->
                        Text(p, style = NBFont.brand(400, 14f).copy(lineHeight = spaced(14f, 7f)), color = NB.text2)
                    }
                }
            }
            Row(
                Modifier.fillMaxWidth().hotZoneTap(pressedScale = 1f) {
                    Router.sheet = if (kind == LegalText.Kind.privacy) SheetRoute.About else SheetRoute.Privacy
                },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    if (kind == LegalText.Kind.privacy) L("TERMS OF SERVICE") else L("PRIVACY POLICY"),
                    style = NBFont.ui(500, 14f).tracking(0.06f), color = NB.text1,
                    modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(16.dp))
                Text("›", style = NBFont.ui(400, 16f), color = NB.white.copy(alpha = 0.35f))
            }
        }
    }
}

// MARK: Delete account

/**
 * 07 · asks twice and counts the loss. The second confirm has to say what will be lost.
 * ⚠️ "There is no undo" must line up with the server: the row is deleted, not flagged.
 */
@Composable
fun DeleteAccountSheet(close: () -> Unit) {
    val session = AppSession.session
    val scope = rememberCoroutineScope()
    var weighIns by remember { mutableStateOf<Int?>(null) }
    var weeks by remember { mutableStateOf<Int?>(null) }
    var nights by remember { mutableStateOf<Int?>(null) }
    var failure by remember { mutableStateOf<String?>(null) }

    // ⚠️ 1BAY · exact counts off the server, each "——" until it arrives rather than guessed.
    val losses = L(
        "%@ weigh-ins, %@ of composition and %@ you have slept in it go with it. The NEXTBODY unpairs itself. There is no undo.",
        weighIns?.toString() ?: Fmt.dash,
        weeks?.let { L("%d weeks", it) } ?: Fmt.dash,
        nights?.let { L("%d nights", it) } ?: Fmt.dash,
    )

    LaunchedEffect(Unit) {
        weighIns = SupabaseClient.count("weigh_ins")
        nights = SupabaseClient.count("sleep_nights")
        SupabaseClient.count("body_composition")?.let { days -> weeks = maxOf(1, Math.round(days / 7.0).toInt()) }
        Analytics.track("ACCOUNT_DELETE_SHOWN")
    }

    /**
     * ⚠️ 1DPG · account/delete failing is a legal event, not a toast. If the endpoint cannot be
     * reached the account is still there, and the sheet has to say so.
     */
    suspend fun deleteEverything() {
        val owner = SupabaseClient.currentUserIdSnapshot() ?: return
        Analytics.track("ACCOUNT_DELETE_CONFIRMED")
        try {
            // ⚠️ The confirmation is a literal the server checks, so a mis-routed call cannot
            // delete an account.
            val row = SupabaseClient.callFunction("account-delete", mapOf("confirm" to "DELETE"), expectedOwner = owner)
            if (row.opt("deleted") != true) {
                val err = row.opt("error")?.toString() ?: "unknown"
                failure = deleteFailureCopy(err)
                Analytics.track("ACCOUNT_DELETE_FAILED", mapOf("ERROR" to err))
                return
            }
            // Not reset() — that is the sign-out, and it leaves the band paired and every nb.*
            // key on the phone. The sheet just promised there is no undo.
            session.purgeAfterAccountDelete()
            close()
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            failure = deleteFailureCopy(e.toString())
            Analytics.track("ACCOUNT_DELETE_FAILED", mapOf("ERROR" to e.toString()))
        }
    }

    Column(
        Modifier.fillMaxSize().padding(start = 16.dp, end = 16.dp, top = 26.dp, bottom = 26.dp + ScreenMetrics.safeBottom),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Text(L("Delete your account?"), style = NBFont.ui(500, 24f).tracking(0.01f), color = NB.text1)
        Text(losses, style = NBFont.brand(400, 14f).copy(lineHeight = spaced(14f, 7f)), color = NB.text2)
        failure?.let {
            Text(it, style = NBFont.ui(400, 12f).tracking(0.02f), color = NB.alert2)
        }
        Spacer(Modifier.weight(1f))
        LimePill(L("Keep my account")) { close() }
        Box(
            Modifier
                .width(NB.Layout.contentWidth)
                .height(52.dp)
                .border(1.dp, NB.alert2.copy(alpha = 0.6f), CircleShape)
                .hotZoneTap(pressedScale = 1f) { scope.launch { deleteEverything() } },
            contentAlignment = Alignment.Center,
        ) {
            Text(L("DELETE EVERYTHING"), style = NBFont.ui(500, 12f).tracking(0.2f), color = NB.alert2, maxLines = 1)
        }
    }
}

/**
 * 11 edge 5 · ALL OR NOTHING. The sentence is the board's, and the reference is something a
 * person can read out to support — derived from the error so the same failure gets the same number.
 */
fun deleteFailureCopy(ref: String): String {
    var h = 2166136261u
    for (b in ref.toByteArray(Charsets.UTF_8)) h = (h xor b.toUByte().toUInt()) * 16777619u
    val code = String.format(Locale.US, "%04X-%02X", (h and 0xFFFFu).toInt(), ((h shr 16) and 0xFFu).toInt())
    return L("DELETION FAILED\nNothing was removed. Your account is exactly as it was. Try again, or write to us.\nREF %@", code)
}

// MARK: Sign out

@Composable
fun SignOutSheet(close: () -> Unit) {
    val session = AppSession.session
    SheetFrame(title = L("Sign out?"), footer = {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            LimePill(L("Stay signed in")) { close() }
            Text(
                L("Sign out"), style = NBFont.ui(400, 13f).tracking(0.02f), color = NB.text3Prod,
                modifier = Modifier.hotZoneTap(pressedScale = 1f) {
                    session.reset()
                    close()
                },
            )
        }
    }) {
        // 11 edge 4 · not the same as delete, and it has to say so on the spot.
        Text(
            L("The NEXTBODY stays paired and keeps recording.\nYour data comes back when you sign in."),
            style = NBFont.brand(400, 14f).copy(lineHeight = spaced(14f, 7f)), color = NB.text2,
        )
    }
}

// MARK: sheet chrome

/**
 * Title, content, then the footer pinned to the bottom. Content is a column of its own (18 under
 * the title); a scrolling child takes `Modifier.weight(1f, fill = false)` inside it.
 * `SheetFrame(title = …, footer = { … }) { content }`.
 */
@Composable
fun SheetFrame(
    title: String,
    fillsHeight: Boolean = true,
    footer: @Composable () -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .let { if (fillsHeight) it.fillMaxHeight() else it.wrapContentHeight() }
            .padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 24.dp + ScreenMetrics.safeBottom),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Text(title, style = NBFont.ui(500, 20f).tracking(0.01f), color = NB.text1)
        Column(
            if (fillsHeight) Modifier.fillMaxWidth().weight(1f) else Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(18.dp),
            content = content,
        )
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { footer() }
    }
}

/** The chip every field sits in: carbon-4 at radius 18, one hairline. */
@Composable
internal fun ChipBox(modifier: Modifier = Modifier, height: Dp = 66.dp, content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    Row(
        modifier
            .fillMaxWidth()
            .height(height)
            .background(NB.carbon4, RoundedCornerShape(NB.R.chip))
            .border(1.dp, NB.hairline, RoundedCornerShape(NB.R.chip))
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) { content() }
}

@Composable
fun FieldBox(
    label: String,
    text: String,
    onText: (String) -> Unit,
    modifier: Modifier = Modifier,
    badge: String? = null,
    keyboard: KeyboardType = KeyboardType.Text,
    enabled: Boolean = true,
    imeAction: androidx.compose.ui.text.input.ImeAction = androidx.compose.ui.text.input.ImeAction.Done,
    onSubmit: (() -> Unit)? = null,
) {
    ChipBox(modifier) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, style = NBFont.ui(400, 11f).tracking(0.06f), color = NB.white.copy(alpha = 0.38f))
            BasicTextField(
                value = text,
                onValueChange = onText,
                enabled = enabled,
                singleLine = true,
                textStyle = NBFont.ui(400, 16f).copy(color = NB.text1),
                cursorBrush = SolidColor(NB.lime1),
                keyboardOptions = KeyboardOptions(keyboardType = keyboard, imeAction = imeAction),
                keyboardActions = androidx.compose.foundation.text.KeyboardActions(onAny = { onSubmit?.invoke() }),
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (badge != null) {
            Box(
                Modifier.height(22.dp).border(1.dp, NB.lime1.copy(alpha = 0.4f), CircleShape).padding(horizontal = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(badge, style = NBFont.dot(600, 9f).tracking(0.18f), color = NB.lime1, maxLines = 1)
            }
        }
    }
}

/** A time field in the same chip: the hour and minute, tapping opens the system clock. */
@Composable
fun TimeFieldBox(label: String, time: LocalTime, onChange: (LocalTime) -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    ChipBox(modifier) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, style = NBFont.ui(400, 11f).tracking(0.06f), color = NB.white.copy(alpha = 0.38f))
            Box(
                Modifier
                    .background(NB.white.copy(alpha = 0.12f), RoundedCornerShape(8.dp))
                    .hotZoneTap(pressedScale = 1f) {
                        TimePickerDialog(context, android.R.style.Theme_DeviceDefault_Dialog_Alert, { _, h, m ->
                            onChange(LocalTime.of(h, m))
                        }, time.hour, time.minute, true).show()
                    }
                    .padding(horizontal = 10.dp, vertical = 4.dp),
            ) {
                Text(DateTimeFormatter.ofPattern("HH:mm").format(time), style = systemStyle(17f), color = NB.text1)
            }
        }
    }
}

/** ConnectFlow's `LimePillButton`: the one lime action at the foot of a sheet. */
@Composable
internal fun LimePill(title: String, enabled: Boolean = true, action: () -> Unit) =
    com.nextbody.hoop.features.connect.LimePillButton(title, enabled = enabled, action = action)

/** ValueSheets' `UnitToggle`. */
@Composable
internal fun ProfileUnitToggle(options: List<String>, selection: String, onSelect: (String) -> Unit) =
    com.nextbody.hoop.features.onboarding.UnitToggle(options, selection, onSelect)

/** The height ruler, presented over Your details as its own sheet (Swift `.sheet`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ProfileHeightSheet(value: Double, onDismiss: () -> Unit, onSave: (Double) -> Unit) {
    val state = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = state,
        containerColor = NB.carbon2,
        shape = RoundedCornerShape(topStart = NB.R.panel, topEnd = NB.R.panel),
        dragHandle = null,
    ) {
        Box(Modifier.fillMaxWidth().height(com.nextbody.hoop.app.SheetChrome.height(SheetRoute.Height))) {
            com.nextbody.hoop.features.onboarding.HeightRulerSheet(value, onSave)
        }
    }
}

/** Repository writes the profile sheets make. */
internal object ProfileWrites {
    suspend fun save(profile: Profile, editedFields: List<String>): Boolean =
        com.nextbody.hoop.services.Repository.saveProfile(profile, editedFields)

    suspend fun flushPendingEvidence() = com.nextbody.hoop.services.Repository.flushPendingEvidence(afterCurrent = true)
}
