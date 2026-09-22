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
                  trailing: night.isUserReported ? L("ADDED BY YOU") : night.isCorrected ? L("CORRECTED") : nil,
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
                Text(night.isUserReported
                     ? L("TIMES REPORTED BY YOU")
                     : night.isCorrected
                     ? L("BAND RECORDED %@ → %@", Self.clock(night.bandStart), Self.clock(night.bandEnd))
                     : (editable ? L("FROM THE BAND · EDIT IF IT IS WRONG") : L("FROM THE BAND")))
                    .font(NBFont.ui(300, 12)).tracking(0.02 * 12)
                    .foregroundStyle(NB.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
                if night.unstagedMinutes > 0 {
                    Text(L("%@ WITHOUT STAGE READINGS", Fmt.duration(night.unstagedMinutes)))
                        .font(NBFont.ui(300, 12)).foregroundStyle(NB.text3Prod)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    static func clock(_ at: Date?) -> String {
        guard let at else { return Fmt.dash }
        return Fmt.clock(at)
    }
}

/// The two wheels themselves. A night is corrected through one control wherever the
/// correction started — the sleep page's own sheet, or the confirm the AI puts up when it
/// has guessed the night by ear — so the same drag means the same thing in both.
///
/// ⚠️ One wheel per row, full width. A `.wheel` DatePicker refuses to be narrower than its
/// three columns (hour · minute · AM/PM) and simply overflows the container it is given:
/// side by side, the two of them ran off both edges of the sheet. The alarm sheet has been
/// giving a single wheel the whole width since F1 for the same reason.
struct SleepWindowWheels: View {
    @Binding var start: Date
    @Binding var end: Date
    /// A dialog has less room than a sheet, and the wheel is legible well below its
    /// natural 216pt — fewer rows above and below the one that is selected.
    var wheelHeight: CGFloat = 150

    var body: some View {
        VStack(spacing: 10) {
            wheel(L("FELL ASLEEP"), $start)
            wheel(L("WOKE"), $end)
        }
    }

    private func wheel(_ label: String, _ value: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(NBFont.ui(400, 11)).tracking(0.06 * 11)
                .foregroundStyle(NB.white.opacity(0.38))
            DatePicker("", selection: value, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .frame(maxWidth: .infinity)
                .frame(height: wheelHeight)
                // A shortened wheel is cut, not shrunk, so the first row above and below
                // the selection ends up sliced through the middle of its digits. Fading
                // the two edges is what the wheel does on its own at full height.
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                             .init(color: .black, location: 0.22),
                                             .init(color: .black, location: 0.78),
                                             .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(NB.carbon4, in: RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NB.R.chip, style: .continuous).stroke(NB.hairline, lineWidth: 1))
    }

    /// `HH:MM` on the wearer's own clock — the only shape `correct_sleep_window` accepts.
    static func hhmm(_ at: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: at)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// A wheel has to stand on some date; only its hour and minute are ever read back.
    static func date(_ hhmm: String?, fallback: Date = Date()) -> Date {
        let parts = (hhmm ?? "").split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m),
              let at = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: fallback)
        else { return fallback }
        return at
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
    @State private var savedPending = false
    @State private var failure: String?

    var body: some View {
        SheetFrame(title: night == nil ? L("Add sleep") : L("Sleep times")) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L("The night filed under %@. Times are your own clock; a start after the end belongs to the evening before.", day.key))
                    .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                    .foregroundStyle(NB.white.opacity(0.38))
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("Available measurements are filled from these times. Missing sleep stages and HRV remain unmeasured."))
                    .font(NBFont.ui(300, 12.5)).foregroundStyle(NB.text3Prod)
                    .fixedSize(horizontal: false, vertical: true)
                SleepWindowWheels(start: $start, end: $end)
                    .disabled(saving || savedPending)
                if let failure {
                    Text(failure)
                        .font(NBFont.ui(400, 12.5)).tracking(0.02 * 12.5)
                        .foregroundStyle(savedPending ? NB.text3Prod : NB.ember1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if night?.isCorrected == true, night?.isUserReported != true,
                   night?.bandStart != nil, night?.bandEnd != nil {
                    Button(L("Use the band's times")) { run { try await SleepCorrection.clear(day: day, into: data) } }
                        .font(NBFont.ui(400, 13)).foregroundStyle(NB.text3Prod)
                        .buttonStyle(.plain)
                        .disabled(saving || savedPending)
                }
            }
        } footer: {
            LimePillButton(title: savedPending ? L("Done") : saving ? L("Saving…") : L("Save"), enabled: !saving) {
                if savedPending { dismiss(); return }
                run {
                    if night == nil {
                        return try await SleepCorrection.create(day: day, start: SleepWindowWheels.hhmm(start),
                                                         end: SleepWindowWheels.hhmm(end), into: data)
                    } else {
                        return try await SleepCorrection.save(day: day, start: SleepWindowWheels.hhmm(start),
                                                       end: SleepWindowWheels.hhmm(end), into: data)
                    }
                }
            }
        }
        .background(NB.carbon2)
        .onAppear {
            start = night?.sleepStart ?? SleepWindowWheels.date("23:00", fallback: day.start)
            end = night?.wakeAt ?? SleepWindowWheels.date("07:00", fallback: day.start)
        }
    }

    private func run(_ work: @escaping () async throws -> Bool) {
        guard !saving else { return }
        saving = true
        failure = nil
        Task {
            do {
                let settled = try await work()
                saving = false
                if settled {
                    dismiss()
                } else {
                    savedPending = true
                    failure = L("Saved. Your metrics will refresh after the next sync.")
                }
            } catch {
                failure = SleepCorrection.message(SleepCorrection.code(error))
                saving = false
            }
        }
    }
}
