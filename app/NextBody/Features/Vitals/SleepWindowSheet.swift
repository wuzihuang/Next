import SwiftUI

/// #28 · the night's own start and end, and the way to say the band got them wrong.
///
/// The band is often right about how the night went and wrong about when it began: it
/// counts an hour of reading in bed as sleep, or calls a trip to the bathroom the end of
/// the night. This card prints the window every other number on the page is counted over,
/// and hands it back to the person who was there.
///
/// A correction is an override, never an edit of the band's record. The window the band
/// filed stays underneath it, printed here, and CLEAR gives it back.
struct SleepWindowCard: View {
    let night: SleepSummary
    var editable = true
    let edit: () -> Void

    var body: some View {
        CardBlock(title: L("SLEEP WINDOW"),
                  trailing: night.isCorrected ? L("CORRECTED") : nil,
                  trailingTint: night.isCorrected ? NB.lime1 : nil) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Self.clock(night.sleepStart))
                        .font(NBFont.dot(700, 24)).tracking(0.02 * 24)
                        .foregroundStyle(NB.text1)
                    Text("→").font(NBFont.ui(400, 14)).foregroundStyle(NB.text3Prod)
                    Text(Self.clock(night.wakeAt))
                        .font(NBFont.dot(700, 24)).tracking(0.02 * 24)
                        .foregroundStyle(NB.text1)
                    Spacer(minLength: 0)
                    if editable {
                        Button(L("CHANGE TIMES"), action: edit)
                            .font(NBFont.dot(600, 11)).tracking(0.2 * 11)
                            .foregroundStyle(NB.lime1)
                            .buttonStyle(.plain)
                    }
                }
                // Both windows are printed when they differ, because a corrected night is
                // not a measurement and must not read as one.
                Text(night.isCorrected
                     ? L("BAND RECORDED %@ → %@", Self.clock(night.bandStart), Self.clock(night.bandEnd))
                     : (editable ? L("FROM THE BAND · EDIT IF IT IS WRONG") : L("FROM THE BAND")))
                    .font(NBFont.ui(300, 12)).tracking(0.02 * 12)
                    .foregroundStyle(NB.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func clock(_ at: Date?) -> String {
        guard let at else { return Fmt.dash }
        return Fmt.clock(at)
    }
}

/// Two wheels and an explicit save. A drag is not a correction: nothing is written until
/// SAVE, which is the same rule the AI path gets from its confirmation.
struct SleepWindowSheet: View {
    let day: UserDay
    let night: SleepSummary?
    @EnvironmentObject private var data: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var start = Date()
    @State private var end = Date()
    @State private var saving = false
    @State private var failure: String?

    var body: some View {
        SheetFrame(title: L("Sleep times")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("The night filed under %@. Times are your own clock; a start after the end belongs to the evening before.", day.key))
                    .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                    .foregroundStyle(NB.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    wheel(L("FELL ASLEEP"), $start)
                    wheel(L("WOKE"), $end)
                }
                if let failure {
                    Text(failure)
                        .font(NBFont.ui(400, 12.5)).tracking(0.02 * 12.5)
                        .foregroundStyle(NB.ember1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if night?.isCorrected == true {
                    Button(L("Use the band's times")) { run { try await SleepCorrection.clear(day: day, into: data) } }
                        .font(NBFont.ui(400, 13)).foregroundStyle(NB.text3Prod)
                        .buttonStyle(.plain)
                        .disabled(saving)
                }
            }
        } footer: {
            LimePillButton(title: saving ? L("Saving…") : L("Save"), enabled: !saving) {
                run { try await SleepCorrection.save(day: day, start: Self.hhmm(start),
                                                     end: Self.hhmm(end), into: data) }
            }
        }
        .background(NB.carbon2)
        .onAppear {
            start = night?.sleepStart ?? day.start
            end = night?.wakeAt ?? day.start
        }
    }

    private func wheel(_ label: String, _ value: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(NBFont.ui(400, 11)).tracking(0.06 * 11)
                .foregroundStyle(NB.white.opacity(0.38))
            DatePicker("", selection: value, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .frame(maxWidth: .infinity)
        }
        .padding(10)
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous).stroke(NB.hairline, lineWidth: 1))
    }

    private func run(_ work: @escaping () async throws -> Void) {
        guard !saving else { return }
        saving = true
        failure = nil
        Task {
            do {
                try await work()
                saving = false
                dismiss()
            } catch {
                failure = SleepCorrection.message(SleepCorrection.code(error))
                saving = false
            }
        }
    }

    static func hhmm(_ at: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: at)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
