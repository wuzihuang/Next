import Foundation
import CryptoKit
#if SWIFT_PACKAGE
import NextBodyLocalData
#endif

/// Account-owned publication: callers provide measured facts and read coverage, while
/// this module owns durable identity, replay, acknowledgment and repair bookkeeping.
@MainActor
final class BandEvidencePublication {
    struct Domain {
        let name: String
        let deviceKey: String
        let day: String
        let timezone: String
        let start: Date
        let end: Date
        let observedAt: Date
        let mappingVersion: String
        let status: BandDomainReadStatus
        let samples: [[String: Any]]

        fileprivate var arguments: [String: Any] {
            let iso = ISO8601DateFormatter()
            return [
                "p_device_key": deviceKey, "p_domain": name, "p_day": day,
                "p_timezone": timezone, "p_start": iso.string(from: start),
                "p_end": iso.string(from: end), "p_observed_at": iso.string(from: observedAt),
                "p_mapping_version": mappingVersion, "p_status": status.rawValue,
                "p_samples": samples,
            ]
        }
    }

    struct Publication {
        let changedCount: Int
        let state: BandDomainSyncState
        var confirmed: Bool {
            state.status == .complete || state.status == .notCollected || state.status == .unsupported
        }
    }

    /// The owned transport has a production adapter and a deterministic test adapter.
    /// Both must return the server's acknowledgment rather than infer success locally.
    struct Transport {
        let ingest: @MainActor ([String: Any], String) async throws -> BandIngestionAcknowledgment
        let sleep: @MainActor ([String: Any], String) async throws -> [[String: Any]]
    }

    enum Failure: Error { case sleepNotConfirmed, invalidOwner }
    private let account: String
    private let local: LocalDataStore
    private let authorized: @MainActor () -> Bool
    private let transport: Transport

    init(account: String, local: LocalDataStore, authorized: @escaping @MainActor () -> Bool,
         transport: Transport) {
        self.account = account
        self.local = local
        self.authorized = authorized
        self.transport = transport
    }

    /// Staging has no network work. Origin and RR must already be durable before the
    /// separately published sleep row can suspend or fail the current sync.
    func stage(_ domain: Domain) throws {
        _ = try retain(domain.arguments)
    }

    func publish(_ domain: Domain) async throws -> Publication {
        let args = domain.arguments
        let ids = try retain(args)
        let ack = try await submitDomain(args, ids: ids)
        var status = domain.status
        if !ack.confirms(offered: domain.samples.count) { status = .partial }
        else if domain.samples.isEmpty && status == .complete && domain.name != "sleep" {
            status = .notCollected
        }
        let confirmed = status == .complete || status == .notCollected || status == .unsupported
        return Publication(changedCount: ack.inserted + ack.completed,
            state: BandDomainSyncState(domain: domain.name, status: status, attemptedAt: domain.observedAt,
                acknowledgedStart: confirmed ? domain.start : nil, acknowledgedEnd: confirmed ? domain.end : nil,
                repairStart: confirmed ? nil : domain.start, repairEnd: confirmed ? nil : domain.end))
    }

    func publishSleep(_ row: [String: Any]) async throws {
        try requireAuthorization()
        guard row["user_id"] as? String == account else { throw Failure.invalidOwner }
        let payload = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        let id = identifier("sleep-", payload)
        try local.enqueue(operation: LocalOperation(id: id, account: account, kind: "band-sleep", payload: payload))
        try await submitSleep(row, id: id)
    }

    /// One finite snapshot per pass. New observations wait for the next pass; a group
    /// without a complete acknowledgment retains every operation; a batch with no
    /// progress stops that lane.
    func replay() async throws -> Int {
        try requireAuthorization()
        let sleeps = try local.operations(account: account, kind: "band-sleep")
        let observations = try local.operations(account: account, kind: "band-domain")
        var total = 0
        for batch in batches(sleeps, limit: 30) {
            var acknowledged = 0
            for operation in batch {
                try requireAuthorization()
                guard let row = try JSONSerialization.jsonObject(with: operation.payload) as? [String: Any] else { continue }
                try await submitSleep(row, id: operation.id)
                acknowledged += 1
            }
            total += acknowledged
            if acknowledged == 0 { break }
        }
        for batch in batches(observations, limit: 200) {
            try requireAuthorization()
            let acknowledged = try await replayDomainBatch(batch)
            total += acknowledged
            if acknowledged == 0 { break }
        }
        return total
    }

