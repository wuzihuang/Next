package com.nextbody.hoop.features.device

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.BuildConfig
import com.nextbody.hoop.band.Band
import com.nextbody.hoop.band.BandAlarm
import com.nextbody.hoop.band.BandAlarmMath
import com.nextbody.hoop.band.BandError
import com.nextbody.hoop.band.localizedDescription
import com.nextbody.hoop.data.DebugEdgeFlag
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.ui.Hairline
import com.nextbody.hoop.ui.hotZoneTap
import com.nextbody.hoop.ui.swiftSpring
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

/**
 * Paper 12Y · 04 SWITCH (KUV-0 list, L0H-0 edit).
 * Full-width row layout inside the DEVICE sheet gutter. No outer card container.
 * Times + custom 68x40 mechanical rocker. First row has no top hairline.
 * Adding is one capsule key: filled lime on an empty NEXTBODY, outlined under a list.
 * Capacity is never shown as `2 / ?` — only a real refusal prints both numbers.
 */
@Composable
fun AlarmsSheet(onCount: (Int) -> Unit = {}) {
    var alarms by remember { mutableStateOf<List<BandAlarm>>(emptyList()) }
    var didRead by remember { mutableStateOf(false) }
    var capacity by remember { mutableStateOf<Int?>(null) }
    var draft by remember { mutableStateOf<BandAlarm?>(null) }
    var writing by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    fun hoopMessage(error: Throwable): String =
        if (error is BandError.Busy) L("DEVICE BUSY") else error.localizedDescription

    fun openEditor(alarm: BandAlarm) {
        message = null
        draft = alarm
    }

    fun addAlarm() {
        val id = BandAlarmMath.nextID(alarms)
        if (id == null) {
            capacity = BandAlarm.demoCeiling
            return
        }
        openEditor(
            BandAlarm.emptyRead().copy(
                id = id, hour = 7, minute = 30, on = true,
                repeatMask = BandAlarmMath.weekdaysMask, scene = BandAlarm.silentScene,
            ),
        )
    }

    suspend fun reload() {
        try {
            alarms = Band.live.readAlarms()
            didRead = true
            if (BandAlarmMath.isFull(alarms)) capacity = BandAlarm.demoCeiling
            onCount(alarms.size)
            message = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            didRead = true
            message = hoopMessage(e)
        }
    }

    suspend fun commit(body: suspend () -> List<BandAlarm>) {
        val snapshot = alarms
        val adding = draft?.let { d -> snapshot.none { it.id == d.id } } ?: false
        writing = true
        try {
            alarms = body()
            didRead = true
            if (BandAlarmMath.isFull(alarms)) capacity = BandAlarm.demoCeiling
            onCount(alarms.size)
            message = null
        } catch (e: CancellationException) {
            throw e
        } catch (e: Throwable) {
            alarms = snapshot
            if (adding && e is BandError.Rejected && snapshot.isNotEmpty()) {
                capacity = snapshot.size
                draft = null
            }
            message = hoopMessage(e)
        } finally {
            writing = false
        }
    }

    fun setOn(alarm: BandAlarm, on: Boolean) {
        scope.launch { commit { Band.live.writeAlarm(alarm.copy(on = on)) } }
    }

    fun saveDraft() {
        val d = draft ?: return
        scope.launch {
            commit { Band.live.writeAlarm(d) }
            if (message == null) draft = null
        }
    }

    fun remove(alarm: BandAlarm) {
        scope.launch {
            commit { Band.live.deleteAlarm(alarm) }
            if (message == null) draft = null
        }
    }

    LaunchedEffect(Unit) {
        reload()
        if (BuildConfig.DEBUG && DebugEdgeFlag.on("alarmedit")) addAlarm()
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(NB.carbon2)
            .padding(horizontal = DeviceSheetMetrics.gutter)
            .padding(top = DeviceSheetMetrics.top, bottom = DeviceSheetMetrics.bottom),
    ) {
        val editing = draft
        if (editing != null) {
            AlarmEditor(
                alarm = editing,
                isNew = alarms.none { it.id == editing.id },
                writing = writing,
                message = message,
                onChange = { draft = it },
                onCancel = { draft = null },
                onSave = ::saveDraft,
                onDelete = { remove(editing) },
            )
        } else {
            SheetHeader(
                eyebrow = L("CLOCK"),
                title = L("Alarms"),
                subtitle = L("This NEXTBODY has no screen. An alarm is a buzz on your wrist."),
            )
            if (didRead && alarms.isEmpty()) {
                // No alarms on this NEXTBODY. The header already said what an alarm is; the
                // face is one word and one key — nothing to read, nothing to count.
                Column(Modifier.fillMaxWidth().weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Spacer(Modifier.weight(1f))
                    Text(L("NO ALARMS YET"), style = NBFont.dot(700, 11f).tracking(0.24f), color = NB.white.copy(alpha = 0.38f))
                    HoopKey(L("Add an alarm"), Modifier.padding(top = 22.dp).testTag("alarms.add")) { addAlarm() }
                    message?.let { SheetNote(it, Modifier.padding(top = 14.dp)) }
                    Spacer(Modifier.weight(1f))
                }
            } else if (!didRead) {
                Text(
                    L("ASKING THIS NEXTBODY…"),
                    style = NBFont.dot(600, 10f).tracking(0.16f),
                    color = NB.white.copy(alpha = 0.38f),
                    modifier = Modifier.padding(top = 24.dp),
                )
                message?.let { SheetNote(it, Modifier.padding(top = 14.dp)) }
                Spacer(Modifier.weight(1f))
            } else {
                // A real swipe-to-delete purely for the mechanic every phone owner already
                // knows: swipe a clock left, get a red DELETE.
                LazyColumn(Modifier.fillMaxWidth().weight(1f).padding(top = 8.dp)) {
                    itemsIndexed(alarms, key = { _, a -> a.id }) { index, alarm ->
                        SwipeDeleteRow(onDelete = { remove(alarm) }, tag = "alarms.swipeDelete.${alarm.id}") {
                            AlarmRow(
                                alarm, index,
                                isOn = alarms.firstOrNull { it.id == alarm.id }?.on ?: alarm.on,
                                writing = writing,
                                onOpen = { openEditor(alarm) },
                                onToggle = { setOn(alarm, it) },
                            )
                        }
                        if (index < alarms.size - 1) Hairline()
                    }
                }
                message?.let { SheetNote(it, Modifier.padding(top = 14.dp)) }
                // The detent is fixed, so the key belongs on the floor of the sheet rather
                // than floating a hairline under the last clock.
                if (BandAlarmMath.isFull(alarms, capacity ?: BandAlarm.demoCeiling)) {
                    SheetNote(
                        L("This NEXTBODY is full · %d / %d", alarms.size, capacity ?: BandAlarm.demoCeiling),
                        Modifier.padding(top = 22.dp).testTag("alarms.full"),
                    )
                } else {
                    HoopKey(L("Add an alarm"), Modifier.padding(top = 22.dp).testTag("alarms.add"), skin = HoopKeySkin.outline) { addAlarm() }
                }
            }
        }
    }
}

