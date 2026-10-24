package com.nextbody.hoop.features.vitals

import com.nextbody.hoop.band.DetailWindow
import com.nextbody.hoop.band.RollingPills
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.band.VitalSample
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.SleepSummary
import java.time.Instant

/** Tick merge and ruler for a vitals second-level page. Hero math stays on the instrument;
 *  this module only names the window and clips the curve to it. */
object VitalsWindowAssembly {
    fun window(metric: VitalsMetric, range: RollingPills, day: UserDay, now: Instant, sleep: SleepSummary?): VitalsWindow {
        val detail = DetailWindow(metric.detailSurface, range)
        if (metric == VitalsMetric.heart && range != RollingPills.day) {
            return VitalsWindow.rollingUserDays(detail.days, day, now)
        }
        if (metric.hasMetricRange && range != RollingPills.day) {
            return VitalsWindow.rollingUserDays(detail.days, day, now)
        }
        return when (metric.timeline) {
            VitalsTimelineKind.lastNight -> VitalsWindow.night(sleep?.sleepStart, sleep?.wakeAt, day)
            VitalsTimelineKind.userDayToNow -> VitalsWindow.userDay(day, now)
        }
    }

    fun ticks(metric: VitalsMetric, window: VitalsWindow, history: List<DailyMetrics>, today: DailyMetrics): List<VitalSample> {
        if (metric.timeline == VitalsTimelineKind.lastNight && window.span <= 0) return emptyList()
        val stored = history.flatMap { it.vitalsCurve }
        return VitalSample.merging(stored, today.vitalsCurve).filter {
            window.contains(it.ts) && (metric.timeline != VitalsTimelineKind.lastNight ||
                today.sleep?.containsSleepTimestamp(it.ts) == true)
        }
    }

    fun displayMetrics(metric: VitalsMetric, range: RollingPills, today: DailyMetrics, ticks: List<VitalSample>): DailyMetrics {
        val metrics = today.copy()
        metrics.vitalsCurve = ticks
        if (range != RollingPills.day) {
            metrics.zoneMinutes = null
            metrics.peakHR = null
        }
        return metrics
    }
}
