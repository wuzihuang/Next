import Foundation

/// A confirmed meal is durable before it becomes visible. Manual entries, accepted
/// estimates and later changes share identity, dependency order and acknowledgment.
@MainActor
public final class MealPublication {
    public enum Failure: Error, LocalizedError {
        case invalidMeal, collectionPaused, http(Int, String), invalidAcknowledgment
        public var errorDescription: String? {
            switch self {
            case .invalidMeal: "Check the meal name, date and nutrients."
            case .collectionPaused: "Data collection is paused. Pending meals stay on this device."
            case .http(let status, _): "Meal synchronization failed (HTTP \(status))."
            case .invalidAcknowledgment: "Meal acknowledgment did not match the pending operation."
            }
        }
    }
    public struct Submitted {
        public let id: UUID
        public let fields: [String: Any]
    }
    public struct Replay {
        public var acknowledged = 0
        public var message: String?
    }
    public struct VisibleMeal {
        public let id: UUID
        public let day: String
        public let at: Date
        public let slot: String
        public let name: String
        public let kcal: Double
        public let protein: Int
        public let carb: Int
        public let fat: Int
        public let confirmed: Bool
        public let source: String?
        public let revisions: Int?
    }
    public struct Projection {
        public let meals: [VisibleMeal]
        public let removedIDs: Set<UUID>
    }
    public static let pausedMessage = "Data collection is paused. Pending meals stay on this device."
    public static let rejectedMessage = "This change could not sync. Retry it or remove the pending change."
    private let account: String
    private let local: LocalDataStore
    private let isCurrent: @MainActor () -> Bool
    private let consent: @MainActor () -> Bool
    private let send: @MainActor (String, [String: Any], String) async throws -> [String: Any]
    private let persistProjection: @MainActor () throws -> Void

    public init(account: String, local: LocalDataStore,
                isCurrent: @escaping @MainActor () -> Bool,
                consent: @escaping @MainActor () -> Bool,
                send: @escaping @MainActor (String, [String: Any], String) async throws -> [String: Any],
                persistProjection: @escaping @MainActor () throws -> Void) {
        self.account = account; self.local = local; self.isCurrent = isCurrent
        self.consent = consent; self.send = send; self.persistProjection = persistProjection
    }

    public func createManual(id: UUID = UUID(), day: String, slot: String, name: String,
                             kcal: Int, at: Date) throws -> Submitted {
        try create(id: id, fields: ["draft_id": id.uuidString.lowercased(), "user_day": day,
            "slot": slot, "name": name.trimmingCharacters(in: .whitespacesAndNewlines),
            "kcal": kcal, "protein_g": 0, "carb_g": 0, "fat_g": 0,
            "confidence": "HIGH", "model_version": "manual-entry-v1",
            "logged_at": ISO8601DateFormatter().string(from: at)], source: "TYPED")
    }

    public func confirmDraft(id: UUID = UUID(), day: String, slot: String,
                             output: [String: Any], at: Date) throws -> Submitted {
        var output = output
        if let macros = output["macros"] as? [String: Any] {
            output["protein_g"] = output["protein_g"] ?? macros["p"]
            output["carb_g"] = output["carb_g"] ?? macros["c"]
            output["fat_g"] = output["fat_g"] ?? macros["f"]
        }
        let envelope: [String: Any] = ["kind": "estimate", "meal_id": id.uuidString.lowercased(),
            "body": ["user_day": day, "slot": slot, "name": output["name"] ?? ""]]
        let operation = LocalOperation(id: id.uuidString.lowercased(), account: account, kind: "meal",
            payload: try JSONSerialization.data(withJSONObject: envelope))
        let promoted = try MealOutboxPolicy.promotedEstimate(operation, output: output)
        guard let fields = try JSONSerialization.jsonObject(with: promoted) as? [String: Any],
              var body = fields["body"] as? [String: Any] else { throw Failure.invalidMeal }
        body["logged_at"] = ISO8601DateFormatter().string(from: at)
        return try create(id: id, fields: body, source: output["source"] as? String == "photo" ? "PHOTO" : "TYPED", revisions: 1)
    }

    public func create(id: UUID, fields: [String: Any], source: String? = nil, revisions: Int = 0) throws -> Submitted {
        guard let draft = fields["draft_id"] as? String, UUID(uuidString: draft) != nil else { throw Failure.invalidMeal }
        try validate(fields)
        let body = fields.merging(["id": id.uuidString.lowercased()]) { _, new in new }
        try retain(id: draft.lowercased(), kind: "create", mealID: id, body: body, source: source, revisions: revisions)
        return Submitted(id: id, fields: body)
    }

