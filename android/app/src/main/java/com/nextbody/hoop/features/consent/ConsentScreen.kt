package com.nextbody.hoop.features.consent

import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.data.DebugEnv
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.ScreenMetrics
import com.nextbody.hoop.design.hex
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.features.auth.GText
import com.nextbody.hoop.features.auth.lineSpacing
import com.nextbody.hoop.features.auth.plainTap
import com.nextbody.hoop.features.auth.track
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.services.ConsentCopy
import com.nextbody.hoop.services.ConsentStore
import com.nextbody.hoop.ui.Chrome
import kotlinx.coroutines.launch

/**
 * 补屏 A · 同意屏 What NEXTBODY collects. The content scrolls; the Continue sits in a fixed
 * 104pt footer.
 *
 * Rule 02 · one checkbox, one Continue. Not pre-checked, the list does not collapse.
 * Rule 03 · two highlight phases, never both: unchecked is an amber-outlined box and a grey,
 * inert Continue with no lime anywhere; checked is a lime box and a lime Continue.
 * Declining · the chevron is the only other exit. Not ticking is not agreeing.
 */
@Composable
fun ConsentScreen(onContinue: () -> Unit, onBack: () -> Unit) {
    val scope = rememberCoroutineScope()
    var agreed by remember { mutableStateOf(DebugEnv["NB_DEBUG_CONSENT_CHECK"] == "1") }
    var shownAt by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var scrolledToBox by remember { mutableStateOf(false) }

    // The board's own values, not tokens: these are the colours the file draws this screen in.
    val eyebrow = hex(0x6E6E76)
    val ink = hex(0xF4F4F6)
    val lede = hex(0xA6A6AE)
    val bodyInk = hex(0x8A8A93)
    val rule = hex(0x1A1A1E)
    val screenPx = with(LocalDensity.current) { ScreenMetrics.height.toPx() }

    LaunchedEffect(Unit) {
        shownAt = System.currentTimeMillis()
        track("CONSENT_SHOWN", mapOf("VERSION" to ConsentStore.version, "IS_DELTA" to ConsentStore.decided))
    }
    fun msOnScreen(): Int = (System.currentTimeMillis() - shownAt).toInt()

    fun decline() {
        scope.launch {
            ConsentStore.record(ConsentStore.Choice.Declined, msOnScreen())
            onBack()
        }
    }
    BackHandler { decline() }

    Column(Modifier.fillMaxSize().background(NB.carbon)) {
        // The list scrolls under the status bar like any list; the bar itself keeps its ground.
        Box(Modifier.weight(1f).fillMaxWidth()) {
            Column(
                Modifier.fillMaxSize().statusBarsPadding().verticalScroll(rememberScrollState())
                    .padding(horizontal = 24.dp).padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(22.dp),
            ) {
                Box(
                    Modifier.padding(top = (Chrome.boardStatusBar - 30f).dp)
                        .size(44.dp)
                        .semantics { contentDescription = L("Back") }
                        .plainTap { decline() },
                    contentAlignment = Alignment.CenterStart,
                ) {
                    GText(L("‹"), NBFont.brand(400, 24f), NB.white.copy(alpha = 0.55f))
                }
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    GText(L(ConsentCopy.eyebrow), NBFont.dot(600, 11f).tracking(0.24f), eyebrow)
                    GText(L(ConsentCopy.title), NBFont.brand(600, 34f).tracking(-0.01f).lineSpacing(4f), ink)
                    GText(L(ConsentCopy.lede), NBFont.ui(300, 15f).lineSpacing(8f), lede)
                }
                for (section in ConsentCopy.sections) {
                    Column(Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                        GText(L(section.head), NBFont.dot(600, 10f).tracking(0.24f), eyebrow)
                        for (item in section.items) {
                            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                                GText(L(item.name), NBFont.brand(500, 16f).lineSpacing(6f), ink)
                                GText(L(item.why), NBFont.ui(300, 13f).lineSpacing(6f), bodyInk)
                            }
                        }
                    }
                }
                ConsentCopy.notes.forEachIndexed { i, note ->
                    Column(Modifier.fillMaxWidth()) {
                        if (i == 0) Box(Modifier.fillMaxWidth().height(1.dp).background(rule))
                        Column(Modifier.padding(top = if (i == 0) 11.dp else 0.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
                            GText(L(note.head), NBFont.dot(600, 10f).tracking(0.24f), eyebrow)
                            GText(L(note.body), NBFont.ui(300, 13f).lineSpacing(6f), bodyInk)
                        }
                    }
                }
                // The checkbox row. The rule at the top, then the box and its sentence.
                Column(
                    Modifier.fillMaxWidth().onGloballyPositioned { c ->
                        if (!scrolledToBox && c.positionInRoot().y < screenPx) {
                            scrolledToBox = true
                            track("CONSENT_SCROLLED_TO_CHECKBOX", mapOf("VERSION" to ConsentStore.version))
                        }
                    },
                ) {
                    Box(Modifier.fillMaxWidth().height(1.dp).background(rule))
                    Row(Modifier.padding(top = 13.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                        val fill by animateColorAsState(if (agreed) NB.lime1 else NB.lime1.copy(alpha = 0f), tween(120), label = "box")
                        Box(
                            Modifier.size(20.dp)
                                .semantics { contentDescription = L(ConsentCopy.agree); selected = agreed }
                                .background(fill, RoundedCornerShape(5.dp))
                                .border(1.dp, if (agreed) NB.lime1 else NB.ember1, RoundedCornerShape(5.dp))
                                .plainTap { agreed = !agreed },
                            contentAlignment = Alignment.Center,
                        ) {
                            if (agreed) {
                                Canvas(Modifier.size(12.dp)) {
                                    val s = size.width / 12f
                                    val p = Path().apply { moveTo(2f * s, 6.4f * s); lineTo(4.8f * s, 9.2f * s); lineTo(10f * s, 3f * s) }
                                    drawPath(p, NB.carbon, style = Stroke(2f * s, cap = StrokeCap.Round, join = StrokeJoin.Round))
                                }
                            }
                        }
                        GText(L(ConsentCopy.agree), NBFont.ui(400, 15f).lineSpacing(7f), ink,
                            Modifier.weight(1f))
                    }
                }
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    GText(L(ConsentCopy.ifNot), NBFont.ui(300, 13f).lineSpacing(6f), bodyInk)
                    GText(L(ConsentCopy.withdraw), NBFont.ui(300, 13f).lineSpacing(6f), bodyInk)
                }
            }
        }
        // 1F4L · 390 × 104, one 342 × 52 button. Grey and inert until the box is ticked.
        Box(Modifier.fillMaxWidth().background(NB.carbon).navigationBarsPadding().height(104.dp),
            contentAlignment = Alignment.Center) {
            val label = NBFont.ui(500, 13.5f).tracking(0.15f)
            if (agreed) {
                Box(
                    Modifier.width(NB.Layout.contentWidth - 16.dp).height(52.dp).background(NB.lime1, CircleShape)
                        .plainTap {
                            scope.launch {
                                ConsentStore.record(ConsentStore.Choice.Granted, msOnScreen())
                                onContinue()
                            }
                        },
                    contentAlignment = Alignment.Center,
                ) { GText(L(ConsentCopy.cta), label, NB.carbon) }
            } else {
                Box(
                    Modifier.width(NB.Layout.contentWidth - 16.dp).height(52.dp).background(rule, CircleShape)
                        .semantics { contentDescription = L("Continue · tick the box first") },
                    contentAlignment = Alignment.Center,
                ) { GText(L(ConsentCopy.cta), label, eyebrow) }
            }
        }
    }
}
