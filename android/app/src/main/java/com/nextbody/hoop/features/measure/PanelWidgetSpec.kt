package com.nextbody.hoop.features.measure

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import com.nextbody.hoop.app.Destination
import com.nextbody.hoop.features.home.panel.BalanceAnswer
import com.nextbody.hoop.features.home.panel.CompositionAnswer
import com.nextbody.hoop.features.home.panel.PanelData
import com.nextbody.hoop.features.home.panel.PanelTag
import com.nextbody.hoop.features.home.panel.PanelType
import com.nextbody.hoop.features.home.panel.PanelWidget

/**
 * What a measurement or a sport session folds back onto the home panel — the fields of
 * Swift's `PanelWidget` these two features fill, field for field. Home's panel port turns it
 * into its own `PanelWidget` through [toPanelWidget].
 *
 * Kept as a plain description so the measure / sport features do not depend on the panel's
 * renderer, which is ported separately.
 */
data class PanelWidgetSpec(
    val type: Type,
    /** ≤ 18, upper-cased */
    val title: String,
    /** MOVE / FUEL / RECOVER / ALERT — classification only */
    val tag: Tag?,
    val sentence: String,
    val footer: String?,
    val action: String?,
    val hero: String? = null,
    val accentOverride: Color? = null,
    val targetOverride: Destination? = null,
    val data: Data = Data.None,
    /** 06 · 20 · the body scan's own block. */
    val composition: CompositionAnswer? = null,
    /** 06 · the balance check's own frame. */
    val balance: BalanceAnswer? = null,
    /** 06 · 17 · tapping the frame asks about the numbers (AI-only; inert while AI is off). */
    val replyPrompt: String? = null,
    /** 06 · 16 · the measured number as a 60 pt hero, with its own line under it. */
    val heroLarge: Boolean = false,
    val heroSub: String? = null,
) {
    /** Swift `PanelType` cases these features produce. */
    enum class Type { wave, metric, workout, text }

    /** Swift `PanelTag`. */
    enum class Tag(val raw: String) { move("MOVE"), fuel("FUEL"), recover("RECOVER"), alert("ALERT") }

    /** Swift `PanelData` cases these features produce. */
    sealed class Data {
        data object None : Data()
        data class Trace(val samples: List<Double>, val hz: Double) : Data()
        data class Rows(val items: List<RowItem>) : Data()
    }

    data class RowItem(val label: String, val value: String, val spark: List<Double>? = null, val tint: Color? = null)

    data class CompositionAnswer(
        /** BODY FAT · 22.1% IN JUNE */
        val heroSub: String,
        val fields: List<Field>,
    ) {
        data class Field(val label: String, val value: String, val tint: Color)
    }

    data class BalanceAnswer(
        val headline: String,
        val note: String,
        /** 0…1 · the beat-to-beat half's share of the cloud. */
        val restShare: Double,
        val footer: String,
        /** Consecutive interval pairs in milliseconds: (this beat, the next). */
        val points: List<Pair<Double, Double>>,
    )
}

/** The panel's own widget for this description (features.home.panel). */
fun PanelWidgetSpec.toPanelWidget(): PanelWidget = PanelWidget(
    type = when (type) {
        PanelWidgetSpec.Type.wave -> PanelType.wave
        PanelWidgetSpec.Type.metric -> PanelType.metric
        PanelWidgetSpec.Type.workout -> PanelType.workout
        PanelWidgetSpec.Type.text -> PanelType.text
    },
    title = title,
    tag = tag?.let { t -> PanelTag.entries.first { it.raw == t.raw } },
    sentence = sentence,
    footer = footer,
    action = action,
    hero = hero,
    accentOverride = accentOverride,
    targetOverride = targetOverride,
    data = when (val d = data) {
        PanelWidgetSpec.Data.None -> PanelData.None
        is PanelWidgetSpec.Data.Trace -> PanelData.Trace(d.samples, d.hz)
        is PanelWidgetSpec.Data.Rows -> PanelData.Rows(d.items.map { PanelData.RowItem(it.label, it.value, it.spark, it.tint) })
    },
    composition = composition?.let { c ->
        CompositionAnswer(c.heroSub, c.fields.map { CompositionAnswer.Field(it.label, it.value, it.tint) })
    },
    balance = balance?.let { b ->
        BalanceAnswer(b.headline, b.note, b.restShare, b.footer,
            b.points.map { Offset(it.first.toFloat(), it.second.toFloat()) })
    },
    replyPrompt = replyPrompt,
    heroLarge = heroLarge,
    heroSub = heroSub,
)
