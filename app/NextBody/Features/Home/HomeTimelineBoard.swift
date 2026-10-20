import SwiftUI

/// 11-A · Today timeline. The workout pill is chrome, not an event.
/// The top edge is the way home: a lime chevron and "Swipe down for home".
struct HomeTimelineBoard: View {
    let events: [HomeV2Model.TimelineItem]
    let earlier: Bool
    let onEarlier: () -> Void
    let onWorkout: () -> Void
    let onOpen: (HomeV2Model.TimelineItem) -> Void
    let onClose: () -> Void
    /// Sheet progress owned by the deck: 1 is up, 0 is dismissed. The header pull writes it.
    @Binding var pull: CGFloat
    /// Finger lifted mid-pull. Velocity is points per second; the second value is where the pull started.
    let onPullEnd: (CGFloat, CGFloat) -> Void

    @State private var pulling = false
    @State private var pullAtTouch: CGFloat = 1

    private var rows: [HomeV2Model.TimelineItem] {
        if ProcessInfo.processInfo.environment["NB_DEBUG_HOME_BOARD"] == "timeline" {
            return Self.board
        }
        return events
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            slideHint
                .padding(.top, ScreenMetrics.safeArea.top + 2)
            HStack(alignment: .center) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(L("Today"))
                        .font(.custom("InterTight-Bold", size: 30))
                        .tracking(-0.02 * 30)
                        .foregroundStyle(Color.white)
                    Text(L("%d events", rows.count))
                        .font(.custom("Jost-Regular", size: 13))
                        .foregroundStyle(Color.white.opacity(0.48))
                }
                Spacer()
                Button(action: onWorkout) {
                    HStack(spacing: 6) {
                        PlayMark()
                        Text(L("Workout"))
                            .font(.custom("Jost-SemiBold", size: 13))
                            .tracking(0.01 * 13)
                    }
                    .foregroundStyle(NB.carbon)
                    .padding(.leading, 13)
                    .padding(.trailing, 15)
                    .padding(.vertical, 7)
                    .background(NB.lime1, in: Capsule())
                }
                .buttonStyle(HotZoneTap(pressedScale: 0.97))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, rows.isEmpty ? 8 : 18)
            .contentShape(Rectangle())
            .gesture(headerPull)
            if rows.isEmpty {
                Button(action: onWorkout) {
                    Text(L("Start your workout"))
                        .font(.custom("Jost-Regular", size: 15))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
                .buttonStyle(HotZoneTap(pressedScale: 1))
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, event in
                        TimelineRailRow(event: event, continues: index < rows.count - 1, onOpen: { onOpen(event) })
                    }
                    Button(action: onEarlier) {
                        Text(earlier ? L("Today only") : L("Past 7 days ↓"))
                            .font(.custom("Jost-Regular", size: 14))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                    .buttonStyle(HotZoneTap(pressedScale: 1))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, ScreenMetrics.safeArea.bottom + 12)
                .background {
                    TimelineSheetPull(onChanged: dragSheet, onEnded: endSheet)
                        .frame(width: 0, height: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon)
    }

    /// Pinned under the status bar. The planet's up-chevron opens this sheet; this one sends it home.
    private var slideHint: some View {
        Button(action: onClose) {
            HStack(spacing: 6) {
                ChevronDownMark()
                    .accessibilityHidden(true)
                Text(L("Swipe down for home"))
                    .font(.custom("Jost-Regular", size: 12))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(HotZoneTap(pressedScale: 1))
        .simultaneousGesture(headerPull)
        .accessibilityIdentifier("TIMELINE_DISMISS")
    }

    /// Dragging the hint or the title down carries the sheet with the finger.
    private var headerPull: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in dragSheet(value.translation.height) }
            .onEnded { value in endSheet(value.velocity.height) }
    }

    private func dragSheet(_ translation: CGFloat) {
        if !pulling {
            pulling = true
            pullAtTouch = pull
        }
        let span = max(ScreenMetrics.size.height, 1)
        pull = min(1, max(0, pullAtTouch - translation / span))
    }

    private func endSheet(_ velocity: CGFloat) {
        let started = pullAtTouch
        pulling = false
        onPullEnd(velocity, started)
    }

    private static var board: [HomeV2Model.TimelineItem] {
        let day = UserDay.containing(Date())
        func at(_ h: Int, _ m: Int) -> Date {
            Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: day.start) ?? day.start
        }
        return [
            .init(id: "now", at: at(14, 12), title: "Now · walking",
                  detail: "1,840 steps · 18 min outdoor · HR 98", accent: .now, meal: nil, trailing: "+0.9"),
            .init(id: "lunch", at: at(12, 45), title: "Lunch · chicken rice bowl",
                  detail: "Steady · within 6% of usual", accent: .meal,
                  meal: .init(kcal: 620, protein: 38, carb: 72, fat: 18), trailing: nil),
            .init(id: "stress", at: at(11, 30), title: "Stress peak · 68",
                  detail: "Seated 35 min · recovered by 12:05", accent: .stress, meal: nil, trailing: nil),
            .init(id: "move", at: at(8, 15), title: "Morning mobility",
                  detail: "22 min · Zone 2 · 142 kcal", accent: .workout, meal: nil, trailing: "+2.4"),
            .init(id: "wake", at: at(7, 12), title: "Woke up · sleep 82",
                  detail: "7h 12m · HRV 54 ms · SpO2 97%", accent: .sleep, meal: nil, trailing: nil)
        ]
    }
}

