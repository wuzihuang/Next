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
        let statusFollowsSleep: Bool

        init(name: String, deviceKey: String, day: String, timezone: String, start: Date, end: Date,
             observedAt: Date, mappingVersion: String, status: BandDomainReadStatus,
             samples: [[String: Any]], statusFollowsSleep: Bool = false) {
            self.name = name
            self.deviceKey = deviceKey
            self.day = day
            self.timezone = timezone
            self.start = start
            self.end = end
            self.observedAt = observedAt
            self.mappingVersion = mappingVersion
            self.status = status
            self.samples = samples
            self.statusFollowsSleep = statusFollowsSleep
        }

        fileprivate var arguments: [String: Any] {
            let iso = ISO8601DateFormatter()
            return [
                "p_device_key": deviceKey, "p_domain": name, "p_day": day,
                "p_timezone": timezone, "p_start": iso.string(from: start),
                "p_end": iso.string(from: end), "p_observed_at": iso.string(from: observedAt),
                "p_mapping_version": mappingVersion,
                "p_status": statusFollowsSleep ? "pending_sleep" : status.rawValue,
                "p_samples": samples,
            ]
        }

        fileprivate func followingSleep(_ succeeded: Bool) -> Domain {
            Domain(name: name, deviceKey: deviceKey, day: day, timezone: timezone, start: start,
                end: end, observedAt: observedAt, mappingVersion: mappingVersion,
                status: succeeded ? .complete : .failed, samples: samples, statusFollowsSleep: true)
        }
    }

    struct Publication {
        let changedCount: Int
        let state: BandDomainSyncState
        var confirmed: Bool {
            state.status == .complete || state.status == .notCollected || state.status == .unsupported
        }
    }

    struct UploadMetrics {
        fileprivate(set) var calls = 0
        fileprivate(set) var rounds = 0
        let domains: Int

        fileprivate init(calls: Int, rounds: Int, domains: Int) {
            self.calls = calls
            self.rounds = rounds
            self.domains = domains
        }
    }

    /// The owned transport has a production adapter and a deterministic test adapter.
    /// Both must return the server's acknowledgment rather than infer success locally.
    struct Transport {
        let ingest: @MainActor ([String: Any], String) async throws -> BandIngestionAcknowledgment
        let sleep: @MainActor ([String: Any], String) async throws -> [[String: Any]]
        let bundle: (@MainActor ([[String: Any]], [String: Any]?, Int?, String) async throws -> BandBundleReply?)?

        init(ingest: @escaping @MainActor ([String: Any], String) async throws -> BandIngestionAcknowledgment,
             sleep: @escaping @MainActor ([String: Any], String) async throws -> [[String: Any]],
             bundle: (@MainActor ([[String: Any]], [String: Any]?, Int?, String) async throws -> BandBundleReply?)? = nil) {
            self.ingest = ingest
            self.sleep = sleep
            self.bundle = bundle
        }
    }

    enum Failure: Error {
        case sleepNotConfirmed, invalidOwner, deferred
        case server(code: String, message: String)
    }
    private let account: String
    private let local: LocalDataStore
    private let authorized: @MainActor () -> Bool
    private let transport: Transport
    private(set) var uploadMetrics = UploadMetrics(calls: 0, rounds: 0, domains: 0)

    private struct DomainOffer {
        let args: [String: Any]
        let references: [[String: Any]]
    }

    private struct PendingDomain {
        let index: Int
        let args: [String: Any]
        let ids: [String]
        var fullSamples = false
    }

    private struct ReplayPage {
        let args: [String: Any]
        let ids: [String]
    }

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
    /// bundled sleep publication can suspend or fail the current sync.
    func stage(_ domain: Domain) throws {
        _ = try retain(domain.arguments)
    }

    func publish(_ domain: Domain) async throws -> Publication {
        var args = domain.arguments
        if domain.statusFollowsSleep { args["p_status"] = domain.status.rawValue }
        let ids = try retain(args)
        let ack = try await submitDomain(args, ids: ids)
        return publication(domain, acknowledgment: ack)
    }

    /// Independent domains overlap only their network waits. All local transactions
    /// remain MainActor-isolated; the server serializes account mutations itself.
    /// Keep input order even when replies arrive out of order, and never let one
    /// rejected domain cancel another domain's durable publication.
    func publish(_ domains: [Domain]) async -> [Result<Publication, Error>] {
        var results = domains.map { _ in Result<Publication, Error>.failure(CancellationError()) }
        for start in stride(from: 0, to: domains.count, by: 3) {
            guard !Task.isCancelled, authorized() else { break }
            let end = min(start + 3, domains.count)
            let tasks = (start..<end).map { index in
                Task { @MainActor in
                    do { results[index] = .success(try await self.publish(domains[index])) }
                    catch { results[index] = .failure(error) }
                }
            }
            await withTaskCancellationHandler {
                for task in tasks { await task.value }
            } onCancel: {
                for task in tasks { task.cancel() }
            }
        }
        return results
    }

    func publishSleep(_ row: [String: Any]) async throws {
        try requireAuthorization()
        guard row["user_id"] as? String == account else { throw Failure.invalidOwner }
        let payload = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        let id = identifier("sleep-", payload)
        try local.enqueue(operation: LocalOperation(id: id, account: account, kind: "band-sleep", payload: payload))
        try await submitSleep(row, id: id)
    }

    func publish(_ domains: [Domain], sleep row: [String: Any]?) async
        -> (domains: [Result<Publication, Error>], sleep: Result<Void, Error>?) {
        uploadMetrics = UploadMetrics(calls: 0, rounds: 0, domains: domains.count)
        var results = domains.map { _ in Result<Publication, Error>.failure(CancellationError()) }
        guard !Task.isCancelled, authorized() else {
            return (results, row.map { _ in .failure(CancellationError()) })
        }

        var retained: [[String]?] = Array(repeating: nil, count: domains.count)
        for (index, domain) in domains.enumerated() {
            do { retained[index] = try retain(domain.arguments) }
            catch { results[index] = .failure(error) }
        }

        var sleepID: String?
        var sleepResult: Result<Void, Error>?
        if let row {
            do {
                try requireAuthorization()
                guard row["user_id"] as? String == account else { throw Failure.invalidOwner }
                let payload = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
                let id = identifier("sleep-", payload)
                try local.enqueue(operation: LocalOperation(id: id, account: account, kind: "band-sleep", payload: payload))
                sleepID = id
            } catch { sleepResult = .failure(error) }
        }

        guard let bundle = transport.bundle else {
            return await publishLegacy(domains, retained: retained, results: results, sleep: row,
                                       sleepID: sleepID, sleepResult: sleepResult)
        }

        var pending = domains.indices.compactMap { index -> PendingDomain? in
            guard retained[index] != nil else { return nil }
            return PendingDomain(index: index, args: domains[index].arguments, ids: retained[index]!)
        }
        var sleepPending = sleepID != nil
        var sleepSucceeded = false

        for round in 1...3 {
            guard !pending.isEmpty || sleepPending else { break }
            guard !Task.isCancelled, authorized() else { break }
            uploadMetrics.rounds = round

            var offers: [(PendingDomain, DomainOffer)] = []
            var nextPending: [PendingDomain] = []
            for item in pending {
                do {
                    let domain = domains[item.index]
                    var args = item.args
                    if domain.statusFollowsSleep, row != nil, !sleepPending {
                        args["p_status"] = sleepSucceeded ? "complete" : "failed"
                    }
                    let offer = try domainOffer(args, fullSamples: item.fullSamples)
                    offers.append((item, offer))
                } catch {
                    results[item.index] = .failure(error)
                }
            }

            let chunks = bundleChunks(offers, sleep: sleepPending ? row : nil)
            var sleepDeferredThisRound = false
            var unsupported = false
            for (chunkIndex, chunk) in chunks.enumerated() {
                guard !Task.isCancelled, authorized() else { break }
                let attachedSleep = chunkIndex == 0 && sleepPending ? row : nil
                let blocked = chunk.filter {
                    sleepDeferredThisRound && chunkIndex > 0 && domains[$0.0.index].statusFollowsSleep
                }
                nextPending.append(contentsOf: blocked.map { $0.0 })
                let eligible = chunk.filter { pair in
                    !(sleepDeferredThisRound && chunkIndex > 0 && domains[pair.0.index].statusFollowsSleep)
                }.map { item, offer -> (PendingDomain, DomainOffer) in
                    var args = offer.args
                    if domains[item.index].statusFollowsSleep {
                        args["p_status"] = attachedSleep != nil || row == nil
                            ? "pending_sleep" : (sleepSucceeded ? "complete" : "failed")
                    }
                    return (item, DomainOffer(args: args, references: offer.references))
                }
                if eligible.isEmpty && attachedSleep == nil { continue }
                let callOffers = eligible.map { $0.1.args }
                let reply: BandBundleReply?
                do {
                    uploadMetrics.calls += 1
                    reply = try await bundle(callOffers, attachedSleep, nil, account)
                } catch {
                    if attachedSleep != nil {
                        sleepResult = .failure(error)
                        sleepPending = false
                    }
                    for (item, _) in eligible { results[item.index] = .failure(error) }
                    continue
                }
                guard let reply else {
                    unsupported = true
                    break
                }
                do { try requireAuthorization() }
                catch {
                    for (item, _) in eligible { results[item.index] = .failure(error) }
                    break
                }

                if attachedSleep != nil {
                    switch reply.sleep {
                    case .ok(let accepted):
                        do {
                            try confirmSleep(accepted, row: row!, id: sleepID!)
                            sleepResult = .success(())
                            sleepSucceeded = true
                            sleepPending = false
                        } catch {
                            sleepResult = .failure(error)
                            sleepSucceeded = false
                            sleepPending = false
                        }
                    case .deferred:
                        sleepDeferredThisRound = true
                    case .error(let code, let message):
                        sleepResult = .failure(Failure.server(code: code, message: message))
                        sleepSucceeded = false
                        sleepPending = false
                    case nil:
                        sleepResult = .failure(Failure.server(code: "INVALID_BUNDLE_REPLY",
                            message: "Missing sleep result"))
                        sleepSucceeded = false
                        sleepPending = false
                    }
                }

                for (resultIndex, pair) in eligible.enumerated() {
                    let (item, offer) = pair
                    guard resultIndex < reply.results.count else {
                        results[item.index] = .failure(Failure.server(code: "INVALID_BUNDLE_REPLY",
                            message: "Missing domain result"))
                        continue
                    }
                    switch reply.results[resultIndex] {
                    case .ok(let ack):
                        if !offer.references.isEmpty && !(ack.needsSamples ?? []).isEmpty {
                            nextPending.append(PendingDomain(index: item.index, args: item.args, ids: item.ids,
                                fullSamples: true))
                            continue
                        }
                        do {
                            try acknowledgeDomain(item.args, ids: item.ids, acknowledgment: ack,
                                                  references: offer.references)
                            let domain = domains[item.index]
                            results[item.index] = .success(publication(domain, acknowledgment: ack,
                                sleepSucceeded: domain.statusFollowsSleep ? sleepSucceeded : nil))
                        } catch { results[item.index] = .failure(error) }
                    case .deferred:
                        nextPending.append(item)
                    case .error(let code, let message):
                        results[item.index] = .failure(Failure.server(code: code, message: message))
                    }
                }
            }

            if unsupported {
                return await publishLegacy(domains, retained: retained, results: results, sleep: row,
                                           sleepID: sleepID, sleepResult: sleepResult)
            }
            pending = nextPending
            if Task.isCancelled || !authorized() { break }
        }

        if Task.isCancelled || !authorized() {
            for item in pending { results[item.index] = .failure(CancellationError()) }
            if row != nil && sleepPending { sleepResult = .failure(CancellationError()) }
            return (results, row == nil ? nil : sleepResult)
        }
        if sleepPending { sleepResult = .failure(Failure.deferred) }
        for item in pending { results[item.index] = .failure(Failure.deferred) }
        return (results, row == nil ? nil : sleepResult)
    }

    private func publishLegacy(_ domains: [Domain], retained: [[String]?],
                               results: [Result<Publication, Error>], sleep row: [String: Any]?,
                               sleepID: String?, sleepResult initialSleepResult: Result<Void, Error>?)
        async -> (domains: [Result<Publication, Error>], sleep: Result<Void, Error>?) {
        var results = results
        var sleepResult = initialSleepResult
        var sleepSucceeded = false
        if let row, let sleepID {
            do {
                try requireAuthorization()
                uploadMetrics.calls += 1
                try await submitSleep(row, id: sleepID)
                sleepResult = .success(())
                sleepSucceeded = true
            } catch {
                sleepResult = .failure(error)
            }
        }

        let active = domains.indices.filter { retained[$0] != nil }
        let legacyDomains = active.map { index in
            domains[index].statusFollowsSleep ? domains[index].followingSleep(sleepSucceeded) : domains[index]
        }
        if !legacyDomains.isEmpty {
            uploadMetrics.calls += legacyDomains.count
            uploadMetrics.rounds = max(uploadMetrics.rounds, (legacyDomains.count + 2) / 3)
            let legacyResults = await publish(legacyDomains)
            for (index, result) in zip(active, legacyResults) { results[index] = result }
        }
        return (results, row == nil ? nil : sleepResult)
    }

    private func publication(_ domain: Domain, acknowledgment: BandIngestionAcknowledgment,
                             sleepSucceeded: Bool? = nil) -> Publication {
        var status = domain.status
        if domain.statusFollowsSleep, let sleepSucceeded {
            status = sleepSucceeded ? .complete : .failed
            if sleepSucceeded && !acknowledgment.confirms(offered: domain.samples.count) {
                status = .partial
            }
        } else if domain.statusFollowsSleep {
            if status == .complete && !acknowledgment.confirms(offered: domain.samples.count) {
                status = .partial
            }
        } else if !acknowledgment.confirms(offered: domain.samples.count) {
            status = .partial
        } else if domain.samples.isEmpty && status == .complete && domain.name != "sleep" {
            status = .notCollected
        }
        let confirmed = status == .complete || status == .notCollected || status == .unsupported
        return Publication(changedCount: acknowledgment.inserted + acknowledgment.completed,
            state: BandDomainSyncState(domain: domain.name, status: status, attemptedAt: domain.observedAt,
                acknowledgedStart: confirmed ? domain.start : nil, acknowledgedEnd: confirmed ? domain.end : nil,
                repairStart: confirmed ? nil : domain.start, repairEnd: confirmed ? nil : domain.end))
    }

    private func domainOffer(_ args: [String: Any], fullSamples: Bool = false) throws -> DomainOffer {
        if fullSamples {
            var full = args
            full.removeValue(forKey: "p_receipts")
            return DomainOffer(args: full, references: [])
        }
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
                let referenceBytes = try JSONSerialization.data(withJSONObject: reference).count
                let sampleBytes = try JSONSerialization.data(withJSONObject: sample).count
                if referenceBytes + 24 < sampleBytes { references.append(reference) }
                else { values.append(sample) }
            } else {
                values.append(sample)
            }
        }
        var offer = args
        offer["p_samples"] = values
        if !references.isEmpty { offer["p_receipts"] = references }
        return DomainOffer(args: offer, references: references)
    }

    private func acknowledgeDomain(_ args: [String: Any], ids: [String],
                                   acknowledgment ack: BandIngestionAcknowledgment,
                                   references: [[String: Any]]) throws {
        let samples = args["p_samples"] as? [[String: Any]] ?? []
        guard !samples.isEmpty, ack.confirms(offered: samples.count) else { return }
        let key = try receiptKey(args)
        var confirmed = try receipts(key: key)
        let verifiedTokens = Dictionary(references.compactMap { reference -> (String, String)? in
            guard let ts = reference["ts"] as? String, let token = reference["receipt"] as? String else { return nil }
            return (ts, token)
        }, uniquingKeysWith: { _, last in last })
        for sample in samples {
            guard let ts = sample["ts"] as? String else { continue }
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

    private func bundleChunks(_ offers: [(PendingDomain, DomainOffer)],
                              sleep: [String: Any]?) -> [[(PendingDomain, DomainOffer)]] {
        guard !offers.isEmpty || sleep != nil else { return [] }
        let maximumBytes = 1_500_000
        var chunks: [[(PendingDomain, DomainOffer)]] = []
        var chunk: [(PendingDomain, DomainOffer)] = []
        var bytes = sleep.map(serializedSize) ?? 2
        for pair in offers {
            let size = serializedSize(pair.1.args) + 1
            if !chunk.isEmpty && (chunk.count == 8 || bytes + size > maximumBytes) {
                chunks.append(chunk)
                chunk = []
                bytes = 2
            }
            chunk.append(pair)
            bytes += size
            if bytes > maximumBytes {
                chunks.append(chunk)
                chunk = []
                bytes = 2
            }
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        if chunks.isEmpty { chunks.append([]) }
        return chunks
    }

    private func serializedSize(_ value: Any) -> Int {
        (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).count) ?? 0
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
            let expected = replayableOperationCount(batch)
            let acknowledged = try await replayDomainBatch(batch)
            total += acknowledged
            if acknowledged == 0 || acknowledged < expected { break }
        }
        return total
    }

    private func replayableOperationCount(_ operations: [LocalOperation]) -> Int {
        operations.reduce(0) { count, operation in
            guard let args = try? JSONSerialization.jsonObject(with: operation.payload) as? [String: Any],
                  let samples = args["p_samples"] as? [[String: Any]], !samples.isEmpty else { return count }
            return count + 1
        }
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
        let offer = try domainOffer(args)
        var ack = try await transport.ingest(offer.args, account)
        try requireAuthorization()
        // A token can expire or another phone can revise the same measurement. A miss
        // changes nothing on the server; replay the durable full observation once.
        var references = offer.references
        if !references.isEmpty && !(ack.needsSamples ?? []).isEmpty {
            ack = try await transport.ingest(args, account)
            try requireAuthorization()
            references = []
        }
        try acknowledgeDomain(args, ids: ids, acknowledgment: ack, references: references)
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
        try confirmSleep(accepted, row: row, id: id)
    }

    private func confirmSleep(_ accepted: [[String: Any]], row: [String: Any], id: String) throws {
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
            var pagesToReplay: [ReplayPage] = []
            for page in pages {
                guard var args = page.first?.1 else { continue }
                let samples = page.flatMap { $0.1["p_samples"] as? [[String: Any]] ?? [] }
                args["p_samples"] = samples
                args["p_start"] = page.compactMap { $0.1["p_start"] as? String }.min()
                args["p_end"] = page.compactMap { $0.1["p_end"] as? String }.max()
                pagesToReplay.append(ReplayPage(args: args, ids: page.map { $0.0.id }))
            }
            let replayed = try await replayPages(pagesToReplay)
            acknowledged += replayed
            if replayed < pagesToReplay.reduce(0, { $0 + $1.ids.count }) { return acknowledged }
        }
        return acknowledged
    }

    private func replayPages(_ pages: [ReplayPage]) async throws -> Int {
        guard let bundle = transport.bundle else { return try await replayIndividually(pages) }
        var acknowledged = 0
        var index = 0
        while index < pages.count {
            try requireAuthorization()
            let chunk = Array(pages[index..<min(index + 8, pages.count)])
            let offers = try chunk.map { try domainOffer($0.args) }
            let reply = try await bundle(offers.map(\.args), nil, nil, account)
            try requireAuthorization()
            guard let reply else {
                acknowledged += try await replayIndividually(Array(pages[index...]))
                return acknowledged
            }
            for (offset, page) in chunk.enumerated() {
                guard offset < reply.results.count else { return acknowledged }
                var acknowledgment: BandIngestionAcknowledgment
                var references = offers[offset].references
                switch reply.results[offset] {
                case .ok(let ack):
                    acknowledgment = ack
                    if !references.isEmpty && !(ack.needsSamples ?? []).isEmpty {
                        let full = try domainOffer(page.args, fullSamples: true)
                        guard let fullReply = try await bundle([full.args], nil, nil, account) else {
                            let fullAck = try await submitDomain(page.args, ids: page.ids)
                            if !fullAck.confirms(offered: (page.args["p_samples"] as? [[String: Any]] ?? []).count) {
                                return acknowledged
                            }
                            acknowledged += page.ids.count
                            continue
                        }
                        try requireAuthorization()
                        guard let first = fullReply.results.first else { return acknowledged }
                        switch first {
                        case .ok(let fullAck): acknowledgment = fullAck
                        case .deferred: return acknowledged
                        case .error(let code, let message): throw Failure.server(code: code, message: message)
                        }
                        references = []
                    }
                case .deferred:
                    return acknowledged
                case .error(let code, let message):
                    throw Failure.server(code: code, message: message)
                }
                let offered = (page.args["p_samples"] as? [[String: Any]] ?? []).count
                guard acknowledgment.confirms(offered: offered) else { return acknowledged }
                try acknowledgeDomain(page.args, ids: page.ids, acknowledgment: acknowledgment,
                                      references: references)
                acknowledged += page.ids.count
            }
            index += chunk.count
        }
        return acknowledged
    }

    private func replayIndividually(_ pages: [ReplayPage]) async throws -> Int {
        var acknowledged = 0
        for page in pages {
            try requireAuthorization()
            let samples = page.args["p_samples"] as? [[String: Any]] ?? []
            let ack = try await submitDomain(page.args, ids: page.ids)
            guard ack.confirms(offered: samples.count) else { return acknowledged }
            acknowledged += page.ids.count
        }
        return acknowledged
    }

    private func batches<T>(_ values: [T], limit: Int) -> [[T]] {
        stride(from: 0, to: values.count, by: limit).map {
            Array(values[$0..<min($0 + limit, values.count)])
        }
    }
}
