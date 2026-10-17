import Foundation

/// UI-independent records preserve the complete conversation, including image and widget payloads.
struct ChatArchiveSnapshot: Codable, Equatable, Sendable {
    let activeSessionID: String?
    let sessions: [ChatArchiveSession]
}

struct ChatArchiveSession: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let updatedAt: Date
    let tags: [String]
    let photosCount: Int
    let messages: [ChatArchiveMessage]
}

struct ChatArchiveMessage: Codable, Equatable, Sendable {
    let id: UUID
    let sender: String
    let text: String
    let imageDataURL: String?
    let at: Date
    let envelope: Data?
}

enum ChatArchiveError: Error, LocalizedError, Equatable {
    case emptyAccountID
    case accountMismatch
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .emptyAccountID: "无法保存聊天：缺少账户信息。"
        case .accountMismatch: "聊天记录与当前账户不匹配。"
        case let .unsupportedVersion(version): "暂时无法读取版本 \(version) 的聊天记录。"
        }
    }
}

/// Local, per-account persistence. Callers surface errors and decide when snapshots are saved.
final class ChatArchiveStore {
    private struct Document: Codable {
        let version: Int
        let accountID: String
        let snapshot: ChatArchiveSnapshot
    }

    private let accountID: String
    private let directory: URL
    private let fileURL: URL
    private static let version = 1

    init(accountID: String, directory: URL? = nil) throws {
        guard !accountID.isEmpty else { throw ChatArchiveError.emptyAccountID }
        let resolvedDirectory: URL
        if let directory {
            resolvedDirectory = directory
        } else {
            resolvedDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("NextBody/ChatArchives", isDirectory: true)
        }
        // Hex encoding is reversible and collision-free without permitting path traversal.
        let filename = accountID.utf8.map { String(format: "%02x", $0) }.joined()
        self.accountID = accountID
        self.directory = resolvedDirectory
        self.fileURL = resolvedDirectory.appendingPathComponent("\(filename).json")
    }

    func load() throws -> ChatArchiveSnapshot? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.accountID == accountID else { throw ChatArchiveError.accountMismatch }
        guard document.version == Self.version else {
            throw ChatArchiveError.unsupportedVersion(document.version)
        }
        return document.snapshot
    }

    func save(_ snapshot: ChatArchiveSnapshot) throws {
        let document = Document(version: Self.version, accountID: accountID, snapshot: snapshot)
        let data = try JSONEncoder().encode(document)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }

    func clear() throws {
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }
}

/// Progress belongs to one account, conversation and request, even if navigation changes.
struct ChatTurnScope: Equatable {
    let accountID: String
    let sessionID: String
    let turnID: UUID

    func isVisible(accountID: String, sessionID: String) -> Bool {
        self.accountID == accountID && self.sessionID == sessionID
    }

    func accepts(turnID: UUID) -> Bool { self.turnID == turnID }
}
