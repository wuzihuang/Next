import SwiftUI

/// The same saved record is shown immediately after stopping and from Training history.
struct SportRecapView: View {
    let recap: SportSessionRecap
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var data: DataStore
    @ObservedObject private var records = SportRecapStore.shared

    private var contributions: [(day: UserDay, value: TrainingSessionContribution)] {
        var found: [UserDay: TrainingSessionContribution] = [:]
        for row in data.history + [data.today] {
            if let contribution = row.trainingSettlement?.session(recap.sessionID, on: row.day) {
                found[row.day] = contribution
            }
        }
        return found.map { (day: $0.key, value: $0.value) }.sorted { $0.day < $1.day }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(recap.title).font(NBFont.ui(600, 24)).foregroundStyle(NB.text1)
                    Text("\(Fmt.clock(recap.startedAt)) → \(Fmt.clock(recap.endedAt)) · \(Fmt.duration(recap.seconds / 60))")
                        .font(NBFont.ui(400, 12)).foregroundStyle(NB.text3Prod)
                    HStack {
                        stat("AVG HR", recap.avgHR.map(String.init) ?? Fmt.dash)
                        Spacer()
                        stat("PEAK", recap.peakHR.map(String.init) ?? Fmt.dash)
                        Spacer()
                        stat(recap.caloriesEstimated ? "KCAL EST" : "ACTIVE KCAL",
                             recap.hasEnergy ? "\(recap.caloriesEstimated ? "≈" : "")\(Int(recap.kcal.rounded()))" : Fmt.dash)
                    }
                    CardBlock(title: L("HEART RATE"), trailing: "BPM") {
                        SportRecapCurve(recap: recap).frame(height: 140)
                        HStack {
                            Text(Fmt.clock(recap.startedAt))
                            Spacer()
                            Text(Fmt.clock(recap.endedAt))
                        }.font(NBFont.ui(400, 10)).foregroundStyle(NB.text3Prod)
                        Text(L("Gaps have no heart-rate observations."))
                            .font(NBFont.ui(400, 11)).foregroundStyle(NB.text3Prod)
                    }
                    CardBlock(title: L("TIME IN EACH ZONE"), trailing: "") {
                        ForEach(0..<5, id: \.self) { index in
                            let minutes = recap.zoneMinutes.indices.contains(index) ? recap.zoneMinutes[index] : 0
                            let observed = recap.observedSeconds ?? recap.zoneMinutes.reduce(0, +) * 60
                            let share = observed > 0 ? minutes * 60 / observed : 0
                            ZoneBar(zone: "Z\(index + 1)", fill: share,
                                tint: index < 3 ? NB.lime1 : NB.ember1,
                                value: recap.hasZones ? String(format: "%.1f MIN · %.0f%%", minutes, share * 100) : Fmt.dash)
                        }
                        Text(L(recap.restHR == nil
                            ? "Estimated maximum HR: Z1 50–60%, Z2 60–70%, Z3 70–80%, Z4 80–90%, Z5 ≥90%."
                            : "Heart-rate reserve: Z1 30–40%, Z2 40–55%, Z3 55–70%, Z4 70–85%, Z5 ≥85%."))
                            .font(NBFont.ui(400, 11)).foregroundStyle(NB.text3Prod)
                        Text(L("Shares use observed time. Below Z1 is excluded; gaps add no time."))
                            .font(NBFont.ui(400, 11)).foregroundStyle(NB.text3Prod)
                    }
                    Text(L(recap.conclusion)).font(NBFont.ui(500, 14)).foregroundStyle(NB.text1)
                    Text(L("Aerobic: Z1–3. Anaerobic: Z4–5. This describes recorded intensity."))
                        .font(NBFont.ui(400, 11)).foregroundStyle(NB.text3Prod)
                    CardBlock(title: L("LOAD"), trailing: "") {
                        if !contributions.isEmpty {
                            ForEach(contributions, id: \.day) { row in
                                HStack {
                                    Text(row.day.date.formatted(date: .abbreviated, time: .omitted))
                                    Spacer()
                                    Text(row.value.deltaText).foregroundStyle(NB.lime1)
                                }
                                Text(L(row.value.rawLoad == 0
                                    ? "No measurable training contribution in the observed intervals."
                                    : "Included in the day's settled training load."))
                                    .font(NBFont.ui(400, 12)).foregroundStyle(NB.text3Prod)
                            }
                        } else {
                            Text(L(recap.hasZones || recap.hasEnergy
                                ? "Session recorded. Its load will appear after sync."
                                : "No continuous sensor evidence. This session has no measured load."))
                                .font(NBFont.ui(400, 12)).foregroundStyle(NB.text3Prod)
                        }
                        SportPublicationStatus()
                    }
                }.padding(16)
            }
            .background(NB.panelInk)
            .navigationTitle(L("SESSION"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L("DONE")) { dismiss() } } }
        }
        .task {
            guard !Band.allowsSeed else { return }
            // Refresh every day touched by a workout, including a midnight crossing.
            await Repository.shared.load(days: 2, endingAt: UserDay.containing(recap.endedAt), into: data)
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("sport.recap")
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L(title)).font(NBFont.ui(400, 10)).foregroundStyle(NB.text3Prod)
            Text(value).font(NBFont.dot(700, 24)).foregroundStyle(NB.lime1)
        }
    }
}

struct SportPublicationStatus: View {
    @ObservedObject private var records = SportRecapStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if records.updatingTraining {
                Text(L("UPDATING TRAINING"))
            }
            if let error = records.errorLine ?? records.trainingError {
                Text(error).foregroundStyle(NB.ember1)
                Button(L("RETRY")) { Task { await records.retry() } }
                    .disabled(records.updatingTraining)
            } else if records.pendingCount > 0 {
                Text(L("Session saved on this phone. Waiting to upload."))
            }
        }.font(NBFont.ui(400, 12)).foregroundStyle(NB.text3Prod)
    }
}

private struct SportRecapCurve: View {
    let recap: SportSessionRecap
    var body: some View {
        if let points = recap.curvePoints, !points.isEmpty {
            Canvas { context, size in
                let low = Double(max(0, (points.map(\.bpm).min() ?? 50) - 10))
                let high = Double((points.map(\.bpm).max() ?? 150) + 10)
                let duration = max(1, recap.endedAt.timeIntervalSince(recap.startedAt))
                var previous: SportRecapMath.Beat?
                for beat in points {
                    let point = CGPoint(x: min(1, max(0, beat.at.timeIntervalSince(recap.startedAt) / duration)) * size.width,
                        y: (1 - (Double(beat.bpm) - low) / (high - low)) * size.height)
                    if let last = previous, last.segment == beat.segment {
                        var line = Path()
                        line.move(to: CGPoint(x: min(1, max(0, last.at.timeIntervalSince(recap.startedAt) / duration)) * size.width,
                            y: (1 - (Double(last.bpm) - low) / (high - low)) * size.height))
                        line.addLine(to: point)
                        context.stroke(line, with: .color(NB.lime1), lineWidth: 2)
                    }
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)), with: .color(NB.lime1))
                    previous = beat
                }
            }
            .accessibilityLabel(L("HEART RATE"))
        } else {
            VStack(spacing: 10) {
                Text(Fmt.dash).font(NBFont.dot(700, 24))
                Text(L("No heart-rate record." )).font(NBFont.ui(400, 12))
            }.foregroundStyle(NB.text3Prod).frame(maxWidth: .infinity)
        }
    }
}
