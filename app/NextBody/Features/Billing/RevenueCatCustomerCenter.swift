import SwiftUI
import RevenueCat
import RevenueCatUI

/// Subscription support for the signed-in health account. Never grants AI locally.
struct CustomerCenterHost: View {
    @ObservedObject var billing: BillingStore
    var onFinished: () -> Void
    @State private var identity: UUID?
    @State private var preparing = true
    @State private var synchronizing = false
    @State private var centerRevision = UUID()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onFinished()
                } label: {
                    CloseMark().frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Close"))
                .accessibilityIdentifier("customer-center.close")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            content
            if synchronizing { ProgressView().tint(NB.lime1).padding() }
            if let message = billing.lastMessage, !message.isEmpty {
                Text(message).foregroundStyle(NB.ember1).padding(16)
            }
        }
        .background(NB.carbon.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onDisappear { Task { await billing.refresh() } }
        .task {
            guard !billing.usesStoreFreePreview else { preparing = false; return }
            identity = await billing.preparePaywall()
            preparing = false
        }
    }

    @ViewBuilder private var content: some View {
        #if DEBUG
        if billing.usesStoreFreePreview {
            Spacer()
            Text("Customer Center preview").accessibilityIdentifier("customer-center.preview")
            Spacer()
        } else {
            customerCenter
        }
        #else
        customerCenter
        #endif
    }

    @ViewBuilder private var customerCenter: some View {
        if identity != nil {
            CustomerCenterView()
                .onCustomerCenterRestoreInitiated { resume in
                    resume(shouldProceed: false)
                    Task { @MainActor in
                        guard let identity, !synchronizing else { return }
                        synchronizing = true
                        let result = await billing.restore(expectedIdentity: identity)
                        if case .failed(let message) = result { billing.lastMessage = message }
                        synchronizing = false
                        centerRevision = UUID()
                    }
                }
                .onCustomerCenterPromotionalOfferSucceeded { _, _, _ in
                    Task { await billing.refresh() }
                }
                .id(centerRevision)
                .disabled(synchronizing)
        } else {
            Spacer()
            if preparing { ProgressView().tint(NB.lime1) }
            Spacer()
        }
    }

}
