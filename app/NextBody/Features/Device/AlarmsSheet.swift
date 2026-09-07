import SwiftUI

/// Paper 12Y · 04 SWITCH (KUV-0 list, L0H-0 edit).
/// Full-width row layout inside the DEVICE sheet gutter (`DeviceSheet`). No outer card container.
/// Times + custom 68x40 mechanical rocker. First row has no top hairline.
/// Adding is one capsule key: filled lime on an empty HOOP, outlined under a list.
/// Capacity is never shown as `2 / ?` — only a real refusal prints both numbers.
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
                SheetHeader(
                    eyebrow: L("CLOCK"),
                    title: L("Alarms"),
                    subtitle: L("This HOOP has no screen. An alarm is a buzz on your wrist.")
                )
                if didRead, alarms.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
        }
        .padding(.horizontal, DeviceSheet.gutter)
        .padding(.top, DeviceSheet.top)
        .padding(.bottom, DeviceSheet.bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NB.carbon2)
        .task {
            await reload()
            #if DEBUG
            if DebugEdge.on("alarmedit") { addAlarm() }
            #endif
        }
    }

    /// No alarms on this HOOP. The header already said what an alarm is; the face is
    /// one word and one key — nothing to read, nothing to count.
    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Text(L("NO ALARMS YET"))
                .font(NBFont.dot(700, 11))
                .tracking(0.24 * 11)
                .foregroundStyle(NB.white.opacity(0.38))

            addKey(filled: true)
                .padding(.top, 22)

            errorLine

            Spacer(minLength: 0)
        }
        // The sheet sits at a fixed 0.78 detent, so the key really does land in the
        // middle of the face. Without maxHeight the two Spacers collapse to nothing.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !didRead {
                Text(L("ASKING THIS HOOP…"))
                    .font(NBFont.dot(600, 10))
                    .tracking(0.16 * 10)
                    .foregroundStyle(NB.white.opacity(0.38))
                    .padding(.top, 24)
                errorLine
                Spacer(minLength: 0)
            } else {
                // A real `List` purely for the mechanic every iPhone owner already knows:
                // swipe a clock left, get a red 删除. Rolling our own drag would be a
                // worse copy of it. The chrome is stripped back to the SWITCH face.
                List {
                    ForEach(Array(alarms.enumerated()), id: \.element.id) { index, alarm in
                        alarmRow(alarm, index: index)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparatorTint(NB.hairline)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                            .alignmentGuide(.listRowSeparatorTrailing) { $0.width }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await remove(alarm) }
                                } label: {
                                    Label(L("DELETE"), systemImage: "trash")
                                }
                                // The app tint is lime, which paints even a destructive
                                // role the same colour as ON. Say red out loud.
                                .tint(NB.alert2)
                                .accessibilityIdentifier("alarms.swipeDelete.\(alarm.id)")
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
                .padding(.top, 8)

                errorLine

                // The detent is fixed, so the key belongs on the floor of the sheet
                // rather than floating a hairline under the last clock.
                if hoopIsFull {
                    fullLine.padding(.top, 22)
                } else {
                    addKey(filled: false).padding(.top, 22)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The only way to add. No `2 / ?` — capacity is not a number the wearer asked for.
    private func addKey(filled: Bool) -> some View {
        HoopKey(title: L("Add an alarm"), skin: filled ? .lime : .outline) { addAlarm() }
            .accessibilityIdentifier("alarms.add")
    }

    /// Only when the band actually refused. Both numbers are real by then.
    private var fullLine: some View {
        SheetNote(text: L("This HOOP is full · %d / %d", alarms.count, capacity ?? BandAlarm.demoCeiling))
            .accessibilityIdentifier("alarms.full")
    }

    @ViewBuilder
    private var errorLine: some View {
        if let message {
            SheetNote(text: message)
                .padding(.top, 14)
        }
    }

    private var hoopIsFull: Bool {
        BandAlarmMath.isFull(alarms, ceiling: capacity ?? BandAlarm.demoCeiling)
    }

    private func alarmRow(_ alarm: BandAlarm, index: Int) -> some View {
        HStack(spacing: 12) {
            Button { openEditor(alarm) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(alarm.clock)
                        .font(NBFont.dot(700, 28))
                        .tracking(-0.02 * 28)
                        .foregroundStyle(alarm.on || !alarm.showsSwitch ? NB.text1 : NB.white.opacity(0.40))
                    Text(L(BandAlarmMath.phrase(alarm.repeatMask)))
                        .font(NBFont.dot(500, 10))
                        .tracking(0.14 * 10)
                        .foregroundStyle(alarm.on || !alarm.showsSwitch ? NB.white.opacity(0.42) : NB.white.opacity(0.24))
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
                .toggleStyle(HoopSwitchStyle())
                .disabled(writing)
                .accessibilityIdentifier("alarms.switch.\(alarm.id)")
            } else {
                Color.clear.frame(width: 68, height: 40)
            }
        }
        .padding(.vertical, DeviceSheet.rowInset)
    }

    /// One way out that writes (SAVE) and one that does not (Cancel, in the corner where
    /// iOS always puts it). The old pair said SAVE and DONE, which read as two ways to agree.
    private func editor(_ alarm: BandAlarm) -> some View {
        let isNew = !alarms.contains(where: { $0.id == alarm.id })
        return VStack(alignment: .leading, spacing: 16) {
            SheetHeader(
                eyebrow: isNew ? L("NEW ALARM") : L("EDIT ALARM"),
                title: alarm.clock,
                subtitle: L("Vibrate only. Scene stays 0.")
            ) {
                Button { draft = nil } label: {
                    Text(L("Cancel"))
                        .font(NBFont.ui(500, 14))
                        .foregroundStyle(NB.text2)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("alarms.cancel")
            }

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
                            .background(NB.carbon2, in: Capsule())
                            .overlay(Capsule().stroke(on ? NB.lime1 : NB.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("alarms.day.\(day.short)")
                }
            }

            Text(L(BandAlarmMath.phrase(alarm.repeatMask)))
                .font(NBFont.dot(500, 11))
                .tracking(0.1 * 11)
                .foregroundStyle(NB.white.opacity(0.38))

            if let message {
                SheetNote(text: message)
            }

            Spacer(minLength: 0)

            HoopKey(title: L("SAVE"), enabled: !writing) { Task { await saveDraft() } }
                .accessibilityIdentifier("alarms.save")

            // Same destination as the swipe, kept here because an alarm you opened to
            // change is often one you meant to be rid of. Plain text, not a second plate.
            if !isNew {
                Button { Task { await remove(alarm) } } label: {
                    Text(L("Delete alarm"))
                        .font(NBFont.ui(500, 14))
                        .foregroundStyle(NB.alert2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .disabled(writing)
                .accessibilityIdentifier("alarms.delete")
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
            // ADR 0018 · the next turn cites these without a second BLE read.
            PhoneToolRunner.shared.remember(alarms)
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

/// Paper 12Y · 04 SWITCH bespoke 68x40 rocker.
/// Lime fill with carbon-4 thumb when ON; translucent white with light thumb when OFF.
struct HoopSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? NB.lime1 : Color.white.opacity(0.133))
                    .frame(width: 68, height: 40)
                Circle()
                    .fill(configuration.isOn ? NB.carbon4 : Color.white.opacity(0.60))
                    .frame(width: 32, height: 32)
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(configuration)
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isOn)
    }
}
