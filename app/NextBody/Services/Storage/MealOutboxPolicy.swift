import Foundation
import CoreFoundation

/// Durable rejection state stays attached to its operation and preserves dependency order.
public enum MealOutboxPolicy {
    /// Incomplete model output must remain a pending estimate, never a zero-macro meal.
    public static func promotedEstimate(_ operation: LocalOperation, output: [String: Any]) throws -> Data {
        let envelope = try fields(operation)
        guard let original = envelope["body"] as? [String: Any],
              let draft = output["draft_id"] as? String, UUID(uuidString: draft) != nil else {
            throw LocalDataStore.Failure.database("Invalid meal estimate")
        }
        func nutrient(_ key: String, minimum: Double) throws -> Int {
            guard let value = output[key] as? NSNumber,
                  CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite,
                  value.doubleValue >= minimum, value.doubleValue <= 100000,
                  value.doubleValue.rounded() == value.doubleValue else {
                throw LocalDataStore.Failure.database("Incomplete meal nutrients: " + key)
            }
            return value.intValue
        }
        let body: [String: Any] = ["id": operation.id, "draft_id": draft,
            "user_day": original["user_day"] ?? "", "slot": original["slot"] ?? "",
            "name": output["name"] ?? original["name"] ?? "", "kcal": try nutrient("kcal", minimum: 1),
            "protein_g": try nutrient("protein_g", minimum: 0), "carb_g": try nutrient("carb_g", minimum: 0),
            "fat_g": try nutrient("fat_g", minimum: 0), "confidence": output["confidence"] ?? "MEDIUM",
            "model_version": output["model_version"] ?? ""]
        return try JSONSerialization.data(withJSONObject:
            ["kind": "create", "meal_id": operation.id, "body": body], options: .sortedKeys)
    }
    public static func remappingMeal(_ operation: LocalOperation, from oldID: String, to canonicalID: String) throws -> Data {
        let value = try fields(operation)
        func remap(_ fields: [String: Any], keys: [String]) -> [String: Any] {
            fields.mapValues { $0 }.merging(Dictionary(uniqueKeysWithValues: keys.compactMap { key in
                guard let id = fields[key] as? String, id.lowercased() == oldID.lowercased() else { return nil }
                return (key, canonicalID as Any)
            })) { _, new in new }
        }
        let body = value["body"] as? [String: Any] ?? [:]
        let nextBody = remap(body, keys: ["id", "meal_id"])
        let next = remap(value, keys: ["meal_id"]).merging(["body": nextBody]) { _, new in new }
        let alias: [String: Any] = value["kind"] as? String == "create"
            && (body["id"] as? String)?.lowercased() == oldID.lowercased() && oldID.lowercased() != canonicalID.lowercased()
            ? ["canonical_previous_id": oldID] : [:]
        return try JSONSerialization.data(withJSONObject: next.merging(alias) { _, new in new }, options: .sortedKeys)
    }
    public static func fields(_ operation: LocalOperation) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: operation.payload) as? [String: Any] else {
            throw LocalDataStore.Failure.database("Invalid pending meal")
        }
        return value
    }
    public static func affectedMeals(_ operation: LocalOperation) throws -> Set<String> {
        let value = try fields(operation)
        let body = value["body"] as? [String: Any] ?? [:]
        let replacement = body["replacement"] as? [String: Any] ?? [:]
        return Set([value["meal_id"] as? String, replacement["id"] as? String].compactMap { $0 })
    }
    public static func rejection(_ operation: LocalOperation) throws -> String? {
        try fields(operation)["rejection"] as? String
    }
    public static func replacingRejection(_ operation: LocalOperation, message: String?) throws -> Data {
        let original = try fields(operation)
        let clean = original.filter { $0.key != "rejection" }
        let next = message.map { clean.merging(["rejection": $0]) { _, new in new } } ?? clean
        return try JSONSerialization.data(withJSONObject: next, options: .sortedKeys)
    }
    /// Rejected work blocks only dependent records. Independent meals can still upload.
    public static func runnable(_ operations: [LocalOperation]) throws -> [LocalOperation] {
        var blocked = Set<String>()
        var result: [LocalOperation] = []
        for operation in operations {
            let affected = try affectedMeals(operation)
            if try rejection(operation) != nil || !blocked.isDisjoint(with: affected) {
                blocked.formUnion(affected)
            } else { result.append(operation) }
        }
        return result
    }
    public static func rejectedChain(_ id: String, operations: [LocalOperation]) throws -> [LocalOperation] {
        guard let initial = operations.first(where: { $0.id == id }), try rejection(initial) != nil else { return [] }
        var affected = try affectedMeals(initial)
        var result = [initial]
        var found = false
        for operation in operations {
            if operation.id == id { found = true; continue }
            guard found else { continue }
            let related = try affectedMeals(operation)
            if !affected.isDisjoint(with: related) { result.append(operation); affected.formUnion(related) }
        }
        return result
    }
}
