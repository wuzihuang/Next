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
}

