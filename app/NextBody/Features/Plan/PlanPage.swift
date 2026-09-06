import SwiftUI

/// Paper 04D · B 目录. Magazine index, not a sixth detail page.
struct PlanPage: View {
    let face: PlanFaceMath.Face
    var flatten: CGFloat
    var reduceMotion: Bool
    var closeEnabled = true
    var onCloseDragChanged: (CGFloat) -> Void
    var onCloseDragEnded: (CGFloat, CGFloat) -> Void

    @State private var scrollY: CGFloat = 0
    @State private var closing = false

    var body: some View {
        ZStack(alignment: .top) {
            NB.carbon.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    chrome
                    head
                    Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)
                        .padding(.top, 14)
                    contents
                    readLog
                    why
                }
                .frame(width: NB.Layout.contentWidth)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 28)
            }
            .scrollDisabled(closing)
            .modifier(PlanScrollWatch(onChange: { scrollY = $0 }))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.page")
        // Keep `.all` once the close pull has started. `closeEnabled` is `planOpen`
        // on the parent, and that flips false after one point of travel — dropping
        // the mask mid-swipe cancelled the first pull and made people swipe twice.
        .simultaneousGesture(
            closeGesture,
            including: (closeEnabled || closing) && canCloseFromHere ? .all : .subviews)
    }

    private var canCloseFromHere: Bool { scrollY <= 2 || closing }

    private var closeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let dy = value.translation.height
                guard dy > 0 else { return }
                closing = true
                onCloseDragChanged(dy)
            }
            .onEnded { value in
                let dy = value.translation.height
                closing = false
                onCloseDragEnded(dy, value.velocity.height)
            }
    }

    private var chrome: some View {
        VStack(spacing: 7) {
            PlanChevron(up: false, playing: !reduceMotion, flatten: flatten,
                        armed: false, reduceMotion: reduceMotion)
            HStack(spacing: 6) {
                Circle().fill(NB.lime1).frame(width: 3, height: 3)
                Text(L("AGENT · %@ generated", face.generatedClock))
                    .font(NBFont.dot(600, 9))
                    .tracking(0.24 * 9)
                    .foregroundStyle(NB.lime1.opacity(0.60))
            }
        }
        // Home ignores the vertical safe area, so this page has to clear
        // the Dynamic Island itself — 8pt of air under the cutout.
        .padding(.top, ScreenMetrics.safeArea.top + 8)
        .padding(.bottom, 2)
        .accessibilityLabel(L("Swipe down for home"))
    }

    private var head: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L("TODAY'S CONTENTS"))
                    .font(NBFont.dot(600, 10))
                    .tracking(0.30 * 10)
                    .foregroundStyle(NB.lime1)
                    .accessibilityIdentifier("plan.eyebrow")
                Text(headline)
                    .font(NBFont.brand(700, 24))
                    .tracking(-0.01 * 24)
                    .foregroundStyle(NB.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if let score = face.score {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(score)")
                        .font(NBFont.dot(700, 26))
                        .tracking(-0.02 * 26)
                        .foregroundStyle(scoreTint(score))
                    Text(L("SLEEP"))
                        .font(NBFont.dot(600, 9))
                        .tracking(0.20 * 9)
                        .foregroundStyle(Color.white.opacity(0.42))
                }
            }
        }
        .padding(.top, 18)
    }

    private var contents: some View {
        VStack(spacing: 17) {
            if face.empty {
                Text(L("No scored night. The plan stays silent."))
                    .font(NBFont.ui(300, 13))
                    .foregroundStyle(Color.white.opacity(0.60))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            } else {
                ForEach(Array(face.actions.enumerated()), id: \.offset) { index, action in
                    actionRow(index: index, action: action)
                }
            }
        }
        .padding(.top, 16)
    }

    private func actionRow(index: Int, action: PlanFaceMath.Action) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(format: "%02d", index + 1))
                .font(NBFont.dot(700, 21))
                .foregroundStyle(NB.lime1)
                .frame(width: 30, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 8) {
                    Text(actionTitle(action))
                        .font(NBFont.brand(600, 15.5))
                        .foregroundStyle(NB.white)
                        .fixedSize()
                    dashedLeader
                    Text(action.kind == .strength ? L("RUN TOMORROW") : action.trailing)
                        .font(NBFont.dot(700, 11))
                        .tracking(0.04 * 11)
                        .foregroundStyle(NB.lime1)
                        .fixedSize()
                }
                Text(actionDetail(action))
                    .font(NBFont.ui(300, 12))
                    .foregroundStyle(Color.white.opacity(0.50))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var dashedLeader: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .foregroundStyle(Color.white.opacity(0.20))
            .frame(height: 1)
            .padding(.bottom, 5)
    }

    private var readLog: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("WHAT THE AI READ"))
                    .font(NBFont.dot(600, 9))
                    .tracking(0.26 * 9)
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
                Text(L("4 READS · CAP 4"))
                    .font(NBFont.dot(500, 9))
                    .tracking(0.16 * 9)
                    .foregroundStyle(Color.white.opacity(0.30))
            }
            .padding(.bottom, 9)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            ForEach(Array(face.reads.enumerated()), id: \.offset) { index, read in
                if index > 0 {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%02d", index + 1))
                        .font(NBFont.dot(600, 9))
                        .foregroundStyle(NB.lime1)
                        .frame(width: 14, alignment: .leading)
                    Text(readTitle(read.kind))
                        .font(NBFont.ui(500, 12))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 118, alignment: .leading)
                    Text(readGrain(read))
                        .font(NBFont.dot(500, 9))
                        .tracking(0.08 * 9)
                        .foregroundStyle(Color.white.opacity(0.35))
                        .frame(width: 62, alignment: .leading)
                    Text(readValue(read))
                        .font(NBFont.dot(600, 10))
                        .tracking(0.04 * 10)
                        .foregroundStyle(Color.white.opacity(0.60))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.vertical, 9)
            }
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack {
                Text(readyLine)
                    .font(NBFont.dot(500, 9))
                    .tracking(0.14 * 9)
                    .foregroundStyle(Color.white.opacity(0.30))
                Spacer()
                Text(L("LOCAL · NO TURN"))
                    .font(NBFont.dot(500, 9))
                    .tracking(0.14 * 9)
                    .foregroundStyle(Color.white.opacity(0.30))
            }
            .padding(.top, 9)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.top, 20)
    }

    private var why: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(L("WHY THESE FOUR"))
                    .font(NBFont.dot(600, 9))
                    .tracking(0.28 * 9)
                    .foregroundStyle(Color.white.opacity(0.42))
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
            Text(whyCopy)
                .font(NBFont.ui(300, 13))
                .lineSpacing(7)
                .foregroundStyle(Color.white.opacity(0.60))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 20)
    }

    private var headline: String {
        if face.empty { return L("NO NIGHT YET") }
        switch face.weakest {
        case .recovery:     return L("Put recovery back")
        case .regularity:   return L("Bring bedtime back")
        case .architecture: return L("Fix last night's structure")
        case .duration:     return L("Sleep long enough")
        case nil:           return L("TODAY'S CONTENTS")
        }
    }

    private func actionTitle(_ action: PlanFaceMath.Action) -> String {
        switch action.kind {
        case .bed:
            return L("Bed at %@", action.bedClock ?? action.trailing)
        case .load:
            return L("Cap training load at %@", action.trailing)
        case .strength:
            return L("Strength only")
        case .meal:
            return L("Log today's meals")
        }
    }

    private func actionDetail(_ action: PlanFaceMath.Action) -> String {
        switch action.kind {
        case .bed:
            let late = action.minutesLate ?? 0
            if let regularity = action.regularity,
               let part = PlanFaceMath.weighted(regularity, weight: 15) {
                return L("Fell asleep %d minutes later than your median · regularity %d/15",
                         late, part)
            }
            return L("Fell asleep %d minutes later than your median", late)
        case .load:
            if let yesterday = action.yesterday, let dayBefore = action.dayBefore {
                return L("Yesterday %@ · day before %@ · two days without a drop",
                         PlanFaceMath.loadLabel(yesterday),
                         PlanFaceMath.loadLabel(dayBefore))
            }
            if let yesterday = action.yesterday {
                return L("Yesterday %@", PlanFaceMath.loadLabel(yesterday))
            }
            return L("Keep today's training load at the target.")
        case .strength:
            return L("Don't stack cardio volume before recovery returns")
        case .meal:
            return L("The calorie table is still UNLOGGED · DIFF cannot be named")
        }
    }

    private func readTitle(_ kind: String) -> String {
        switch kind {
        case "score":  return L("SLEEP SCORE")
        case "hrv":    return L("NIGHT HRV")
        case "load":   return L("Training load")
        default:       return L("ACTIVE MINUTES")
        }
    }

    private func readGrain(_ read: PlanFaceMath.Read) -> String {
        switch read.kind {
        case "score":
            if face.scoredNightCount > 0 {
                return L("%d NIGHTS", face.scoredNightCount)
            }
            return PlanFaceMath.dash
        case "hrv":    return L("30 MIN BUCKET")
        case "load":   return L("DAILY")
        default:       return L("DERIVED")
        }
    }

    private func readValue(_ read: PlanFaceMath.Read) -> String {
        switch read.kind {
        case "score":
            guard let night = face.night else { return PlanFaceMath.dash }
            if let recovery = PlanFaceMath.weighted(night.recovery, weight: 35) {
                return "\(night.score) · \(L("REC %d/35", recovery))"
            }
            return "\(night.score)"
        case "hrv":
            guard let ms = face.night?.hrvMs else { return PlanFaceMath.dash }
            let value = L("%d MS", Int(ms.rounded()))
            if let index = face.night?.nightIndex, index > 0 {
                return "\(value) · \(L("NIGHT %d", index))"
            }
            return value
        case "load":
            let yesterday = PlanFaceMath.loadLabel(face.load.yesterday)
            let dayBefore = PlanFaceMath.loadLabel(face.load.dayBefore)
            if yesterday == PlanFaceMath.dash && dayBefore == PlanFaceMath.dash {
                return PlanFaceMath.dash
            }
            return "\(yesterday) · \(dayBefore) · \(L("CAP 21"))"
        default:
            return read.value
        }
    }

    private var readyLine: String {
        if let from = face.readyFrom, let to = face.readyTo {
            return L("READY %@ → %@", from, to)
        }
        return L("READY ——")
    }

    private var whyCopy: String {
        if face.empty {
            return L("No scored night. The plan stays silent.")
        }
        let night = face.night
        let duration = PlanFaceMath.weighted(night?.duration, weight: 25).map(String.init) ?? PlanFaceMath.dash
        let architecture = PlanFaceMath.weighted(night?.architecture, weight: 25).map(String.init) ?? PlanFaceMath.dash
        let recovery = PlanFaceMath.weighted(night?.recovery, weight: 35).map(String.init) ?? PlanFaceMath.dash
        let regularity = PlanFaceMath.weighted(night?.regularity, weight: 15).map(String.init) ?? PlanFaceMath.dash
        return L("Duration took %@/25, structure %@/25. Recovery %@/35 is the low group, regularity %@/15 next. Recovery's levers today are training load — night HRV, resting heart, overnight oxygen are results, not actions. So the load comes down, and bedtime moves toward your own median. Meals do not enter the score, but DIFF cannot be named until they are logged.",
                 duration, architecture, recovery, regularity)
    }

    private func scoreTint(_ score: Int) -> Color {
        switch score {
        case 80...:   NB.optimal2
        case 60..<80: NB.violet1
        case 40..<60: NB.compareAmber
        default:      NB.ember1
        }
    }
}

