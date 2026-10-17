import Foundation

/// Request identity is independent of the page's animation and view lifetime.
/// Reopening joins an unfinished request; a later opening can always start another.
struct AdviceRequestLifetime {
    struct Scope: Equatable {
        let owner: String?
        let dayKey: String
    }
    private var scope: Scope?
    private var activeRequest: UUID?

    @discardableResult
    mutating func prepare(owner: String?, dayKey: String) -> Bool {
        let next = Scope(owner: owner, dayKey: dayKey)
        guard scope != next else { return false }
        scope = next
        activeRequest = nil
        return true
    }

    mutating func begin() -> UUID? {
        guard scope != nil, activeRequest == nil else { return nil }
        let request = UUID()
        activeRequest = request
        return request
    }

    func accepts(_ request: UUID, owner: String?, dayKey: String) -> Bool {
        activeRequest == request && scope == Scope(owner: owner, dayKey: dayKey)
    }

    @discardableResult
    mutating func finish(_ request: UUID) -> Bool {
        guard activeRequest == request else { return false }
        activeRequest = nil
        return true
    }

    mutating func reset() {
        scope = nil
        activeRequest = nil
    }
}
