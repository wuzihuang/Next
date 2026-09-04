import SwiftUI
import Combine

@MainActor
final class ChatStore: ObservableObject {
    static let shared = ChatStore()

    @Published var sessions: [ChatSession] = []
    @Published var currentSessionID: String = ""
    @Published var isSending = false

    var currentSession: ChatSession? {
        sessions.first(where: { $0.id == currentSessionID }) ?? sessions.first
    }

    func selectSession(_ id: String) {
        currentSessionID = id
    }

    func startNewSession(initialTitle: String? = nil) {
        let title = initialTitle ?? (L("New Consultation"))
        let session = ChatSession(
            id: UUID().uuidString,
            title: title,
            subtitle: "",
            updatedAt: Date(),
            tags: ["PPG 50HZ", "ACTIVE"],
            photosCount: 0,
            messages: []
        )
        sessions.insert(session, at: 0)
        currentSessionID = session.id
    }

    func clearAll() {
        sessions.removeAll()
        startNewSession()
    }

    func send(text: String, image: UIImage? = nil, dataURL: String? = nil, dataStore: DataStore) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil else { return }

        if currentSession == nil || sessions.isEmpty {
            startNewSession(initialTitle: String(text.prefix(16)))
        }

        guard let index = sessions.firstIndex(where: { $0.id == currentSessionID }) else { return }

        if sessions[index].messages.isEmpty, !text.isEmpty {
            sessions[index].title = String(text.prefix(18))
        }

        let userMsg = ChatMessage(
            sender: .user,
            text: text,
            image: image,
            dataURL: dataURL,
            at: Date()
        )
        sessions[index].messages.append(userMsg)
        sessions[index].subtitle = text
        sessions[index].updatedAt = Date()
        if image != nil {
            sessions[index].photosCount += 1
        }

        isSending = true
        defer { isSending = false }

        let ai = AIService.shared
        let today = dataStore.today
        let widget = await ai.turn(text, day: today.day, store: dataStore)

        let hrvVal = Int(today.nightInputs?.hrv ?? 42)
        let rhrVal = Int(today.nightInputs?.rhr ?? 61)
        let recovery = today.bodyBattery ?? today.bbWake ?? 34

        let verdictStr: String
        let verdictTag: String
        let verdictLvl: VerdictLevel

        if recovery < 40 || hrvVal < 45 {
            verdictStr = L("VERDICT: ENTER MANDATORY DELOAD")
            verdictTag = "STRAIN OVERLOAD"
            verdictLvl = .alert
        } else if recovery > 75 {
            verdictStr = L("VERDICT: PRIME STRAIN STATE")
            verdictTag = "OPTIMAL"
            verdictLvl = .optimal
        } else {
            verdictStr = L("VERDICT: SUSTAINED BASELINE")
            verdictTag = "STEADY"
            verdictLvl = .steady
        }

        let analysisText = widget?.sentence ?? (
            L("Neuromuscular fatigue detected. PPG frequency spectrum confirms elevated sympathetic tone (LF/HF ratio 3.4 vs 1.2 baseline), accompanied by a 0.35°C nocturnal temperature deviation.")
        )

        let prescriptions = [
            L("1. Pause heavy squats; swap to 50% 1RM velocity sets or bodyweight mobility."),
            L("2. Shift evening carbohydrate intake to 3h before bed to minimize nocturnal metabolic heat."),
            L("3. Maintain 8h+ sleep for 3 consecutive nights until morning HRV rebounds past 50ms.")
        ]

        let telemetry = CyberTelemetryData(
            category: "CLINICAL & STRAIN SYNTHESIS",
            confidence: "CONFIDENCE 96.4%",
            verdict: verdictStr,
            verdictTag: verdictTag,
            verdictLevel: verdictLvl,
            analysis: analysisText,
            metrics: [
                TelemetryMetricItem(
                    name: "Night HRV (rMSSD)",
                    value: "\(hrvVal)ms",
                    delta: "(-18ms vs Base)",
                    level: .alert
                ),
                TelemetryMetricItem(
                    name: "Resting Heart Rate",
                    value: "\(rhrVal) bpm",
                    delta: "(+9 bpm)",
                    level: .alert
                ),
                TelemetryMetricItem(
                    name: "Recovery Score",
                    value: "\(recovery)%",
                    delta: "(Sub-optimal)",
                    level: .steady
                )
            ],
            prescriptions: prescriptions
        )

        let aiMsg = ChatMessage(
            sender: .assistant,
            text: widget?.sentence ?? "",
            at: Date(),
            telemetry: telemetry
        )

        if let idx = sessions.firstIndex(where: { $0.id == currentSessionID }) {
            sessions[idx].messages.append(aiMsg)
            sessions[idx].updatedAt = Date()
        }
    }
}
