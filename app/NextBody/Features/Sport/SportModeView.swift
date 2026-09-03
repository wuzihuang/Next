import SwiftUI

/// Sport Mode · pick one of the catalogued modes, open it on the band, keep it open until
/// Stop. Entered from the plus menu (and from Training's START A SESSION once that CTA is live).
/// Back always stops a running session first — leaving one open would drain the band.
struct SportModeView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    @State private var active: SportModeOption?
    @State private var startedAt: Date?
    @State private var starting: Int?
    @State private var stopping = false
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
            VStack(alignment: .leading, spacing: 14) {
                if let active, let startedAt {
                    sessionCard(active, startedAt: startedAt)
                } else {
                    picker
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        } onBack: {
            Task { await leave() }
        }
        .task {
            await Analytics.shared.track("SPORT_MODE_OPEN", ["CONNECTED": connected])
            if Band.live.state != .connected { await Band.live.reconnectIfBound() }
            data.band.connected = Band.live.state == .connected
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick a mode. The band opens it and keeps it open until you stop.")
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

    private func sessionCard(_ mode: SportModeOption, startedAt: Date) -> some View {
        VStack(spacing: 22) {
            Text(mode.name.uppercased())
                .font(NBFont.dot(700, 14)).tracking(0.18 * 14)
                .foregroundStyle(NB.cyanPale)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(elapsed(from: startedAt, to: context.date))
                    .font(NBFont.dot(700, 48)).tracking(0.02 * 48)
                    .foregroundStyle(NB.text1)
                    .monospacedDigit()
            }
            Text("SESSION RUNNING · #\(mode.rawValue)")
                .font(NBFont.dot(600, 10.5)).tracking(0.14 * 10.5)
                .foregroundStyle(NB.white.opacity(0.38))

            if let errorLine {
                Text(errorLine)
                    .font(NBFont.dot(600, 10.5)).tracking(0.12 * 10.5)
                    .foregroundStyle(NB.ember1)
            }

            Button {
                Task { await stop(thenLeave: false) }
            } label: {
                Text(stopping ? "STOPPING…" : "STOP SESSION")
                    .font(NBFont.ui(500, 12)).tracking(0.2 * 12)
                    .foregroundStyle(NB.carbon)
                    .frame(width: NB.Layout.contentWidth, height: 48)
                    .background(NB.lime1, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(stopping)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .cardSkin()
    }

    private func start(_ mode: SportModeOption) {
        guard connected, starting == nil, active == nil else { return }
        starting = mode.rawValue
        errorLine = nil
        Task {
            defer { starting = nil }
            do {
                try await Band.live.startSportMode(mode.rawValue)
                active = mode
                startedAt = Date()
                await Analytics.shared.track("SESSION_START", [
                    "MODE": mode.rawValue, "NAME": mode.name,
                ])
            } catch {
                if case BandError.unsupported = error {
                    refused.insert(mode.rawValue)
                } else if case BandError.rejected = error {
                    refused.insert(mode.rawValue)
                }
                errorLine = error.localizedDescription
            }
        }
    }

    private func stop(thenLeave: Bool) async {
        guard let active else {
            if thenLeave { await MainActor.run { router.backToRoot() } }
            return
        }
        stopping = true
        errorLine = nil
        let mode = active
        let started = startedAt ?? Date()
        defer { stopping = false }
        do {
            try await Band.live.stopSportMode(mode.rawValue)
            let sec = Int(Date().timeIntervalSince(started))
            await Analytics.shared.track("SESSION_END", [
                "MODE": mode.rawValue, "SEC": sec,
            ])
            self.active = nil
            startedAt = nil
            if thenLeave { await MainActor.run { router.backToRoot() } }
        } catch {
            errorLine = error.localizedDescription
            // A failed stop still leaves the page when the user pressed Back — better to
            // surface the error on Home than trap them on a stuck session screen.
            if thenLeave {
                self.active = nil
                startedAt = nil
                await MainActor.run { router.backToRoot() }
            }
        }
    }

    private func leave() async {
        await stop(thenLeave: true)
    }

    private func elapsed(from start: Date, to now: Date) -> String {
        let sec = max(0, Int(now.timeIntervalSince(start)))
        let m = sec / 60
        let s = sec % 60
        return String(format: "%d:%02d", m, s)
    }
}
