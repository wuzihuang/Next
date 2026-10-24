package com.nextbody.hoop.features.vitals

import com.nextbody.hoop.band.DetailSurface
import com.nextbody.hoop.band.DetailWindow
import com.nextbody.hoop.band.MealResponseIndex
import com.nextbody.hoop.band.OpticalAutoSwitch
import com.nextbody.hoop.band.RollingPills
import com.nextbody.hoop.model.DailyMetrics
import java.time.Instant

/** Builds the page-two RESPONSE index from the day the app already holds. Sleep windows come
 *  from nights on file; optical points are a dedicated series, not origin ticks. */
object MealResponsePresentation {
    /** Swift's `(below:, near:, above:)`. */
    data class Split(val below: Int, val near: Int, val above: Int)

    data class Board(
        val index: MealResponseIndex.Result,
        val range: RollingPills,
        val window: MealResponseIndex.HorizonWindow,
    ) {
        val heroPoint: Double?
            get() = when (range) {
                RollingPills.day -> index.latestPoint
                RollingPills.week, RollingPills.month -> window.dailyMean
            }

        val heroPercent: Int?
            get() = when (range) {
                RollingPills.day -> index.hero
                RollingPills.week, RollingPills.month -> {
                    val mean = window.dailyMean
                    if (mean == null) null else MealResponseIndex.percent(mean, index.ownMedian ?: 0.0)
                }
            }

        val split: Split
            get() = when (range) {
                RollingPills.day -> Split(index.below, index.near, index.above)
                RollingPills.week, RollingPills.month -> Split(window.below, window.near, window.above)
            }

        val pointCount: Int
            get() = when (range) {
                RollingPills.day -> index.trendPoints.size
                RollingPills.week, RollingPills.month -> window.points.size
            }
    }

    fun index(
        today: DailyMetrics,
        history: List<DailyMetrics>,
        points: List<MealResponseIndex.Point>,
        zerosToday: Boolean,
        now: Instant = Instant.now(),
        switchOff: Boolean = OpticalAutoSwitch.isOff,
    ): MealResponseIndex.Result {
        val windows = (listOf(today) + history).mapNotNull { day ->
            val start = day.sleep?.sleepStart ?: return@mapNotNull null
            val wake = day.sleep?.wakeAt ?: return@mapNotNull null
            if (wake <= start) null else MealResponseIndex.SleepWindow(start, wake)
        }
        return MealResponseIndex.make(points, windows, now, switchOff = switchOff, allZeros = zerosToday)
    }

    fun board(
        today: DailyMetrics,
        history: List<DailyMetrics>,
        points: List<MealResponseIndex.Point>,
        zerosToday: Boolean,
        now: Instant = Instant.now(),
        range: RollingPills = RollingPills.day,
        switchOff: Boolean = OpticalAutoSwitch.isOff,
    ): Board {
        val index = index(today, history, points, zerosToday, now, switchOff)
        return Board(
            index = index,
            range = range,
            window = MealResponseIndex.horizonWindow(
                points = points,
                ownMedian = index.ownMedian,
                now = now,
                horizon = DetailWindow(DetailSurface.response, range).responseHorizon,
            ),
        )
    }
}
