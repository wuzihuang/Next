import SwiftUI

/// ME yellow card. START PRO, or the current Pro period. The whole card is one hot zone.
struct ProfileProCard: View {
    @ObservedObject var billing: BillingStore

    var body: some View {
        Button(action: {
            if !billing.isPro { billing.presentFromProfile() }
        }) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("NEXTBODY PRO"))
                        .font(NBFont.dot(600, 11)).tracking(0.2 * 11)
                        .foregroundStyle(NB.carbon.opacity(0.62))
                    Text(statusLine)
                        .font(NBFont.brand(700, 22))
                        .foregroundStyle(NB.carbon)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(detailLine)
                        .font(NBFont.ui(400, 13))
                        .foregroundStyle(NB.carbon.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(billing.isPro ? L("PRO PLAN") : L("START PRO"))
                    .font(NBFont.dot(700, 11)).tracking(0.16 * 11)
                    .foregroundStyle(NB.lime1)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(NB.carbon, in: Capsule())
            }
            .padding(16)
            .frame(width: NB.Layout.contentWidth, alignment: .leading)
            .background(NB.lime1, in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(billing.isPro)
        .accessibilityIdentifier("profile.pro")
    }

    private var statusLine: String {
        if billing.snapshot.isTrial { return L("Free month") }
        if billing.isPro { return L("Pro is on") }
        return L("AI needs Pro")
    }

    private var detailLine: String {
        if billing.isPro {
            return L("Panel, coach, suggestions and voice.")
        }
        return L(BillingCopy.conditionKey(for: billing.offer), billing.snapshot.localizedPrice)
    }
}
