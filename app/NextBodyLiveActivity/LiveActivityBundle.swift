import SwiftUI
import WidgetKit

/// Live Activity and the TODAY glance. TODAY only displays the day's numbers.
@main
struct NextBodyLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        SessionLiveActivity()
        TodayWidget()
    }
}
