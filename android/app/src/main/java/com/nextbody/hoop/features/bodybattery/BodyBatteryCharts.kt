package com.nextbody.hoop.features.bodybattery

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import com.nextbody.hoop.design.NB
import kotlin.math.max
import kotlin.math.min

/**
 * One point per day on a 0–100 ruler, drawn as a line so WEEK and MONTH read the
 * same way DAY's curve does. A day without a morning reading is a hole in the line,
 * bridged by a dashed segment — never a dim zero. Today carries the ringed lime dot.
 *
 * ⚠️ Points sit at the centre of an equal-width column, `(i + 0.5) / count`, so a label
 * row of weight(1f) columns lines up under them without any edge arithmetic.
 */
@Composable
fun BodyBatteryDayLine(
    values: List<Int?>,
    /** The dashed rule the window's typical morning sits on. null draws no rule. */
    average: Double?,
    modifier: Modifier = Modifier,
    todayIndex: Int? = null,
) {
    Canvas(modifier) {
        if (values.isEmpty()) return@Canvas
        val u = density
        val pad = 8f * u
        val w = size.width
        val h = size.height
        val plot = max(0f, h - pad * 2)
        val slot = w / values.size
        fun y(value: Double): Float = h - pad - (min(100.0, max(0.0, value)) / 100).toFloat() * plot
        fun point(index: Int, value: Int): Offset = Offset((index + 0.5f) * slot, y(value.toDouble()))

        for (rule in listOf(30.0, 70.0)) {
            drawRect(NB.white.copy(alpha = 0.06f), Offset(0f, y(rule)), Size(w, 1f * u))
        }
        drawRect(NB.white.copy(alpha = 0.10f), Offset(0f, h - 1f * u), Size(w, 1f * u))
        // ⚠️ A day with no morning reading gets a mark on the floor, never a point at 0 —
        // and without it a window that has nothing yet is an empty box rather than a
        // field waiting for readings.
        values.forEachIndexed { i, value ->
            if (value != null) return@forEachIndexed
            val mw = min(14f * u, slot * 0.5f)
            drawRect(NB.white.copy(alpha = 0.16f), Offset((i + 0.5f) * slot - mw / 2, h - 3f * u), Size(mw, 2f * u))
        }

        val runs = bodyBatteryRuns(values).map { run -> run.map { point(it.first, it.second) } }
        if (runs.isEmpty()) return@Canvas

        // The wash under the line gives a flat week a body. It is anchored to the run's
        // own crest, so a line riding high never fills the whole card, and it stops at
        // the run's ends, so a missing morning stays a hole in the fill too.
        for (run in runs) {
            if (run.size <= 1) continue
            val area = Path().apply {
                moveTo(run[0].x, h)
                for (p in run) lineTo(p.x, p.y)
                lineTo(run[run.size - 1].x, h)
                close()
            }
            val crest = run.minOf { it.y }
            drawPath(area, Brush.verticalGradient(
                listOf(NB.lime1.copy(alpha = 0.18f), NB.lime1.copy(alpha = 0f)), startY = crest, endY = h))
        }

        runs.forEachIndexed { i, run ->
            if (run.size > 1) {
                val line = Path().apply {
                    moveTo(run[0].x, run[0].y)
                    for (p in run.drop(1)) lineTo(p.x, p.y)
                }
                drawPath(line, NB.lime1, style = Stroke(2f * u, cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
            if (i + 1 < runs.size) {
                val tail = run.last()
                val head = runs[i + 1].first()
                drawLine(NB.lime1.copy(alpha = 0.28f), tail, head, strokeWidth = 1.2f * u,
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(2f * u, 4f * u)))
            }
        }

        if (average != null) {
            drawLine(NB.limePale.copy(alpha = 0.4f), Offset(0f, y(average)), Offset(w, y(average)),
                strokeWidth = 1f * u, pathEffect = PathEffect.dashPathEffect(floatArrayOf(3f * u, 4f * u)))
        }

        // A run of one has no line at all, so its dot is the reading.
        val r = (if (values.size > 14) 1.8f else 2.6f) * u
        for (p in runs.flatten()) drawCircle(NB.lime1.copy(alpha = 0.9f), r, p)

        if (todayIndex != null && todayIndex in values.indices) {
            val value = values[todayIndex]
            if (value != null) {
                val p = point(todayIndex, value)
                drawCircle(NB.lime1.copy(alpha = 0.45f), 6f * u, p, style = Stroke(1f * u))
                drawCircle(NB.lime1, 3.4f * u, p)
            }
        }
    }
}

/** Uninterrupted stretches of days that published a reading. An empty slot ends a run. */
fun bodyBatteryRuns(values: List<Int?>): List<List<Pair<Int, Int>>> {
    val out = mutableListOf<List<Pair<Int, Int>>>()
    var run = mutableListOf<Pair<Int, Int>>()
    values.forEachIndexed { i, value ->
        if (value != null) {
            run.add(i to value)
        } else if (run.isNotEmpty()) {
            out.add(run)
            run = mutableListOf()
        }
    }
    if (run.isNotEmpty()) out.add(run)
    return out
}
