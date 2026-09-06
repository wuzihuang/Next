import SwiftUI

/// Log or edit a meal. The page behind becomes a card (radius + scale) and a dim
/// sits over it so the plate reads as a layer — Profile chrome, plus-menu rise.
enum FuelPlate: Equatable {
    case log
    case edit(MealEntry)
}

struct FuelPlateLayer: View {
    let plate: FuelPlate
    let day: UserDay
    var onClose: () -> Void

    @StateObject private var keyboard = KeyboardHeight()
    @State private var drag: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityIdentifier("fuel.plate.dim")

            VStack(spacing: 0) {
                Capsule()
                    .fill(NB.white.opacity(0.18))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                switch plate {
                case .log:
                    LogMealSheet(day: day, onClose: close)
                case .edit(let entry):
                    EditMealSheet(entry: entry, onClose: close)
                }
            }
            .frame(maxWidth: .infinity)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: NB.R.panel,
                                       topTrailingRadius: NB.R.panel,
                                       style: .continuous)
                    .fill(NB.carbon2)
                    .shadow(color: Color.black.opacity(0.55), radius: 28, y: -6)
            }
            .overlay {
                UnevenRoundedRectangle(topLeadingRadius: NB.R.panel,
                                       topTrailingRadius: NB.R.panel,
                                       style: .continuous)
                    .stroke(NB.hairline, lineWidth: 1)
            }
            .offset(y: max(0, drag) - rise)
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in drag = max(0, value.translation.height) }
                    .onEnded { value in
                        let throw_ = value.translation.height + value.predictedEndTranslation.height
                        if throw_ > 120 { close() }
                        else { withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { drag = 0 } }
                    })
        }
        .animation(.easeOut(duration: 0.25), value: keyboard.height)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)))
        .accessibilityIdentifier("fuel.plate")
    }

    private var rise: CGFloat {
        keyboard.height > 0 ? keyboard.height : 0
    }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { onClose() }
    }
}

struct LogMealSheet: View {
    let day: UserDay
    var onClose: () -> Void
    @EnvironmentObject private var data: DataStore

    @State private var text = ""
    @State private var kcal = ""

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (Double(kcal) ?? 0) > 0
    }

    var body: some View {
        SheetFrame(title: L("Log a meal"), fillsHeight: false) {
            VStack(spacing: 10) {
                FieldBox(label: L("What you ate"), text: $text)
                FieldBox(label: L("KCAL"), text: $kcal, keyboard: .numberPad)
            }
            Text(L("Macros stay —— until the model reads this later."))
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(NB.white.opacity(0.38))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } footer: {
            LimePillButton(title: L("Save"), enabled: canSave) {
                data.addManualMeal(text: text, kcal: Double(kcal) ?? 0, day: day)
                onClose()
            }
        }
        .padding(.bottom, keyboardPad)
    }

    private var keyboardPad: CGFloat {
        max(8, Chrome.homeIndicatorBlock - 8)
    }
}
