import Foundation

/// Where the thread should land when the page appears or a new line arrives.
enum ChatScrollTarget {
    static let thinking = "thinking-indicator"
    static let bottom = "chat-bottom"

    static func id(lastMessageID: UUID?, isThinking: Bool) -> String {
        if isThinking { return thinking }
        if let lastMessageID { return lastMessageID.uuidString }
        return bottom
    }
}
