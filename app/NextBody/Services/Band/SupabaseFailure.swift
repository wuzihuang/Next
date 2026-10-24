import Foundation

/// Shared transport errors; read modules classify server conflicts without losing HTTP failures.
enum SupabaseFailure: Error, LocalizedError {
    case http(Int, String)
    case transport(Error)
    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .transport(let e): return e.localizedDescription
        }
    }

    /// The SQL exception behind a PostgREST failure. Its error body is
    /// `{"code","message","details","hint"}`, and `raise exception 'NAME'` arrives as `message`.
    var serverMessage: String? {
        guard case .http(_, let body) = self,
              let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
        else { return nil }
        return object["message"] as? String
    }
}