private struct TimelineRailRow: View {
    let event: HomeV2Model.TimelineItem
    let continues: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            row
        }
        .buttonStyle(HotZoneTap(pressedScale: 1))
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(Fmt.clock(event.at))
                .font(NBFont.dot(700, 13))
                .foregroundStyle(Color.white.opacity(0.72))
                .frame(width: 44, alignment: .leading)
                .padding(.top, 2)
            VStack(spacing: 0) {
                Circle()
                    .fill(dot)
                    .frame(width: 7, height: 7)
                    .padding(.top, 7)
                if continues {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 6)
                }
            }
            .frame(width: 12)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(event.title)
                        .font(.custom(event.accent == .now ? "InterTight-Bold" : "InterTight-SemiBold", size: 15))
                        .foregroundStyle(event.accent == .now ? NB.lime1 : Color.white)
                    Spacer(minLength: 8)
                    if let trailing = event.trailing {
                        Text(trailing)
                            .font(NBFont.dot(700, 13))
                            .foregroundStyle(Color.white.opacity(0.56))
                    }
                }
                if let meal = event.meal {
                    mealCard(meal)
                }
                if !event.detail.isEmpty {
                    if event.meal != nil {
                        HStack(spacing: 10) {
                            SteadyWave()
                            Text(event.detail)
                                .font(.custom("Jost-Regular", size: 13))
                                .foregroundStyle(Color.white.opacity(0.56))
                        }
                    } else {
                        Text(event.detail)
                            .font(.custom("Jost-Regular", size: 13))
                            .foregroundStyle(Color.white.opacity(0.56))
                    }
                }
            }
            .padding(.bottom, continues ? 22 : 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var dot: Color {
        switch event.accent {
        case .now: return NB.lime1
        case .meal: return Color.white.opacity(0.35)
        case .stress: return NB.ember1
        case .workout: return Color.white.opacity(0.35)
        case .sleep: return Color.white.opacity(0.35)
        case .sync: return Color.white.opacity(0.25)
        }
    }

    private func mealCard(_ meal: HomeV2Model.TimelineMeal) -> some View {
        HStack(spacing: 12) {
            PlateThumb()
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(meal.kcal)")
                        .font(NBFont.dot(700, 22))
                        .foregroundStyle(Color.white)
                    Text("kcal")
                        .font(.custom("Jost-Regular", size: 12))
                        .foregroundStyle(Color.white.opacity(0.56))
                }
                HStack(spacing: 2) {
                    Rectangle().fill(NB.lime1).frame(maxWidth: .infinity)
                    Rectangle().fill(Color.white.opacity(0.56)).frame(maxWidth: .infinity)
                    Rectangle().fill(Color.white.opacity(0.24)).frame(maxWidth: .infinity)
                }
                .frame(height: 4)
                Text(L("Protein %dg · Carbs %dg · Fat %dg", meal.protein, meal.carb, meal.fat))
                    .font(.custom("Jost-Regular", size: 12))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
        }
        .padding(10)
        .background(Color(hex: 0x141418), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}

private struct PlateThumb: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: 0xE9E1D0)).frame(width: 44, height: 44).offset(y: 2)
            Circle().fill(Color(hex: 0xF6F1E6)).frame(width: 34, height: 34).offset(y: 2)
            Ellipse().fill(Color(hex: 0xC98A4B)).frame(width: 16, height: 10).offset(x: -7, y: -2)
            Circle().fill(Color(hex: 0x6FA44A)).frame(width: 8, height: 8).offset(x: 6, y: 6)
            Circle().fill(Color(hex: 0xE2543B)).frame(width: 5, height: 5).offset(x: 10, y: 2)
        }
        .frame(width: 64, height: 64)
        .background(Color(hex: 0x2A241C), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SteadyWave: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height * 0.65))
            path.addCurve(to: CGPoint(x: size.width * 0.4, y: size.height * 0.3),
                          control1: CGPoint(x: size.width * 0.15, y: size.height * 0.65),
                          control2: CGPoint(x: size.width * 0.25, y: size.height * 0.3))
            path.addCurve(to: CGPoint(x: size.width, y: size.height * 0.6),
                          control1: CGPoint(x: size.width * 0.6, y: size.height * 0.3),
                          control2: CGPoint(x: size.width * 0.75, y: size.height * 0.6))
            context.stroke(path, with: .color(Color.white.opacity(0.72)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .frame(width: 72, height: 18)
        .accessibilityHidden(true)
    }
}

