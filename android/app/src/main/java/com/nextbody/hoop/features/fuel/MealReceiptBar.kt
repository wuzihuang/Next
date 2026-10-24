package com.nextbody.hoop.features.fuel

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.data.DataStore
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.ui.hotZoneTap
import kotlin.math.abs

/**
 * What just went on the record, and the one tap that takes it back.
 *
 * It appears for eight seconds wherever a meal was just written, states what the row says and
 * what is left of TARGET, and disappears on its own. Not a toast to be dismissed and not a
 * second chrome element: no close button, no queue, one receipt at a time, newest replaces last.
 * The caller animates its arrival (Swift: `.transition(.move(edge: .bottom).combined(with: .opacity))`).
 */
@Composable
fun MealReceiptBar(modifier: Modifier = Modifier) {
    val data = DataStore
    val receipt = data.mealReceipt ?: return
    // The photo of the plate this receipt is for, when the row just written has one.
    val photoPath = receipt.added.firstOrNull()?.let { id ->
        (data.meals.firstOrNull { it.id == id } ?: data.recentMeals.firstOrNull { it.id == id })?.photoPath
    }
    val shape = RoundedCornerShape(NB.R.card)
    Row(
        modifier
            .padding(horizontal = 16.dp)
            .fillMaxWidth()
            .shadow(18.dp, shape, ambientColor = NB.carbon, spotColor = androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.5f))
            .background(NB.carbon2, shape)
            .border(1.dp, NB.ember1.copy(alpha = 0.3f), shape)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (photoPath != null) MealThumbnail(photoPath, side = 34.dp, radius = 9.dp)
        // 12 + 8 + 12, as SwiftUI spaces around the Spacer
        Column(Modifier.weight(1f).padding(end = 20.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(L("ON THE RECORD"), style = NBFont.dot(600, 9f).tracking(0.18f), color = NB.ember1)
            Text(receipt.line, style = NBFont.ui(400, 13.5f), color = NB.text1, maxLines = 1,
                overflow = TextOverflow.Ellipsis)
        }
        val left = receipt.left
        if (left != null) {
            // Under the target is a number; over it is still a number, said as over.
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(if (left >= 0) L("LEFT") else L("OVER"), style = NBFont.dot(600, 9f).tracking(0.18f),
                    color = NB.white.copy(alpha = 0.42f))
                Text(Fmt.kcal(abs(left)), style = NBFont.dot(600, 14f), color = if (left >= 0) NB.text1 else NB.ember1)
            }
        }
        Box(
            Modifier
                .height(32.dp)
                .hotZoneTap { data.undoMealReceipt() }
                .background(NB.carbon4, CircleShape)
                .border(1.dp, NB.hairline, CircleShape)
                .padding(horizontal = 14.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(L("UNDO"), style = NBFont.dot(600, 11f).tracking(0.14f), color = NB.text1)
        }
    }
}
