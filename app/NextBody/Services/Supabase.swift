import Foundation

/// Thin REST/Edge-Function client. Everything server-side lives in Supabase (see supabase/).
struct SupabaseConfig {
    static let url = URL(string: "https://gkgzwcxivnffsecshvfs.supabase.co")!
    static let publishableKey = "sb_publishable_FBRhpyBVNzlpBdjp4NOF4Q_1ZrVGWRt"
}

actor SupabaseClient {
    static let shared = SupabaseClient()

    private var accessToken: String?
    private var refreshToken: String?
    private(set) var userId: String?
    /// The address the session belongs to. 11 prints it under the name, so it has to be
    /// whoever actually signed in.
    private(set) var userEmail: String?
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.waitsForConnectivity = true
        return URLSession(configuration: c)
    }()

    func setAccessToken(_ token: String?) { accessToken = token }

    var isSignedIn: Bool { accessToken != nil }

    /// Email + password. The gate's real flow is a six-digit code (`signInWithOtp`);
    /// this path exists so the seeded demo account can be reached without a mailbox.
    @discardableResult
    func signIn(email: String, password: String) async throws -> String {
        var r = URLRequest(url: SupabaseConfig.url
            .appendingPathComponent("auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "password")]))
        r.httpMethod = "POST"
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])

        let (data, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code),
              let out = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = out["access_token"] as? String else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        accessToken = token
        refreshToken = out["refresh_token"] as? String
        userId = ((out["user"] as? [String: Any])?["id"] as? String)
        userEmail = (out["user"] as? [String: Any])?["email"] as? String
        return token
    }

    /// The gate's real path: ask for a six-digit code.
    func requestCode(email: String) async throws {
        var r = URLRequest(url: SupabaseConfig.url.appendingPathComponent("auth/v1/otp"))
        r.httpMethod = "POST"
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "create_user": true])
        _ = try await session.data(for: r)
    }

    @discardableResult
    func verifyCode(email: String, token: String) async throws -> String {
        var r = URLRequest(url: SupabaseConfig.url.appendingPathComponent("auth/v1/verify"))
        r.httpMethod = "POST"
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email, "token": token, "type": "email",
        ])
        let (data, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code),
              let out = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = out["access_token"] as? String else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        accessToken = access
        userId = ((out["user"] as? [String: Any])?["id"] as? String)
        userEmail = (out["user"] as? [String: Any])?["email"] as? String
        return access
    }

    /// A PostgREST select. RLS does the filtering; we never send a user id.
    func select(_ table: String, query: [URLQueryItem]) async throws -> [[String: Any]] {
        let url = SupabaseConfig.url
            .appendingPathComponent("rest/v1/\(table)")
            .appending(queryItems: query)
        var r = URLRequest(url: url)
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(accessToken ?? SupabaseConfig.publishableKey)",
                   forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    /// ⚠️ `returning` is not a convenience. Asking for the row back makes PostgREST add a
    /// RETURNING clause, and RETURNING has to pass a *select* policy — so on a table that is
    /// deliberately write-only, like analytics_events, a perfectly legal insert comes back as
    /// "new row violates row-level security policy" and looks like the write was rejected.
    @discardableResult
    func insert(_ table: String, rows: [[String: Any]],
                returning: Bool = true) async throws -> [[String: Any]] {
        var r = URLRequest(url: SupabaseConfig.url.appendingPathComponent("rest/v1/\(table)"))
        r.httpMethod = "POST"
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(accessToken ?? SupabaseConfig.publishableKey)",
                   forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(returning ? "return=representation" : "return=minimal",
                   forHTTPHeaderField: "Prefer")
        r.httpBody = try JSONSerialization.data(withJSONObject: rows)
        let (data, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    /// An upsert. PostgREST wants the conflict target named, otherwise a repeat write is a
    /// duplicate-key error rather than a replacement.
    @discardableResult
    func upsert(_ table: String, row: [String: Any], onConflict: String) async throws -> [[String: Any]] {
        var r = URLRequest(url: SupabaseConfig.url
            .appendingPathComponent("rest/v1/\(table)")
            .appending(queryItems: [URLQueryItem(name: "on_conflict", value: onConflict)]))
        r.httpMethod = "POST"
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(accessToken ?? SupabaseConfig.publishableKey)",
                   forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        r.httpBody = try JSONSerialization.data(withJSONObject: [row])
        let (data, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    @discardableResult
    func insert(_ table: String, row: [String: Any]) async throws -> [[String: Any]] {
        try await insert(table, rows: [row])
    }

    /// A PATCH by primary key. Used to close a row that was opened before the work started —
    /// a sync run, a turn — so the row exists even if the work never finishes.
    @discardableResult
    func patch(_ table: String, id: String, row: [String: Any]) async throws -> [[String: Any]] {
        var r = URLRequest(url: SupabaseConfig.url
            .appendingPathComponent("rest/v1/\(table)")
            .appending(queryItems: [URLQueryItem(name: "id", value: "eq.\(id)")]))
        r.httpMethod = "PATCH"
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(accessToken ?? SupabaseConfig.publishableKey)",
                   forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("return=representation", forHTTPHeaderField: "Prefer")
        r.httpBody = try JSONSerialization.data(withJSONObject: row)
        let (data, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    /// The signed-in user's id. Every write that names a user_id needs it; RLS still checks
    /// it, so this is convenience, never authority.
    var currentUserId: String? { userId }

    enum Failure: Error, LocalizedError {
        case http(Int, String)
        case transport(Error)
        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "HTTP \(code): \(body)"
            case .transport(let e): return e.localizedDescription
            }
        }
    }

    private func request(_ path: String, method: String, body: Data?, isFunction: Bool) throws -> URLRequest {
        let base = isFunction
            ? SupabaseConfig.url.appendingPathComponent("functions/v1")
            : SupabaseConfig.url.appendingPathComponent("rest/v1")
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = method
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(accessToken ?? SupabaseConfig.publishableKey)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        return r
    }

    func callFunction(_ name: String, payload: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let req = try request(name, method: "POST", body: data, isFunction: true)
        do {
            let (out, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                throw Failure.http(code, String(data: out, encoding: .utf8) ?? "")
            }
            return (try? JSONSerialization.jsonObject(with: out) as? [String: Any]) ?? [:]
        } catch let e as Failure {
            throw e
        } catch {
            throw Failure.transport(error)
        }
    }

    /// Streams an Edge Function's SSE response line by line.
    func streamFunction(_ name: String, payload: [String: Any]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try JSONSerialization.data(withJSONObject: payload)
                    let req = try request(name, method: "POST", body: data, isFunction: true)
                    let (bytes, resp) = try await session.bytes(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(code) else {
                        continuation.finish(throwing: Failure.http(code, ""))
                        return
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        continuation.yield(payload)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func signedInEmail() -> String? { userEmail }
}
