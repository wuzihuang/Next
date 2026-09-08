import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

/// 04 · THE ROOT. The only root in the product; every detail page returns here.
struct HomeView: View {
    @EnvironmentObject private var data: DataStore
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var session: SessionStore

    @StateObject private var ai = AIService.shared
    @StateObject private var keyboard = KeyboardHeight()
    @StateObject private var firstRun = FirstRun()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 04 · a live readout is the band's sensor held open. Backgrounded, nobody is looking
    /// at it and nothing is drawn — so the measurement stops with the scene, not with the view.
    @Environment(\.scenePhase) private var scenePhase
    @State private var dockMode: Dock.Mode = .idle
    @State private var asrStream: ASRStreamingSession?
    /// 06 · the plus menu stands over the dock; the dock stays and the plus becomes ×.
    @State private var plusOpen = false
    /// How far the finger has pulled the sheet down. It follows 1:1 and springs back under 120 pt.
    @State private var sheetDrag: CGFloat = 0
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
    /// Plus · Photograph your meal sends the plate as soon as the shutter returns.
    /// The keyboard-field camera key still attaches and waits for a caption.
    @State private var cameraSendsFood = false
    @State private var attachment: Attachment?
    struct Attachment: Equatable {
        var image: UIImage
        var dataURL: String
        var progress: Double      // 0…1 · 100 % is the only completion signal
        var failed = false
        static func == (a: Attachment, b: Attachment) -> Bool { a.dataURL == b.dataURL && a.progress == b.progress && a.failed == b.failed }
    }
    @ObservedObject private var reachability = Reachability.shared
    /// 14 · the sport session the band is running. While one is on, the panel is the whole
    /// screen (`LiveSessionTakeover`), the page does not turn, and the resting readout is
    /// stood down — the session reads the wrist itself.
    @ObservedObject private var liveSession = LiveSessionStore.shared
    @State private var widget: PanelWidget?
    /// Every asynchronous panel answer belongs to one request. Dismissing the panel rotates
    /// this id, so a late network result cannot put a closed frame back over STANDBY.
    @State private var panelRequestID = UUID()
    // 04B · page two. 0 is the root, 1 is the instruments. The header and the home indicator
    // stay; the panel, the strip and the dock slide out together, and the drag is a plain
    // offset so the first frame follows the finger 1:1.
    /// ⚠️ The ONE thing both pages are drawn against: the root's x, 0 on page one and
    /// −width on page two, finger included. `router.homePage` records which page the user is
    /// on (it has to survive a detail push) but the offset is never computed from it. It used
    /// to be `-homePage * width + drag`, and the router is an @EnvironmentObject: on the frame
    /// the turn landed, the local drag was already 0 while the published page was still 1, so
    /// page one drew at −width for one frame and then slid in from the left. Two publishers,
    /// two frames. One number cannot disagree with itself.
    @State private var pageX: CGFloat = 0
    /// Where `pageX` stood when the finger went down, so the drag is added to a fixed base
    /// instead of to a value the same drag is changing.
    @State private var pageXAtTouch: CGFloat = 0
    #if DEBUG
    /// `SIMCTL_CHILD_NB_DEBUG_HOME_DRAG=0.45` freezes a mid-swipe frame — page one 45 % out,
    /// page two 45 % in, dots mid-handover — so the handover can be screenshotted.
    private let debugDragFraction = Double(ProcessInfo.processInfo.environment["NB_DEBUG_HOME_DRAG"] ?? "")
    #endif
    /// 04B col 02 · a confirmed horizontal drag owns every touch on both pages until the
    /// finger lifts — a swipe that ends on a card is a swipe, never a tap (「什么都不可点」).
    /// Without this gate a slow drag that started on the SLEEP card ended by opening 13.
    @State private var swiping = false
    /// Direction lock, SpringBoard-style: the first points of travel decide the axis for the
    /// whole touch, so a mostly-vertical flick never becomes a page turn halfway through.
    private enum HomeDrag { case horizontal, plan, dead }
    /// One owner per touch. The first points lock the axis: sideways turns the two
    /// home pages, an upward pull on the lip opens the plan face, anything else dies.
    @State private var homeDrag: HomeDrag?
    @State private var pageTwoSince: Date?
    /// 0 = closed (below the screen), −height = open. The plan face is not a Destination.
    @State private var planY: CGFloat = 0
    @State private var planYAtTouch: CGFloat = 0
    @State private var planDragDy: CGFloat = 0
    /// Stays true for the whole close pull. A 1pt planY threshold must not
    /// drive the lip or hit-testing — that rebuild flashed the face.
    @State private var planSettledOpen = false
    /// ADR 0018 · the plan is a server row; this is its store and the thinking clock.
    @ObservedObject private var planStore = PlanStore.shared
    @State private var planThinkingStartedAt = Date()

