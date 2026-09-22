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
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(dismissDrag)
                switch plate {
                case .log:
                    LogMealSheet(day: day, onClose: close)
                case .edit(let entry):
                    EditMealSheet(entry: entry, keyboard: keyboard.height, onClose: close)
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
                    .allowsHitTesting(false)
            }
            .offset(y: max(0, drag) - rise)

        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.easeOut(duration: 0.25), value: keyboard.height)
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom).combined(with: .opacity)))
        .accessibilityIdentifier("fuel.plate")
    }

    // Dismissal belongs to the handle. A pan recognizer over the entire form competes
    // with text selection and scrolling just as the keyboard changes the form's size.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in drag = max(0, value.translation.height) }
            .onEnded { value in
                let travel = value.translation.height + value.predictedEndTranslation.height
                if travel > 120 { close() }
                else { withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { drag = 0 } }
            }
    }

    /// Both plates ride on top of the keyboard, so nothing being typed into sits behind the
    /// keys. Edit is the tall one — it shrinks its own form to the room that is left instead
    /// of pushing the handle off the top of the screen (#35D).
    /// The keyboard frame is measured from the bottom of the screen, so it already contains
    /// the home indicator strip the plate is inset by — lifting by the raw height leaves a
    /// black band between the plate and the keys.
    private var rise: CGFloat { max(0, keyboard.height - ScreenMetrics.safeArea.bottom) }

    private func close() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { onClose() }
    }
}

/// ⚠️ This plate used to demand two things: what you ate, and how many calories it was.
/// The second one is the number the product exists to work out — the photo path never asked
/// for it, and the model writes each食物 as its own row with portions and macros. Asking the
/// person for it here made the manual rail strictly worse than the AI rail in the same app.
/// It is now an override, not a gate: leave it blank and the estimate runs; fill it in and
/// that exact number is what goes on the record, with nothing re-estimated over it.
struct LogMealSheet: View {
    let day: UserDay
    var onClose: () -> Void
    @EnvironmentObject private var data: DataStore
    @StateObject private var billing = BillingStore.shared

    @StateObject private var favorites = MealFavorites.shared
    @State private var text = ""
    @State private var kcal = ""
    @State private var working = false
    @State private var failure: String?

    private var typed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var override: Double? {
        guard let value = Double(kcal.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")), value.isFinite, value >= 1, value <= 100000 else { return nil }
        return value
    }
    private var canSave: Bool { !typed.isEmpty && !working }

    var body: some View {
        SheetFrame(title: L("Log a meal"), fillsHeight: false) {
            VStack(spacing: 10) {
                if !favorites.list.isEmpty { regulars }
                PlatePhotoButton(busy: working) { shoot() }
                FieldBox(label: L("What you ate"), text: $text)
                FieldBox(label: L("KCAL · OPTIONAL"), text: $kcal, keyboard: .decimalPad)
            }
            Text(failure ?? explanation)
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(failure == nil ? NB.white.opacity(0.38) : NB.ember1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        } footer: {
            LimePillButton(title: working ? L("READING…") : L("Save"), enabled: canSave) { save() }
        }
        .padding(.bottom, keyboardPad)
        .task { await favorites.load() }
    }

    /// The second time you eat something costs one tap. Every number on these came from an
    /// estimate this person already accepted, so logging one calls no model and waits for
    /// nothing.
    private var regulars: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("REGULARS"))
                .font(NBFont.dot(600, 10)).tracking(0.18 * 10)
                .foregroundStyle(NB.white.opacity(0.42))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(favorites.list) { favorite in
                        Button {
                            favorites.log(favorite, day: day, into: data)
                            onClose()
                        } label: {
                            HStack(spacing: 8) {
                                if favorite.photoPath != nil {
                                    MealThumbnail(path: favorite.photoPath, side: 22, radius: 6)
                                }
                                Text(favorite.label)
                                    .font(NBFont.ui(500, 13))
                                    .foregroundStyle(NB.text1)
                                    .lineLimit(1)
                                Text(Fmt.nutrient(favorite.kcal))
                                    .font(NBFont.dot(600, 12))
                                    .foregroundStyle(NB.ember1)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 40)
                            .background(NB.carbon4, in: Capsule())
                            .overlay(Capsule().stroke(NB.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("fuel.plate.regular")
                    }
                }
                .padding(.horizontal, 1)
            }
            .frame(height: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var explanation: String {
        override == nil
            ? L("Leave KCAL empty and the model reads it: one row per food, with portions. What it cannot tell stays ——.")
            : L("Logged at exactly this number. Nothing is estimated over it.")
    }

    private func save() {
        failure = nil
        if let override {
            data.addManualMeal(text: typed, kcal: override, day: day)
            onClose()
            return
        }
        guard billing.allowAI() else { return }
        working = true
        let sentence = typed
        AIService.shared.beginReadingPlate(caption: sentence, image: nil)
        Task {
            let frame = await AIService.shared.turn(sentence, day: day, store: data, intent: "meal")
            working = false
            AIService.shared.endReadingPlate()
            if frame == nil, let error = AIService.shared.lastError { failure = error; return }
            onClose()
        }
    }

    /// The photo is the fastest true answer, so it is the first control on the plate rather
    /// than a second menu two taps away. The shutter closes this plate on the way out: the
    /// receipt is where the answer lands.
    private func shoot() {
        guard billing.allowAI() else { return }
        failure = nil
        CameraGate.present(onCapture: { image in
            guard let payload = AIImagePayload.prepare(image) else {
                failure = L("That photo could not be prepared. Try again.")
                return
            }
            working = true
            let caption = typed
            AIService.shared.pendingPlatePhoto = payload.preview
            AIService.shared.beginReadingPlate(caption: caption, image: payload.preview)
            // The plate closes on the shutter: the table's own placeholder row is where the
            // wait belongs, not a sheet held open over the page it is about to change.
            onClose()
            Task {
                let frame = await AIService.shared.turn(caption, day: day, store: data,
                                                        imageDataURL: payload.dataURL, intent: "meal")
                working = false
                AIService.shared.endReadingPlate()
                if frame == nil, let error = AIService.shared.lastError { failure = error }
            }
        }, onCancel: {})
    }

    private var keyboardPad: CGFloat {
        max(8, Chrome.homeIndicatorBlock - 8)
    }
}

/// Carbon plate, ember rule: the fuel page's own accent. Never a lime LOG A MEAL pill —
/// that combination is on the fuel window's Avoid list.
private struct PlatePhotoButton: View {
    let busy: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "camera")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(NB.ember1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("PHOTOGRAPH THE PLATE"))
                        .font(NBFont.ui(500, 13)).tracking(0.06 * 13)
                        .foregroundStyle(NB.text1)
                    Text(L("One row per food. No numbers to type."))
                        .font(NBFont.ui(300, 12)).tracking(0.02 * 12)
                        .foregroundStyle(NB.white.opacity(0.38))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 62)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous).fill(NB.carbon3))
            .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous)
                .stroke(NB.ember1.opacity(0.34), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
        .accessibilityIdentifier("fuel.plate.camera")
    }
}
