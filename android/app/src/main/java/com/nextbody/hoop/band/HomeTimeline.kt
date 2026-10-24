package com.nextbody.hoop.band

import java.time.Instant
import java.util.UUID

object HomeTimeline {
    enum class Accent(val raw: String) {
        meal("meal"), workout("workout"), activity("activity"), sleep("sleep"), wake("wake"),
        stress("stress"), weighIn("weighIn"), bodyScan("bodyScan"), balanceCheck("balanceCheck")
    }

    data class Meal(
        val kcal: Int,
        val protein: Int,
        val carb: Int,
        val fat: Int,
        val photoPath: String? = null,
    )

    data class Item(
        val id: String,
        val at: Instant,
        val title: String,
        val detail: String,
        val accent: Accent,
        val meal: Meal?,
        val trailing: String?,
        val endAt: Instant? = null,
        val recordID: UUID? = null,
    ) {
        val day: UserDay get() = UserDay.containing(at)
    }

    fun visible(candidates: List<Item>, on: UserDay, earlier: Boolean, now: Instant, lookbackDays: Int = 6): List<Item> {
        val day = on
        val start = if (earlier) day.adding(days = -maxOf(0, lookbackDays)).start else day.start
        val seen = HashSet<String>()
        val recorded = candidates.filter { seen.add(it.id) }
            .filter { event -> event.at <= now && (event.endAt?.let { it >= event.at && it <= now } ?: true) }
        val workouts = recorded.filter { it.accent == Accent.workout && it.endAt != null }
        return recorded.filter { it.at >= start && it.at < day.end }
            .filter { event ->
                if (event.accent != Accent.activity) return@filter true
                workouts.none { workout ->
                    val end = workout.endAt ?: return@none false
                    if (end <= workout.at) return@none false
                    val activityEnd = event.endAt
                    if (activityEnd == null || activityEnd <= event.at) {
                        return@none event.at >= workout.at && event.at < end
                    }
                    val overlap = BandTime.interval(minOf(activityEnd, end), maxOf(event.at, workout.at))
                    overlap > 0 && event.at >= workout.at.minusSeconds(5 * 60) &&
                        activityEnd <= end.plusSeconds(5 * 60)
                }
            }
            .sortedWith { a, b ->
                if (a.at == b.at) a.id.compareTo(b.id) else b.at.compareTo(a.at)
            }
    }
}
