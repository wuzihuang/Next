import Foundation

/// Receipts for native history commands, never cached measurement rows. A shared refresh
/// keeps each completed domain until it finishes; other callers retain the short freshness
/// window. Connection/scope generations reject replies from a link that has already ended.
final class BandHistoryReadCache: @unchecked Sendable {
    struct Scope: Equatable {
        let account: String?
        let binding: String?
        let device: String?
        var sessionGeneration: UUID? = nil
    }
    enum Domain { case all, hrv, temperature, oxygen }
    struct Receipt {
        let status: BandDomainReadStatus
        let startedAt: Date
        let completedAt: Date
    }
    private let lock = NSLock()
    private var scope: Scope?
    private var epoch: UInt = 0
    private var refreshing = false
    private var receipts: [Domain: Receipt] = [:]

    func beginRefresh(scope: Scope) {
        lock.lock(); defer { lock.unlock() }
        reset()
        self.scope = scope
        refreshing = true
    }

    func endRefresh() {
        lock.lock(); defer { lock.unlock() }
        refreshing = false
    }

    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        reset()
        scope = nil
    }

    func generation(scope: Scope) -> UInt {
        lock.lock(); defer { lock.unlock() }
        adopt(scope)
        return epoch
    }

    func status(for domain: Domain, scope: Scope, at now: Date = Date()) -> BandDomainReadStatus? {
        receipt(for: domain, scope: scope, at: now)?.status
    }

    func receipt(for domain: Domain, scope: Scope, at now: Date = Date()) -> Receipt? {
        lock.lock(); defer { lock.unlock() }
        adopt(scope)
        guard let receipt = receipts[domain], now >= receipt.completedAt,
              refreshing || now.timeIntervalSince(receipt.completedAt) < 60 else { return nil }
        return receipt
    }

    func record(_ status: BandDomainReadStatus, for domain: Domain,
                generation: UInt, startedAt: Date? = nil, at now: Date = Date()) {
        lock.lock(); defer { lock.unlock() }
        guard generation == epoch else { return }
        // Only a terminal read or explicit lack of SDK support can be reused. Failure,
        // partial progress and an uncollected database row never certify the transfer.
        if status == .complete || status == .unsupported {
            receipts[domain] = Receipt(status: status, startedAt: startedAt ?? now, completedAt: now)
        } else {
            receipts[domain] = nil
        }
    }

    private func adopt(_ scope: Scope) {
        guard self.scope != scope else { return }
        reset()
        self.scope = scope
    }

    private func reset() {
        epoch &+= 1
        refreshing = false
        receipts.removeAll()
    }
}