    public func amend(id: UUID, replacement: [String: Any], source: String? = nil,
                      revisions: Int = 1, operationID: UUID = UUID()) throws -> Submitted {
        guard let raw = replacement["id"] as? String, let replacementID = UUID(uuidString: raw) else { throw Failure.invalidMeal }
        try validate(replacement)
        let op = operationID.uuidString.lowercased()
        try retain(id: op, kind: "amend", mealID: id,
            body: ["operation_id": op, "kind": "amend", "meal_id": id.uuidString.lowercased(), "replacement": replacement],
            source: source, revisions: revisions)
        return Submitted(id: replacementID, fields: replacement)
    }

    public func delete(id: UUID, operationID: UUID = UUID()) throws {
        let op = operationID.uuidString.lowercased()
        try retain(id: op, kind: "delete", mealID: id,
            body: ["operation_id": op, "kind": "delete", "meal_id": id.uuidString.lowercased()])
    }

    private func requireCurrent() throws {
        guard !account.isEmpty, isCurrent(), !Task.isCancelled else { throw CancellationError() }
    }

    private func retain(id: String, kind: String, mealID: UUID, body: [String: Any],
                        source: String? = nil, revisions: Int = 0) throws {
        try requireCurrent()
        guard kind == "delete" || consent() else { throw Failure.collectionPaused }
        var envelope: [String: Any] = ["kind": kind, "meal_id": mealID.uuidString.lowercased(), "body": body, "revisions": revisions]
        envelope["source"] = source
        let bytes = try JSONSerialization.data(withJSONObject: envelope, options: .sortedKeys)
        try local.enqueue(operation: LocalOperation(id: id, account: account, kind: "meal", payload: bytes),
            documentKey: "meal.\(mealID.uuidString.lowercased())", document: bytes)
    }

