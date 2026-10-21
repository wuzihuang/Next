import SwiftUI

/// Historical timeline: day columns share a time-of-day axis instead of stacking event rows.
struct HomeRhythmHistory: View {
    let today: UserDay
    let events: [HomeV2Model.TimelineItem]
    let metrics: [DailyMetrics]
    let loading: Bool
    let onBack: () -> Void
    let onOpen: (HomeV2Model.TimelineItem) -> Void

    @State private var range = 30
    @State private var selected: UserDay?

    private var days: [UserDay] { UserDay.last(range, endingAt: today) }
    private var firstWeekday: Int {
        (Calendar.current.component(.weekday, from: days[0].start) + 5) % 7
    }
    private var calendarDays: [UserDay?] {
        let filled = Array(repeating: Optional<UserDay>.none, count: firstWeekday)
            + days.map(Optional.some)
        return filled + Array(repeating: nil, count: (7 - filled.count % 7) % 7)
    }
    private var visibleEvents: [HomeV2Model.TimelineItem] {
        events.filter { $0.at >= days[0].start && $0.at < today.end }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Text("‹ " + L("Today"))
                        .font(.custom("Jost-Medium", size: 15))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .accessibilityIdentifier("RHYTHM_BACK")
                Spacer()
                HStack(spacing: 2) {
                    rangeButton(7)
                    rangeButton(30)
                    Text("1Y")
                        .font(NBFont.dot(600, 10))
                        .foregroundStyle(.white.opacity(0.25))
                        .frame(width: 39, height: 25)
                        .accessibilityLabel(L("Year view unavailable"))
                }
                .padding(3)
                .background(Color(hex: 0x141418), in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, ScreenMetrics.safeArea.top + 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(range == 30 ? L("PAST 30 DAYS") : L("PAST 7 DAYS")) · \(Fmt.displayDate(days[0].start, format: "MMM d").uppercased()) – \(Fmt.displayDate(today.start, format: "MMM d").uppercased())")
                        .font(NBFont.dot(600, 11))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.4))
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("Rhythm")
                            .font(.custom("InterTight-Bold", size: 30))
                            .foregroundStyle(.white)
                        Text(L("columns are weekdays"))
                            .font(.custom("Jost-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    .padding(.bottom, 15)
                    weekdayHeader
                    if loading {
                        ProgressView()
                            .tint(NB.lime1)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 8)
                            .accessibilityLabel(L("Loading history"))
                    }
                    if range == 30 {
                        monthGrid
                    } else {
                        weekGrid
                    }
                    legend
                        .padding(.top, 17)
                    summary
                        .padding(.top, 20)
                    Text(L("TAP A DAY FOR ITS TIMELINE"))
                        .font(NBFont.dot(600, 9))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 25)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, ScreenMetrics.safeArea.bottom + 20)
            }
            .accessibilityIdentifier("RHYTHM_SCROLL")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon)
        .overlay {
            if let selected {
                dayDetail(selected)
                    .transition(.opacity)
            }
        }
    }

    private func rangeButton(_ value: Int) -> some View {
        Button {
            selected = nil
            range = value
        } label: {
            Text(value == 7 ? "7D" : "30D")
                .font(NBFont.dot(600, 10))
                .tracking(1)
                .foregroundStyle(range == value ? NB.carbon : .white.opacity(0.55))
                .frame(width: 39, height: 25)
                .background(range == value ? NB.lime1 : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("RHYTHM_\(value)D")
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                let date = range == 7 ? days[index].start
                    : days[0].adding(days: index - firstWeekday).start
                Text(Fmt.displayDate(date, format: "EEEEE").uppercased())
                    .font(NBFont.dot(600, 9))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 12)
    }

    private var monthGrid: some View {
        VStack(spacing: 8) {
            ForEach(0..<(calendarDays.count / 7), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        if let day = calendarDays[row * 7 + column] {
                            dayCell(day, height: 62, compact: true)
                        } else {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 80)
                        }
                    }
                }
            }
        }
    }

    private var weekGrid: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                dayCell(day, height: 300, compact: false)
            }
        }
    }

    private func dayCell(_ day: UserDay, height: CGFloat, compact: Bool) -> some View {
        let entries = events.filter { $0.day == day }
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { selected = day }
        } label: {
            VStack(spacing: 5) {
                Text(Fmt.displayDate(day.start, format: "d"))
                    .font(NBFont.dot(600, compact ? 9 : 11))
                    .foregroundStyle(day == today ? NB.lime1 : .white.opacity(0.55))
                RhythmBar(day: day, today: today, events: events, height: height,
                          width: compact ? 12 : 23)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height + (compact ? 18 : 26), alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("RHYTHM_DAY_\(day.key)")
        .accessibilityLabel("\(Fmt.displayDate(day.start, format: "EEE d MMM")), \(entries.count) \(L("events"))")
    }

    private var legend: some View {
        HStack(spacing: 13) {
            legendItem(L("SLEEP"), color: Color(hex: 0x7B83E8).opacity(0.6))
            legendItem(L("MEAL"), color: .white.opacity(0.72))
            legendItem(L("ACTIVITY"), color: NB.lime1)
            legendItem(L("STRESS"), color: NB.ember1)
        }
        .frame(maxWidth: .infinity)
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(NBFont.dot(600, 9))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var summary: some View {
        let recorded = metrics.filter { days.contains($0.day) }
        let nights = recorded.compactMap { $0.sleep?.totalMinutes }.filter { $0 > 0 }
        let steps = recorded.compactMap(\.steps)
        return HStack(alignment: .top, spacing: 0) {
            summaryValue(L("SLEEP AVG"),
                         nights.isEmpty ? Fmt.dash : Fmt.duration(nights.reduce(0, +) / nights.count))
            summaryValue(L("STEPS"),
                         steps.isEmpty ? Fmt.dash : steps.reduce(0, +).formatted())
            summaryValue(L("WORKOUTS"),
                         recorded.isEmpty && visibleEvents.isEmpty ? Fmt.dash
                             : String(visibleEvents.filter { $0.accent == .workout }.count))
        }
        .padding(.top, 15)
        .overlay(alignment: .top) { Color.white.opacity(0.08).frame(height: 1) }
    }

    private func summaryValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(NBFont.dot(600, 9))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.custom("InterTight-SemiBold", size: 16))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayDetail(_ day: UserDay) -> some View {
        let entries = events.filter { $0.day == day }
        return ZStack(alignment: .bottom) {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { selected = nil } }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(Fmt.displayDate(day.start, format: "EEE d MMM").uppercased())
                        .font(NBFont.dot(600, 13))
                        .foregroundStyle(NB.lime1)
                    Spacer()
                    Button(L("Close")) { withAnimation { selected = nil } }
                        .font(.custom("Jost-Medium", size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if entries.isEmpty {
                            Text(L("No events yet"))
                                .font(.custom("Jost-Regular", size: 15))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        ForEach(entries.sorted { $0.at < $1.at }) { entry in
                            Button {
                                selected = nil
                                onOpen(entry)
                            } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    Text(Fmt.clock(entry.at))
                                        .font(NBFont.dot(600, 12))
                                        .foregroundStyle(.white.opacity(0.6))
                                        .frame(width: 45, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.title)
                                            .font(.custom("InterTight-Medium", size: 15))
                                        if !entry.detail.isEmpty {
                                            Text(entry.detail)
                                                .font(.custom("Jost-Regular", size: 12))
                                                .foregroundStyle(.white.opacity(0.55))
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(.white)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(entry.accent == .weighIn)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
            .padding(20)
            .padding(.bottom, ScreenMetrics.safeArea.bottom)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x141418), in: UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("RHYTHM_DAY_DETAIL")
    }
}

private struct RhythmBar: View {
    let day: UserDay
    let today: UserDay
    let events: [HomeV2Model.TimelineItem]
    let height: CGFloat
    let width: CGFloat

    private func position(_ date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(day.start) / day.end.timeIntervalSince(day.start)) * height
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: 0x111116))
            ForEach(events.filter { event in
                event.accent == .sleep && event.at < day.end
                    && (event.endAt.map { $0 > day.start } ?? false)
            }) { entry in
                if let end = entry.endAt {
                    let top = max(0, position(entry.at))
                    let bottom = min(height, position(end))
                    Rectangle()
                        .fill(Color(hex: 0x7B83E8).opacity(0.46))
                        .frame(width: width - 2, height: max(0, bottom - top))
                        .offset(y: top)
                }
            }
            ForEach(events.filter {
                $0.day == day && [.meal, .wake, .workout, .activity, .stress].contains($0.accent)
            }) { entry in
                let marker: Color = switch entry.accent {
                case .meal, .wake: .white.opacity(0.72)
                case .workout, .activity: NB.lime1
                case .stress: NB.ember1
                default: .clear
                }
                RoundedRectangle(cornerRadius: 1)
                    .fill(marker)
                    .frame(width: width - 3,
                           height: entry.accent == .workout || entry.accent == .activity ? 5 : 2)
                    .offset(y: max(0, min(height - 5, position(entry.at))))
            }
            if day == today {
                Rectangle()
                    .fill(NB.lime1)
                    .frame(width: width + 4, height: 1)
                    .offset(y: max(0, min(height, position(VitalsClock.now))))
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(day == today ? NB.lime1.opacity(0.8) : .clear, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
