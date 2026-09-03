import SwiftUI
import PhotosUI

/// 04 · THE ROOT. The only root in the product; every detail page returns here.
struct HomeView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var session: SessionStore

    @StateObject private var ai = AIService.shared
    @StateObject private var keyboard = KeyboardHeight()
    @StateObject private var firstRun = FirstRun()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dockMode: Dock.Mode = .idle
    /// 06 · the plus menu stands over the dock; the dock stays and the plus becomes ×.
    @State private var plusOpen = false
    @State private var draft = ""
    /// 09 edge 5 · the day a back-logged meal belongs to; nil means today.
    @State private var backlogDay: UserDay?
    /// F4 §02 · the model cannot write. When her frame says 「确认记录」 the plate she drafted is
    /// the sentence the user sent, and the tap is what commits it — through meal + meal-commit.
    @State private var lastSent: (text: String, day: UserDay)?
    /// 05 edges · what the dock is saying instead of listening.
    @State private var dockNote: DockNote?
    @State private var rootShift: CGFloat = 0
    /// 05 · C · the photo waits for the caption; they leave as one message.
    @State private var photoItem: PhotosPickerItem?
    @State private var attachment: Attachment?
    struct Attachment: Equatable {
        var image: UIImage
        var dataURL: String
        var progress: Double      // 0…1 · 100 % is the only completion signal
        var failed = false
        static func == (a: Attachment, b: Attachment) -> Bool { a.dataURL == b.dataURL && a.progress == b.progress && a.failed == b.failed }
    }
    @ObservedObject private var reachability = Reachability.shared
    @State private var widget: PanelWidget?
    // 04B · page two. 0 is the root, 1 is the instruments. The header and the home indicator
    // stay; the panel, the strip and the dock slide out together, and the drag is a plain
    // offset so the first frame follows the finger 1:1.
    // `SIMCTL_CHILD_NB_DEBUG_HOME_PAGE=1` opens the app on the second page for a screenshot.
    @State private var homePage = ProcessInfo.processInfo.environment["NB_DEBUG_HOME_PAGE"] == "1" ? 1 : 0
    @State private var pageDrag: CGFloat = 0
    /// 04B col 02 · a confirmed horizontal drag owns every touch on both pages until the
    /// finger lifts — a swipe that ends on a card is a swipe, never a tap (「什么都不可点」).
    /// Without this gate a slow drag that started on the SLEEP card ended by opening 13.
    @State private var swiping = false
    /// Direction lock, SpringBoard-style: the first points of travel decide the axis for the
    /// whole touch, so a mostly-vertical flick never becomes a page turn halfway through.
    @State private var dragAxis: Axis?
    @State private var pageTwoSince: Date?

    // MARK: geometry · the page is laid out against the device, not against the board's
    // 390 × 844. Header under the status bar, dock over the home indicator, the strip above
    // the dock, and the panel takes whatever is left — on a 390 × 844 phone that is the
    // board's own 470; on a taller one the panel simply grows.
    private var screen: CGSize { ScreenMetrics.size }
    private var safe: UIEdgeInsets { ScreenMetrics.safeArea }
    private var columnWidth: CGFloat { screen.width - 2 * NB.Layout.gutter }
    private var panelTop: CGFloat { safe.top + HomeHeader.height + 12 }
    /// the dock's foot, measured from the bottom edge of the screen
    private var dockBottom: CGFloat { safe.bottom + 8 }
    /// On a short phone the panel is smaller than the board's canvas and the widget scales
    /// down inside it (AIPanel); on a tall one it grows. The strip and the dock never change.
    private var panelHeight: CGFloat {
        screen.height - panelTop - 12 - NB.Layout.stripHeight - 12 - NB.Layout.dockHeight - dockBottom
    }
    private var pageShift: CGFloat { -CGFloat(homePage) * screen.width + pageDrag }
    /// 04B right column · the swipe yields to every overlay: the plus menu, the keyboard, the
    /// listening chamber — and to the first-run ceremony, until the dock exists.
    private var pagingEnabled: Bool {
        firstRun.dockVisible && !plusOpen && keyboard.height == 0 && dockMode == .idle
    }
    /// 04B · from the panel's top to just over the home indicator; the page's own foot
    /// carries LAST TICK and the dots.
    private var pageTwoHeight: CGFloat { screen.height - panelTop - safe.bottom - 6 }

    var body: some View {
        // The panel is one view for the whole ceremony: it starts as the entire screen and
        // folds to 358 × 470 at ◇7. Everything else is laid out around the space it leaves.
        ZStack(alignment: .topLeading) {
            page
                // 05 · A · with the keyboard up the dock rides over the panel's foot, so the page
                // draws above the panel for exactly as long as the keyboard is there.
                // 05M · B·03 · and for as long as the chamber is open: its scrim has to fall
                // over the panel too, and the scrim is drawn behind the dock, inside the page.
                .zIndex(keyboard.height > 0 || dockMode == .listening ? 2 : 0)
                .allowsHitTesting(!swiping)
            panel
                // C01 · the panel dims behind the field while typing.
                .overlay(Color(hex: 0x09090B).opacity(keyboard.height > 0 ? 0.55 : 0).allowsHitTesting(false))
                .allowsHitTesting(!swiping)

            // 04B · the second page rides in from the right, one column wide, at the panel's
            // top. Eight cards and not one read of the band — it is the same ticks laid out
            // another way.
            VitalsPage(m: data.today, history: data.history, vitals: data.vitals,
                       syncedOnce: data.lastSync != nil,
                       width: columnWidth,
                       onSleep: { router.open(.bodyBattery, from: .home) },
                       onHRV: {
                           Task { await Analytics.shared.track("PAGE2_HRV_TAP") }
                           router.open(.bodyBattery, from: .home)
                       })
                .frame(width: columnWidth, height: pageTwoHeight, alignment: .top)
                .offset(x: screen.width + NB.Layout.gutter + pageShift, y: panelTop)
                .opacity(firstRun.dockVisible ? 1 : 0)
                .allowsHitTesting(!swiping)
                .zIndex(1)
            // The root's own page dots, in the 12 pt seam between the strip and the dock —
            // the only place the dock leaves for them (04B right column). They are furniture:
            // they hold their lane through the drag and hand over to page two's own dots.
            PageDots(current: 0)
                .frame(width: screen.width)
                .offset(y: panelTop + panelHeight + 12 + NB.Layout.stripHeight + 4)
                .opacity(firstRun.dockVisible && homePage == 0 ? 1 : 0)
                .allowsHitTesting(false)
                .zIndex(1)

            // 06 · 02–06 · the page behind falls to 30 % while the menu is up; the dock row is
            // left alone, because its right key is now the way out. Tap the scrim, tap ×, or
            // pull the panel down — three routes, one 0.22 s ease-in.
            if plusOpen {
                Color(hex: 0x09090B).opacity(0.70)
                    .padding(.bottom, NB.Layout.dockHeight + dockBottom + 8)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closePlus() }
                    .transition(.opacity)
                    .zIndex(3)
                PlusMenuSheet(inline: true, onClose: { closePlus() },
                              onCamera: { showPicker = true }, onLibrary: { showPicker = true })
                    .frame(width: columnWidth)
                    .background(NB.carbon2, in: RoundedRectangle(cornerRadius: NB.R.panel, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: NB.R.panel, style: .continuous).stroke(NB.hairline, lineWidth: 1))
                    .overlay(alignment: .top) {
                        Capsule().fill(NB.white.opacity(0.18)).frame(width: 36, height: 4).padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, NB.Layout.dockHeight + dockBottom + 12)
                    .gesture(DragGesture(minimumDistance: 12).onEnded { v in if v.translation.height > 40 { closePlus() } })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(4)
            }
        }
        // 05 · A·04 · 「键盘升起，版式一格都不动」. ⚠️ Inside the navigation stack the keyboard
        // still re-proposed this view 119 pt taller and 119 pt higher, whatever safe-area
        // modifier sat above it; every ignoresSafeArea(.keyboard) placement was tried. So the
        // page reads where the container put it and puts itself back: only the dock moves.
        .simultaneousGesture(pageGesture, including: pagingEnabled ? .all : .subviews)
        .onChange(of: homePage) { _, p in
            if p == 1 {
                pageTwoSince = Date()
                trackPageTwoOpen()
            } else if let since = pageTwoSince {
                pageTwoSince = nil
                let ms = Int(Date().timeIntervalSince(since) * 1000)
                Task { await Analytics.shared.track("HOME_PAGE2_DWELL", ["MS": ms]) }
            }
        }
        .onChange(of: router.measuredWidget) { _, w in
            guard let w else { return }
            // 06 · G·03 / F05 · 0.5S · SPRING 0.80 — the reading lands in the panel it grew from.
            withAnimation(.spring(response: 0.50, dampingFraction: 0.80)) { widget = w }
            router.measuredWidget = nil
        }
        .onChange(of: router.dockPrefill) { _, p in
            guard let p else { return }
            draft = p.text
            backlogDay = p.day
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { dockMode = .keyboard }
            router.dockPrefill = nil
        }
        .offset(y: -rootShift)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { rootShift = g.frame(in: .global).minY }
                .onChange(of: g.frame(in: .global).minY) { _, y in rootShift = y }
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .carbonPage()
        .ignoresSafeArea(.container, edges: .vertical)
        // 05 · A·04 · the keyboard rises with the screen and the layout does not move a pixel.
        // The dock rides up on top of the keyboard; nothing else shifts.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // 05 · C01 · the picker is presented from the page, not from inside the dock: a presenter
        // inside the offset dock pulled the whole page up under the keyboard.
        .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard item != nil else { return }
            Task { await attach(retry: false) }
        }
        .statusBarHidden(firstRun.statusBarHidden)
        // Any tap at all lands on ◇11 — there is no "skip?" to answer.
        .contentShape(Rectangle())
        .onTapGesture { firstRun.skip() }
        // 05M · ANSWER 0.18S — the frame arrives in the panel at the board's speed.
        .animation(.easeInOut(duration: 0.18), value: widget)
        .task {
            // DEBUG · 05 edges on a simulator with no microphone story of its own.
            switch DebugEdge.name {
            case "micdenied":   note(DockNote(line: "MICROPHONE OFF", text: "Typing still works.\nTurn the mic on in Settings.", action: "Open Settings"))
            case "tooshort":    note(DockNote(line: "0.3S · TOO SHORT", text: "Hold, say it, then let go."))
            case "nospeech":    note(DockNote(line: "NOTHING HEARD", text: "Say it again, or type it."))
            case "offline":     note(DockNote(line: "NO CONNECTION", text: "It stays here. Send it when you're back."))
            case "interrupted": note(DockNote(line: "INTERRUPTED AT 0:07", text: "Not saved. Say it again when you're free."))
            // 05M · B·03 / B·04 · the chamber and its cancel state, on a simulator that has no
            // microphone to hold; the waveform shows the board's own bars.
            case "recording", "cancelling": dockMode = .listening
            default: break
            }
            #if DEBUG
            // `SIMCTL_CHILD_NB_DEBUG_ASR_FILE=/path/clip.wav` · push one known clip through the
            // real transcribe path with the app's own session and log what asr answered.
            if let path = ProcessInfo.processInfo.environment["NB_DEBUG_ASR_FILE"] {
                Task {
                    try? await Task.sleep(for: .seconds(6))     // after the session is restored
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("nb-debug.wav")
                    try? FileManager.default.removeItem(at: tmp)
                    try? FileManager.default.copyItem(atPath: path, toPath: tmp.path)
                    let r = await ai.transcribe(tmp)
                    NSLog("NB asr debug · \(r)")
                }
            }
            #endif
            firstRun.start(reduceMotion: reduceMotion,
                           lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)

            // F3 §05 · the home screen reads one row of daily_results and nothing else.
            // ⚠️ Unstructured on purpose: `.task` is cancelled the moment a detail page is
            // pushed over this view, and a cancelled load fell back to the offline seed —
            // opening any page in the first seconds silently turned the whole app into a mock.
            let store = data
            let load = Task { @MainActor in
                try? await Repository.shared.openSession()
                await Repository.shared.loadToday(into: store)
            }
            await load.value

            // A device with no session is not a home screen, it is a gate that was skipped.
            // Every read above came back empty under the anon key and every write would be
            // dropped in silence — the phone sat on "——" with the band paired and no account
            // behind it. Back to the gate; the band stays bound, the history stays on the
            // server. (The simulator keeps its seeded walk-through.)
            if !Band.allowsSeed, await SupabaseClient.shared.currentUserId == nil {
                session.stage = .gateSignIn
                return
            }

            // 13 col 01 · 昨夜, once a day, within six hours of waking. F5 C4 · the notification
            // primer follows the first real morning and nothing else.
            if widget == nil, let morning = MorningWidget.frame(today: data.today, history: data.history) {
                withAnimation { widget = morning }
                await MorningWidget.markShown(day: data.today.day, widget: morning)
                if await NotificationPrimer.shouldOffer() { router.takeover = .notificationPrimer }
            }

            #if DEBUG
            // `NB_DEBUG_TURN=今天心率怎么样` · one question through the real dock path, on a
            // device no harness can type into. Exactly the path a typed message takes.
            if let q = ProcessInfo.processInfo.environment["NB_DEBUG_TURN"], !q.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(8))
                    handleSend(q)
                }
            }
            // `NB_DEBUG_PANEL=thinking` pins the singularity so it can be read against
            // board 07 · 16 · 02; it is on screen for seconds in real use, which is long
            // enough to see and too short to check. `=<type>` pins one catalogue sample of
            // that widget instead, which is the only way to reach a chart whose data the
            // account does not have today.
            if let want = ProcessInfo.processInfo.environment["NB_DEBUG_PANEL"], !want.isEmpty {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4))
                    if want == "thinking" {
                        widget = .thinking("Why am I so tired today?")
                    } else if let t = PanelType(rawValue: want) {
                        widget = WidgetCatalogue.sample(t)
                    }
                }
            }
            #endif

            // F1 · A · the gate was walked once. Every launch after that reconnects on its
            // own; being asked to pair again is how a user learns their history is gone.
            await Band.live.reconnectIfBound()
            data.band.connected = Band.live.state == .connected
            // The band's own facts — link, battery, firmware, what it can do — on the header
            // and in the store, off the band, for the life of the process. Until now nothing
            // wrote them after the gate, and a device kept the simulator's 82%.
            BandPresence.shared.start(store: store)
            let presence = Task { @MainActor in await BandPresence.shared.refresh(store: store) }
            await presence.value

            // P2 · background. Pulling the band's day is the lowest priority in the queue:
            // anything the user presses jumps in front of it.
            // 补屏 rule 01 · 「02 板配对成功不构成取数许可」. The band stays paired; without consent
            // startReadOriginData() is never called.
            guard data.band.connected, ConsentStore.shared.granted else { return }
            // Same reason as the load above: the pull must outlive this view's `.task`.
            let sync = Task { @MainActor in
                await OriginDataSync.refreshNow(into: store, minimumInterval: 0)
                // First time on this phone: the days the band still holds, behind today's.
                await OriginDataSync().backfillIfNeeded(into: store)
            }
            _ = await sync.value

            // A tick is five minutes wide, so that is the fastest the day can change; the
            // device page can stretch the cadence up to an hour. Under the view's own task,
            // so leaving the screen ends it.
            // ⚠️ Not a poll of the server: it asks the band, and a pull that finds no new tick
            // stops there — no upload, no settle, no reload. The half-minute check is what
            // lets a cadence changed on the device page apply without a relaunch.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                guard OriginDataSync.isDue else { continue }
                await OriginDataSync.refreshNow(into: store)
            }
        }
    }

    private var page: some View {
        VStack(spacing: 12) {
            // the status bar; iOS paints into it
            Color.clear.frame(height: max(0, safe.top - 12))

            // ◇8 · the top bar slides in from −8px as the card lands.
            HomeHeader(name: data.profile.displayName, initials: data.profile.initials,
                       batteryPercent: data.band.batteryPercent,
                       width: columnWidth,
                       onProfile: { router.open(.profile, from: .home) },
                       onDevice: { router.open(.device, from: .home) })
            .opacity(firstRun.chromeVisible ? 1 : 0)
            .offset(y: firstRun.chromeVisible ? 0 : -8)

            // the room the panel occupies once it has folded
            Color.clear.frame(width: columnWidth, height: panelHeight)

            // ◇9 · the two tiles rise from +16px, left before right by 80ms.
            BottomStrip(m: data.today, width: columnWidth,
                        onTraining: { router.open(.training, from: .home) },
                        onFuel: { router.open(.fuel, from: .home) })
                .opacity(firstRun.tilesVisible ? 1 : 0)
                .offset(y: firstRun.tilesVisible ? 0 : 16)
                .offset(x: pageShift)

            // ◇10 · the three keys land together: it is one tool, not three.
            // ⚠️ Before that the dock is simply not there — never a greyed-out disabled state.
            if firstRun.dockVisible {
                Dock(mode: $dockMode, note: dockNote, attachmentReady: attachment.map { $0.progress >= 1 && !$0.failed },
                     width: columnWidth,
                     draft: $draft,
                     onSend: handleSend,
                     onCamera: { showPicker = true },
                     onPlus: {
                        if plusOpen { closePlus() }
                        else { withAnimation(.easeOut(duration: 0.14)) { plusOpen = true } }
                     },
                     menuOpen: plusOpen,
                     onListen: beginListening,
                     onStopListening: endListening,
                     onCancelListening: cancelListening)
                    // 05M · B·03 · while the chamber is open the page behind falls to 52 % and a
                    // carbon gradient rises 220 pt behind the dock. Neither takes a touch: the
                    // only gesture alive is the finger already on the key.
                    .background(alignment: .bottom) {
                        if dockMode == .listening {
                            ListeningScrim()
                                .frame(width: screen.width, height: screen.height)
                                .offset(y: dockBottom)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    // 05 · C02–C04 · the tray hangs above the field: 100 × 100, radius 16, no card and
                    // no background — it reads as "attached to this message", not as a message.
                    .overlay(alignment: .topLeading) {
                        if let a = attachment {
                            PhotoTray(attachment: a,
                                      onRetry: { Task { await attach(retry: true) } },
                                      onRemove: { withAnimation { attachment = nil; dockNote = nil } })
                                .offset(x: 0, y: -116)
                                .transition(.scale(scale: 0.94).combined(with: .opacity))
                        }
                    }
                    // 05 edges · the sentence and its one key sit above the dock; the slots never move.
                    .overlay(alignment: .top) {
                        if let dockNote {
                            VStack(spacing: 10) {
                                // While typing the centre slot is the field, so the amber line
                                // (`UPLOAD FAILED`) stands above the sentence instead.
                                if dockMode != .idle {
                                    Text(dockNote.line)
                                        .font(NBFont.dot(600, 11)).tracking(0.2 * 11)
                                        .foregroundStyle(NB.ember1.opacity(0.85))
                                }
                                Text(dockNote.text)
                                    .font(NBFont.brand(400, 13.5)).lineSpacing(4)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(NB.white.opacity(0.70))
                                    .frame(width: 294)
                                if let key = dockNote.action {
                                    Button {
                                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                    } label: {
                                        Text(key)
                                            .font(NBFont.ui(500, 14)).tracking(0.04 * 14)
                                            .foregroundStyle(NB.white)
                                            .frame(width: 220, height: 40)
                                            .overlay(Capsule().stroke(NB.white.opacity(0.16), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            // The board draws the sentence under the dock on a bare carbon ground.
                            // On device the dock sits on the home indicator, so the sentence stands
                            // over the strip instead — on its own ground, never printed across the cards.
                            .padding(.horizontal, 22)
                            .padding(.vertical, 18)
                            .background(NB.carbon2, in: RoundedRectangle(cornerRadius: NB.R.card, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: NB.R.card, style: .continuous).stroke(NB.hairline, lineWidth: 1))
                            // above the tray when a photo is attached (05 · C edge 4)
                            .offset(y: (dockNote.action == nil ? -70 : -122) - (attachment == nil ? 0 : 118))
                            .transition(.opacity)
                        }
                    }
                    // The keyboard lift comes last so the tray and the note ride with the dock
                    // (an overlay added after `.offset` would stay at the unlifted frame).
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    .offset(y: -keyboard.height)
                    .animation(.spring(response: 0.34, dampingFraction: 0.9), value: keyboard.height)
                    // 04B · the dock belongs to the root and leaves with it.
                    .offset(x: pageShift)
                    .transition(.opacity)
            } else {
                Color.clear.frame(height: NB.Layout.dockHeight)
            }

            // iOS draws the home indicator itself; the dock stops 8pt short of it.
            Color.clear.frame(height: max(0, dockBottom - 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 05 · A·04 · the container that holds the field is the one the keyboard would push;
        // it ignores the keyboard so only the dock's own offset moves.
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// ⚠️ One view, animating frame and cornerRadius. Two views cross-fading would show a
    /// seam exactly where the whole moment lives.
    private var panel: some View {
        let full = firstRun.panelIsFullScreen
        return AIPanel(onTurnOn: { router.takeover = .consent },
                       m: data.today, band: data.band, lastSync: data.lastSync, vitals: data.vitals,
                       widget: widget, firstRun: firstRun,
                       size: full ? screen
                                  : CGSize(width: columnWidth, height: panelHeight),
                       radius: firstRun.panelRadius) { target in
            // 06 · 17 · a fresh measurement answers a tap with a message, not a page.
            if let q = widget?.replyPrompt { handleSend(q) }
            else if let a = widget?.action, a.contains("确认记录") || a.localizedCaseInsensitiveContains("confirm"),
                    let sent = lastSent {
                confirmMeal(sent.text, day: sent.day)
            } else { router.open(target, from: .home) }
        }
        .offset(x: full ? 0 : NB.Layout.gutter + pageShift,
                y: full ? 0 : panelTop)
            // F5 §09 · 「整屏接管」in the accessibility layer: while a frame is up, VoiceOver's
            // focus stays inside the panel, the way the eye does.
            .accessibilityAddTraits(widget == nil ? [] : .isModal)
    }

    /// 04B col 02 · the swipe. Horizontal only, two pages, no overscroll. Past 40 % of the
    /// width or faster than 300 pt/s it turns the page; otherwise it springs back. Both
    /// directions share one spring, and nothing on the page animates once it has landed.
    /// While the finger is down and moving sideways nothing else on either page is tappable
    /// (`swiping`), and a touch that started out vertical never turns a page (`dragAxis`).
    private var pageGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                let dx = v.translation.width, dy = v.translation.height
                if dragAxis == nil { dragAxis = abs(dx) >= abs(dy) ? .horizontal : .vertical }
                guard dragAxis == .horizontal else { return }
                pageDrag = homePage == 0 ? min(0, dx) : max(0, dx)
                swiping = true
            }
            .onEnded { v in
                let dx = v.translation.width
                let horizontal = dragAxis != .vertical
                swiping = false
                dragAxis = nil
                guard horizontal else { pageDrag = 0; return }
                let far = abs(dx) > screen.width * 0.4
                let fast = abs(v.velocity.width) > 300
                var target = homePage
                if homePage == 0, dx < 0, far || fast { target = 1 }
                if homePage == 1, dx > 0, far || fast { target = 0 }
                let turned = target != homePage
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    homePage = target
                    pageDrag = 0
                }
                if turned {
                    Task { await Analytics.shared.track("HOME_PAGE_SWIPE", ["DIR": target == 1 ? "right" : "left", "MS": 350]) }
                }
            }
    }

    /// 05 · the wave only plays once the microphone is running. If the permission is refused or
    /// the recorder will not start, the dock stays idle rather than animating over nothing —
    /// which is what it did before there was a recorder at all.
    private func beginListening() {
        Task {
            withAnimation { dockNote = nil }
            // 05 edge 1 · MIC DENIED. iOS asks once; after that the dock says so and typing
            // still works. No system prompt the second time.
            if SpeechCapture.permissionDenied || DebugEdge.on("micdenied") {
                note(DockNote(line: "MICROPHONE OFF", text: "Typing still works.\nTurn the mic on in Settings.", action: "Open Settings"))
                return
            }
            guard await SpeechCapture.shared.start() else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { dockMode = .listening }
        }
    }

    @State private var showPicker = false

    /// 05 · C02 → C04 · the thumbnail lands, the progress is drawn on the photo itself, and
    /// 100 % is the only completion signal. ⚠️ There is no storage bucket in this build: the
    /// bytes travel with the message, so "upload" is the read-and-resize that makes them ready.
    private func attach(retry: Bool) async {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) { dockNote = nil }
        if !retry { attachment = nil }
        do {
            guard let item = photoItem, let data = try await item.loadTransferable(type: Data.self),
                  let raw = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
            let image = raw.nb_resized(maxSide: 1024)
            guard let jpeg = image.jpegData(compressionQuality: 0.72) else { throw CocoaError(.fileWriteUnknown) }
            if DebugEdge.on("uploadfailed") { throw CocoaError(.fileWriteUnknown) }
            var a = Attachment(image: image, dataURL: "data:image/jpeg;base64," + jpeg.base64EncodedString(), progress: 0)
            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) { attachment = a }
            // the bar and the percentage climb on the photo; the field stays typeable throughout
            for step in 1...10 {
                try? await Task.sleep(for: .milliseconds(60))
                a.progress = Double(step) / 10
                attachment = a
            }
            await Analytics.shared.track("PHOTO_ATTACH", [:])
            await Analytics.shared.track("PHOTO_UPLOAD", ["MS": 600, "BYTES": jpeg.count, "OK": true])
            if dockMode != .keyboard { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { dockMode = .keyboard } }
        } catch {
            // 05 edge 4 · UPLOAD FAILED. The caption stays, the send stays dark, the photo says so.
            if var a = attachment { a.failed = true; attachment = a }
            else if let raw = photoItem, let d = try? await raw.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                attachment = Attachment(image: img, dataURL: "", progress: 0, failed: true)
            }
            note(DockNote(line: "UPLOAD FAILED", text: "Tap the photo to retry, or remove it."))
            await Analytics.shared.track("PHOTO_UPLOAD", ["MS": 0, "BYTES": 0, "OK": false])
        }
    }

    /// 05 edges · show the line, and clear it on its own when the board says so.
    /// The draft she rendered becomes a row: the same path a food sentence takes directly.
    private func confirmMeal(_ text: String, day: UserDay) {
        lastSent = nil
        withAnimation { widget = .thinking(text) }
        Task {
            let entry = MealEntry(id: UUID(), day: day, at: Date(), slot: slotFor(day: day),
                                  status: .confirmed, text: text,
                                  kcal: 0, protein: 0, carb: 0, fat: 0, source: .typed)
            data.logMeal(entry)
            if let frame = await ai.estimate(entry: entry, into: data) {
                withAnimation { widget = frame }
            } else {
                data.deleteMeal(entry.id)
                withAnimation { widget = PanelWidget(type: .text, title: "OFFLINE", tag: .fuel,
                                                     sentence: AppLanguage.isEnglish ? "That meal did not save. Tap confirm once more." : "这一餐没记上。再点一次确认。",
                                                     footer: String(text.prefix(42)), action: AppLanguage.isEnglish ? "CONFIRM" : "确认记录", data: .none) }
                lastSent = (text, day)
            }
        }
    }

    private func closePlus() {
        withAnimation(.easeIn(duration: 0.22)) { plusOpen = false }
    }

    /// 04B 上线前 · 埋点在写卡之前先埋好. Every opening of page two reports what the cards
    /// actually showed — FRESH / STALE / GONE / EMPTY per card — plus the two states that
    /// otherwise leave no trace: never synced, and an off-wrist gap of an hour or more
    /// (the same one the foot line prints, once per user day).
    private func trackPageTwoOpen() {
        let m = data.today, vitals = data.vitals, lastSync = data.lastSync
        let states = VitalsPage.cardStates(m: m, vitals: vitals)
        let gap = VitalsMath.offWrist(m.vitalsCurve)
        Task {
            for card in ["SLEEP", "HEART", "HRV", "STRESS", "TEMP", "STEPS", "DISTANCE", "ACTIVE"] {
                await Analytics.shared.track("PAGE2_CARD_STATE", ["CARD": card, "STATE": states[card] ?? "EMPTY"])
            }
            if lastSync == nil {
                await Analytics.shared.track("PAGE2_NOT_SYNCED", ["PLATFORM": "ios"])
            }
            if let gap, gap.minutes >= 60 {
                let key = "nb.page2.offwrist.\(m.day.key)"
                if !UserDefaults.standard.bool(forKey: key) {
                    UserDefaults.standard.set(true, forKey: key)
                    await Analytics.shared.track("PAGE2_OFF_WRIST", ["MIN": gap.minutes])
                }
            }
        }
    }

    private func note(_ n: DockNote, clearAfter seconds: Double? = nil) {
        withAnimation { dockNote = n }
        if let seconds {
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if dockNote == n { withAnimation { dockNote = nil } }
            }
        }
    }

    /// The tap that ends listening is also the send. There is no separate confirm step: the
    /// board gives the key one job, and a second press to approve what you just said would be
    /// asking a question already answered.
    /// 05M · B·04 / 05 rule 05 · slide-up cancel: the mic stops, nothing is transcribed or sent,
    /// the dock writes nothing. Reversible by design.
    private func cancelListening() {
        // 05M · B·04 → idle · the chamber goes back into the capsule the same way a send does.
        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) { dockMode = .idle }
        Task { _ = await SpeechCapture.shared.stop() }
        Task { await Analytics.shared.track("VOICE_CANCEL", ["REASON": "SLIDE_UP"]) }
    }

    private func endListening() {
        // 05M · B·05 · RELEASE 0.22S · EASE-OUT-BACK · the chamber collapses into the capsule.
        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) { dockMode = .idle }
        Task {
            let elapsed = SpeechCapture.shared.elapsed
            // stop() waits on the audio queue rather than the main one, for the same reason
            // start() does: tearing down a session that is not answering must not freeze a tap.
            guard let clip = await SpeechCapture.shared.stop() else { return }
            // 05 edge 6 · INTERRUPTED. A call or an alarm took the mic: half a sentence is worse
            // than none, so nothing is sent and the dock says it was not saved.
            if let t = SpeechCapture.shared.interruptedAt {
                note(DockNote(line: String(format: "INTERRUPTED AT %d:%02d", Int(t) / 60, Int(t) % 60),
                              text: "Not saved. Say it again when you're free."), clearAfter: 4)
                return
            }
            // 05 edge 2 · TOO SHORT. Under 0.6 s is a slip: no send, no error, 1.2 s on the capsule.
            if elapsed < 0.6 {
                note(DockNote(line: String(format: "%.1fS · TOO SHORT", elapsed), text: "Hold, say it, then let go."), clearAfter: 1.2)
                return
            }
            // 05 edge 5 · OFFLINE. A clip cannot wait in the dock the way a draft does, so the
            // capsule says when to say it again rather than pretending it heard nothing.
            if !reachability.isOnline || DebugEdge.on("offline") {
                note(DockNote(line: "NO CONNECTION", text: "Say it again when you're back."), clearAfter: 4)
                return
            }
            withAnimation { widget = .thinking }
            switch await ai.transcribe(clip) {
            case .text(let said):
                handleSend(said)
            case .silence:
                // 05 edge 3 · NO SPEECH. Recorded, transcribed to nothing: it stays in the dock
                // for the next take rather than sending her an empty message.
                withAnimation { widget = nil }
                note(DockNote(line: "NOTHING HEARD", text: "Say it again, or type it."), clearAfter: 4)
            case .failed:
                // Not on the board's list of six, because the board assumed the server answers.
                // A 401, a 503 or a dropped upload is not silence, and telling her to speak up
                // for it would be a lie; the line names the step that failed.
                withAnimation { widget = nil }
                note(DockNote(line: "COULDN'T TRANSCRIBE", text: "Say it again, or type it."), clearAfter: 4)
            }
        }
    }

    private func handleSend(_ text: String) {
        // 补屏 edge 2 · withdrawn or never granted: the server would answer 403 consent_withdrawn;
        // this side does not ask. The panel is already NOT COLLECTING, and the way back is the
        // consent screen, not a turn.
        guard ConsentStore.shared.granted else { router.takeover = .consent; return }
        // 05 edge 5 · OFFLINE. The message never leaves the dock: the draft is put back and the
        // capsule says when to try.
        if !reachability.isOnline || DebugEdge.on("offline") {
            draft = text
            note(DockNote(line: "NO CONNECTION", text: "It stays here. Send it when you're back."))
            return
        }
        let day = backlogDay ?? UserDay.containing(Date())
        let backlogging = backlogDay != nil
        backlogDay = nil
        lastSent = (text, day)
        withAnimation { widget = .thinking(text) }

        // 05 · C05 → C07 · photo and caption leave as one object and come back as one answer
        // with the source chip. The plate is logged to today's fuel on the way.
        if let a = attachment, a.progress >= 1, !a.failed {
            let sent = a
            withAnimation(.spring(response: 0.26, dampingFraction: 0.74)) { attachment = nil }
            photoItem = nil
            Task {
                if MedicalStop.matches(text) { withAnimation { widget = MedicalStop.frame }; return }
                let frame = await ai.photoMeal(image: sent.image, dataURL: sent.dataURL, caption: text,
                                               slot: slotForNow(), into: data)
                await Analytics.shared.track("MSG_SEND", ["TYPE": "PHOTO", "CHARS": text.count, "HAS_PHOTO": true])
                withAnimation { widget = frame ?? PanelWidget(type: .text, title: "OFFLINE", tag: .fuel,
                                                              sentence: AppLanguage.isEnglish ? "Could not read that plate. Your words are kept; send it again." : "这张盘子没读出来。字先留着，再发一次。",
                                                              footer: String(text.prefix(42)), action: nil, data: .none) }
            }
            return
        }

        Task {
            // S7 · the stop runs before the classifier, not after it. 吃药 contains 吃, so a
            // question about medication otherwise routes to the meal path — and that path
            // writes the row before the model is called.
            if MedicalStop.matches(text) {
                withAnimation { widget = MedicalStop.frame }
                return
            }
            if backlogging || Self.looksLikeFood(text) {
                let entry = MealEntry(id: UUID(), day: day, at: Date(), slot: slotFor(day: day),
                                      status: .confirmed, text: text,
                                      kcal: 0, protein: 0, carb: 0, fat: 0, source: .typed)
                data.logMeal(entry)
                if let frame = await ai.estimate(entry: entry, into: data) {
                    withAnimation { widget = frame }
                    return
                }
            }
            let frame = await ai.turn(text, day: day, store: data)
            withAnimation { widget = frame ?? .thinking(text) }
        }
    }

    /// D05 · food goes entirely through the model — no food database, no barcodes,
    /// no portion calculator. This only decides which endpoint the sentence goes to.
    ///
    /// ⚠️ A question about food is not a food log. These markers are substrings, and 吃 sits
    /// inside 「今天吃了多少」 exactly as it sits inside 「吃了半碗面」 — so asking how much you
    /// had ate one kcal of itself, logged under the question's own text, before the model was
    /// called at all. Same shape as the 吃药 hole: the classifier decides which tool runs, so
    /// anything it gets wrong is wrong before anything else gets a say.
    private static func looksLikeFood(_ text: String) -> Bool {
        guard !isQuestion(text) else { return false }
        let markers = ["吃", "喝", "早饭", "午饭", "晚饭", "夜宵", "加餐", "记一笔"]
        if markers.contains(where: { text.contains($0) }) { return true }
        // ⚠️ The English markers were substrings: "ate" sat inside "heart r-ate", so "Show my
        // heart rate range this week" was logged as a meal — a 1 kcal row named DINNER —
        // before the model ever saw the question. Whole words only.
        let words = ["ate", "had", "drank", "breakfast", "lunch", "dinner", "snack"]
        if text.range(of: "\\b(" + words.joined(separator: "|") + ")\\b",
                      options: [.regularExpression, .caseInsensitive]) != nil { return true }
        // A plate named without a verb — 「半碗面加一个鸡蛋」 — is a log in everyday Chinese.
        // Both a food noun and a portion word are required, so 「面」 alone, or 「三个」 alone,
        // still goes to her as a question. F4 §02: the model has no write tool, so a plate
        // that reaches `turn` can only come back as a draft; this is the path that commits.
        let foods = ["面", "饭", "蛋", "肉", "鸡", "鱼", "虾", "奶", "菜", "包子", "粥", "汤", "饼", "豆",
                     "果", "茶", "咖啡", "面包", "沙拉", "三明治", "寿司", "饺子", "馒头", "酸奶", "燕麦",
                     "薯", "米", "牛排", "披萨", "汉堡", "蛋糕", "饼干", "坚果", "香蕉", "苹果"]
        let portions = ["碗", "份", "个", "杯", "片", "块", "根", "盘", "颗", "两", "克", "斤", "半", "一", "二", "三", "四", "五", "ml", "g "]
        let hasFood = foods.contains { text.contains($0) }
        let hasPortion = portions.contains { text.localizedCaseInsensitiveContains($0) }
        return hasFood && hasPortion && text.count <= 40
    }

    /// Deliberately narrow. 「几」 is left out because 「吃了几个鸡蛋」 is as often a log as a
    /// question, and reading a log as a question only costs a round trip — while reading a
    /// question as a log writes a row the user then has to find and delete.
    private static func isQuestion(_ text: String) -> Bool {
        let markers = ["吗", "呢", "多少", "什么", "怎么", "?", "？",
                       "how much", "how many", "what did", "what have"]
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

    /// 09 edge 5 · which slot a plate joins. On today it is the clock's slot. On a closed day
    /// the clock is meaningless (a plate back-logged at 00:30 is not that day's SNACK), so it
    /// takes the first slot the day still has open, and SNACK once the three meals are filled —
    /// a back-logged plate is an addition, never a re-write of a meal already on the day.
    /// ⚠️ Ruling made here under an explicit assumption: the board says only "back-logging stays
    /// open", not which slot. Revisit if 09/13 settle it differently.
    private func slotFor(day: UserDay) -> MealEntry.Slot {
        guard day < UserDay.containing(Date()) else { return slotForNow() }
        let taken = Set((data.meals + data.recentMeals)
            .filter { $0.day == day && $0.status == .confirmed }.map(\.slot))
        return [.breakfast, .lunch, .dinner].first { !taken.contains($0) } ?? .snack
    }
}


// MARK: 05 · C · the photo tray

/// 100 × 100, radius 16: the lime bar and the Doto percentage sit on the photo itself with a
/// dimming mask, and the × at the corner removes it. Failed = amber border, the reason under the dock.
private struct PhotoTray: View {
    let attachment: HomeView.Attachment
    let onRetry: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: { if attachment.failed { onRetry() } }) {
                ZStack(alignment: .bottomLeading) {
                    Image(uiImage: attachment.image).resizable().scaledToFill()
                        .frame(width: 100, height: 100).clipped()
                    if attachment.progress < 1 && !attachment.failed {
                        Color(hex: 0x0B0B0D).opacity(0.46)
                        Text("\(Int(attachment.progress * 100))%")
                            .font(NBFont.dot(600, 15)).tracking(0.06 * 15)
                            .foregroundStyle(NB.white.opacity(0.82))
                            .frame(width: 100, height: 100)
                        ZStack(alignment: .leading) {
                            Capsule().fill(NB.white.opacity(0.16)).frame(width: 80, height: 3)
                            Capsule().fill(NB.lime1).frame(width: max(6, 80 * attachment.progress), height: 3)
                        }
                        .offset(x: 10, y: -10)
                    }
                }
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(attachment.failed ? NB.ember1.opacity(0.9) : NB.white.opacity(0.10), lineWidth: attachment.failed ? 1.5 : 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(attachment.failed ? "Photo · upload failed · tap to retry" : "Photo · \(Int(attachment.progress * 100)) percent")

            Button(action: onRemove) {
                ZStack {
                    Circle().fill(NB.carbon)
                    Circle().stroke(NB.white.opacity(0.26), lineWidth: 1)
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(NB.white.opacity(0.72))
                }
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .offset(x: 12, y: -12)
            .accessibilityLabel("Remove photo")
        }
        .frame(width: 100, height: 100)
    }
}

extension UIImage {
    /// The bytes travel with the message, so the plate is sent at 1024 px on its long side.
    func nb_resized(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        guard scale < 1 else { return self }
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}
