import ActivityKit
import SwiftUI
import WidgetKit

/// 14 · LIVE SESSION · the session on the Dynamic Island and the Lock Screen.
///
/// The takeover is the session when you are looking at the phone. This is the session when
/// you are not: the same three numbers, in the same lime on the same carbon, in the space
/// the system gives. Nothing here polls or measures — the app pushes a `ContentState` when
/// the wrist reports, and the elapsed clock counts up on the island's own time, so the
/// seconds keep moving between updates without the phone waking for them.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionAttributes.self) { context in
            LockScreenSession(attributes: context.attributes,
                              state: context.state, stale: context.isStale)
                .activityBackgroundTint(Island.carbon)
                .activitySystemActionForegroundColor(Island.lime)
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            let tone = Island.tone(effort: state.effort)

            return DynamicIsland {
                // Expanded · the long press. Four regions, and the clock across the foot:
                // the two numbers flank the sport, the way the takeover stacks them.
                DynamicIslandExpandedRegion(.leading) {
                    IslandStat(value: heartText(state, stale: stale), unit: "BPM",
                               tint: state.live && !stale ? tone : Island.white.opacity(0.32))
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IslandStat(value: String(state.kcal), unit: "KCAL",
                               tint: stale ? Island.white.opacity(0.32) : Island.white.opacity(0.86))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 6) {
                        Circle().fill(stale ? Island.ember : tone).frame(width: 5, height: 5)
                        Text(context.attributes.sport.uppercased())
                            .font(Island.dot(600, 11)).tracking(0.14 * 11)
                            .foregroundStyle(Island.white.opacity(0.78))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        Text(timerInterval: Island.elapsedRange(from: state.startedAt),
                             countsDown: false, showsHours: false)
                            .font(Island.dot(700, 34)).tracking(0.02 * 34)
                            .foregroundStyle(Island.white)
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                        Text(footLine(state, stale: stale))
                            .font(Island.dot(600, 9.5)).tracking(0.16 * 9.5)
                            .foregroundStyle(stale ? Island.ember : Island.white.opacity(0.42))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Circle().fill(stale ? Island.ember : tone).frame(width: 5, height: 5)
                    Text(heartText(state, stale: stale))
                        .font(Island.dot(700, 14))
                        .foregroundStyle(state.live && !stale ? tone : Island.white.opacity(0.42))
                        .monospacedDigit()
                }
            } compactTrailing: {
                Text(timerInterval: Island.elapsedRange(from: state.startedAt),
                     countsDown: false, showsHours: false)
                    .font(Island.dot(600, 13))
                    .foregroundStyle(Island.white.opacity(0.72))
                    .monospacedDigit()
                    // The island gives the trailing slot what it asks for; without a width
                    // the digits shuffle the whole capsule every time a minute rolls over.
                    .frame(width: 44)
            } minimal: {
                // Sharing the island with something else: the beat, and nothing else.
                Text(heartText(state, stale: stale))
                    .font(Island.dot(700, 13))
                    .foregroundStyle(state.live && !stale ? tone : Island.white.opacity(0.42))
                    .monospacedDigit()
            }
            // Tapping anything here opens the app, which is already showing the session.
            .widgetURL(URL(string: "nextbody://session"))
            .keylineTint(tone)
        }
    }

    private func heartText(_ s: SessionAttributes.ContentState, stale: Bool) -> String {
        guard !stale, let hr = s.heartRate else { return "——" }
        return String(hr)
    }

    private func footLine(_ s: SessionAttributes.ContentState, stale: Bool) -> String {
        if stale { return "NO SIGNAL FROM THE PHONE" }
        if let note = s.note { return note }
        return s.live ? "HEART RATE FROM THE WRIST" : "TIMING · THE WRIST IS NOT BEING READ"
    }
}

/// One number over its label, in a fixed column so the digits changing width do not move it.
private struct IslandStat: View {
    let value: String
    let unit: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(Island.brand(22))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                Text(unit)
                    .font(Island.dot(600, 9))
                    .foregroundStyle(Island.white.opacity(0.34))
            }
            .lineLimit(1)
        }
    }
}

/// The Lock Screen banner — the takeover's foot, laid out flat: what is running, then the
/// three numbers in a row. No globe: it would be a picture at 40 pt, and this surface is
/// read at a glance from a table.
private struct LockScreenSession: View {
    let attributes: SessionAttributes
    let state: SessionAttributes.ContentState
    let stale: Bool

    private var tone: Color { Island.tone(effort: state.effort) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle().fill(stale ? Island.ember : tone).frame(width: 6, height: 6)
                Text(stale ? "PAUSED" : "LIVE")
                    .font(Island.dot(600, 11)).tracking(0.24 * 11)
                    .foregroundStyle(stale ? Island.ember : tone)
                Text("·")
                    .font(Island.dot(600, 11))
                    .foregroundStyle(Island.white.opacity(0.28))
                Text(attributes.sport.uppercased())
                    .font(Island.dot(600, 11)).tracking(0.16 * 11)
                    .foregroundStyle(Island.white.opacity(0.78))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("HOOP")
                    .font(Island.dot(600, 10)).tracking(0.2 * 10)
                    .foregroundStyle(Island.white.opacity(0.34))
            }

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                column("ELAPSED") {
                    Text(timerInterval: Island.elapsedRange(from: state.startedAt),
                         countsDown: false, showsHours: false)
                        .font(Island.dot(700, 30)).tracking(0.02 * 30)
                        .foregroundStyle(Island.white)
                        .monospacedDigit()
                }

                column("HEART RATE") {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(stale ? "——" : state.heartRate.map(String.init) ?? "——")
                            .font(Island.brand(28))
                            .foregroundStyle(state.live && !stale ? tone : Island.white.opacity(0.32))
                            .monospacedDigit()
                        Text("BPM")
                            .font(Island.dot(600, 9))
                            .foregroundStyle(Island.white.opacity(0.30))
                    }
                }

                column("BURNED") {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(state.kcal))
                            .font(Island.brand(28))
                            .foregroundStyle(Island.white.opacity(0.86))
                            .monospacedDigit()
                        Text("KCAL")
                            .font(Island.dot(600, 9))
                            .foregroundStyle(Island.white.opacity(0.30))
                    }
                }
            }

            if let note = state.note ?? (stale ? "NO SIGNAL FROM THE PHONE" : nil) {
                Text(note)
                    .font(Island.dot(600, 9.5)).tracking(0.16 * 9.5)
                    .foregroundStyle(stale ? Island.ember : Island.white.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column<V: View>(_ label: String, @ViewBuilder value: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            value()
            Text(label)
                .font(Island.dot(600, 9)).tracking(0.18 * 9)
                .foregroundStyle(Island.white.opacity(0.34))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
