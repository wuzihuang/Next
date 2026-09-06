import SwiftUI
import WidgetKit

struct ShotEntry: TimelineEntry {
    let date: Date
}

struct ShotProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShotEntry {
        ShotEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (ShotEntry) -> Void) {
        completion(ShotEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShotEntry>) -> Void) {
        completion(Timeline(entries: [ShotEntry(date: Date())], policy: .never))
    }
}

struct ShotWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetBridge.shotKind, provider: ShotProvider()) { _ in
            ShotWidgetFace()
                .widgetURL(WidgetBridge.photoURL)
                .containerBackground(for: .widget) { Island.carbon }
        }
        .configurationDisplayName("Log a meal")
        .description("Photograph a meal.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

#Preview("Log a meal", as: .systemSmall) {
    ShotWidget()
} timeline: {
    ShotEntry(date: .now)
}
