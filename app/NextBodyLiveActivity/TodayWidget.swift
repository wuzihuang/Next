import SwiftUI
import WidgetKit

struct TodayEntry: TimelineEntry {
    let date: Date
    let readout: WidgetFaceMath.TodayReadout
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        let glance = WidgetFaceMath.Glance.placeholder
        return TodayEntry(date: glance.numbersAt,
                          readout: WidgetFaceMath.today(glance, now: glance.numbersAt))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entry(now: Date(), placeholder: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let glance = WidgetBridge.loadGlance() ?? (context.isPreview ? .placeholder : .empty)
        let next = WidgetFaceMath.nextReload(after: glance, now: now)
        completion(Timeline(entries: [TodayEntry(date: now, readout: WidgetFaceMath.today(glance, now: now))],
                            policy: .after(next)))
    }

    private func entry(now: Date, placeholder: Bool) -> TodayEntry {
        let glance = WidgetBridge.loadGlance() ?? (placeholder ? .placeholder : .empty)
        return TodayEntry(date: now, readout: WidgetFaceMath.today(glance, now: now))
    }
}

struct TodayWidget: Widget {
    static let kind = WidgetBridge.todayKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.todayKind, provider: TodayProvider()) { entry in
            TodayWidgetFace(readout: entry.readout)
                .widgetURL(URL(string: "nextbody://home"))
                .containerBackground(for: .widget) { Island.carbon }
        }
        .configurationDisplayName("Today")
        .description("Body battery, training load, and what you ate.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