@Composable
private fun AlarmRow(
    alarm: BandAlarm,
    index: Int,
    isOn: Boolean,
    writing: Boolean,
    onOpen: () -> Unit,
    onToggle: (Boolean) -> Unit,
) {
    val lit = alarm.on || !alarm.showsSwitch
    Row(
        Modifier.fillMaxWidth().background(NB.carbon2).padding(vertical = DeviceSheetMetrics.rowInset),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            Modifier.weight(1f).testTag("alarms.row.$index").hotZoneTap(pressedScale = 1f) { onOpen() },
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(alarm.clock, style = NBFont.dot(700, 28f).tracking(-0.02f),
                color = if (lit) NB.text1 else NB.white.copy(alpha = 0.40f))
            Text(L(BandAlarmMath.phrase(alarm.repeatMask)), style = NBFont.dot(500, 10f).tracking(0.14f),
                color = if (lit) NB.white.copy(alpha = 0.42f) else NB.white.copy(alpha = 0.24f))
        }
        if (alarm.showsSwitch) {
            HoopSwitch(isOn, enabled = !writing, modifier = Modifier.testTag("alarms.switch.${alarm.id}"), onChange = onToggle)
        } else {
            Spacer(Modifier.size(68.dp, 40.dp))
        }
    }
}

/** Swipe left reveals red DELETE; a full swipe deletes. The row springs back either way —
 *  the list itself drops the row once the band has answered. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SwipeDeleteRow(onDelete: () -> Unit, tag: String, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState(
        confirmValueChange = {
            if (it == SwipeToDismissBoxValue.EndToStart) onDelete()
            false
        },
        positionalThreshold = { it * 0.5f },
    )
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(
                Modifier.fillMaxSize().background(NB.alert2).padding(horizontal = 20.dp).testTag(tag),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Text(L("DELETE"), style = NBFont.ui(600, 14f), color = NB.white)
            }
        },
    ) { content() }
}

/** One way out that writes (SAVE) and one that does not (Cancel, in the corner). */
@Composable
private fun AlarmEditor(
    alarm: BandAlarm,
    isNew: Boolean,
    writing: Boolean,
    message: String?,
    onChange: (BandAlarm) -> Unit,
    onCancel: () -> Unit,
    onSave: () -> Unit,
    onDelete: () -> Unit,
) {
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        SheetHeader(
            eyebrow = if (isNew) L("NEW ALARM") else L("EDIT ALARM"),
            title = alarm.clock,
            subtitle = L("Vibrate only. Scene stays 0."),
        ) {
            Text(
                L("Cancel"),
                style = NBFont.ui(500, 14f),
                color = NB.text2,
                modifier = Modifier.testTag("alarms.cancel").hotZoneTap(pressedScale = 1f) { onCancel() },
            )
        }

        ClockWheel(alarm.hour, alarm.minute) { h, m -> onChange(alarm.copy(hour = h, minute = m)) }

        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (day in BandAlarmMath.Weekday.entries) {
                val on = BandAlarmMath.has(alarm.repeatMask, day)
                Box(
                    Modifier
                        .weight(1f)
                        .height(36.dp)
                        .background(NB.carbon2, CircleShape)
                        .border(1.dp, if (on) NB.lime1 else NB.hairline, CircleShape)
                        .testTag("alarms.day.${day.short}")
                        .hotZoneTap(pressedScale = 1f) {
                            onChange(alarm.copy(repeatMask = BandAlarmMath.toggling(alarm.repeatMask, day)))
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(day.pill, style = NBFont.dot(600, 12f), color = if (on) NB.lime1 else NB.text2)
                }
            }
        }

        Text(L(BandAlarmMath.phrase(alarm.repeatMask)), style = NBFont.dot(500, 11f).tracking(0.1f),
            color = NB.white.copy(alpha = 0.38f))

        if (message != null) SheetNote(message)

        Spacer(Modifier.weight(1f))

        HoopKey(L("SAVE"), Modifier.testTag("alarms.save"), enabled = !writing) { onSave() }

        // Same destination as the swipe, kept here because an alarm you opened to change is
        // often one you meant to be rid of. Plain text, not a second plate.
        if (!isNew) {
            Box(
                Modifier.fillMaxWidth().height(44.dp).testTag("alarms.delete")
                    .hotZoneTap(enabled = !writing, pressedScale = 1f) { onDelete() },
                contentAlignment = Alignment.Center,
            ) {
                Text(L("Delete alarm"), style = NBFont.ui(500, 14f), color = NB.alert2)
            }
        }
    }
}

