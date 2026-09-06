import SwiftUI
import WidgetKit

/// Live Activity, the TODAY glance, and the Shot shutter.
@main
struct NextBodyLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        SessionLiveActivity()
        TodayWidget()
        ShotWidget()
    }
}
