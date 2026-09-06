import Foundation

/// A server may cap a page below the requested limit. Only an empty page ends the
/// bounded sample read; callers receive the complete result or an error.
enum SamplePageRead {
    @MainActor
    static func all<Row>(fetch: (_ offset: Int) async throws -> [Row]) async throws -> [Row] {
        var rows: [Row] = []
        while true {
            try Task.checkCancellation()
            let page = try await fetch(rows.count)
            try Task.checkCancellation()
            guard !page.isEmpty else { return rows }
            rows.append(contentsOf: page)
        }
    }
}