enum PlanSnapshot {
    private static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd"
        return formatter
    }()

    static func make(today: DailyMetrics, history: [DailyMetrics],
                     scores: [String: SleepScore], now: Date = Date()) -> PlanFaceMath.Face {
        let past = history.filter { $0.day < today.day }.sorted { $0.day < $1.day }
        let yesterday = past.last
        let dayBefore = past.dropLast().last
        let load = PlanFaceMath.Load(
            yesterday: yesterday?.trainingLoad,
            dayBefore: dayBefore?.trainingLoad,
            target: today.targetLoad ?? yesterday?.targetLoad,
            activeMinutes: today.activeMinutes)
        let mealsLogged = today.fuelState != .unlogged
        let scored = (0..<7).compactMap { back -> (UserDay, SleepScore)? in
            let day = today.day.adding(days: -back)
            guard let score = scores[day.key] else { return nil }
            return (day, score)
        }
        let readyFrom = scored.last.map { monthDay.string(from: $0.0.date) }
        let readyTo = scored.first.map { monthDay.string(from: $0.0.date) }
        let nightScore = scores[today.day.key] ?? today.sleepScore
        let night = nightScore.map { score in
            PlanFaceMath.Night(
                score: score.score,
                duration: score.duration,
                architecture: score.architecture,
                recovery: score.recovery,
                regularity: score.regularity,
                personalWeight: score.personalWeight,
                hrvMs: score.inputs["hrv_ms"],
                bedOffset: score.inputs["bed_offset"],
                nightIndex: scores.count)
        }
        return PlanFaceMath.face(
            night: night,
            load: load,
            mealsLogged: mealsLogged,
            scoredNightCount: scores.count,
            readyFrom: readyFrom,
            readyTo: readyTo,
            now: now)
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

private struct PlanScrollWatch: ViewModifier {
    let onChange: (CGFloat) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, value in onChange(value) }
        } else {
            content
        }
    }
}
