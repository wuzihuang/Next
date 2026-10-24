package com.nextbody.hoop.features.measure

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.design.NBFont
import com.nextbody.hoop.design.tracking
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.swiftFormat
import java.time.Instant
import kotlin.math.max
import kotlin.math.min

/**
 * 06 · the body scan's shared state words: the takeover's `Phase` and onboarding's stream both
 * map onto this, so the status / headline / help lines and their tints are written once and
 * can never drift between the two screens.
 */
sealed class BodyScanState {
    data object Opening : BodyScanState()
    data object Waiting : BodyScanState()
    data object Nudge : BodyScanState()
    data object Contact : BodyScanState()
    data class Counting(val fields: Int) : BodyScanState()
    data object Halfway : BodyScanState()
    data class Lost(val grace: Int) : BodyScanState()
    data object Computing : BodyScanState()

    val status: String
        get() = when (this) {
            Opening -> ""
            Waiting -> L("WAITING FOR YOUR FINGER")
            Nudge -> L("NO CONTACT · %dS", 6)
            Contact -> L("CONTACT · CIRCUIT CLOSED")
            is Counting -> L("%d / 14 FIELDS", fields)
            Halfway -> L("HALFWAY · KEEP THE FINGER THERE")
            is Lost -> L("PAUSED · %dS TO RESUME", grace)
            Computing -> L("COMPUTING 14 FIELDS")
        }

    val statusTint: Color
        get() = when (this) {
            // E02 · the waiting line is lime: the screen saying it is ready, not a warning.
            Waiting -> NB.lime1.copy(alpha = 0.85f)
            Nudge, is Lost -> NB.ember2
            Contact, is Counting, Halfway -> NB.lime1
            Opening, Computing -> NB.white.copy(alpha = 0.40f)
        }

    val headline: String
        get() = when (this) {
            // The board's own words: which finger, and which key.
            Opening, Waiting -> L("Index finger on the side key.")
            Nudge -> L("Still nothing on the key.")
            Contact -> L("Got it. Hold still.")
            is Counting -> L("Mapping you.")
            Halfway -> L("Halfway.")
            is Lost -> L("Put it back.")
            Computing -> L("Working it out.")
        }

    val help: String
        get() = when (this) {
            Opening -> ""
            Waiting -> L("Rest your hand on the table. Nothing to press. It takes about 30 seconds.")
            Nudge -> L("Skin, not a nail or a sleeve. Let it rest, don't press.")
            Contact -> L("A tiny current crosses your body. You won't feel it.")
            // ⚠️ Body composition has no resume: lifting off restarts the whole 30 seconds.
            is Counting -> L("Lift a finger and the scan starts over.")
            Halfway -> L("One steady contact makes one reading.")
            is Lost -> L("Your finger came off the key. This one has to start over.")
            Computing -> L("You can lift your finger now.")
        }
}

/** The countdown the scanning screen carries: white while it runs, amber the moment a finger
 *  comes off — holding where it stopped, never at zero. */
@Composable
fun BodyScanCount(remaining: Int, held: Boolean, modifier: Modifier = Modifier) {
    Box(modifier.height(56.dp), contentAlignment = Alignment.Center) {
        MText(swiftFormat("00:%02d", max(0, remaining)), NBFont.dot(700, 52f).tracking(0.04f),
            if (held) NB.ember1 else NB.text1)
    }
}

/**
 * S1 · prepare: header, the stage (hoop or a card), the status sentence, the help line, then
 * the foot rule and whatever the caller puts under it. The takeover and onboarding hand in
 * their own insets — the takeover draws under the system bars, onboarding lives inside them.
 */
@Composable
fun BodyScanPrepareLayout(
    topInset: Dp,
    bottomInset: Dp,
    status: String,
    statusTint: Color,
    headline: String,
    help: String,
    header: @Composable () -> Unit,
    stage: @Composable () -> Unit,
    footer: @Composable () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(topInset))
        header()
        Box(Modifier.fillMaxWidth().weight(1f)) { stage() }
        MText(status, NBFont.dot(600, 10.5f).tracking(0.16f), statusTint,
            Modifier.heightIn(min = 13.dp).width(NB.Layout.contentWidth), align = TextAlign.Center)
        MText(headline, NBFont.brand(500, 22f).tracking(-0.01f), NB.text1,
            Modifier.padding(top = 12.dp).width(318.dp), align = TextAlign.Center)
        MText(help, NBFont.ui(300, 12.5f), NB.white.copy(alpha = 0.42f),
            Modifier.padding(top = 10.dp).width(318.dp), align = TextAlign.Center)
        Spacer(Modifier.height(20.dp))
        MText(L("NOTHING TO PRESS · KEEP STILL"), NBFont.dot(500, 9.5f).tracking(0.16f), NB.white.copy(alpha = 0.30f))
        footer()
        Spacer(Modifier.height(bottomInset))
    }
}

/**
 * S2 · scanning: header, the big count, the fields line, the body figure on a measured height,
 * the two sentences at the foot. The figure fills a capped share of what is left.
 */
@Composable
fun BodyScanScanningLayout(
    topInset: Dp,
    bottomInset: Dp,
    headerHeight: Dp,
    remaining: Int,
    held: Boolean,
    status: String,
    statusTint: Color,
    headline: String,
    help: String,
    beat: Int,
    total: Int,
    beatAt: Instant,
    complete: Boolean,
    header: @Composable () -> Unit,
    footer: @Composable () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        val top = topInset + headerHeight + 18.dp + 56.dp + 16.dp
        val bottom = bottomInset + 28.dp + 30.dp + 40.dp + 10.dp + 16.dp
        val stageHeight = min(maxHeight.value * 0.53f, max(220f, (maxHeight - top - bottom).value)).dp
        Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.height(topInset))
            header()
            BodyScanCount(remaining, held, Modifier.padding(top = 18.dp))
            MText(status, NBFont.dot(600, 10.5f).tracking(0.16f), statusTint,
                Modifier.padding(top = 2.dp).width(NB.Layout.contentWidth), align = TextAlign.Center)
            Spacer(Modifier.weight(1f).heightIn(min = 8.dp))
            ScanBody(beat = beat, total = total, beatAt = beatAt, held = held, complete = complete,
                modifier = Modifier.fillMaxWidth().height(stageHeight))
            Spacer(Modifier.weight(1f).heightIn(min = 8.dp))
            MText(headline, NBFont.brand(500, 24f).tracking(-0.01f), NB.text1,
                Modifier.width(318.dp), align = TextAlign.Center)
            MText(help, NBFont.ui(300, 12.5f), NB.white.copy(alpha = 0.42f),
                Modifier.padding(top = 10.dp).width(318.dp), align = TextAlign.Center)
            footer()
            Spacer(Modifier.height(bottomInset))
        }
    }
}
