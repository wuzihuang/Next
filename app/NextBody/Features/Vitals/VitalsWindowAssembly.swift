import Foundation

/// Tick merge and ruler for a vitals second-level page. Hero math stays on the
/// instrument; this module only names the window and clips the curve to it.
enum VitalsWindowAssembly {
    static func window(metric: VitalsMetric, range: RollingPills, day: UserDay,
                       now: Date, sleep: SleepSummary?) -> VitalsWindow {
        let detail = DetailWindow(metric.detailSurface, range)
        if metric == .heart, range != .day {
            return VitalsWindow.rollingUserDays(detail.days, endingOn: day, now: now)
        }
        if metric.hasMetricRange, range != .day {
            return VitalsWindow.rollingUserDays(detail.days, endingOn: day, now: now)
        }
        switch metric.timeline {
        case .lastNight:
            return VitalsWindow.night(
                start: sleep?.sleepStart,
                end: sleep?.wakeAt,
                fallback: day
            )
        case .rolling24Hours:
            return VitalsWindow.rolling24Hours(endingAt: now)
        case .userDayToNow:
            return VitalsWindow.userDay(day, now: now)
        }
    }

    static func ticks(metric: VitalsMetric, window: VitalsWindow,
                      history: [DailyMetrics], today: DailyMetrics) -> [VitalSample] {
        guard metric.timeline != .lastNight || window.span > 0 else { return [] }
        let stored = history.flatMap(\.vitalsCurve)
        return VitalSample.merging(stored, with: today.vitalsCurve)
            .filter {
                window.contains($0.ts)
                    && (metric.timeline != .lastNight
                        || today.sleep?.containsSleepTimestamp($0.ts) == true)
            }
    }

    static func displayMetrics(metric: VitalsMetric, range: RollingPills,
                               today: DailyMetrics, ticks: [VitalSample]) -> DailyMetrics {
        var metrics = today
        metrics.vitalsCurve = ticks
        if metric.timeline == .rolling24Hours || (metric == .heart && range != .day) {
            metrics.zoneMinutes = nil
            metrics.peakHR = nil
        }
        return metrics
    }
}
