import SwiftUI
import Combine

@MainActor
final class ChatStore: ObservableObject {
    static let shared = ChatStore()

    @Published var sessions: [ChatSession] = []
    @Published var currentSessionID: String = ""
    /// A separate service keeps panel/voice progress out of the chat stream.
    let ai = AIService()
    @Published private(set) var sendingScope: ChatTurnScope?
    var isSending: Bool { sendingScope != nil }
    var isSendingCurrentSession: Bool {
        sendingScope?.isVisible(accountID: currentAccountID, sessionID: currentSessionID) == true
    }
    @Published private(set) var persistenceError: String?
    private var accountID: String?
    private var archiveStore: ChatArchiveStore?
    private var storageReady = false

    private var currentAccountID: String {
        SupabaseClient.currentUserIdSnapshot() ?? SessionKeychain.userId ?? "signed-out"
    }

    init() { prepareForCurrentAccount() }

    func prepareForCurrentAccount() {
        let account = currentAccountID
        guard accountID != account else { return }
        accountID = account
        sendingScope = nil
        sessions = []
        currentSessionID = ""
        archiveStore = nil
        storageReady = false
        persistenceError = nil
        do {
            let archive = try ChatArchiveStore(accountID: account)
            archiveStore = archive
            if let saved = try archive.load() {
                sessions = saved.sessions.map(ChatSession.init(archive:))
                currentSessionID = saved.activeSessionID ?? sessions.first?.id ?? ""
                if !sessions.contains(where: { $0.id == currentSessionID }) {
                    currentSessionID = sessions.first?.id ?? ""
                }
            }
            storageReady = true
        } catch {
            reportPersistenceError(error)
        }
    }

    private func persist() {
        guard storageReady, let archiveStore else { return }
        do {
            try archiveStore.save(ChatArchiveSnapshot(
                activeSessionID: currentSessionID, sessions: sessions.map(\.archive)))
            persistenceError = nil
        } catch {
            reportPersistenceError(error)
        }
    }

    private func reportPersistenceError(_ error: Error) {
        persistenceError = L("Chat history could not be saved or loaded. Please try again.")
        NSLog("Chat archive error: %@", String(describing: error))
    }

    func retryPersistence() {
        if storageReady { persist() }
        else { accountID = nil; prepareForCurrentAccount() }
    }

    var currentSession: ChatSession? {
        sessions.first(where: { $0.id == currentSessionID }) ?? sessions.first
    }

    func selectSession(_ id: String) {
        guard sessions.contains(where: { $0.id == id }) else { return }
        currentSessionID = id
        persist()
    }

    func startNewSession(initialTitle: String? = nil) {
        guard storageReady else { return }
        let title = initialTitle ?? L("New chat")
        let session = ChatSession(
            id: UUID().uuidString,
            title: title,
            subtitle: "",
            updatedAt: Date(),
            tags: ["AI COACH"],
            photosCount: 0,
            messages: []
        )
        sessions.insert(session, at: 0)
        currentSessionID = session.id
        persist()
    }

    func clearAll() {
        do {
            try archiveStore?.clear()
            sessions = []
            currentSessionID = ""
            storageReady = archiveStore != nil
            startNewSession()
        } catch {
            reportPersistenceError(error)
        }
    }

    func send(text: String, image: UIImage? = nil, dataURL: String? = nil, dataStore: DataStore) async {
        prepareForCurrentAccount()
        guard storageReady, !isSending else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || image != nil || dataURL != nil else { return }

        if currentSession == nil || sessions.isEmpty {
            startNewSession(initialTitle: String(text.prefix(16)))
        }

        guard let index = sessions.firstIndex(where: { $0.id == currentSessionID }) else { return }

        if sessions[index].messages.isEmpty, !text.isEmpty {
            sessions[index].title = String(text.prefix(18))
        }

        let history = contextHistory(sessions[index].messages)
        let attachment = dataURL ?? image?.jpegData(compressionQuality: 0.7).map {
            "data:image/jpeg;base64," + $0.base64EncodedString()
        }
        let userMsg = ChatMessage(
            sender: .user,
            text: text,
            image: image,
            dataURL: attachment,
            at: Date()
        )
        sessions[index].messages.append(userMsg)
        sessions[index].subtitle = text
        sessions[index].updatedAt = Date()
        if attachment != nil {
            sessions[index].photosCount += 1
        }

        persist()
        let sessionID = currentSessionID
        let sendingAccount = currentAccountID
        let scope = ChatTurnScope(accountID: sendingAccount, sessionID: sessionID, turnID: userMsg.id)
        sendingScope = scope
        defer { if sendingScope == scope { sendingScope = nil } }

        let widget = await ai.turn(
            text, day: dataStore.today.day, store: dataStore,
            imageDataURL: attachment, surface: "chat", history: history, conversationID: UUID(uuidString: sessionID), turnID: userMsg.id
        )
        let aiMsg = ChatMessage(
            sender: .assistant,
            text: widget?.sentence ?? L("Unable to answer right now. Please try again."),
            at: Date(),
            widget: widget
        )

        guard sendingScope?.accepts(turnID: userMsg.id) == true, sendingAccount == currentAccountID, sendingAccount == accountID else { return }
        if let idx = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[idx].messages.append(aiMsg)
            sessions[idx].updatedAt = Date()
            persist()
        }
    }

    private func contextHistory(_ messages: [ChatMessage]) -> [[String: String]] {
        var budget = 64_000
        var result: [[String: String]] = []
        for message in messages.suffix(32).reversed() {
            let content = String(decoding: message.contextText.utf16.prefix(min(8_000, budget)), as: UTF16.self)
            guard !content.isEmpty else { continue }
            result.append(["role": message.sender.rawValue, "content": content])
            budget -= content.utf16.count
            if budget == 0 { break }
        }
        return result.reversed()
    }
}