/**
 * The iOS wheel time picker (`DatePicker(.wheel, .hourAndMinute)`, dark): two snapping
 * columns, five rows visible, the selection band behind the middle row.
 */
@Composable
private fun ClockWheel(hour: Int, minute: Int, onChange: (Int, Int) -> Unit) {
    val rowHeight = 34.dp
    Box(Modifier.fillMaxWidth().height(rowHeight * 5), contentAlignment = Alignment.Center) {
        Box(
            Modifier.width(220.dp).height(rowHeight)
                .background(NB.white.copy(alpha = 0.10f), RoundedCornerShape(8.dp)),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            WheelColumn(24, hour, rowHeight) { onChange(it, minute) }
            Text(":", style = NBFont.ui(400, 22f), color = NB.text1)
            WheelColumn(60, minute, rowHeight) { onChange(hour, it) }
        }
    }
}

@Composable
private fun WheelColumn(count: Int, value: Int, rowHeight: androidx.compose.ui.unit.Dp, onPick: (Int) -> Unit) {
    // A long virtual list so the wheel feels endless, as iOS's does.
    val loops = 200
    val base = count * (loops / 2)
    val state = rememberLazyListState(initialFirstVisibleItemIndex = base + value - 2)
    val fling = rememberSnapFlingBehavior(state)
    val currentValue by androidx.compose.runtime.rememberUpdatedState(value)
    val currentPick by androidx.compose.runtime.rememberUpdatedState(onPick)
    val centre by remember { derivedStateOf { state.firstVisibleItemIndex + 2 + if (state.firstVisibleItemScrollOffset > 0) 1 else 0 } }
    LaunchedEffect(state) {
        snapshotFlow { state.isScrollInProgress to (state.firstVisibleItemIndex + 2) }
            .distinctUntilChanged()
            .collect { (moving, index) ->
                if (!moving) {
                    val picked = ((index % count) + count) % count
                    if (picked != currentValue) currentPick(picked)
                }
            }
    }
    LazyColumn(
        Modifier.width(72.dp).height(rowHeight * 5),
        state = state,
        flingBehavior = fling,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        items(count * loops) { i ->
            val n = i % count
            val distance = kotlin.math.abs(i - centre)
            Box(Modifier.height(rowHeight).fillMaxWidth(), contentAlignment = Alignment.Center) {
                Text(
                    String.format(java.util.Locale.ROOT, "%02d", n),
                    style = NBFont.ui(400, 21f),
                    color = NB.text1.copy(alpha = when (distance) { 0 -> 1f; 1 -> 0.55f; else -> 0.28f }),
                )
            }
        }
    }
}