    /// Display metadata lives in the durable envelope, outside the server's immutable
    /// meal fields. The same projection is used after submission, reopen and rebasing.
    public func projection() throws -> Projection {
        try requireCurrent()
        var entries: [VisibleMeal] = []
        var removed = Set<UUID>()
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let iso = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for operation in try local.operations(account: account, kind: "meal") {
            let envelope = try MealOutboxPolicy.fields(operation)
            guard let kind = envelope["kind"] as? String, let body = envelope["body"] as? [String: Any],
                  let original = envelope["meal_id"] as? String, let originalID = UUID(uuidString: original) else { continue }
            if let previous = envelope["canonical_previous_id"] as? String, let oldID = UUID(uuidString: previous) {
                removed.insert(oldID); entries.removeAll { $0.id == oldID }
            }
            if kind == "amend" || kind == "delete" {
                removed.insert(originalID); entries.removeAll { $0.id == originalID }
            }
            if kind == "delete" { continue }
            let fields = kind == "amend" ? body["replacement"] as? [String: Any] : body
            guard let fields, let raw = fields["id"] as? String, let id = UUID(uuidString: raw),
                  let day = fields["user_day"] as? String, let midnight = formatter.date(from: day),
                  let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: midnight),
                  let slot = fields["slot"] as? String else { continue }
            let at = (fields["logged_at"] as? String).flatMap { iso.date(from: $0) ?? fractional.date(from: $0) } ?? noon
            entries.removeAll { $0.id == id }
            entries.append(VisibleMeal(id: id, day: day, at: at, slot: slot, name: fields["name"] as? String ?? "",
                kcal: (fields["kcal"] as? NSNumber)?.doubleValue ?? 0,
                protein: (fields["protein_g"] as? NSNumber)?.intValue ?? 0,
                carb: (fields["carb_g"] as? NSNumber)?.intValue ?? 0,
                fat: (fields["fat_g"] as? NSNumber)?.intValue ?? 0,
                confirmed: kind != "estimate" && envelope["rejection"] == nil,
                source: envelope["source"] as? String, revisions: envelope["revisions"] as? Int))
        }
        return Projection(meals: entries, removedIDs: removed)
    }

    private func validate(_ fields: [String: Any]) throws {
        guard let name = fields["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 8000, let day = fields["user_day"] as? String,
              let slot = fields["slot"] as? String, ["BREAKFAST", "LUNCH", "DINNER", "SNACK"].contains(slot),
              let kcal = fields["kcal"] as? Int, (1...100000).contains(kcal),
              ["protein_g", "carb_g", "fat_g"].allSatisfy({ key in
                  guard let n = fields[key] as? Int else { return false }; return (0...100000).contains(n)
              }) else { throw Failure.invalidMeal }
        let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX")
        date.timeZone = TimeZone(secondsFromGMT: 0); date.dateFormat = "yyyy-MM-dd"; date.isLenient = false
        guard let parsed = date.date(from: day), date.string(from: parsed) == day else { throw Failure.invalidMeal }
    }

    /// Drain one finite snapshot. Rejected changes block only their dependents; lost
    /// replies and local save failures leave the original operation available to retry.
    public func replay() async throws -> Replay {
        try requireCurrent()
        var result = Replay()
        var collectionPaused = !consent()
        for queued in try local.operations(account: account, kind: "meal") {
            try requireCurrent()
            let rows = try local.operations(account: account, kind: "meal")
            guard let operation = rows.first(where: { $0.id == queued.id }) else { continue }
            let fields = try MealOutboxPolicy.fields(operation)
            let probe = fields["rejection"] != nil && fields["kind"] as? String == "create"
                && fields["canonical_probe_attempted"] as? Bool != true
            let runnable = try MealOutboxPolicy.runnable(rows)
            guard probe || runnable.contains(where: { $0.id == operation.id }) else { continue }
            do {
                let envelope = try MealOutboxPolicy.fields(operation)
                let kind = envelope["kind"] as? String
                guard kind == "delete" || (!collectionPaused && consent()) else {
                    result.message = Self.pausedMessage; continue
                }
                if kind == "estimate" {
                    let message = "Send this meal again to review and confirm its estimate."
                    let payload = try MealOutboxPolicy.replacingRejection(operation, message: message)
                    try local.replaceOperation(operation, payload: payload, documentKey: "meal.\(operation.id)")
                    result.message = message; continue
                }
                guard let body = envelope["body"] as? [String: Any], let kind else { throw Failure.invalidMeal }
                let request = probe ? body.merging(["reconcile_only": true]) { _, new in new } : body
                let response = try await send(kind == "create" ? "meal-commit" : "meal-operation", request, account)
                try requireCurrent()
                guard kind == "delete" || consent() else { throw Failure.collectionPaused }
                let ack = response[kind == "create" ? "client_op_id" : "operation_id"] as? String
                let acceptedID = (response["id"] as? String)?.lowercased()
                let requestedID = (body["id"] as? String)?.lowercased()
                let canonicalMatch = kind == "create" && acceptedID.flatMap(UUID.init(uuidString:)) != nil
                    && (response["requested_meal_id"] as? String)?.lowercased() == requestedID
                    && (response["meal_id"] as? String)?.lowercased() == acceptedID
                guard ack?.lowercased() == (kind == "create" ? (body["draft_id"] as? String)?.lowercased() : operation.id.lowercased()),
                      kind != "create" || acceptedID == requestedID || canonicalMatch else { throw Failure.invalidAcknowledgment }
                if kind == "create", let requestedID, let acceptedID, canonicalMatch || probe {
                    let changes = try local.operations(account: account, kind: "meal").map { row in
                        let mapped = try MealOutboxPolicy.remappingMeal(row, from: requestedID, to: acceptedID)
                        let remapped = LocalOperation(id: row.id, account: row.account, kind: row.kind, payload: mapped)
                        let payload = row.id == operation.id ? try MealOutboxPolicy.replacingRejection(remapped, message: nil) : mapped
                        let fields = try MealOutboxPolicy.fields(remapped)
                        return (expected: row, payload: payload, documentKey: "meal.\(fields["meal_id"] as? String ?? row.id)")
                    }
                    try local.replaceOperations(changes)
                }
                // The pending projection includes canonical aliases, so the saved display
                // and dependent changes agree before the acknowledged fact leaves the queue.
                try persistProjection()
                try requireCurrent()
                try local.acknowledge(account: account, id: operation.id)
                result.acknowledged += 1
            } catch Failure.http(let code, _) where code == 403 {
                try requireCurrent()
                collectionPaused = true; result.message = Self.pausedMessage
            } catch Failure.http(let code, let responseBody) where (400..<500).contains(code)
                && code != 401 && code != 408 && code != 429 {
                try requireCurrent()
                let errorData = responseBody.data(using: .utf8)
                let serverBody = errorData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let serverError = serverBody?["error"] as? String
                // The server's own word for the refusal (DAY_ALREADY_FASTED, MEAL_EDIT_WINDOW_CLOSED,
                // MEAL_NOT_FOUND…) rides in the message so the Fuel page and a voice turn can say why.
                let reason = [serverBody?["reason"] as? String, serverError].compactMap { $0 }.first { !$0.isEmpty && $0 != "E_SCHEMA" }
                let rejected = try MealOutboxPolicy.replacingRejection(operation, message: reason.map { Self.rejectedMessage + " [" + $0 + "]" } ?? Self.rejectedMessage)
                let rejectedOperation = LocalOperation(id: operation.id, account: operation.account, kind: operation.kind, payload: rejected)
                let fields = try MealOutboxPolicy.fields(rejectedOperation)
                let definitiveMismatch = code == 409 && ["NO_CANONICAL_MATCH", "OPERATION_CONFLICT"].contains(serverError ?? "")
                let next = probe && definitiveMismatch ? fields.merging(["canonical_probe_attempted": true]) { _, new in new } : fields
                let payload = try JSONSerialization.data(withJSONObject: next, options: .sortedKeys)
                try local.replaceOperation(operation, payload: payload, documentKey: "meal.\(operation.id)")
            }
        }
        return result
    }
}
