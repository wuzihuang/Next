import SwiftUI

/// Paper 12Y · 04 SWITCH. Times + rocker. First row has no top hairline.
/// Add an alarm has no rocker. Edit stays on this sheet.
struct AlarmsSheet: View {
    var onCount: (Int) -> Void = { _ in }

    @State private var alarms: [BandAlarm] = []
    @State private var didRead = false
    @State private var capacity: Int?
    @State private var draft: BandAlarm?
    @State private var time = Date()
    @State private var writing = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let draft {
                editor(draft)
            } else {
                list
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon4)
        .task { await reload() }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Alarms"))
                .font(NBFont.ui(500, 20)).tracking(0.01 * 20)
                .foregroundStyle(NB.text1)
            Text(L("This HOOP vibrates. It has no screen for a label."))
                .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                .foregroundStyle(NB.white.opacity(0.38))
                .padding(.top, 6)

            if !didRead {
                Text(L("ASKING THIS HOOP…"))
                    .font(NBFont.dot(600, 10)).tracking(0.16 * 10)
                    .foregroundStyle(NB.white.opacity(0.38))
                    .padding(.top, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(alarms.enumerated()), id: \.element.id) { index, alarm in
                        alarmRow(alarm, index: index)
                        if index < alarms.count - 1 {
                            Hairline()
                                .accessibilityIdentifier("alarms.hairline.\(index + 1)")
                        }
                    }
                    if !alarms.isEmpty || hoopIsFull {
                        Hairline()
                            .accessibilityIdentifier("alarms.hairline.add")
                    }
                    footerRow
                }
                .frame(width: NB.Layout.contentWidth)
                .cardSkin()
                .padding(.top, 16)
            }

            if let message {
                Text(message)
                    .font(NBFont.dot(600, 10)).tracking(0.12 * 10)
                    .foregroundStyle(NB.ember1)
                    .padding(.top, 12)
            }
            Spacer(minLength: 0)
        }
    }

    private var hoopIsFull: Bool {
        BandAlarmMath.isFull(alarms, ceiling: capacity ?? BandAlarm.demoCeiling)
    }

    private func alarmRow(_ alarm: BandAlarm, index: Int) -> some View {
        HStack(spacing: 12) {
            Button { openEditor(alarm) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(alarm.clock)
                        .font(NBFont.dot(700, 36))
                        .tracking(-0.03 * 36)
                        .foregroundStyle(alarm.on || !alarm.showsSwitch ? NB.text1 : NB.white.opacity(0.34))
                    Text(L(BandAlarmMath.phrase(alarm.repeatMask)))
                        .font(NBFont.dot(500, 11)).tracking(0.1 * 11)
                        .foregroundStyle(NB.white.opacity(0.38))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("alarms.row.\(index)")

            if alarm.showsSwitch {
                Toggle("", isOn: Binding(
                    get: { alarms.first(where: { $0.id == alarm.id })?.on ?? alarm.on },
                    set: { on in Task { await setOn(alarm, on) } }
                ))
                .labelsHidden()
                .tint(NB.lime1)
                .frame(width: 68)
                .disabled(writing)
                .accessibilityIdentifier("alarms.switch.\(alarm.id)")
            } else {
                Color.clear.frame(width: 68, height: 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private var footerRow: some View {
        if hoopIsFull {
            Text(L("This HOOP is full · %d / %d", alarms.count, capacity ?? BandAlarm.demoCeiling))
                .font(NBFont.ui(500, 14))
                .foregroundStyle(NB.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .accessibilityIdentifier("alarms.full")
        } else {
            Button { addAlarm() } label: {
                HStack {
                    Text(L("Add an alarm"))
                        .font(NBFont.ui(500, 15))
                        .foregroundStyle(NB.text1)
                    Spacer(minLength: 0)
                    Text(BandAlarmMath.countLabel(count: didRead ? alarms.count : nil,
                                                  didRead: didRead, capacity: capacity))
                        .font(NBFont.dot(600, 12))
                        .foregroundStyle(NB.white.opacity(0.38))
                    Color.clear.frame(width: 68, height: 1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("alarms.add")
        }
    }

    private func editor(_ alarm: BandAlarm) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(alarm.clock)
                .font(NBFont.dot(700, 44))
                .tracking(-0.03 * 44)
                .foregroundStyle(NB.text1)
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .frame(maxWidth: .infinity)
                .onChange(of: time) { _, value in
                    applyTime(value)
                }

            HStack(spacing: 6) {
                ForEach(BandAlarmMath.Weekday.allCases, id: \.self) { day in
                    let on = BandAlarmMath.has(alarm.repeatMask, day)
                    Button {
                        toggleDay(day)
                    } label: {
                        Text(day.pill)
                            .font(NBFont.dot(600, 12))
                            .foregroundStyle(on ? NB.lime1 : NB.text2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(NB.carbon4, in: Capsule())
                            .overlay(Capsule().stroke(on ? NB.lime1 : NB.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("alarms.day.\(day.short)")
                }
            }

            Text(L(BandAlarmMath.phrase(alarm.repeatMask)))
                .font(NBFont.dot(500, 11)).tracking(0.1 * 11)
                .foregroundStyle(NB.white.opacity(0.38))

            if let message {
                Text(message)
                    .font(NBFont.dot(600, 10)).tracking(0.12 * 10)
                    .foregroundStyle(NB.ember1)
            }

            Spacer(minLength: 0)

            Button { Task { await saveDraft() } } label: {
                Text(L("SAVE"))
                    .font(NBFont.ui(600, 13)).tracking(0.16 * 13)
                    .foregroundStyle(NB.carbon)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(NB.lime1, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(writing)
            .accessibilityIdentifier("alarms.save")

            HStack(spacing: 10) {
                Button { draft = nil } label: {
                    Text(L("DONE"))
                        .font(NBFont.ui(500, 12)).tracking(0.14 * 12)
                        .foregroundStyle(NB.text2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .overlay(Capsule().stroke(NB.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                if alarms.contains(where: { $0.id == alarm.id }) {
                    Button { Task { await remove(alarm) } } label: {
                        Text(L("DELETE"))
                            .font(NBFont.ui(500, 12)).tracking(0.14 * 12)
                            .foregroundStyle(NB.alert2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .overlay(Capsule().stroke(NB.alert2.opacity(0.6), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(writing)
                    .accessibilityIdentifier("alarms.delete")
                }
            }
        }
    }

    private func addAlarm() {
        guard let id = BandAlarmMath.nextID(in: alarms) else {
            capacity = BandAlarm.demoCeiling
            return
        }
        var next = BandAlarm.emptyRead()
        next.id = id
        next.hour = 7
        next.minute = 30
        next.on = true
        next.repeatMask = BandAlarmMath.weekdaysMask
        next.scene = BandAlarm.silentScene
        openEditor(next)
    }

    private func openEditor(_ alarm: BandAlarm) {
        message = nil
        draft = alarm
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        parts.hour = alarm.hour
        parts.minute = alarm.minute
        time = Calendar.current.date(from: parts) ?? Date()
    }

    private func applyTime(_ value: Date) {
        guard var draft else { return }
        draft.hour = Calendar.current.component(.hour, from: value)
        draft.minute = Calendar.current.component(.minute, from: value)
        self.draft = draft
    }

    private func toggleDay(_ day: BandAlarmMath.Weekday) {
        guard var draft else { return }
        draft.repeatMask = BandAlarmMath.toggling(draft.repeatMask, day)
        self.draft = draft
    }

    private func reload() async {
        do {
            alarms = try await Band.live.readAlarms()
            didRead = true
            if BandAlarmMath.isFull(alarms) { capacity = BandAlarm.demoCeiling }
            onCount(alarms.count)
            message = nil
        } catch {
            didRead = true
            message = hoopMessage(error)
        }
    }

    private func setOn(_ alarm: BandAlarm, _ on: Bool) async {
        var next = alarm
        next.on = on
        await commit { try await Band.live.writeAlarm(next) }
    }

    private func saveDraft() async {
        guard let draft else { return }
        await commit { try await Band.live.writeAlarm(draft) }
        if message == nil { self.draft = nil }
    }

    private func remove(_ alarm: BandAlarm) async {
        await commit { try await Band.live.deleteAlarm(alarm) }
        if message == nil { draft = nil }
    }

    private func commit(_ body: () async throws -> [BandAlarm]) async {
        let snapshot = alarms
        let adding = draft.map { draft in snapshot.contains(where: { $0.id == draft.id }) == false } ?? false
        writing = true
        defer { writing = false }
        do {
            alarms = try await body()
            didRead = true
            if BandAlarmMath.isFull(alarms) { capacity = BandAlarm.demoCeiling }
            onCount(alarms.count)
            message = nil
        } catch {
            alarms = snapshot
            if adding, let band = error as? BandError, case .rejected = band, !snapshot.isEmpty {
                capacity = snapshot.count
                draft = nil
            }
            message = hoopMessage(error)
        }
    }

    private func hoopMessage(_ error: Error) -> String {
        if let band = error as? BandError, case .busy = band { return L("DEVICE BUSY") }
        return error.localizedDescription
    }
}