/**
 * Paper 12Y · 04 SWITCH bespoke 68x40 rocker. Lime fill with carbon-4 thumb when ON;
 * translucent white with light thumb when OFF.
 */
@Composable
fun HoopSwitch(isOn: Boolean, modifier: Modifier = Modifier, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    val x by animateDpAsState(if (isOn) 32.dp else 0.dp, swiftSpring(0.22f, 0.78f), label = "hoopSwitch")
    val fill by animateFloatAsState(if (isOn) 1f else 0f, swiftSpring(0.22f, 0.78f), label = "hoopSwitch.fill")
    Box(
        modifier
            .size(68.dp, 40.dp)
            .alpha(if (enabled) 1f else 0.5f)
            .semantics {
                role = Role.Switch
                toggleableState = ToggleableState(isOn)
                stateDescription = if (isOn) "on" else "off"
            }
            .background(lerp(Color.White.copy(alpha = 0.133f), NB.lime1, fill), CircleShape)
            .hotZoneTap(enabled = enabled, pressedOpacity = 1f, pressedScale = 1f) { onChange(!isOn) },
    ) {
        Box(
            Modifier.offset(x = x).padding(4.dp).size(32.dp)
                .background(lerp(Color.White.copy(alpha = 0.60f), NB.carbon4, fill), CircleShape),
        )
    }
}

private fun lerp(a: Color, b: Color, t: Float): Color = androidx.compose.ui.graphics.lerp(a, b, t.coerceIn(0f, 1f))
