#if DEBUG
import SwiftUI

/// A manual hardware probe: selection reflects the device reply, never the tapped row.
struct HealthLightDebugSheet: View {
    @EnvironmentObject private var data: DataStore
    @State private var current: BandHealthLightState?
    @State private var busy = false
    @State private var unsupported = false
    @State private var message: String?
    @State private var operation: Task<Void, Never>?

    private var connected: Bool { data.band.connected }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Health light")).font(NBFont.ui(500, 20)).foregroundStyle(NB.text1)
                Text(L("Choose a state and observe the light on your band. The checkmark follows the device reply."))
                    .font(NBFont.ui(300, 13)).foregroundStyle(NB.text3Prod)
                HStack {
                    Text(status).font(NBFont.ui(400, 14)).foregroundStyle(NB.lime1)
                    Spacer()
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
                .cardSkin()
                Button(L("Read again")) { perform(nil) }
                    .foregroundStyle(NB.lime1)
                    .disabled(busy || !connected)
                    .accessibilityIdentifier("healthLight.refresh")
                if let message {
                    Text(message).font(NBFont.ui(400, 13)).foregroundStyle(NB.ember1)
                }
            }
            .padding(20)
        }
        .onAppear { perform(nil) }
        .onDisappear { operation?.cancel() }
        .onChange(of: connected) { _, on in
            operation?.cancel()
            current = nil
            unsupported = false
            if on && !busy { perform(nil) }
        }
    }

    private var status: String {
        if !connected { return L("DISCONNECTED") }
        if unsupported { return L("This band does not support health light control.") }
        if let current { return L("Device state: %@", L(current.title)) }
        return L("Device state not read")
    }

    private func perform(_ requested: BandHealthLightState?) {
        guard !busy else { return }
        guard connected else { message = L("Connect the band first."); return }
        guard let owner = LiveReadout.currentOwner else {
            message = L("Connect the band first."); return
        }
        busy = true
        message = nil
        operation = Task { @MainActor in
            defer { busy = false }
            do {
                let state = try await BandReadiness.read(account: owner.account, binding: owner.binding) {
                    if let requested { return try await Band.live.writeHealthLight(requested) }
                    return try await Band.live.readHealthLight()
                }
                try Task.checkCancellation()
                current = state
                unsupported = false
                if let requested, requested != state {
                    message = L("The band returned a different state: %@", L(state.title))
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
                BandLog.shared.record("healthLight.debug", error: error)
                message = L(error.localizedDescription)
            }
        }
    }
}
#endif
