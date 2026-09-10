import Foundation

/// A fresh set of evidence-based suggestions; `plan` and `tasks` remain wire names.
struct DailyPlan: Equatable {
    struct Source: Equatable {
        let title: String
        let url: URL
    }
    struct Task: Equatable, Identifiable {
        let id: String
        let title: String
        let sub: String
        let basis: String?
        let sources: [Source]
    }
    let dayKey: String
    let title: String
    let summary: String
    let tasks: [Task]
    let readFrom: String
    let readTo: String
    let sources: [Source]

    init?(row: [String: Any], dayKey: String? = nil) {
        guard let title = row["title"] as? String, let summary = row["summary"] as? String,
              let rawTasks = row["tasks"] as? [[String: Any]], rawTasks.count <= 5 else { return nil }
        let tasks = rawTasks.compactMap { task -> Task? in
            guard let id = task["id"] as? String, !id.isEmpty,
                  let title = task["title"] as? String, !title.isEmpty,
                  let sub = task["sub"] as? String else { return nil }
            return Task(id: id, title: title, sub: sub,
                        basis: (task["basis"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                        sources: Self.readSources(task["sources"]))
        }
        // Zero suggestions is an honest result when the available evidence is insufficient.
        // A malformed item must not silently become a valid empty result.
        guard tasks.count == rawTasks.count, Set(tasks.map(\.id)).count == tasks.count else { return nil }
        self.dayKey = dayKey ?? (row["user_day"] as? String) ?? ""
        self.title = title
        self.summary = summary
        self.tasks = tasks
        self.readFrom = (row["read_from"] as? String) ?? ""
        self.readTo = (row["read_to"] as? String) ?? ""
        var seen = Set<URL>()
        self.sources = Array((tasks.flatMap(\.sources) + Self.readSources(row["web_sources"]))
            .filter { seen.insert($0.url).inserted }.prefix(12))
    }

    private static func readSources(_ value: Any?) -> [Source] {
        guard let rows = value as? [[String: Any]] else { return [] }
        return rows.prefix(12).compactMap { row in
            guard let text = row["url"] as? String, let url = URL(string: text),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, url.user == nil, url.password == nil else { return nil }
            return Source(title: String((row["title"] as? String ?? host).prefix(160)), url: url)
        }
    }
}
