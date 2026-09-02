import SwiftUI

/// 04 · THE ROOT. The only root in the product; every detail page returns here.
struct HomeView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router

    @StateObject private var ai = AIService.shared
    @StateObject private var keyboard = KeyboardHeight()
    @StateObject private var firstRun = FirstRun()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dockMode: Dock.Mode = .idle
    @State private var draft = ""
    @State private var widget: PanelWidget?

    var body: some View {
        // The panel is one view for the whole ceremony: it starts as the entire screen and
        // folds to 358 × 470 at ◇7. Everything else is laid out around the space it leaves.
        ZStack(alignment: .topLeading) {
            page
            panel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .carbonPage()
        .ignoresSafeArea(.container, edges: .vertical)
        // 05 · A·04 · the keyboard rises with the screen and the layout does not move a pixel.
        // The dock rides up on top of the keyboard; nothing else shifts.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .statusBarHidden(firstRun.statusBarHidden)
        // Any tap at all lands on ◇11 — there is no "skip?" to answer.
        .contentShape(Rectangle())
        .onTapGesture { firstRun.skip() }
        .animation(.easeInOut(duration: 0.28), value: widget)
        .task {
            firstRun.start(reduceMotion: reduceMotion,
                           lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)

            // F3 §05 · the home screen reads one row of daily_results and nothing else.
            try? await Repository.shared.signInDemo()
            await Repository.shared.loadToday(into: data)

            // F1 · A · the gate was walked once. Every launch after that reconnects on its
            // own; being asked to pair again is how a user learns their history is gone.
            await Band.live.reconnectIfBound()
            data.band.connected = Band.live.state == .connected

            // P2 · background. Pulling the band's day is the lowest priority in the queue:
            // anything the user presses jumps in front of it.
            guard data.band.connected else { return }
            await OriginDataSync().sync(day: UserDay.containing(Date()), into: data)
        }
    }

    private var page: some View {
        VStack(spacing: 12) {
            Color.clear.frame(height: Chrome.statusBarBlock - 12)

            // ◇8 · the top bar slides in from −8px as the card lands.
            HomeHeader(batteryPercent: data.band.batteryPercent) {
                router.open(.profile, from: .home)
            }
            .opacity(firstRun.chromeVisible ? 1 : 0)
            .offset(y: firstRun.chromeVisible ? 0 : -8)

            // the room the panel occupies once it has folded
            Color.clear.frame(width: NB.Layout.contentWidth, height: NB.Layout.panelHeight)

            // ◇9 · the two tiles rise from +16px, left before right by 80ms.
            BottomStrip(m: data.today,
                        onTraining: { router.open(.training, from: .home) },
                        onFuel: { router.open(.fuel, from: .home) })
                .opacity(firstRun.tilesVisible ? 1 : 0)
                .offset(y: firstRun.tilesVisible ? 0 : 16)

            // ◇10 · the three keys land together: it is one tool, not three.
            // ⚠️ Before that the dock is simply not there — never a greyed-out disabled state.
            if firstRun.dockVisible {
                Dock(mode: $dockMode, draft: $draft,
                     onSend: handleSend,
                     onCamera: { router.sheet = .plusMenu },
                     onPlus: { router.sheet = .plusMenu })
                    .offset(y: -keyboard.height)
                    .animation(.spring(response: 0.34, dampingFraction: 0.9), value: keyboard.height)
                    .transition(.opacity)
            } else {
                Color.clear.frame(height: NB.Layout.dockHeight)
            }

            HomeIndicator().opacity(firstRun.indicatorVisible ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// ⚠️ One view, animating frame and cornerRadius. Two views cross-fading would show a
    /// seam exactly where the whole moment lives.
    private var panel: some View {
        let full = firstRun.panelIsFullScreen
        return AIPanel(m: data.today, band: data.band, lastSync: data.lastSync, vitals: data.vitals,
                       widget: widget, firstRun: firstRun,
                       size: full ? CGSize(width: 390, height: 844)
                                  : CGSize(width: NB.Layout.contentWidth,
                                           height: NB.Layout.panelHeight),
                       radius: firstRun.panelRadius) { target in
            router.open(target, from: .home)
        }
        .offset(x: full ? 0 : NB.Layout.gutter,
                y: full ? 0 : Chrome.statusBarBlock + 12 + 30 + 12)
    }

    private func handleSend(_ text: String) {
        let day = UserDay.containing(Date())
        withAnimation { widget = .thinking }

        Task {
            // S7 · the stop runs before the classifier, not after it. 吃药 contains 吃, so a
            // question about medication otherwise routes to the meal path — and that path
            // writes the row before the model is called.
            if MedicalStop.matches(text) {
                withAnimation { widget = MedicalStop.frame }
                return
            }
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
