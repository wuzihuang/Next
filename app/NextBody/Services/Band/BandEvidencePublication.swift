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

    private struct ContentReceipt: Codable {
        let content: String
        let token: String
    }

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
        let samples = args["p_samples"] as? [[String: Any]] ?? []
        let key = try receiptKey(args)
        let cached = try receipts(key: key)
        var values: [[String: Any]] = []
        var references: [[String: Any]] = []
        for sample in samples {
            if let ts = sample["ts"] as? String, let receipt = cached[ts],
               receipt.content == (try contentFingerprint(sample)) {
                var reference: [String: Any] = ["ts": ts, "receipt": receipt.token]
                if let readAt = sample["origin_read_at"] { reference["origin_read_at"] = readAt }
                // A scalar temperature/HRV value can be smaller than its receipt. Account
                // for the extra p_receipts array as well; compaction must save wire bytes.
                let referenceBytes = try JSONSerialization.data(withJSONObject: reference).count
                let sampleBytes = try JSONSerialization.data(withJSONObject: sample).count
                if referenceBytes + 24 < sampleBytes { references.append(reference) }
                else { values.append(sample) }
            } else { values.append(sample) }
        }
        var offer = args
        offer["p_samples"] = values
        if !references.isEmpty { offer["p_receipts"] = references }
        var ack = try await transport.ingest(offer, account)
        try requireAuthorization()
        // A token can expire or another phone can revise the same measurement. A miss
        // changes nothing on the server; replay the durable full observation once.
        if !references.isEmpty && !(ack.needsSamples ?? []).isEmpty {
            ack = try await transport.ingest(args, account)
            try requireAuthorization()
            references = []
        }
        let offered = samples.count
        // Empty offers still publish read status, but have no durable sample to retire.
        if offered > 0 && ack.confirms(offered: offered) {
            // An aggregate "unchanged" can mean a stale revision was ignored. Only
            // explicit server receipts prove that our values match current stored facts.
            var confirmed = try receipts(key: key)
            let verifiedTokens = Dictionary(references.compactMap { reference -> (String, String)? in
                guard let ts = reference["ts"] as? String, let token = reference["receipt"] as? String else { return nil }
                return (ts, token)
            }, uniquingKeysWith: { _, last in last })
            for sample in samples {
                guard let ts = sample["ts"] as? String else { continue }
                // A successful delta response verified all references under its write lock.
                // Their existing tokens need not be sent back over the network again.
                let token = ack.receipts?[ts] ?? (ack.receipts == nil ? nil : verifiedTokens[ts])
                if let token, !token.isEmpty, token.utf8.count <= 256 {
                    confirmed[ts] = ContentReceipt(content: try contentFingerprint(sample), token: token)
                } else {
                    confirmed.removeValue(forKey: ts)
                }
            }
            let data = try JSONEncoder().encode(confirmed)
            try local.acknowledge(account: account, ids: ids, documents: [key: data])
        }
        return ack
    }

    private func receiptKey(_ args: [String: Any]) throws -> String {
        let scope = ["p_device_key", "p_domain", "p_day", "p_timezone", "p_mapping_version"].map {
            args[$0] as? String ?? ""
        }
        return identifier("band.receipts.v1.", try JSONEncoder().encode(scope))
    }

    private func receipts(key: String) throws -> [String: ContentReceipt] {
        guard let data = try local.readDocument(account: account, key: key) else { return [:] }
        return (try? JSONDecoder().decode([String: ContentReceipt].self, from: data)) ?? [:]
    }

    private func contentFingerprint(_ sample: [String: Any]) throws -> String {
        var content = sample
        content.removeValue(forKey: "origin_read_at")
        return identifier("", try JSONSerialization.data(withJSONObject: content, options: [.sortedKeys]))
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
            guard let group = groups[key] else { continue }
            // p_observed_at has second precision. Distinct durable revisions captured
            // within that second must remain ordered, not collide in one delta batch.
            var pages: [[(LocalOperation, [String: Any])]] = []
            var page: [(LocalOperation, [String: Any])] = []
            var seen: Set<String> = []
            let iso = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            for entry in group {
                let times = Set((entry.1["p_samples"] as? [[String: Any]] ?? []).compactMap { sample -> String? in
                    guard let raw = sample["ts"] as? String else { return nil }
                    return (iso.date(from: raw) ?? fractional.date(from: raw))
                        .map { String($0.timeIntervalSince1970) } ?? raw
                })
                if !seen.isDisjoint(with: times) { pages.append(page); page = []; seen = [] }
                page.append(entry)
                seen.formUnion(times)
            }
            if !page.isEmpty { pages.append(page) }
            for page in pages {
                guard var args = page.first?.1 else { continue }
                let samples = page.flatMap { $0.1["p_samples"] as? [[String: Any]] ?? [] }
                args["p_samples"] = samples
                args["p_start"] = page.compactMap { $0.1["p_start"] as? String }.min()
                args["p_end"] = page.compactMap { $0.1["p_end"] as? String }.max()
                let ids = page.map { $0.0.id }
                let ack = try await submitDomain(args, ids: ids)
                if ack.confirms(offered: samples.count) { acknowledged += ids.count }
                else { return acknowledged }
            }
        }
        return acknowledged
    }

    private func batches<T>(_ values: [T], limit: Int) -> [[T]] {
        stride(from: 0, to: values.count, by: limit).map {
            Array(values[$0..<min($0 + limit, values.count)])
        }
    }
}
