package com.nextbody.hoop.features.fuel

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.FuelState
import com.nextbody.hoop.model.MacroSlot
import com.nextbody.hoop.services.ConsentStore
import com.nextbody.hoop.services.HomeSnapshot
import com.nextbody.hoop.services.MealQueue
import com.nextbody.hoop.services.Repository
import com.nextbody.hoop.services.SupabaseClient
import com.nextbody.hoop.services.SupabaseFailure
import com.nextbody.hoop.ui.hotZoneTap
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.time.Instant

/** This destructive action succeeds only after the authenticated server transaction. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FastingAction(day: UserDay) {
    val data = DataStore
    var confirming by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()

    val fasted = data.today.day == day && data.today.fuelState == FuelState.Fasted
    val hasFood = (data.meals + data.recentMeals).any { it.day == day } || (data.today.eIn ?: 0.0) > 0 ||
        MealQueue.pendingCount > 0

    fun save(confirmed: Boolean = false) {
        if (saving) return
        saving = true; error = null
        scope.launch {
            try {
                data.markTodayFasted(day = day, confirmed = confirmed)
                confirming = false
            } catch (e: SupabaseFailure.Http) {
                if (e.body.contains("FOOD_REQUIRES_CONFIRMATION")) confirming = true
                else error = L("Couldn't confirm. Check your connection and wait for pending meals to sync, then try again.")
            } catch (e: Exception) {
                error = L("Couldn't confirm. Check your connection and wait for pending meals to sync, then try again.")
            } finally {
                saving = false
            }
        }
    }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally) {
        Row(
            Modifier
                .fillMaxWidth()
                .heightIn(min = 44.dp)
                .hotZoneTap(enabled = !(saving || fasted), pressedOpacity = 0.6f, pressedScale = 1f) {
                    if (saving || fasted) return@hotZoneTap
                    if (hasFood) confirming = true else save()
                },
            horizontalArrangement = Arrangement.spacedBy(7.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (saving) CircularProgressIndicator(Modifier.size(14.dp), color = NB.lime1, strokeWidth = 1.5.dp)
            // A line of small yellow type, underlined: it has to read as something you can tap,
            // not as a caption sitting under the boards.
            Text(
                if (fasted) L("Recorded: nothing eaten today") else L("MARK TODAY AS FASTED"),
                style = NBFont.ui(500, 13f).tracking(0.02f)
                    .copy(textDecoration = if (fasted) null else TextDecoration.Underline),
                color = if (fasted) NB.text3Prod else NB.lime1,
            )
        }
        error?.let { Text(it, style = NBFont.ui(400, 12f), color = NB.alert2) }
    }

    if (confirming) {
        val sheetState = rememberModalBottomSheetState(
            skipPartiallyExpanded = true,
            confirmValueChange = { !saving },
        )
        ModalBottomSheet(
            onDismissRequest = { if (!saving) { confirming = false; error = null } },
            sheetState = sheetState,
            containerColor = NB.carbon2,
            shape = RoundedCornerShape(topStart = NB.R.panel, topEnd = NB.R.panel),
        ) {
            ConfirmSheet(saving = saving, error = error,
                onConfirm = { save(confirmed = true) },
                onCancel = { confirming = false; error = null })
        }
    }
}

/** Three layers, none of them full-bleed: the ask, the consequence on its own panel, then the
 *  two answers. 24 gutters keep the copy off the sheet's edges. */
@Composable
private fun ConfirmSheet(saving: Boolean, error: String?, onConfirm: () -> Unit, onCancel: () -> Unit) {
    Column(
        Modifier.fillMaxWidth().height(320.dp - 40.dp)
            .padding(horizontal = 24.dp).padding(top = 26.dp - 22.dp, bottom = 18.dp),
    ) {
        Text(L("MARK TODAY AS FASTED"), Modifier.padding(bottom = 8.dp),
            style = NBFont.dot(600, 10f).tracking(0.24f), color = NB.ember1)
        Text(L("Confirm no food today"), Modifier.padding(bottom = 16.dp),
            style = NBFont.ui(500, 20f).tracking(0.01f), color = NB.text1)
        val panel = RoundedCornerShape(NB.R.chip)
        Column(
            Modifier.fillMaxWidth().background(NB.carbon4, panel).border(1.dp, NB.hairline, panel).padding(14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(L("This will permanently clear all food recorded today and record zero intake. You will not be able to add or change food for today."),
                style = NBFont.ui(400, 13.5f).copy(lineHeight = (13.5f + 5).sp), color = NB.text3Prod)
            if (error != null) Text(error, style = NBFont.ui(400, 12f), color = NB.alert2)
        }
        Spacer(Modifier.weight(1f).heightIn(min = 16.dp))
        Box(
            Modifier.fillMaxWidth().heightIn(min = 50.dp)
                .hotZoneTap(enabled = !saving) { if (!saving) onConfirm() }
                .alpha(if (saving) 0.4f else 1f)
                .background(NB.lime1, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(if (saving) L("Saving…") else L("Clear food and confirm"),
                style = NBFont.ui(500, 15f).tracking(0.04f), color = NB.carbon)
        }
        Box(
            Modifier.fillMaxWidth().heightIn(min = 40.dp).padding(top = 2.dp)
                .hotZoneTap(enabled = !saving, role = Role.Button) { if (!saving) onCancel() },
            contentAlignment = Alignment.Center,
        ) {
            Text(L("Cancel"), style = NBFont.ui(400, 13f), color = NB.text3Prod, textAlign = TextAlign.Center)
        }
    }
}

/**
 * Swift `DataStore.markTodayFasted(day:confirmed:)`. Throws on any failure (a guard that fails
 * throws the equivalent of `CancellationError`).
 */
suspend fun DataStore.markTodayFasted(day: UserDay, confirmed: Boolean) {
    val owner = SupabaseClient.currentUserIdSnapshot()
    if (!(day == UserDay.containing(Instant.now()) && today.day == day && owner != null && ConsentStore.granted)) {
        throw CancellationException()
    }
    MealQueue.flush()
    MealQueue.refreshStatus(owner)
    if (MealQueue.pendingCount != 0) throw CancellationException()
    val receipt = SupabaseClient.rpc("mark_day_fasted",
        mapOf("p_day" to day.key, "p_clear_existing" to confirmed), expectedOwner = owner)
    val fields = receipt as? JSONObject
    if (SupabaseClient.currentUserIdSnapshot() != owner || fields == null ||
        fields.optString("user_day") != day.key || fields.optString("intake_state") != "FASTED") {
        throw CancellationException()
    }
    // A midnight rollover never applies yesterday's acknowledgment to a new day.
    if (!(today.day == day && day == UserDay.containing(Instant.now()))) return
    meals = meals.filter { it.day != day }
    recentMeals = recentMeals.filter { it.day != day }
    val updated = today.copy()
    updated.fuelState = FuelState.Fasted; updated.eIn = 0.0
    updated.proteinIn = 0; updated.carbIn = 0; updated.fatIn = 0
    updated.protein = updated.protein?.let { MacroSlot(target = it.target, eaten = 0) }
    updated.carb = updated.carb?.let { MacroSlot(target = it.target, eaten = 0) }
    updated.fat = updated.fat?.let { MacroSlot(target = it.target, eaten = 0) }
    updated.balance = updated.eOutNow?.let { -it }
    updated.nextMeal = 0.0
    today = updated
    HomeSnapshot.save(this)
    Repository.loadToday(into = this)
}