    private func requireAuthorization() throws {
        guard !Task.isCancelled, authorized() else { throw CancellationError() }
        guard !account.isEmpty else { throw Failure.invalidOwner }
    }

    private func identifier(_ prefix: String, _ payload: Data) -> String {
        prefix + SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    private func retain(_ args: [String: Any]) throws -> [String] {
        try requireAuthorization()
        let iso = ISO8601DateFormatter()
        let operations = try (args["p_samples"] as? [[String: Any]] ?? []).map { sample in
            var single = args
            single["p_samples"] = [sample]
            single["p_status"] = "partial"
            // Preserve the existing payload identity and original observation clock.
            // A retry must never become a newer measurement revision.
            if let raw = sample["ts"] as? String, let ts = iso.date(from: raw) {
                single["p_start"] = raw
                single["p_end"] = iso.string(from: ts.addingTimeInterval(60))
            }
            let payload = try JSONSerialization.data(withJSONObject: single, options: [.sortedKeys])
            return LocalOperation(id: identifier("band-", payload), account: account, kind: "band-domain", payload: payload)
        }
        try local.enqueue(operations: operations)
        return operations.map(\.id)
    }

    private func submitDomain(_ args: [String: Any], ids: [String]) async throws -> BandIngestionAcknowledgment {
        try requireAuthorization()
        let ack = try await transport.ingest(args, account)
        try requireAuthorization()
        let offered = (args["p_samples"] as? [[String: Any]])?.count ?? 0
        // Empty offers still publish read status, but have no durable sample to retire.
        if offered > 0 && ack.confirms(offered: offered) {
            try local.acknowledge(account: account, ids: ids)
        }
        return ack
    }

    private func submitSleep(_ row: [String: Any], id: String) async throws {
        try requireAuthorization()
        guard row["user_id"] as? String == account else { throw Failure.invalidOwner }
        let accepted = try await transport.sleep(row, account)
        try requireAuthorization()
        // The server may merge HRV revisions into raw: confirmation is intentionally
        // about the recorded night, not byte equality with the submitted row.
        guard let saved = accepted.first, saved["user_id"] as? String == account,
              saved["user_day"] as? String == row["user_day"] as? String,
              saved["total_minutes"] as? Int == row["total_minutes"] as? Int else {
            throw Failure.sleepNotConfirmed
        }
        try local.acknowledge(account: account, id: id)
    }

    private func replayDomainBatch(_ pending: [LocalOperation]) async throws -> Int {
        let decoded = try pending.compactMap { operation -> (LocalOperation, [String: Any])? in
            guard let args = try JSONSerialization.jsonObject(with: operation.payload) as? [String: Any],
                  let samples = args["p_samples"] as? [[String: Any]], !samples.isEmpty else { return nil }
            return (operation, args)
        }
        let groups = Dictionary(grouping: decoded) { item in
            ["p_device_key", "p_domain", "p_day", "p_timezone", "p_mapping_version", "p_observed_at"].map {
                item.1[$0] as? String ?? ""
            }.joined(separator: "|")
        }
        var acknowledged = 0
        for key in groups.keys.sorted() {
            guard let group = groups[key], var args = group.first?.1 else { continue }
            let samples = group.flatMap { $0.1["p_samples"] as? [[String: Any]] ?? [] }
            args["p_samples"] = samples
            args["p_start"] = group.compactMap { $0.1["p_start"] as? String }.min()
            args["p_end"] = group.compactMap { $0.1["p_end"] as? String }.max()
            let ids = group.map { $0.0.id }
            let ack = try await submitDomain(args, ids: ids)
            if ack.confirms(offered: samples.count) { acknowledged += ids.count }
        }
        return acknowledged
    }

    private func batches<T>(_ values: [T], limit: Int) -> [[T]] {
        stride(from: 0, to: values.count, by: limit).map {
            Array(values[$0..<min($0 + limit, values.count)])
        }
    }
}
