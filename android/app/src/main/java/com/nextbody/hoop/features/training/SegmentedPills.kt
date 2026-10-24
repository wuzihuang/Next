package com.nextbody.hoop.features.training

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.ui.hotZoneTap

// From TrainingDetailView.swift — the shared DAY / WEEK / MONTH control, GateRow and
// (from Services/DebugEdge.swift) the EdgeNote voice. Every detail page uses these.

object SegmentedPillsMetrics {
    val height: Dp = 44.dp
    val inset: Dp = 3.dp
}

/**
 * The range control. [lined] is 线条方案 · tabs on a hairline, the chosen one underlined,
 * no capsule.
 */
@Composable
fun SegmentedPills(
    options: List<String>,
    selection: String,
    onSelect: (String) -> Unit,
    modifier: Modifier = Modifier,
    lined: Boolean = false,
) {
    if (lined) LinedPills(options, selection, onSelect, modifier)
    else CapsulePills(options, selection, onSelect, modifier)
}

@Composable
private fun LinedPills(options: List<String>, selection: String, onSelect: (String) -> Unit, modifier: Modifier) {
    Row(
        modifier
            .width(NB.Layout.contentWidth)
            .height(SegmentedPillsMetrics.height)
            .drawBehind {
                val h = 1.dp.toPx()
                drawRect(NB.hairline, Offset(0f, size.height - h), Size(size.width, h))
            },
    ) {
        for (o in options) {
            val selected = selection == o
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .semantics { this.selected = selected }
                    .hotZoneTap(pressedOpacity = 1f, pressedScale = 1f) { if (!selected) onSelect(o) },
                contentAlignment = Alignment.BottomCenter,
            ) {
                Box(Modifier.width(IntrinsicSize.Max)) {
                    Text(
                        L(o),
                        style = NBFont.ui(if (selected) 600 else 500, 15f),
                        color = if (selected) NB.text1 else NB.text3Prod,
                        maxLines = 1,
                        softWrap = false,
                        modifier = Modifier.padding(horizontal = 12.dp).padding(bottom = 10.dp),
                    )
                    Box(
                        Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(2.dp)
                            .background(if (selected) NB.text1 else Color.Transparent, CircleShape),
                    )
                }
            }
        }
    }
}

@Composable
private fun CapsulePills(options: List<String>, selection: String, onSelect: (String) -> Unit, modifier: Modifier) {
    val inset = SegmentedPillsMetrics.inset
    Row(
        modifier
            .width(NB.Layout.contentWidth)
            .height(SegmentedPillsMetrics.height)
            .background(NB.carbon4, CircleShape)
            .border(1.dp, NB.hairline, CircleShape)
            .padding(inset),
        horizontalArrangement = Arrangement.spacedBy(inset),
    ) {
        for (o in options) {
            val selected = selection == o
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .heightIn(min = SegmentedPillsMetrics.height - inset * 2)
                    .background(if (selected) NB.barTrack else Color.Transparent, CircleShape)
                    .semantics { this.selected = selected }
                    .hotZoneTap(pressedOpacity = 1f, pressedScale = 1f) { if (!selected) onSelect(o) },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    L(o),
                    style = NBFont.ui(if (selected) 600 else 500, 12f).tracking(0.14f),
                    color = if (selected) NB.text1 else NB.text3Prod,
                    maxLines = 1,
                )
            }
        }
    }
}

/** A gate line: title left, when right, 44 tall. */
@Composable
fun GateRow(title: String, `when`: String, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().height(44.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, style = NBFont.ui(500, 11f).tracking(0.2f), color = NB.text2, maxLines = 1, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(16.dp))
        Text(`when`, style = NBFont.dot(500, 10f).tracking(0.14f), color = NB.text3Prod, maxLines = 1)
    }
}

/**
 * 08 / 09 / 10 edge fragments share one voice: an optional dim sub-line, one amber status
 * line in Doto, and a centred sentence. Optionally tappable (08 edge 2 links to the switch).
 */
@Composable
fun EdgeNote(sub: String? = null, line: String, text: String, modifier: Modifier = Modifier, action: (() -> Unit)? = null) {
    Column(
        (if (action != null) modifier.hotZoneTap { action() } else modifier),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (sub != null) {
            Text(sub, style = NBFont.dot(500, 11f).tracking(0.18f), color = NB.white.copy(alpha = 0.34f))
        }
        Text(line, style = NBFont.dot(600, 12f).tracking(0.22f), color = NB.ember1.copy(alpha = 0.85f))
        Text(
            text,
            style = NBFont.brand(400, 13.5f).copy(lineHeight = (13.5f * 1.2f + 5f).let { androidx.compose.ui.unit.TextUnit(it, androidx.compose.ui.unit.TextUnitType.Sp) }),
            color = NB.white.copy(alpha = 0.70f),
            textAlign = TextAlign.Center,
            modifier = Modifier.width(300.dp),
        )
    }
}
