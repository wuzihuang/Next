import Foundation
import os

/// [DEBUG-night-hrv] Local summaries only. Never pass identities, credentials or raw SDK payloads.
/// A persisted 48-hour lease survives relaunches and never automatically renews.
final class NightDiagnostics: @unchecked Sendable {
    static let shared: NightDiagnostics = {
        #if DEBUG
        let enabled = true
        #else
        let enabled = false
        #endif
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return NightDiagnostics(directory: documents.appendingPathComponent("night-diagnostics"), enabled: enabled)
    }()

    private let queue = DispatchQueue(label: "com.nextbody.hoop.night-diagnostics")
    private let directory: URL
    private let configuredEnabled: Bool
    private let now: () -> Date
    private let maximumFileBytes: Int
    private let session = UUID().uuidString
    private let timestamp = ISO8601DateFormatter()
    private var expiresAt: Date?
    private var sequence = 0
    private var lastFailure: String?
    private let log = Logger(subsystem: "com.nextbody.hoop", category: "night-diagnostics")

    init(directory: URL, enabled: Bool, now: @escaping () -> Date = Date.init,
         maximumFileBytes: Int = 4 * 1024 * 1024, leaseDuration: TimeInterval = 48 * 3600) {
        self.directory = directory
        configuredEnabled = enabled
        self.now = now
        self.maximumFileBytes = max(1024, maximumFileBytes)
        timestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard enabled else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try protect(directory)
            let lease = directory.appendingPathComponent("lease.json")
            if FileManager.default.fileExists(atPath: lease.path) {
                let contents = try Data(contentsOf: lease)
                let stored = try JSONDecoder().decode(Lease.self, from: contents)
                expiresAt = Date(timeIntervalSince1970: stored.expiresAt)
            } else {
                let start = now()
                let stored = Lease(startedAt: start.timeIntervalSince1970, expiresAt: start.addingTimeInterval(leaseDuration).timeIntervalSince1970)
                try JSONEncoder().encode(stored).write(to: lease, options: .atomic)
                try protect(lease)
                expiresAt = Date(timeIntervalSince1970: stored.expiresAt)
            }
        } catch {
            reportFailure("initialize", error: error)
        }
    }

    var isEnabled: Bool { queue.sync { active(at: now()) } }

    /// Safe metadata for confirming whether the diagnostic lease is still collecting.
    var status: [String: String] {
        queue.sync {
            ["enabled": String(active(at: now())), "session": session,
             "expiresAt": expiresAt.map { timestamp.string(from: $0) } ?? "unavailable",
             "lastFailure": lastFailure ?? "none"]
        }
    }

    func record(_ event: String, fields: [String: String] = [:]) {
        queue.sync {
            let instant = now()
            guard active(at: instant) else { return }
            do {
                sequence += 1
                // Bound caller summaries before serialization; larger records are rejected, never silently truncated.
                guard event.utf8.count <= 128, fields.count <= 64,
                      fields.allSatisfy({ $0.key.utf8.count <= 128 && $0.value.utf8.count <= 8192 }) else {
                    reportFailure("oversized_fields", error: nil)
                    return
                }
                let zone = TimeZone.current
                let record: [String: Any] = [
                    "version": 1, "timestamp": timestamp.string(from: instant),
                    "timezone": zone.identifier, "utcOffsetSeconds": zone.secondsFromGMT(for: instant),
                    "session": session, "sequence": sequence, "event": event, "fields": fields
                ]
                var bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                bytes.append(0x0A)
                guard bytes.count <= min(16384, maximumFileBytes) else {
                    reportFailure("oversized_record", error: nil)
                    return
                }
                let day = String(timestamp.string(from: instant).prefix(10))
                let file = directory.appendingPathComponent("events-\(day).jsonl")
                try append(bytes, to: file)
                try pruneFiles()
            } catch {
                reportFailure("write", error: error)
            }
        }
    }

    private struct Lease: Codable { let startedAt: Double; let expiresAt: Double }

    private func active(at instant: Date) -> Bool {
        configuredEnabled && expiresAt.map { instant < $0 } == true
    }

    private func append(_ bytes: Data, to file: URL) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: file.path) {
            try bytes.write(to: file, options: .atomic)
            try protect(file)
            return
        }
        let size = (try manager.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        if size + bytes.count > maximumFileBytes {
            // Retain the most recent whole JSONL records; never leave half a JSON object.
            let previous = try Data(contentsOf: file)
            let targetStart = max(0, previous.count - maximumFileBytes / 2)
            let boundary = previous[targetStart...].firstIndex(of: 0x0A).map { $0 + 1 } ?? previous.endIndex
            var tail = Data(previous[boundary...])
            while tail.count + bytes.count > maximumFileBytes, let newline = tail.firstIndex(of: 0x0A) {
                tail.removeSubrange(...newline)
            }
            tail.append(bytes)
            try tail.write(to: file, options: .atomic)
            try protect(file)
        } else {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: bytes)
            try handle.synchronize()
        }
    }

    private func pruneFiles() throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("events-") && $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in files.dropFirst(3) { try FileManager.default.removeItem(at: file) }
    }

    private func protect(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }

    private func reportFailure(_ operation: String, error: Error?) {
        // Error messages can contain paths or payloads; emit only the numeric code.
        let code = (error as NSError?)?.code ?? 0
        lastFailure = "\(operation):\(code)"
        log.error("[DEBUG-night-hrv] diagnostic failure operation=\(operation, privacy: .public) code=\(code)")
    }
}
