import SwiftUI

/// Sport Mode · pick one of the catalogued modes and open it on the band. The moment the
/// band takes it this page is done: it returns to the root, and the session lives on the
/// home screen as the panel grown full size (`LiveSessionTakeover`) until STOP is held there.
/// Entered from the plus menu and from Training's START A SESSION.
struct SportModeView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    @State private var starting: Int?
    @State private var errorLine: String?
    /// Modes this firmware refused. Kept for the page's life so a dead row is not offered twice.
    @State private var refused: Set<Int> = []

    private var connected: Bool { data.band.connected }

    var body: some View {
        DetailScroll(glow: NB.cyan1, title: "SPORT MODE", trailing: {
            HStack(spacing: 7) {
                Circle().fill(connected ? NB.lime1 : NB.white.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text(connected ? "CONNECTED" : "DISCONNECTED")
                    .font(NBFont.dot(600, 10)).tracking(0.2 * 10)
                    .foregroundStyle(connected ? NB.lime1 : NB.text3Prod)
            }
            .padding(.horizontal, 10).frame(height: 24)
            .overlay(connected ? nil : Capsule().stroke(NB.hairline, lineWidth: 1))
        }) {
            picker
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
        } onBack: {
            router.backToRoot()
        }
        .task {
            await Analytics.shared.track("SPORT_MODE_OPEN", ["CONNECTED": connected])
            if Band.live.state != .connected { await Band.live.reconnectIfBound() }
            data.band.connected = Band.live.state == .connected
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick a mode. The band opens it, and home turns into the session until you stop.")
                .font(NBFont.ui(300, 13)).tracking(0.02 * 13)
                .foregroundStyle(NB.white.opacity(0.42))

            if !connected {
                Text("THE BAND ISN'T CONNECTED")
                    .font(NBFont.dot(600, 10.5)).tracking(0.12 * 10.5)
                    .foregroundStyle(NB.ember1)
            }
            if let errorLine {
                Text(errorLine)
                    .font(NBFont.dot(600, 10.5)).tracking(0.12 * 10.5)
                    .foregroundStyle(NB.ember1)
            }

            VStack(spacing: 0) {
                ForEach(Array(SportModeCatalog.modes.enumerated()), id: \.element.id) { index, mode in
                    let dead = refused.contains(mode.rawValue)
                    Button { start(mode) } label: {
                        HStack(spacing: 10) {
                            Text(mode.name)
                                .font(NBFont.dot(500, 12)).tracking(0.1 * 12)
                                .foregroundStyle(dead || !connected ? NB.white.opacity(0.32) : NB.text1)
                            Text("#\(mode.rawValue)")
                                .font(NBFont.dot(400, 10)).tracking(0.1 * 10)
                                .foregroundStyle(NB.white.opacity(0.28))
                            Spacer(minLength: 0)
                            if starting == mode.rawValue {
                                ProgressView().tint(NB.cyan1)
                            } else if dead {
                                Text("NO")
                                    .font(NBFont.dot(600, 10.5)).tracking(0.12 * 10.5)
                                    .foregroundStyle(NB.ember1)
                            } else {
                                Text("GO")
                                    .font(NBFont.dot(600, 10.5)).tracking(0.12 * 10.5)
                                    .foregroundStyle(connected ? NB.cyan1 : NB.white.opacity(0.28))
                            }
                        }
                        .padding(.horizontal, 16).frame(height: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!connected || starting != nil || dead)
                    if index < SportModeCatalog.modes.count - 1 {
                        Hairline().padding(.leading, 16)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .cardSkin()
        }
    }

    /// The tap is the start. The session is handed to the store and the page leaves at
    /// once; the takeover grows out of home's panel while the band is still being asked,
    /// and folds back on its own if the band says no.
    private func start(_ mode: SportModeOption) {
        guard connected, starting == nil, LiveSessionStore.shared.session == nil else { return }
        errorLine = nil
        LiveSessionStore.shared.begin(mode, profile: data.profile,
                                      weightKg: data.today.weightKg ?? data.weighIns.first?.weightKg)
        router.backToRoot()
    }
}
