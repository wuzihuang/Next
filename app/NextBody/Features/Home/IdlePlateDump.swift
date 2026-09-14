#if DEBUG
import SwiftUI
import os

/// DEBUG · `SIMCTL_CHILD_NB_DUMP_PLATES=1` plus optional `NB_DUMP_PLATE=1…28`
/// holds one IdlePlateArt on the real window so `simctl io screenshot` can
/// grab it. Detached ImageRenderer / drawHierarchy of Canvas stays black.
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
}

struct IdlePlateDumpOverlay: View {
    var body: some View {
        if IdlePlateDump.requested {
            let plate = IdlePlateDump.plate
            ZStack {
                Color(hex: 0x070709)
                Canvas { ctx, sz in
                    let pose = IdlePlateMotion.pose(plate: plate, clock: IdlePlateDump.clock, moving: true)
                    IdlePlateArt.draw(plate: plate, pose: pose,
                                      charge: 0.72, chargeKnown: true,
                                      in: &ctx, size: sz)
                }
                .frame(width: IdlePlateArt.board.width, height: IdlePlateArt.board.height)
            }
            .ignoresSafeArea()
            .onAppear {
                Logger(subsystem: "com.nextbody.hoop", category: "debug")
                    .notice("idle plate dump showing plate=\(plate)")
            }
        }
    }
}
#endif
