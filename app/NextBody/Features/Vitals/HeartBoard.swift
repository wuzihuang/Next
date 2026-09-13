import SwiftUI

/// HEART second level after the hero. The page stays a heart page: the lead envelope is
/// the pulse, HRV and overnight SpO2 share the same clock as companions. Empty slots stay
/// empty — SpO2 has nothing to draw in daylight.
struct HeartBoard: View {
    let range: RollingPills
    let window: VitalsWindow
    let ticks: [VitalSample]
    let oxygen: [OvernightOxygenPoint]
    let readout: VitalsReadout
    let slotMinutes: Double
    let dial: VitalsDial.Model?
    /// False on the rolling windows, where the trend hero above already drew the pulse a
    /// night at a time and a second envelope of the same days would be the page repeating
    /// itself.
    var showsLead = true

    var body: some View {
        if showsLead {
            CardBlock(title: L("HEART RATE"), trailing: readout.chartNote) {
                lead
                VitalsAxis(labels: window.labels, highlightsLast: window.endsNow, tint: NB.lime1)
                    .padding(.trailing, VitalsScaleRail.gutter)
                VitalsChartLegend(
                    items: [
                        .init(text: range == .day
                              ? L("EVERY %d MIN · MEASURED", Int(DetailWindow(.heart, .day).slotMinutes))
                              : L("EVERY DAY · MEASURED"),
                              tint: NB.lime1, stops: dial?.legendStops)
                    ] + (readout.referenceLabel.map {
                        [VitalsChartLegend.Item(text: $0, tint: NB.lime1, isArea: true)]
                    } ?? []),
                    trailing: ticks.compactMap { $0.hr }.max().map { L("MAX %d", $0) },
                    trailingTint: NB.lime1)
            }
        }

        CardBlock(title: L("ON THE SAME CLOCK"), trailing: L("COMPANIONS SHARE THIS CLOCK")) {
            companionHRV
            companionOxygen
            VitalsAxis(labels: window.labels, highlightsLast: window.endsNow, tint: VitalsMetric.hrv.tint)
                .padding(.trailing, VitalsScaleRail.gutter)
            VitalsChartLegend(
                items: [
                    .init(text: L("WINDOW RMSSD · SPARSER THAN HEART"), tint: VitalsMetric.hrv.tint),
                    .init(text: L("NIGHT WINDOW ONLY · DAY IS EMPTY"), tint: NB.optimal2)
                ],
                trailing: nil)
        }
    }

    @ViewBuilder
    private var lead: some View {
        if ticks.contains(where: { $0.hr != nil }) {
            VitalsTrace(samples: ticks, value: { $0.hr.map(Double.init) },
                        window: window, low: 40, high: 160, tint: NB.lime1,
                        zones: dial,
                        referenceBand: readout.referenceBand,
                        referenceSpan: readout.referenceSpan,
                        slotMinutes: slotMinutes,
                        unit: "BPM")
        } else {
            VitalsChartEmpty(line: range == .day
                             ? L("NO HEART TICKS IN 24H")
                             : L("NO HEART TICKS IN THIS WINDOW"),
                             sub: L("THE NEXT SYNC DRAWS THE LINE"))
        }
    }

    @ViewBuilder
    private var companionHRV: some View {
        if ticks.contains(where: { $0.hrv != nil }) {
            VitalsTrace(samples: ticks, value: { $0.hrv },
                        window: window, low: 0, high: 90, tint: VitalsMetric.hrv.tint,
                        height: 112,
                        slotMinutes: slotMinutes,
                        unit: "MS")
            companionNote(L("HRV · RMSSD"),
                          trailing: ticks.compactMap(\.hrv).max().map { L("NIGHT HIGH %d", Int($0.rounded())) },
                          tint: VitalsMetric.hrv.tint)
        } else {
            VitalsChartEmpty(line: L("NO RMSSD IN THIS WINDOW"),
                             sub: L("THE BAND MEASURES IT EVERY TEN MINUTES"))
        }
    }

    @ViewBuilder
    private var companionOxygen: some View {
        if !oxygen.isEmpty {
            // The same line the sleep page draws: overnight oxygen is one reading every few
            // minutes, and an occupancy capsule per slot reads as a fence, not a night.
            VitalsLineTrace(points: oxygen.map { (ts: $0.ts, value: Double($0.percent)) },
                            window: window, low: 85, high: 100, tint: NB.optimal2,
                            marksMaximum: false,
                            height: 112,
                            unit: "%")
            companionNote(L("OVERNIGHT SPO2"),
                          trailing: oxygen.map(\.percent).min().map { L("MIN %d", $0) },
                          tint: NB.optimal2)
        } else {
            VitalsChartEmpty(line: L("NO OVERNIGHT OXYGEN"),
                             sub: L("AUTO NIGHT MEASUREMENT WAS OFF OR EMPTY"))
        }
    }

    private func companionNote(_ title: String, trailing: String?, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(NBFont.ui(500, 10)).tracking(0.12 * 10)
                .foregroundStyle(NB.white.opacity(0.45))
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(NBFont.ui(500, 10))
                    .foregroundStyle(tint)
            }
        }
        .padding(.top, 4)
    }
}
