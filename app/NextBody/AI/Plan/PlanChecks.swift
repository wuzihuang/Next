import Foundation

/// Today's five catalog ticks. Local to the user day — checking one is not a server write.
enum PlanChecks {
    static func load(dayKey: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key(dayKey)) ?? [])
    }

    static func save(dayKey: String, done: Set<String>) {
        UserDefaults.standard.set(Array(done).sorted(), forKey: key(dayKey))
    }

    private static func key(_ dayKey: String) -> String {
        "plan.checks.2.\(dayKey)"
    }
}