private struct PlayMark: View {
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 1, y: 1))
            path.addLine(to: CGPoint(x: 8, y: 5))
            path.addLine(to: CGPoint(x: 1, y: 9))
            path.closeSubpath()
        }
        .fill(NB.carbon)
        .frame(width: 9, height: 10)
    }
}

/// Same stroke as the planet's up-chevron, turned down.
private struct ChevronDownMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion)) { timeline in
            let wave = reduceMotion ? 0.0 : sin(timeline.date.timeIntervalSinceReferenceDate * 2.4)
            stroke.offset(y: CGFloat(wave) * 2)
        }
    }

    private var stroke: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 2, y: 2))
            path.addLine(to: CGPoint(x: size.width / 2, y: size.height - 2))
            path.addLine(to: CGPoint(x: size.width - 2, y: 2))
            context.stroke(path, with: .color(NB.lime1),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .square, lineJoin: .miter))
        }
        .frame(width: 16, height: 10)
    }
}

/// A downward pull that starts with the list at rest carries the sheet.
/// Upward travel fails immediately so the list can still scroll.
private struct TimelineSheetPull: UIViewRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onLayout = { context.coordinator.attach(host: $0) }
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.attach(host: uiView)
    }

    static func dismantleUIView(_ uiView: ProbeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class ProbeView: UIView {
        var onLayout: ((UIView) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onLayout?(self)
        }
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            onLayout?(self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: (CGFloat) -> Void = { _ in }
        private var pan: SheetPullPan?
        private weak var scroll: UIScrollView?
        private var ticket = 0

        func attach(host: UIView) {
            guard host.window != nil else { return }
            ticket += 1
            let ticket = self.ticket
            DispatchQueue.main.async { [weak self, weak host] in
                guard let self, let host, ticket == self.ticket else { return }
                guard let scroll = Self.findScroll(from: host) else { return }
                if let pan = self.pan, pan.view === scroll { return }
                self.detach()
                scroll.gestureRecognizers?
                    .filter { $0 is SheetPullPan }
                    .forEach { scroll.removeGestureRecognizer($0) }
                let pan = SheetPullPan(target: self, action: #selector(self.handle(_:)))
                pan.delegate = self
                scroll.addGestureRecognizer(pan)
                self.pan = pan
                self.scroll = scroll
            }
        }

        func detach() {
            if let pan { pan.view?.removeGestureRecognizer(pan) }
            pan = nil
            scroll = nil
        }

        func gestureRecognizer(_: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            _ = other
            return true
        }

        @objc private func handle(_ pan: SheetPullPan) {
            switch pan.state {
            case .began, .changed:
                onChanged(pan.travel)
            case .ended:
                guard pan.engaged else { return }
                onEnded(pan.velocityY)
            case .cancelled:
                guard pan.engaged else { return }
                onEnded(0)
            default:
                break
            }
        }

        private static func findScroll(from view: UIView) -> UIScrollView? {
            var current: UIView? = view
            var steps = 0
            while let next = current, steps < 30 {
                if let scroll = next as? UIScrollView { return scroll }
                current = next.superview
                steps += 1
            }
            return nil
        }
    }
}

/// Stays possible through the first 8pt, then either takes the sheet or fails so the list scrolls.
private final class SheetPullPan: UIGestureRecognizer {
    private(set) var travel: CGFloat = 0
    private(set) var velocityY: CGFloat = 0
    private(set) var engaged = false
    private var origin = CGPoint.zero
    private var armed = false
    private var claimed = false
    private var samples: [(y: CGFloat, t: TimeInterval)] = []

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard touches.count == 1, let touch = touches.first else {
            state = .failed
            return
        }
        origin = touch.location(in: nil)
        samples = [(origin.y, touch.timestamp)]
        travel = 0
        velocityY = 0
        engaged = false
        claimed = false
        armed = atTop
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else { return }
        let point = touch.location(in: nil)
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        note(point.y, touch.timestamp)
        travel = max(0, dy)
        if state == .possible {
            if abs(dx) < 8, abs(dy) < 8 { return }
            if armed, dy > 8, dy > abs(dx) {
                engaged = true
                state = .began
                claimScroll()
            } else {
                state = .failed
            }
            return
        }
        if state == .began || state == .changed {
            pinScroll()
            state = .changed
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        switch state {
        case .began, .changed:
            state = .ended
        case .possible:
            state = .failed
        default:
            break
        }
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        switch state {
        case .began, .changed:
            state = .cancelled
        case .possible:
            state = .failed
        default:
            break
        }
        super.touchesCancelled(touches, with: event)
    }

    override func reset() {
        super.reset()
        travel = 0
        velocityY = 0
        engaged = false
        claimed = false
        armed = false
        samples = []
    }

    private var atTop: Bool {
        guard let scroll = view as? UIScrollView else { return false }
        return scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 1
    }

    /// Cancel the scroll view's pan for this touch only. Disabling that recognizer
    /// retires it; it does not retire this one. Turning it straight back on leaves
    /// the next drag able to scroll.
    private func claimScroll() {
        guard !claimed, let scroll = view as? UIScrollView else { return }
        claimed = true
        let pan = scroll.panGestureRecognizer
        pan.isEnabled = false
        pan.isEnabled = true
        pinScroll()
    }

    private func pinScroll() {
        guard let scroll = view as? UIScrollView else { return }
        let top = -scroll.adjustedContentInset.top
        if scroll.contentOffset.y < top - 0.5 {
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: top), animated: false)
        }
    }

    private func note(_ y: CGFloat, _ time: TimeInterval) {
        samples.append((y, time))
        samples.removeAll { time - $0.t > 0.08 }
        guard let first = samples.first else { return }
        let dt = time - first.t
        if dt > 0.016 { velocityY = (y - first.y) / CGFloat(dt) }
    }
}
