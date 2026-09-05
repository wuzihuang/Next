import SwiftUI

enum MessageSender: String, Codable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Hashable {
    let id: UUID
    let sender: MessageSender
    var text: String
    var image: UIImage?
    var dataURL: String?
    let at: Date
    var widget: PanelWidget?

    init(id: UUID = UUID(), sender: MessageSender, text: String, image: UIImage? = nil, dataURL: String? = nil, at: Date = Date(), widget: PanelWidget? = nil) {
        self.id = id
        self.sender = sender
        self.text = text
        self.image = image
        self.dataURL = dataURL
        self.at = at
        self.widget = widget
    }

    var contextText: String {
        [text, widget?.headline?.sub, widget?.hero, widget?.footer]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    @MainActor
    init(archive: ChatArchiveMessage) {
        let envelope = archive.envelope.flatMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        }
        self.init(id: archive.id, sender: MessageSender(rawValue: archive.sender) ?? .assistant,
                  text: archive.text, dataURL: archive.imageDataURL, at: archive.at,
                  widget: envelope.flatMap { AIService.shared.widget(from: $0) })
        if let url = archive.imageDataURL, let comma = url.firstIndex(of: ","),
           let data = Data(base64Encoded: String(url[url.index(after: comma)...])) {
            image = UIImage(data: data)
        }
    }

    var archive: ChatArchiveMessage {
        ChatArchiveMessage(id: id, sender: sender.rawValue, text: text,
                           imageDataURL: dataURL, at: at, envelope: widget?.envelopeData)
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


extension ChatSession {
    @MainActor
    init(archive: ChatArchiveSession) {
        self.init(id: archive.id, title: archive.title, subtitle: archive.subtitle,
                  updatedAt: archive.updatedAt, tags: archive.tags,
                  photosCount: archive.photosCount, messages: archive.messages.map(ChatMessage.init(archive:)))
    }

    var archive: ChatArchiveSession {
        ChatArchiveSession(id: id, title: title, subtitle: subtitle, updatedAt: updatedAt,
                           tags: tags, photosCount: photosCount, messages: messages.map(\.archive))
    }
}