    // MARK: geometry · the page is laid out against the device, not against the board's
    // 390 × 844. Header under the status bar, dock over the home indicator, the strip above
    // the dock, and the panel takes whatever is left — on a 390 × 844 phone that is the
    // board's own 470; on a taller one the panel simply grows.
    private var screen: CGSize { ScreenMetrics.size }
    private var safe: UIEdgeInsets { ScreenMetrics.safeArea }
    private var columnWidth: CGFloat { screen.width - 2 * NB.Layout.gutter }
    private var panelTop: CGFloat { safe.top + HomeHeader.height + 12 }
    /// Board indicator is 19pt; a real inset is ~34pt. That extra used to sit as a
    /// black void under PLAN. The lip drops into all of it; the dock drops less, so
    /// the voice key and the two strip cards ride down and the panel can grow, and
    /// the chevron is no longer on the voice key (was 8pt of air).
    private var homeIndicatorExtra: CGFloat { max(0, safe.bottom - Chrome.boardHomeIndicator) }
    /// the dock's foot, measured from the bottom edge of the screen.
    /// Lip is chevron + page dots + PLAN above the Home Indicator; the dock sits above that lane.
    /// The dock and the strip ride 8pt lower than they did so the panel gets that height
    /// back and the bottom of the page stops reading as a shelf of air (the chevron keeps
    /// ~18pt under the voice key, the lane itself moves down with it).
    private var dockBottom: CGFloat { safe.bottom + 60 - homeIndicatorExtra - 4 }
    /// On a short phone the panel is smaller than the board's canvas and the widget scales
    /// down inside it (AIPanel); on a tall one it grows. The strip and the dock never change.
    private var panelHeight: CGFloat {
        screen.height - panelTop - 12 - NB.Layout.stripHeight - 12 - NB.Layout.dockHeight - dockBottom
    }
    private var pageShift: CGFloat { pageX }
    /// 1 on the root, 0 on page two — continuous through the drag and the snap spring, so
    /// the two dot sets crossfade in place instead of jumping when homePage flips.
    private var pageFade: Double { 1 - min(1, abs(pageShift) / screen.width) }
    /// 04B right column · the swipe yields to every overlay: the plus menu, the keyboard, the
    /// listening chamber — and to the first-run ceremony, until the dock exists.
    private var pagingEnabled: Bool {
        firstRun.dockVisible && !plusOpen && keyboard.height == 0 && dockMode == .idle
            && liveSession.session == nil
            && (abs(planY) < 1 || homeDrag == .plan)
    }
    /// 04 · when the panel's resting face gets to hold the band. On page one with nothing
    /// over it, the readout runs and the HR / STRESS row is the wrist measuring now instead
    /// of the last stored tick. Everything that covers that face ends it: a widget landing
    /// on the panel, the plus menu, a takeover, a detail page, the keyboard, the listening
    /// chamber. App-level lifecycle policy separately retains streaming in background.
    /// ⚠️ Every one of those is a reason to stop measuring, not a style choice — a live
    /// readout nobody is looking at is a band flat by lunchtime. And without consent the
    /// band is not read at all (补屏 rule 01): pairing is not permission.
    private var liveReadoutAllowed: Bool {
        firstRun.dockVisible && firstRun.playing == false
            && router.path.isEmpty && router.takeover == nil
            && widget == nil && !plusOpen && keyboard.height == 0 && dockMode == .idle
            && liveSession.session == nil
            && abs(planY) < 40
            && data.band.connected && ConsentStore.shared.granted
    }
    /// 04B · page two is the one cover that does not end the session on the spot. Tearing it
    /// down for a page turn put the numbers out and lit them again a beat after the page had
    /// landed — the panel visibly refreshing itself in the user's hand, one word (LIVE →
    /// 3 MIN AGO → REACHING FOR A BEAT → LIVE), two numbers and the pip, all on the readout's
    /// own clock rather than the finger's. A flip to the instruments and back is the same
    /// person looking at the same face, so the session simply stays open for it.
    /// ⚠️ Seconds, not minutes. Past the window the band is put down exactly as before —
    /// this buys a page turn, not a second place to leave the sensor running.
    private static let pageTwoReadoutGrace: TimeInterval = 20
    /// True while page two is holding a session that was running when the page turned.
    @State private var readoutHeldOnPageTwo = false
    @State private var readoutHold: Task<Void, Never>?
    private var liveReadoutWanted: Bool {
        liveReadoutAllowed && (router.homePage == 0 || readoutHeldOnPageTwo)
    }
    /// 04D · chevron, the two page dots, then PLAN. Drops further than the dock
    /// so PLAN sits over the Home Indicator instead of a void, and the chevron
    /// keeps ~20pt of air under the voice key.
    private var planLipLane: CGFloat { safe.bottom + 52 - homeIndicatorExtra - 12 }
    private var pageTwoHeight: CGFloat { screen.height - panelTop - planLipLane - 12 }
    private var planFlatten: CGFloat { CGFloat(PlanFaceMath.flatten(translation: Double(planDragDy))) }
    private var planMotionReduced: Bool {
        reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    private var planLipPlaying: Bool {
        PlanFaceMath.hintPlaying(reduceMotion: planMotionReduced) && !planSettledOpen
    }
    /// Named so Home's ZStack does not type-check the eight-card page inline.
    private var instrumentsPage: some View {
        VitalsPage(m: data.today, history: data.history, vitals: data.vitals,
                   sleepScore: data.sleepScores[data.today.day.key],
                   width: columnWidth, height: pageTwoHeight,
                   onOpen: { card in
                       Task { await Analytics.shared.track("PAGE2_CARD_TAP", ["CARD": card.cardKey]) }
                       router.open(card.destination, from: .home)
                   })
            .frame(width: columnWidth, height: pageTwoHeight, alignment: .top)
            .offset(x: screen.width + NB.Layout.gutter + pageShift, y: panelTop)
            .opacity(firstRun.dockVisible ? 1 : 0)
            .allowsHitTesting(!swiping && planY == 0)
            .zIndex(1)
    }

    /// Chevron + dots + PLAN are root chrome. A page turn only crossfades the
    /// dots (`pageFade`). Hiding the lane on `homeDrag == .horizontal` flashed
    /// both marks at lock and unlock.
    private var planLipVisible: Bool {
        firstRun.dockVisible && !planSettledOpen
    }

    private var planLipLayer: some View {
        PlanLip(pageFade: pageFade, playing: planLipPlaying, flatten: planFlatten,
                armed: homeDrag == .plan, reduceMotion: planMotionReduced)
            .frame(width: screen.width, height: 64, alignment: .bottom)
            .contentShape(Rectangle())
            .highPriorityGesture(planOpenGesture)
            .offset(y: screen.height - planLipLane - 16)
            .opacity(planLipVisible ? 1 : 0)
            .allowsHitTesting(planLipVisible)
            .zIndex(2)
    }

    private var planOpenGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if homeDrag == nil {
                    homeDrag = .plan
                    planYAtTouch = planY
                    Task { await planStore.load(dayKey: data.today.day.key) }
                    Task { await Analytics.shared.track("PLAN_AXIS_LOCK", ["AXIS": "PLAN"]) }
                }
                guard homeDrag == .plan else { return }
                dragPlan(to: planYAtTouch + value.translation.height, dy: value.translation.height)
                swiping = true
            }
            .onEnded { value in
                swiping = false
                homeDrag = nil
                settlePlan(translation: value.translation.height, velocity: value.velocity.height,
                           opening: true)
            }
    }

    @ViewBuilder
    private var planPageLayer: some View {
        if abs(planY) > 0.5 {
            PlanPage(plan: planStore.plan, checked: planStore.checked,
                     flatten: planFlatten, reduceMotion: planMotionReduced,
                     closeEnabled: true,
                     loading: planStore.loading,
                     generating: planStore.generating,
                     errorLine: planStore.errorLine,
                     thinkingReading: ai.reading ?? PhoneToolRunner.shared.running,
                     thoughts: ai.thoughts,
                     thinkingStartedAt: planThinkingStartedAt,
                     onTick: { planStore.tick($0, dayKey: data.today.day.key) },
                     onRegenerate: { generatePlan() },
                     onCloseDragChanged: { dy in
                         dragPlan(to: -screen.height + dy, dy: dy)
                     },
                     onCloseDragEnded: { dy, vel in
                         settlePlan(translation: dy, velocity: vel, opening: false)
                     })
                .frame(width: screen.width, height: screen.height)
                .offset(y: screen.height + planY)
                .zIndex(5)
        }
    }

    private var homeCanvas: some View {
        ZStack(alignment: .topLeading) {
            page
                .zIndex(keyboard.height > 0 || dockMode == .listening ? 2 : 0)
                .allowsHitTesting(!swiping && planY == 0)
            panel
                .overlay(Color(hex: 0x09090B).opacity(keyboard.height > 0 ? 0.55 : 0).allowsHitTesting(false))
                .allowsHitTesting(!swiping && planY == 0)
            instrumentsPage
            planLipLayer
            plusSheetLayer
            liveSessionLayer
            planPageLayer
        }
    }

    @ViewBuilder
    private var plusSheetLayer: some View {
        if plusOpen {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { closePlus() }
                .transition(.opacity)
                .zIndex(3)
            PlusMenuSheet(inline: true, onClose: { closePlus() },
                          onCamera: { openCamera(afterMenu: true, sendFood: true) },
                          onLibrary: { showPicker = true })
                .padding(.horizontal, NB.Layout.gutter - 8)
                .padding(.top, 10)
                .padding(.bottom, safe.bottom + 10)
                .frame(width: screen.width)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: NB.R.panel, topTrailingRadius: NB.R.panel, style: .continuous)
                        .fill(NB.carbon2)
                        .overlay(
                            UnevenRoundedRectangle(topLeadingRadius: NB.R.panel, topTrailingRadius: NB.R.panel, style: .continuous)
                                .stroke(NB.hairline, lineWidth: 1))
                }
                .overlay(alignment: .top) {
                    Capsule().fill(NB.white.opacity(0.18)).frame(width: 36, height: 4).padding(.top, 8)
                }
                .offset(y: max(0, sheetDrag))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { v in sheetDrag = max(0, v.translation.height) }
                        .onEnded { v in
                            if v.translation.height + v.predictedEndTranslation.height > 120 { closePlus() }
                            else { withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { sheetDrag = 0 } }
                        })
                .transition(.move(edge: .bottom))
                .zIndex(4)
        }
    }

    @ViewBuilder
    private var liveSessionLayer: some View {
        if liveSession.session != nil {
            LiveSessionTakeover(
                panelFrame: CGRect(x: NB.Layout.gutter, y: panelTop, width: columnWidth, height: panelHeight),
                screen: screen,
                onFolded: { summary in
                    liveSession.end()
                    if let summary {
                        withAnimation(.spring(response: 0.50, dampingFraction: 0.80)) { widget = summary }
                    }
                })
                .zIndex(6)
        }
    }

    var body: some View {
        homeLifecycle
    }

    private var homeGestured: some View {
        homeCanvas
            .highPriorityGesture(pageGesture, including: pagingEnabled ? .all : .subviews)
    }

    private var homeRouting: some View {
        homeGestured
        .onChange(of: router.homePage) { _, p in
            // The page can also be set from outside the gesture — a detail page returning the
            // user to the page they left. The offset follows it there, without an animation:
            // the turn's own spring has already put `pageX` where it belongs before it sets
            // this, so this only fires for a jump the user did not make with their finger.
            let want = -CGFloat(p) * screen.width
            if homeDrag == nil, pageX != want { pageX = want }
            // 04 · the readout is handed to page two for `pageTwoReadoutGrace`, and only if it
            // was actually running — the grace holds a session open, it never opens one.
            readoutHold?.cancel()
            readoutHold = nil
            if p == 1, liveReadoutAllowed {
                readoutHeldOnPageTwo = true
                readoutHold = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(Self.pageTwoReadoutGrace))
                    guard !Task.isCancelled else { return }
                    readoutHeldOnPageTwo = false
                }
            } else {
                readoutHeldOnPageTwo = false
            }
            if p == 1 {
                pageTwoSince = Date()
                trackPageTwoOpen()
            } else if let since = pageTwoSince {
                pageTwoSince = nil
                let ms = Int(Date().timeIntervalSince(since) * 1000)
                Task { await Analytics.shared.track("HOME_PAGE2_DWELL", ["MS": ms]) }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { fireWidgetShot() }
            guard phase != .active else { return }
            cancelInterruptedDrag()
            readoutHold?.cancel()
            readoutHold = nil
            readoutHeldOnPageTwo = false
        }
        .onReceive(NotificationCenter.default.publisher(for: WidgetBridge.photoDidArrive)) { _ in
            fireWidgetShot()
        }
        .onAppear { fireWidgetShot() }
        .onChange(of: router.planRequest) { _, _ in
            // ADR 0018 · a plan frame or app.open("plan") lands on the face.
            if abs(planY) < 1 { openPlan(fromIdle: false) }
        }
        .onChange(of: router.pendingHomePanel) { _, panel in
            guard panel == "body_battery" else { return }
            if let morning = MorningWidget.frame(today: data.today, history: data.history, ignoreShown: true) {
                withAnimation { widget = morning }
            }
            router.pendingHomePanel = nil
        }
        .onChange(of: router.measuredWidget) { _, w in
            guard let w else { return }
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
    }

    private var homeLifecycle: some View {
        homeRouting
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
            Task { await attachFromPicker() }
        }
        .statusBarHidden(firstRun.statusBarHidden)
        // Any tap at all lands on ◇11 — there is no "skip?" to answer.
        // After idle this gesture must not exist: a parent TapGesture cancels
        // the dock orb's UIKit PressHold, so a tap never opened the plus sheet.
        .contentShape(Rectangle())
        .gesture(
            TapGesture().onEnded { firstRun.skip() },
            including: firstRun.playing ? .all : .none
        )
        // 05M · ANSWER 0.18S — the frame arrives in the panel at the board's speed.
        .animation(.easeInOut(duration: 0.18), value: widget)
        // The app owns the stream. This page contributes demand, not task lifetime.
        .onChange(of: liveReadoutWanted, initial: true) { _, wanted in
            BandLiveLifecycle.shared.setForegroundWanted(wanted)
        }
        .onChange(of: session.holdingLaunchStill) { _, holding in
            if !holding {
                firstRun.start(reduceMotion: reduceMotion,
                               lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
            }
        }
        .onDisappear { BandLiveLifecycle.shared.setForegroundWanted(false) }
        .background { NightHomeDiagnosticObserver(metrics: data.today) }
        .task {
            // DEBUG · 05 edges on a simulator with no microphone story of its own.
            switch DebugEdge.name {
            case "micdenied":   note(DockNote(line: L("MICROPHONE OFF"), text: L("Typing still works.\nTurn the mic on in Settings."), action: L("Open Settings")))
            case "tooshort":    note(DockNote(line: L("0.3S · TOO SHORT"), text: L("Hold, say it, then let go.")))
            case "nospeech":    note(DockNote(line: L("NOTHING HEARD"), text: L("Say it again, or type it.")))
            case "offline":     note(DockNote(line: L("NO CONNECTION"), text: L("It stays here. Send it when you're back.")))
            case "interrupted": note(DockNote(line: L("INTERRUPTED AT 0:07"), text: L("Not saved. Say it again when you're free.")))
            case "uploadfailed": note(DockNote(line: L("UPLOAD FAILED"), text: L("Tap the photo to retry, or remove it.")))
            // 05M · B·03 / B·04 · the chamber and its cancel state, on a simulator that has no
            // microphone to hold; the waveform shows the board's own bars.
            case "recording", "cancelling": dockMode = .listening
            default: break
            }
            #if DEBUG
            // Session takeover does not need home hydration. Waiting for bootstrap
            // made 12s captures land on Home after a cold install.
            if LiveSessionStore.debugFakeWrist {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.8))
                    liveSession.debugAutoStart(profile: data.profile, weightKg: data.today.weightKg)
                }
            }
            if ProcessInfo.processInfo.environment["NB_DEBUG_MORNING"] == "1" {
                let metrics = Band.allowsSeed ? DataStore.seedToday() : data.today
                if let frame = MorningWidget.frame(today: metrics, history: data.history, ignoreShown: true) {
                    widget = frame
                }
            }
            if ProcessInfo.processInfo.environment["NB_DEBUG_PLUS"] == "open" {
                plusOpen = true
            }
            if ProcessInfo.processInfo.environment["NB_DEBUG_PLUS"] == "dismiss" {
                plusOpen = true
                sheetDrag = 240
            }
            if ProcessInfo.processInfo.environment["NB_DEBUG_CAMERA"] == "1" {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.2))
                    openCamera(sendFood: true)
                }
            }
            if let dock = ProcessInfo.processInfo.environment["NB_DEBUG_DOCK"] {
                switch dock {
                case "keyboard":
                    dockMode = .keyboard
                    if let text = ProcessInfo.processInfo.environment["NB_DEBUG_DRAFT"] {
                        draft = text
                    }
                case "listening":
                    dockMode = .listening
                default:
                    break
                }
            }
            #endif
            #if DEBUG
            // `SIMCTL_CHILD_NB_DEBUG_HOME_DRAG=0.45` freezes a mid-swipe frame: the pages and
            // both sets of dots hold exactly where a 45 % drag would leave them.
            if ProcessInfo.processInfo.environment["NB_DEBUG_HOME_PAGE"] == "1" {
                router.homePage = 1
            }
            if ProcessInfo.processInfo.environment["NB_DEBUG_PLAN"] == "empty" {
                Task { @MainActor in
                    planStore.reset()
                    try? await Task.sleep(for: .seconds(0.8))
                    planSettledOpen = true
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        planY = -screen.height
                        planDragDy = 0
                    }
                }
            } else if ProcessInfo.processInfo.environment["NB_DEBUG_PLAN"] == "1" {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    openPlan(fromIdle: true)
                }
            }
            if DebugEdge.on("charging") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.2))
                    data.applyBandObservation(battery: BandBattery(
                        isPercent: true, percent: 64, level: 3, chargeState: .charging))
                }
            }
            if let f = debugDragFraction, router.homePage == 0, pageX == 0 {
                pageX = -min(1, f) * screen.width
            }
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
            if !session.holdingLaunchStill {
                firstRun.start(reduceMotion: reduceMotion,
                               lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
            }

            // F3 §05 · the home screen reads one row of daily_results and nothing else.
            // ⚠️ Unstructured on purpose: `.task` is cancelled the moment a detail page is
            // pushed over this view, and a cancelled load fell back to the offline seed —
            // opening any page in the first seconds silently turned the whole app into a mock.
            let store = data
            let sync = Task { @MainActor in
                await OriginDataSync.refreshNow(into: store, minimumInterval: SyncCadence.interval,
                    fullHistory: false, reuseRecentLiveReceipt: true)
            }
            let load = Task { @MainActor in
                await Repository.shared.bootstrapHome(into: store)
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

            // 13 col 01 · 昨夜, once a day, within six hours of waking. F5 C4 · the
            // primer still follows the first real morning; later edges do not re-ask.
            if widget == nil, let morning = MorningWidget.frame(today: data.today, history: data.history) {
                withAnimation { widget = morning }
                await MorningWidget.markShown(day: data.today.day, widget: morning)
                NotificationReach.cancelMorning()
                if await NotificationPrimer.shouldOffer() { router.takeover = .notificationPrimer }
            }
            await NotificationReach.refresh(today: data.today, history: data.history,
                                            store: data, page: router.notifyPage,
                                            appIsActive: scenePhase == .active)
            #if DEBUG
            if ProcessInfo.processInfo.environment["NB_DEBUG_NOTIFY"] == "1" {
                await NotificationReach.debugFireNow()
            }
            #endif

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
            if ProcessInfo.processInfo.environment["NB_DEBUG_MORNING"] == "1" {
                let metrics = Band.allowsSeed ? DataStore.seedToday() : data.today
                if let frame = MorningWidget.frame(today: metrics, history: data.history, ignoreShown: true) {
                    widget = frame
                }
                Task { @MainActor in
                    for _ in 0..<20 {
                        let metrics = Band.allowsSeed ? DataStore.seedToday() : data.today
                        if let frame = MorningWidget.frame(today: metrics, history: data.history, ignoreShown: true) {
                            widget = frame
                        }
                        try? await Task.sleep(for: .seconds(1.5))
                    }
                }
            }
            if let want = ProcessInfo.processInfo.environment["NB_DEBUG_PANEL"], !want.isEmpty {
                func pinned() -> PanelWidget? {
                    if want == "thinking" { return .thinking("Why am I so tired today?") }
                    if want == "balance-result" { return WidgetCatalogue.balanceResult }
                    return PanelType(rawValue: want).map { WidgetCatalogue.sample($0) }
                }
                // Pin before bootstrap returns. The old 4s delay started *after*
                // `bootstrapHome`, so a 5s capture still photographed STANDBY.
                if let frame = pinned() { widget = frame }
                Task { @MainActor in
                    guard let frame = pinned() else { return }
                    for _ in 0..<40 {
                        if widget?.type != frame.type || widget?.title != frame.title {
                            widget = pinned()
                        }
                        try? await Task.sleep(for: .seconds(1.5))
                    }
                }
            }
            #endif

            // The shared pull started alongside cloud hydration and still retains all history.
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
                // 14 · a running session holds the band's sensor; the day pull waits for it.
                guard OriginDataSync.isDue, liveSession.session == nil else { continue }
                await OriginDataSync.refreshNow(into: store)
            }
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            // the status bar; iOS paints into it
            Color.clear.frame(height: safe.top)

            // ◇8 · the top bar slides in from −8px as the card lands.
            HomeHeader(name: data.profile.displayName, initials: data.profile.initials,
                       batteryPercent: data.band.batteryPercent,
                       chargeState: data.band.connected ? data.band.displayedCharge : .unknown,
                       flame: data.wearFlame,
                       width: columnWidth,
                       onProfile: { router.open(.profile, from: .home) },
                       onDevice: { router.open(.device, from: .home) })
            .opacity(firstRun.chromeVisible ? 1 : 0)
            .offset(y: firstRun.chromeVisible ? 0 : -8)

            Color.clear.frame(height: 12)

            // the room the panel occupies once it has folded
            Color.clear.frame(width: columnWidth, height: panelHeight)

            Color.clear.frame(height: 12)

            // ◇9 · the two tiles rise from +16px, left before right by 80ms.
            BottomStrip(m: data.today, width: columnWidth,
                        onTraining: { router.open(.training, from: .home) },
                        onFuel: { router.open(.fuel, from: .home) })
                .opacity(firstRun.tilesVisible ? 1 : 0)
                .offset(y: firstRun.tilesVisible ? 0 : 16)
                .offset(x: pageShift)

            Color.clear.frame(height: 12)

            // ◇10 · the three keys land together: it is one tool, not three.
            // ⚠️ Before that the dock is simply not there — never a greyed-out disabled state.
            if firstRun.dockVisible {
                Dock(mode: $dockMode, note: dockNote, attachmentReady: attachment.map { $0.progress >= 1 && !$0.failed },
                     width: columnWidth,
                     draft: $draft,
                     onSend: handleSend,
                     onCamera: { openCamera() },
                     onPlus: {
                        if plusOpen { closePlus() }
                        else { sheetDrag = 0; withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { plusOpen = true } }
                     },
                     onPlusLongPress: {
                        let wait = plusOpen
                        if wait { closePlus() }
                        openCamera(afterMenu: wait, sendFood: true)
                     },
                     menuOpen: plusOpen,
                     onListen: beginListening,
                     onStopListening: endListening,
                     onCancelListening: cancelListening,
                     onKeyboardTap: {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        let initialQuery = text.isEmpty ? nil : text
                        let initialAttachment = attachment?.dataURL
                        draft = ""
                        attachment = nil
                        dockMode = .idle
                        router.open(.chat(initialQuery: initialQuery, attachmentDataURL: initialAttachment), from: .home)
                     })
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
                                      onRetry: { Task { await retryAttach() } },
                                      onRemove: { withAnimation { attachment = nil; photoItem = nil; dockNote = nil } })
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
                                    .buttonStyle(HotZoneTap(pressedScale: 1))
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

            // iOS draws the home indicator itself. The lip sits in this band;
            // the voice key keeps ~20pt of air above the chevron.
            Color.clear.frame(height: dockBottom)
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
                       m: data.todayForDisplay, band: data.band,
                       lastSync: data.lastSync, vitals: data.vitals,
                       widget: widget, firstRun: firstRun,
                       size: full ? screen
                                  : CGSize(width: columnWidth, height: panelHeight),
                       radius: firstRun.panelRadius,
                       onDismissWidget: { dismissWidget() }) { target in
            // 06 · 17 · a fresh measurement answers a tap with a message, not a page.
            if let q = widget?.replyPrompt { handleSend(q) }
            else if let w = widget,
                    let a = w.action,
                    a.contains("确认记录") || a.localizedCaseInsensitiveContains("confirm"),
                    ai.canConfirmMeal(frameID: w.id) {
                confirmMeal(w)
            } else { router.open(target, from: .home) }
        }
        .offset(x: full ? 0 : NB.Layout.gutter + pageShift,
                y: full ? 0 : panelTop)
            // F5 §09 · 「整屏接管」in the accessibility layer: while a frame is up, VoiceOver's
            // focus stays inside the panel, the way the eye does.
            // Keep modality on the panel container rather than its summary or dismiss leaf.
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(widget == nil ? [] : .isModal)
    }

    /// 04B col 02 · the swipe. Horizontal only, two pages, no overscroll. Past 40 % of the
    /// width or faster than 300 pt/s it turns the page; otherwise it springs back. Both
    /// directions share one spring, and nothing on the page animates once it has landed.
    /// While the finger is down and moving sideways nothing else on either page is tappable
    /// (`swiping`), and a touch that started out vertical never turns a page (`homeDrag`).
    private var pageGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                let dx = v.translation.width, dy = v.translation.height
                if homeDrag == nil {
                    if abs(dx) >= abs(dy) {
                        homeDrag = .horizontal
                        pageXAtTouch = pageX - dx
                        Task { await Analytics.shared.track("PLAN_AXIS_LOCK", ["AXIS": "H"]) }
                    } else {
                        let lip = v.startLocation.y >= screen.height - safe.bottom - CGFloat(PlanFaceMath.lipHotZone)
                        if planY != 0 || lip {
                            homeDrag = .plan
                            planYAtTouch = planY
                            Task { await planStore.load(dayKey: data.today.day.key) }
                            Task { await Analytics.shared.track("PLAN_AXIS_LOCK", ["AXIS": "PLAN"]) }
                        } else {
                            homeDrag = .dead
                            Task { await Analytics.shared.track("PLAN_AXIS_LOCK", ["AXIS": "DEAD"]) }
                        }
                    }
                }
                switch homeDrag {
                case .horizontal:
                    dragPage(to: pageXAtTouch + dx)
                    swiping = true
                case .plan:
                    dragPlan(to: planYAtTouch + dy, dy: dy)
                    swiping = true
                case .dead, nil:
                    break
                }
            }
            .onEnded { v in
                let from = router.homePage
                let drag = homeDrag
                swiping = false
                homeDrag = nil
                switch drag {
                case .plan:
                    settlePlan(translation: v.translation.height, velocity: v.velocity.height,
                               opening: planYAtTouch > -screen.height / 2)
                case .horizontal:
                    let dx = v.translation.width
                    let far = abs(dx) > screen.width * 0.4
                    let fast = abs(v.velocity.width) > 300
                    var target = from
                    if from == 0, dx < 0, far || fast { target = 1 }
                    if from == 1, dx > 0, far || fast { target = 0 }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        pageX = -CGFloat(target) * screen.width
                    }
                    if target != from {
                        router.homePage = target
                        Task { await Analytics.shared.track("HOME_PAGE_SWIPE", ["DIR": target == 1 ? "right" : "left", "MS": 350]) }
                    }
                default:
                    pageX = -CGFloat(from) * screen.width
                }
            }
    }

    /// ADR 0018 · one turn on the plan surface. The face shows the thinking stream while it
    /// runs; the row lands on the server, so a face closed mid-way finds it on the next pull.
    private func generatePlan() {
        guard ConsentStore.shared.granted else { router.takeover = .consent; return }
        if !reachability.isOnline || DebugEdge.on("offline") {
            note(DockNote(line: L("NO CONNECTION"), text: L("It stays here. Send it when you're back.")))
            return
        }
        guard !planStore.generating else { return }
        planThinkingStartedAt = Date()
        let day = data.today.day
        Task {
            await planStore.generate(day: day, store: data, ai: ai)
            await Analytics.shared.track("PLAN_GENERATE", ["HAS_PLAN": planStore.plan != nil])
        }
    }

    private func dragPage(to x: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            pageX = min(0, max(-screen.width, x))
        }
    }

    /// A touch the system takes away — the swipe-up to the home screen starts in the lip's
    /// hot zone, Control Center, an incoming call — gets `onChanged` and never `onEnded`.
    /// Left alone, `swiping` / `homeDrag` / a half-way `planY` stay set, every
    /// `allowsHitTesting(!swiping && planY == 0)` on the page stays false, and the app comes
    /// back from the background looking frozen until it is relaunched. So the moment the
    /// scene stops being active the touch is treated as cancelled: the page snaps back to
    /// the page it was on and the plan face to whichever end it had settled at.
    private func cancelInterruptedDrag() {
        guard swiping || homeDrag != nil else { return }
        let drag = homeDrag
        swiping = false
        homeDrag = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            switch drag {
            case .horizontal:
                pageX = -CGFloat(router.homePage) * screen.width
            case .plan:
                planY = planSettledOpen ? -screen.height : 0
                planDragDy = 0
            case .dead, nil:
                break
            }
        }
    }

    private func dragPlan(to y: CGFloat, dy: CGFloat) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            planDragDy = dy
            planY = min(0, max(-screen.height, y))
        }
    }

    private func openPlan(fromIdle: Bool) {
        planSettledOpen = true
        // The day's first open writes the plan; later opens read the row.
        Task {
            await planStore.load(dayKey: data.today.day.key)
            if planStore.plan == nil, !planStore.generating, planSettledOpen { generatePlan() }
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            planY = -screen.height
            planDragDy = 0
        }
        Task { await Analytics.shared.track("PLAN_OPEN", ["FROM": fromIdle ? "IDLE" : "DRAG"]) }
    }

    private func settlePlan(translation: CGFloat, velocity: CGFloat, opening: Bool) {
        if PlanFaceMath.shouldCommit(translation: Double(translation),
                                     velocity: Double(velocity),
                                     opening: opening) {
            if opening { openPlan(fromIdle: false) }
            else {
                planSettledOpen = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    planY = 0
                    planDragDy = 0
                }
            }
        } else {
            planSettledOpen = !opening
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                planY = opening ? 0 : -screen.height
                planDragDy = 0
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
                note(DockNote(line: L("MICROPHONE OFF"), text: L("Typing still works.\nTurn the mic on in Settings."), action: L("Open Settings")))
                return
            }
            // The recorder refused to open — no audio device (a simulator), or CoreAudio said
            // no. The dock stays idle, and it says so: a key that answers a press with nothing
            // at all is the same bug as a wave over a dead microphone.
            let stream = reachability.isOnline ? await ai.beginStreamingTranscription() : nil
            guard await SpeechCapture.shared.start(onPCMChunk: { pcm in stream?.append(pcm) }) else {
                stream?.cancel()
                note(DockNote(line: L("MIC UNAVAILABLE"), text: L("The microphone would not open.\nTyping still works.")), clearAfter: 4)
                return
            }
            asrStream = stream
            withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { dockMode = .listening }
        }
    }

    @State private var showPicker = false

    /// A Shot widget tap lands here. The shutter is the send — same as plus-menu food photo.
    private func fireWidgetShot() {
        guard WidgetBridge.consumePhoto() else { return }
        openCamera(sendFood: true)
    }

    /// Plus · Photograph your meal, and a hold on the dock orb, open the camera and send
    /// the plate; the keyboard-field camera key attaches and waits for a caption.
    /// Simulator / no camera → say so, rather than silently opening the library.
    /// `afterMenu` waits for the plus sheet's dismiss (0.22 s) so the camera cover is not fighting it.
    private func openCamera(afterMenu: Bool = false, sendFood: Bool = false) {
        cameraSendsFood = sendFood
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraSendsFood = false
            note(DockNote(line: L("CAMERA UNAVAILABLE"), text: L("Use Photo library from the plus menu.")), clearAfter: 4)
            return
        }
        if afterMenu {
            Task {
                try? await Task.sleep(for: .milliseconds(240))
                presentCamera()
            }
        } else {
            presentCamera()
        }
    }

    private func presentCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentSystemCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        presentSystemCamera()
                    } else {
                        cameraSendsFood = false
                        noteCameraDenied()
                    }
                }
            }
        default:
            cameraSendsFood = false
            noteCameraDenied()
        }
    }

    private func presentSystemCamera() {
        let sendFood = cameraSendsFood
        CameraGate.present(
            onCapture: { image in
                cameraSendsFood = false
                Task {
                    if sendFood { await sendFoodPhoto(image) }
                    else { await attach(image: image) }
                }
            },
            onCancel: { cameraSendsFood = false })
    }

    private func noteCameraDenied() {
        note(DockNote(
            line: L("CAMERA OFF"),
            text: L("Turn the camera on in Settings to photograph a meal."),
            action: L("Open Settings")))
    }

    /// Default caption for a plus-menu food photo. The vision model still reads the plate;
    /// this sentence is only the turn's words.
    private static var foodPhotoPrompt: String {
        L("Log this food from the photo.")
    }

    /// Shutter → prepare → send. No caption step: photographing the meal is the send.
    private func sendFoodPhoto(_ raw: UIImage) async {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) { dockNote = nil }
        do {
            guard let payload = AIImagePayload.prepare(raw) else { throw CocoaError(.fileWriteUnknown) }
            if DebugEdge.on("uploadfailed") { throw CocoaError(.fileWriteUnknown) }
            attachment = Attachment(image: payload.preview, dataURL: payload.dataURL, progress: 1)
            await Analytics.shared.track("PHOTO_ATTACH", [:])
            await Analytics.shared.track("PHOTO_UPLOAD", ["MS": 0, "BYTES": payload.byteCount, "OK": true])
            handleSend(Self.foodPhotoPrompt)
        } catch {
            attachment = Attachment(image: raw, dataURL: "", progress: 0, failed: true)
            note(DockNote(
                line: L("UPLOAD FAILED"),
                text: L("Tap the photo to retry, or remove it.")))
            await Analytics.shared.track("PHOTO_UPLOAD", ["MS": 0, "BYTES": 0, "OK": false])
        }
    }

    private func attachFromPicker() async {
        do {
            guard let item = photoItem,
                  let data = try await item.loadTransferable(type: Data.self),
                  let raw = UIImage(data: data) else { throw CocoaError(.fileReadCorruptFile) }
            await attach(image: raw)
        } catch {
            note(DockNote(line: L("UPLOAD FAILED"), text: L("Tap the photo to retry, or remove it.")))
            await Analytics.shared.track("PHOTO_UPLOAD", ["MS": 0, "BYTES": 0, "OK": false])
        }
    }

    private func retryAttach() async {
        if let image = attachment?.image {
            await attach(image: image, clearingFirst: false)
            return
        }
        await attachFromPicker()
    }

    /// 05 · C02 → C04 · the thumbnail lands, the progress is drawn on the photo itself, and
    /// 100 % is the only completion signal. ⚠️ There is no storage bucket in this build: the
    /// bytes travel with the message, so "upload" is the read-and-resize that makes them ready.
    private func attach(image raw: UIImage, clearingFirst: Bool = true) async {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) { dockNote = nil }
        if clearingFirst { attachment = nil }
        do {
            guard let payload = AIImagePayload.prepare(raw) else { throw CocoaError(.fileWriteUnknown) }
            if DebugEdge.on("uploadfailed") { throw CocoaError(.fileWriteUnknown) }
            var a = Attachment(image: payload.preview, dataURL: payload.dataURL, progress: 0)
            withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) { attachment = a }
            // the bar and the percentage climb on the photo; the field stays typeable throughout
            for step in 1...10 {
                try? await Task.sleep(for: .milliseconds(60))
                a.progress = Double(step) / 10
                attachment = a
            }
            await Analytics.shared.track("PHOTO_ATTACH", [:])
            await Analytics.shared.track("PHOTO_UPLOAD", ["MS": 600, "BYTES": payload.byteCount, "OK": true])
            if dockMode != .keyboard { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { dockMode = .keyboard } }
        } catch {
            // 05 edge 4 · UPLOAD FAILED. The caption stays, the send stays dark, the photo says so.
            if var a = attachment { a.failed = true; attachment = a }
            else {
                attachment = Attachment(image: raw, dataURL: "", progress: 0, failed: true)
            }
            note(DockNote(line: L("UPLOAD FAILED"), text: L("Tap the photo to retry, or remove it.")))
            await Analytics.shared.track("PHOTO_UPLOAD", ["MS": 0, "BYTES": 0, "OK": false])
        }
    }

    /// 05 edges · show the line, and clear it on its own when the board says so.
    /// Confirmation writes the model-selected draft. No second turn, no keyword path.
    private func confirmMeal(_ frame: PanelWidget) {
        lastSent = nil
        let day = backlogDay ?? UserDay.containing(Date())
        if let next = ai.confirmMeal(frameID: frame.id, slot: slotFor(day: day), into: data) {
            withAnimation { widget = next }
        } else {
            withAnimation { widget = PanelWidget(type: .text, title: L("OFFLINE"), tag: .fuel,
                                                 sentence: L("That meal did not save. Tap confirm once more."),
                                                 footer: String(frame.footer?.prefix(42) ?? ""),
                                                 action: L("CONFIRM"), data: .none) }
        }
    }

    private func beginPanelRequest() -> UUID {
        let requestID = UUID()
        panelRequestID = requestID
        return requestID
    }

    /// Every non-idle panel state is temporary. Rotating the request id invalidates any
    /// answer still in flight before restoring STANDBY and its live wrist readout.
    private func dismissWidget() {
        guard widget != nil else { return }
        panelRequestID = UUID()
        lastSent = nil
        withAnimation(.easeOut(duration: 0.18)) { widget = nil }
    }

    private func closePlus() {
        withAnimation(.easeIn(duration: 0.22)) { plusOpen = false }
        sheetDrag = 0
    }

    /// 04B 上线前 · 埋点在写卡之前先埋好. Every opening of page two reports what the cards
    /// actually showed — FRESH / STALE / GONE / EMPTY per card — plus the two states that
    /// otherwise leave no trace: never synced, and an off-wrist gap of an hour or more
    /// (the same one the foot line prints, once per user day).
    private func trackPageTwoOpen() {
        let m = data.today, vitals = data.vitals, lastSync = data.lastSync
        let states = VitalsPage.cardStates(
            m: m, vitals: vitals, history: data.history,
            mealResponsePoints: data.mealResponsePoints,
            mealResponseZerosToday: data.mealResponseZerosToday)
        let gap = VitalsMath.offWrist(m.vitalsCurve)
        Task {
            for card in ["SLEEP", "HEART", "BODY_BATTERY", "STRESS", "TEMP", "STEPS", "DISTANCE", "ACTIVE"] {
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
        let stream = asrStream
        asrStream = nil
        stream?.cancel()
        Task {
            if let clip = await SpeechCapture.shared.stop() {
                try? FileManager.default.removeItem(at: clip)
            }
        }
        Task { await Analytics.shared.track("VOICE_CANCEL", ["REASON": "SLIDE_UP"]) }
    }

    private func endListening() {
        // 05M · B·05 · RELEASE 0.22S · EASE-OUT-BACK · the chamber collapses into the capsule.
        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) { dockMode = .idle }
        let stream = asrStream
        asrStream = nil
        Task {
            let elapsed = SpeechCapture.shared.elapsed
            // stop() waits on the audio queue rather than the main one, for the same reason
            // start() does: tearing down a session that is not answering must not freeze a tap.
            guard let clip = await SpeechCapture.shared.stop() else {
                stream?.cancel()
                return
            }
            defer { try? FileManager.default.removeItem(at: clip) }
            // 05 edge 6 · INTERRUPTED. A call or an alarm took the mic: half a sentence is worse
            // than none, so nothing is sent and the dock says it was not saved.
            if let t = SpeechCapture.shared.interruptedAt {
                stream?.cancel()
                note(DockNote(line: L("INTERRUPTED AT %d:%02d", Int(t) / 60, Int(t) % 60),
                              text: L("Not saved. Say it again when you're free.")), clearAfter: 4)
                return
            }
            // 05 edge 2 · TOO SHORT. Under 0.6 s is a slip: no send, no error, 1.2 s on the capsule.
            if elapsed < 0.6 {
                stream?.cancel()
                note(DockNote(line: L("%.1fS · TOO SHORT", elapsed), text: L("Hold, say it, then let go.")), clearAfter: 1.2)
                return
            }
            // 05 edge 5 · OFFLINE. A clip cannot wait in the dock the way a draft does, so the
            // capsule says when to say it again rather than pretending it heard nothing.
            if !reachability.isOnline || DebugEdge.on("offline") {
                stream?.cancel()
                note(DockNote(line: L("NO CONNECTION"), text: L("Say it again when you're back.")), clearAfter: 4)
                return
            }
            let requestID = beginPanelRequest()
            withAnimation { widget = .thinking }
            switch await ai.transcribe(clip, stream: stream) {
            case .text(let said):
                guard panelRequestID == requestID else { return }
                handleSend(said)
            case .silence:
                guard panelRequestID == requestID else { return }
                // 05 edge 3 · NO SPEECH. Recorded, transcribed to nothing: it stays in the dock
                // for the next take rather than sending her an empty message.
                withAnimation { widget = nil }
                note(DockNote(line: L("NOTHING HEARD"), text: L("Say it again, or type it.")), clearAfter: 4)
            case .failed:
                guard panelRequestID == requestID else { return }
                // Not on the board's list of six, because the board assumed the server answers.
                // A 401, a 503 or a dropped upload is not silence, and telling her to speak up
                // for it would be a lie; the line names the step that failed.
                withAnimation { widget = nil }
                note(DockNote(line: L("COULDN'T TRANSCRIBE"), text: L("Say it again, or type it.")), clearAfter: 4)
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
            note(DockNote(line: L("NO CONNECTION"), text: L("It stays here. Send it when you're back.")))
            return
        }
        let day = backlogDay ?? UserDay.containing(Date())
        backlogDay = nil
        lastSent = (text, day)
        let requestID = beginPanelRequest()
        withAnimation { widget = .thinking(text) }

        // 05 · C05 → C07 · photo and caption leave as one object and come back as one answer
        // with the source chip. The plate is logged to today's fuel on the way.
        if let a = attachment, a.progress >= 1, !a.failed {
            let sent = a
            withAnimation(.spring(response: 0.26, dampingFraction: 0.74)) { attachment = nil }
            photoItem = nil
            Task {
                let frame = await ai.turn(text, day: day, store: data, imageDataURL: sent.dataURL)
                await Analytics.shared.track("MSG_SEND", ["TYPE": "PHOTO", "CHARS": text.count, "HAS_PHOTO": true])
                guard panelRequestID == requestID else { return }
                withAnimation { widget = frame ?? PanelWidget(type: .text, title: L("OFFLINE"), tag: .fuel,
                                                              sentence: L("Could not read that plate. Your words are kept; send it again."),
                                                              footer: String(text.prefix(42)), action: nil, data: .none) }
            }
            return
        }

        Task {
            // ADR 0011 · every dock sentence is one turn. The model picks meal.estimate
            // when the plate is a log; the client does not classify food or medicine.
            let frame = await ai.turn(text, day: day, store: data)
            guard panelRequestID == requestID else { return }
            withAnimation { widget = frame ?? .thinking(text) }
        }
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
            .accessibilityLabel(L("Remove photo"))
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

/// Kept separate so diagnostic observation does not enlarge Home's view-builder expression.
private struct NightHomeDiagnosticObserver: View {
    let metrics: DailyMetrics
    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { record() }
            .onChange(of: metrics.sleep) { _, _ in record() }
            .onChange(of: metrics.vitalsCurve) { _, _ in record() }
            .onChange(of: metrics.day) { _, _ in record() }
    }
    private func record() {
        #if DEBUG
        guard NightDiagnostics.shared.isEnabled else { return }
        NightDiagnostics.shared.record("ui.home_input", fields: HomeSnapshot.diagnosticFields(
            day: metrics.day, samples: metrics.vitalsCurve, sleep: metrics.sleep))
        #endif
    }
}
