package com.nextbody.hoop.band

import java.time.Instant
import kotlin.math.exp

/** End-of-session arithmetic for the folded recap (#38) and the simulator load bump (#37).
 *  Zone boundaries mirror nb.training_zone / nb.zone_of. Z0 stays below the training zones.
 *  Adjacent beats farther than 15 s do not add duration — the same gap the ingest path uses. */
object SportRecapMath {
    const val continuityGap: Double = 15.0

    data class Beat(val at: Instant, val bpm: Int, val segment: Int = 0)

    data class Recap(
        val seconds: Int,
        val avgHR: Int?,
        val peakHR: Int?,
        val curve: List<Double>,
        val curvePoints: List<Beat>,
        val observedSeconds: Double,
        val zoneMinutes: List<Double>,
        val aerobicMinutes: Int,
        val anaerobicMinutes: Int,
        val loadDelta: Double,
        val conclusion: Conclusion,
    ) {
        enum class Conclusion(val raw: String) {
            noHeart("No heart-rate record."),
            insufficient("Not enough continuous heart-rate data for zones."),
            belowZones("Recorded heart rate stayed below Z1."),
            aerobic("Mostly aerobic."),
            anaerobic("Mostly anaerobic."),
            mixed("Mixed aerobic and anaerobic."),
        }
    }

    private val zoneWeights = listOf(0.0, 0.15, 0.5, 1.2, 3.0, 6.0)

    fun recap(beats: List<Beat>, restHR: Int?, maxHR: Int, seconds: Int): Recap {
        val valid = beats.filter { it.bpm in 1..250 }.sortedBy { it.at }
        val avg = if (valid.isEmpty()) null else (valid.sumOf { it.bpm }.toDouble() / valid.size).roundedAway().toInt()
        val peak = valid.maxOfOrNull { it.bpm }
        val zones = DoubleArray(5)
        var load = 0.0
        var observed = 0.0
        if (valid.size >= 2) {
            for (i in 1 until valid.size) {
                val dt = BandTime.interval(valid[i].at, valid[i - 1].at)
                if (!(dt > 0 && dt <= continuityGap && valid[i].segment == valid[i - 1].segment)) continue
                observed += dt
                val zone = zoneIndex(valid[i].bpm, restHR, maxHR)
                if (zone > 0) zones[zone - 1] += dt / 60
                // Simulator-only visual fixture. Production load comes from settlement.
                load += dt / 60 * zoneWeights[zone]
            }
        }
        val aerobicSeconds = (zones[0] + zones[1] + zones[2]) * 60
        val anaerobicSeconds = (zones[3] + zones[4]) * 60
        val aerobic = (aerobicSeconds / 60).roundedAway().toInt()
        val anaerobic = (zones[3] + zones[4]).roundedAway().toInt()
        val conclusion = when {
            valid.isEmpty() -> Recap.Conclusion.noHeart
            observed == 0.0 -> Recap.Conclusion.insufficient
            zones.sum() == 0.0 -> Recap.Conclusion.belowZones
            aerobicSeconds > anaerobicSeconds * 2 -> Recap.Conclusion.aerobic
            anaerobicSeconds > aerobicSeconds * 2 -> Recap.Conclusion.anaerobic
            else -> Recap.Conclusion.mixed
        }
        return Recap(
            seconds = maxOf(0, seconds),
            avgHR = avg,
            peakHR = peak,
            curve = downsample(valid.map { it.bpm.toDouble() }, 40),
            curvePoints = displayPoints(valid),
            observedSeconds = observed,
            zoneMinutes = zones.toList(),
            aerobicMinutes = aerobic,
            anaerobicMinutes = anaerobic,
            loadDelta = minOf(20.9, 21 * (1 - exp(-load / 60))),
            conclusion = conclusion)
    }

    /** Returns Z0…Z5, including observed heart rates below the first training zone. */
    fun zoneIndex(bpm: Int, rest: Int?, maxHR: Int): Int {
        if (maxHR <= 0) return 0
        val thresholds: List<Double>
        val pct: Double
        if (rest != null && maxHR > rest) {
            pct = (bpm - rest).toDouble() / (maxHR - rest).toDouble()
            thresholds = listOf(0.30, 0.40, 0.55, 0.70, 0.85)
        } else {
            pct = bpm.toDouble() / maxHR.toDouble()
            thresholds = listOf(0.50, 0.60, 0.70, 0.80, 0.90)
        }
        return thresholds.count { pct >= it }
    }

    /** Preserve time and continuity before bounding the drawing payload. A long workout
     *  must fit the cloud document budget; subsampling never turns a true gap into a line. */
    fun displayPoints(beats: List<Beat>, limit: Int = 4_000): List<Beat> {
        if (limit <= 1 || beats.isEmpty()) return emptyList()
        var segment = 0
        var previous: Beat? = null
        val normalized = beats.map { beat ->
            val prev = previous
            if (prev != null && (beat.segment != prev.segment || BandTime.interval(beat.at, prev.at) > continuityGap)) segment += 1
            previous = beat
            Beat(at = beat.at, bpm = beat.bpm, segment = segment)
        }
        if (normalized.size <= limit) return normalized
        val step = (normalized.size - 1).toDouble() / (limit - 1).toDouble()
        return (0 until limit).map { normalized[(it * step).roundedAway().toInt()] }
    }

    private fun downsample(values: List<Double>, count: Int): List<Double> {
        if (values.isEmpty()) return emptyList()
        if (values.size <= count) return values
        val step = (values.size - 1).toDouble() / (count - 1).toDouble()
        return (0 until count).map { i -> values[minOf(values.size - 1, (i * step).roundedAway().toInt())] }
    }
}
