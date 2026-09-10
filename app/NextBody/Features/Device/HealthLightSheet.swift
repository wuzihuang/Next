import SwiftUI

/// 12S · the light on the side of the band. Selection reflects the device reply, never the
/// tapped row; a confirmed state is saved on the phone and `BandHealthLightKeeper` writes it
/// back on every connect. Below it, the firmware's own disconnect reminder — the switch that
/// matters when the link really drops and the app is not there to ask.
struct HealthLightSheet: View {
    @EnvironmentObject private var data: DataStore
    @State private var current: BandHealthLightState?
    @State private var reminder: Bool?
    @State private var busy = false
    @State private var unsupported = false
    @State private var message: String?
    @State private var saved = false
    /// A reconnect that arrived while a cancelled command was still draining. The read is
    /// re-run once the band is idle, so the sheet never sits on "interrupted" forever.
    @State private var rereadWhenIdle = false
    /// ⚠️ Only reads are held here. A write is never cancelled: the command reaches the band
    /// whatever this sheet does, so cancelling it only throws away the band's own answer.
    @State private var operation: Task<Void, Never>?

    private var connected: Bool { data.band.connected }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SheetHeader(
                    eyebrow: statusEyebrow,
                    eyebrowTint: unsupported ? NB.ember1 : NB.lime1,
                    title: L("Health light"),
                    subtitle: L("The light on the side of the band. Your choice is saved here and written to the band again every time it connects.")
                ) {
                    if busy { ProgressView().tint(NB.lime1) }
                }
                VStack(spacing: 0) {
                    ForEach(BandHealthLightState.allCases) { state in
                        Button { perform(state) } label: {
                            HStack {
                                Text(L(state.title)).foregroundStyle(NB.text1)
                                Spacer()
                                if current == state {
                                    Image(systemName: "checkmark").foregroundStyle(NB.lime1)
                                }
                            }
                            .font(NBFont.ui(400, 16))
                            .padding(16).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("healthLight.state.\(state.rawValue)")
                        .disabled(busy || !connected || unsupported)
                        if state != .stayOn { Hairline().padding(.leading, 16) }
                    }
                }
                .frame(width: NB.Layout.contentWidth)
                .cardSkin()
                if let reminder {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L("Disconnect reminder"))
                                .font(NBFont.ui(400, 16)).foregroundStyle(NB.text1)
                            Text(L("The band signals on its own when it loses this phone."))
                                .font(NBFont.ui(300, 12)).foregroundStyle(NB.text3Prod)
                        }
                        Spacer(minLength: 0)
                        // The rocker renders the confirmed value, never the tapped one — the
                        // same rule as the alarm switches, so it cannot bounce back.
                        Toggle("", isOn: Binding(get: { reminder }, set: { performReminder($0) }))
                            .labelsHidden()
                            .toggleStyle(HoopSwitchStyle())
                            .disabled(busy || !connected)
                            .accessibilityLabel(L("Disconnect reminder"))
                            .accessibilityIdentifier("healthLight.disconnectReminder")
                    }
                    .padding(16)
                    .frame(width: NB.Layout.contentWidth)
                    .cardSkin()
                }
                Button(L("Read again")) { perform(nil) }
                    .foregroundStyle(NB.lime1)
                    .disabled(busy || !connected)
                    .accessibilityIdentifier("healthLight.refresh")
                if saved {
                    Text(L("Saved. It will be written to the band again on every connect."))
                        .font(NBFont.ui(400, 13)).foregroundStyle(NB.lime1)
                }
                if let message {
                    Text(message).font(NBFont.ui(400, 13)).foregroundStyle(NB.ember1)
                }
            }
            .padding(.horizontal, DeviceSheet.gutter)
            .padding(.top, DeviceSheet.top)
            .padding(.bottom, DeviceSheet.bottom)
        }
        .onAppear { perform(nil) }
        .onDisappear { operation?.cancel() }
        .onChange(of: connected) { _, on in
            operation?.cancel()
            current = nil
            reminder = nil
            unsupported = false
            guard on else { rereadWhenIdle = false; return }
            // A command from the last link may still be draining. Wait for it rather than
            // firing a second one at a band that has not finished answering the first.
            if busy { rereadWhenIdle = true } else { perform(nil) }
        }
    }

    private var statusEyebrow: String {
        if !connected { return L("DISCONNECTED") }
        if unsupported { return L("NO LIGHT") }
        if let current { return L(current.title).uppercased() }
        return L("NOT READ")
    }

    private func owner() -> BandLivePolicy.Owner? {
        guard connected, let owner = LiveReadout.currentOwner else {
            message = L("Connect the band first."); return nil
        }
        return owner
    }

    /// Release the busy gate and, if a reconnect arrived while we were draining, read again.
    private func finish() {
        busy = false
        guard rereadWhenIdle else { return }
        rereadWhenIdle = false
        if connected { perform(nil) }
    }

    /// nil reads the light; a state writes it. The reminder is read alongside the first read,
    /// before the light, so a band without light control still shows its reminder switch.
    private func perform(_ requested: BandHealthLightState?) {
        guard !busy, let owner = owner() else { return }
        busy = true
        message = nil
        saved = false
        let task = Task { @MainActor in
            defer { finish() }
            do {
                if requested == nil, reminder == nil {
                    reminder = try? await BandReadiness.read(account: owner.account, binding: owner.binding) {
                        try await Band.live.readDisconnectReminder()
                    }
                    try Task.checkCancellation()
                }
                let state = try await BandReadiness.read(account: owner.account, binding: owner.binding) {
                    guard let requested else { return try await Band.live.readHealthLight() }
                    let confirmed = try await Band.live.writeHealthLight(requested)
                    // ⚠️ Stored here, the instant the band answers. `BandReadiness.read`
                    // turns a completed write into a cancellation if this sheet was
                    // dismissed while it waited its turn — and the band would then be left
                    // holding a state the phone forgot, which the keeper undoes on the next
                    // connect. The band's reply is the truth whatever the screen is doing.
                    if confirmed == requested { BandHealthLightPreference.store(confirmed) }
                    return confirmed
                }
                try Task.checkCancellation()
                current = state
                unsupported = false
                if let requested {
                    if requested == state {
                        saved = true
                    } else {
                        message = L("The band returned a different state: %@", L(state.title))
                    }
                }
            } catch is CancellationError {
                current = nil
                message = L("Operation interrupted. Read again when the band is ready.")
            } catch BandError.unsupported {
                current = nil
                unsupported = true
                message = L("This band does not support health light control.")
            } catch {
                current = nil
                BandLog.shared.record("healthLight.sheet", error: error)
                message = hoopMessage(error)
            }
        }
        // Only a read may be torn down by leaving the sheet; a write runs to its answer.
        if requested == nil { operation = task }
    }

    private func performReminder(_ on: Bool) {
        guard !busy, let owner = owner() else { return }
        busy = true
        message = nil
        saved = false
        Task { @MainActor in
            defer { finish() }
            do {
                let confirmed = try await BandReadiness.read(account: owner.account, binding: owner.binding) {
                    try await Band.live.writeDisconnectReminder(on)
                }
                reminder = confirmed
            } catch is CancellationError {
                message = L("Operation interrupted. Read again when the band is ready.")
            } catch {
                BandLog.shared.record("healthLight.reminder", error: error)
                message = hoopMessage(error)
            }
        }
    }

    /// `BandError`'s own descriptions are command labels meant for logs. On a screen they
    /// have to be sentences, and translated ones.
    private func hoopMessage(_ error: Error) -> String {
        guard let band = error as? BandError else { return L(error.localizedDescription) }
        switch band {
        case .notConnected: return L("Connect the band first.")
        case .busy:         return L("The band is measuring. Try again in a moment.")
        case .timeout:      return L("The band did not answer. Try again when it is on your wrist.")
        case .unsupported:  return L("This band has no disconnect reminder.")
        case .rejected:     return L("The band refused this setting.")
        }
    }
}
