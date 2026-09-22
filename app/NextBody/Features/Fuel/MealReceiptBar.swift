import SwiftUI

/// What just went on the record, and the one tap that takes it back.
///
/// ADR 0018 gave the phone tools an undo stack, but only the model could reach it: saying
/// 「撤销」 undid the last write and tapping did not exist. This bar is that same right with
/// a surface — it appears for eight seconds wherever a meal was just written, states what
/// the row says and what is left of TARGET, and disappears on its own.
///
/// It is not a toast to be dismissed and not a second chrome element: no close button, no
/// queue, one receipt at a time, and the newest replaces the last.
struct MealReceiptBar: View {
    @EnvironmentObject private var data: DataStore
    /// The photo of the plate this receipt is for, when the row that was just written has one.
    private var photoPath: String? {
        guard let id = data.mealReceipt?.added.first else { return nil }
        return (data.meals.first { $0.id == id } ?? data.recentMeals.first { $0.id == id })?.photoPath
    }

    var body: some View {
        if let receipt = data.mealReceipt {
            HStack(spacing: 12) {
                if photoPath != nil {
                    MealThumbnail(path: photoPath, side: 34, radius: 9)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("ON THE RECORD"))
                        .font(NBFont.dot(600, 9)).tracking(0.18 * 9)
                        .foregroundStyle(NB.ember1)
                    Text(receipt.line)
                        .font(NBFont.ui(400, 13.5))
                        .foregroundStyle(NB.text1)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                if let left = receipt.left {
                    // Under the target is a number; over it is still a number, said as over.
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(left >= 0 ? L("LEFT") : L("OVER"))
                            .font(NBFont.dot(600, 9)).tracking(0.18 * 9)
                            .foregroundStyle(NB.white.opacity(0.42))
                        Text(Fmt.kcal(abs(left)))
                            .font(NBFont.dot(600, 14))
                            .foregroundStyle(left >= 0 ? NB.text1 : NB.ember1)
                    }
                }
                Button {
                    data.undoMealReceipt()
                } label: {
                    Text(L("UNDO"))
                        .font(NBFont.dot(600, 11)).tracking(0.14 * 11)
                        .foregroundStyle(NB.text1)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(NB.carbon4, in: Capsule())
                        .overlay(Capsule().stroke(NB.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("meal.receipt.undo")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous).fill(NB.carbon2))
            .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
                .stroke(NB.ember1.opacity(0.3), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.5), radius: 18, y: 6)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityIdentifier("meal.receipt")
        }
    }
}
