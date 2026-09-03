import SwiftUI

enum MessageSender: String, Codable {
    case user
    case assistant
}

enum VerdictLevel: String, Codable {
    case alert
    case optimal
    case steady

    var color: Color {
        switch self {
        case .alert:   return NB.alert2
        case .optimal: return NB.lime1
        case .steady:  return NB.cyan1
        }
    }
}

struct TelemetryMetricItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let value: String
    let delta: String
    let level: VerdictLevel
}

struct CyberTelemetryData: Hashable {
    var category: String = "CLINICAL & STRAIN SYNTHESIS"
    var confidence: String = "CONFIDENCE 96.4%"
    var verdict: String
    var verdictTag: String
    var verdictLevel: VerdictLevel = .alert
    var analysis: String
    var metrics: [TelemetryMetricItem]
    var prescriptions: [String]
}

struct ChatMessage: Identifiable, Hashable {
    let id: UUID
    let sender: MessageSender
    var text: String
    var image: UIImage?
    var dataURL: String?
    let at: Date
    var telemetry: CyberTelemetryData?

    init(id: UUID = UUID(), sender: MessageSender, text: String, image: UIImage? = nil, dataURL: String? = nil, at: Date = Date(), telemetry: CyberTelemetryData? = nil) {
        self.id = id
        self.sender = sender
        self.text = text
        self.image = image
        self.dataURL = dataURL
        self.at = at
        self.telemetry = telemetry
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(sender)
        hasher.combine(text)
        hasher.combine(dataURL)
        hasher.combine(at)
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.sender == rhs.sender && lhs.text == rhs.text && lhs.dataURL == rhs.dataURL
    }
}

struct ChatSession: Identifiable, Hashable {
    let id: String
    var title: String
    var subtitle: String
    var updatedAt: Date
    var tags: [String]
    var photosCount: Int
    var messages: [ChatMessage]

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(updatedAt)
    }

    static func == (lhs: ChatSession, rhs: ChatSession) -> Bool {
        lhs.id == rhs.id
    }
}
