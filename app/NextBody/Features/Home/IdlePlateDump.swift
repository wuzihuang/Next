#if DEBUG
import SwiftUI
import os

/// DEBUG · `SIMCTL_CHILD_NB_DUMP_PLATES=1` plus optional `NB_DUMP_PLATE=1…28`
/// holds the real deep-space renderer on the window for `simctl io screenshot`.
/// `NB_DUMP_CLOCK` selects an exact still; `NB_DUMP_LIVE=1` advances it for video.
enum IdlePlateDump {
    static var requested: Bool {
        guard let raw = ProcessInfo.processInfo.environment["NB_DUMP_PLATES"] else { return false }
        return !raw.isEmpty
    }

    static var plate: Int {
        let raw = Int(ProcessInfo.processInfo.environment["NB_DUMP_PLATE"] ?? "1") ?? 1
        return min(28, max(1, raw))
    }

    static var clock: Double {
        Double(ProcessInfo.processInfo.environment["NB_DUMP_CLOCK"] ?? "0") ?? 0
    }

    static var live: Bool {
        ProcessInfo.processInfo.environment["NB_DUMP_LIVE"] == "1"
    }
}

struct IdlePlateDumpOverlay: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var elapsed: Double = 0
    @State private var lastTick: Date?
    @State private var visible = false

    var body: some View {
        if IdlePlateDump.requested {
            let plate = IdlePlateDump.plate
            ZStack {
                Color(hex: 0x070709)
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { timeline in
                    DeepSpacePlate(plate: plate, clock: IdlePlateDump.clock + elapsed)
                        .onChange(of: timeline.date) { _, now in
                            guard moving else { return }
                            let previous = lastTick ?? now
                            lastTick = now
                            elapsed += min(max(0, now.timeIntervalSince(previous)), 0.1)
                        }
                }
                .frame(width: 358, height: 470)
            }
            .ignoresSafeArea()
            .onAppear {
                visible = true
                lastTick = nil
                Logger(subsystem: "com.nextbody.hoop", category: "debug")
                    .notice("idle plate dump showing plate=\(plate)")
            }
            .onDisappear {
                visible = false
                lastTick = nil
            }
            .onChange(of: moving) { _, _ in lastTick = nil }
        }
    }

    private var moving: Bool {
        IdlePlateDump.live && visible && scenePhase == .active
    }
}
#endif
