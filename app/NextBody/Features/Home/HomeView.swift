import SwiftUI

/// 04 · THE ROOT. The only root in the product; every detail page returns here.
struct HomeView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    @StateObject private var ai = AIService.shared
    @StateObject private var keyboard = KeyboardHeight()
    @State private var dockMode: Dock.Mode = .idle
    @State private var draft = ""
    @State private var widget: PanelWidget?

    var body: some View {
        VStack(spacing: 12) {
            Color.clear.frame(height: Chrome.statusBarBlock - 12)

            HomeHeader(batteryPercent: data.band.batteryPercent) {
                router.open(.profile, from: .home)
            }

            AIPanel(m: data.today, band: data.band, lastSync: data.lastSync, widget: widget) { target in
                router.open(target, from: .home)
            }

            BottomStrip(m: data.today,
                        onTraining: { router.open(.training, from: .home) },
                        onFuel: { router.open(.fuel, from: .home) })

            Dock(mode: $dockMode, draft: $draft,
                 onSend: handleSend,
                 onCamera: { router.sheet = .plusMenu },
                 onPlus: { router.sheet = .plusMenu })
                .offset(y: -keyboard.height)
                .animation(.spring(response: 0.34, dampingFraction: 0.9), value: keyboard.height)

            HomeIndicator()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .carbonPage()
        .ignoresSafeArea(.container, edges: .vertical)
        // 05 · A·04 · the keyboard rises with the screen and the layout does not move a pixel.
        // The dock rides up on top of the keyboard; nothing else shifts, nothing is re-laid out.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .animation(.easeInOut(duration: 0.28), value: widget)
        .task {
            // F3 §05 · the home screen reads one row of daily_results and nothing else.
            try? await Repository.shared.signInDemo()
            await Repository.shared.loadToday(into: data)

            // P2 · background. Pulling the band's day is the lowest priority in the queue:
            // anything the user presses jumps in front of it.
            guard data.band.connected else { return }
            await OriginDataSync().sync(day: UserDay.containing(Date()), into: data)
        }
    }

    /// The dock never answers in place: whatever she says comes back onto the panel.
    private func handleSend(_ text: String) {
        let day = UserDay.containing(Date())
        withAnimation { widget = .thinking }

        Task {
            if Self.looksLikeFood(text) {
                let entry = MealEntry(id: UUID(), day: day, at: Date(), slot: slotForNow(),
                                      status: .confirmed, text: text,
                                      kcal: 0, protein: 0, carb: 0, fat: 0, source: .typed)
                data.logMeal(entry)
                if let frame = await ai.estimate(entry: entry, into: data) {
                    withAnimation { widget = frame }
                    return
                }
            }
            let frame = await ai.turn(text, day: day, store: data)
            withAnimation { widget = frame ?? .thinking }
        }
    }

    /// D05 · food goes entirely through the model — no food database, no barcodes,
    /// no portion calculator. This only decides which endpoint the sentence goes to.
    private static func looksLikeFood(_ text: String) -> Bool {
        let markers = ["吃", "喝", "早饭", "午饭", "晚饭", "夜宵", "加餐", "记一笔",
                       "ate", "had", "drank", "breakfast", "lunch", "dinner", "snack"]
        return markers.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private func slotForNow() -> MealEntry.Slot {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 4..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<21: return .dinner
        default: return .snack
        }
    }
}
