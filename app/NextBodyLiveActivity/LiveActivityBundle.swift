import SwiftUI
import WidgetKit

/// The extension's whole contents: one Live Activity and no home-screen widgets.
@main
struct NextBodyLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        SessionLiveActivity()
    }
}
