import Foundation
import Security

/// Thin REST/Edge-Function client. Everything server-side lives in Supabase (see supabase/).
struct SupabaseConfig {
    static let url = URL(string: "https://gkgzwcxivnffsecshvfs.supabase.co")!
    static let publishableKey = "sb_publishable_FBRhpyBVNzlpBdjp4NOF4Q_1ZrVGWRt"

    /// Where the Edge Functions live.
    ///
    /// The brief's fifth acceptance line allows the AI to be proven 本地 / 模拟器 / 真机, and
    /// the thing worth proving is the deployed artefact — the real prompt, the real eight
    /// tools, the real SSE stream — rather than a second implementation of it that happens
    /// to live in the app. Set NBFunctionsBase to a locally served host and the simulator
    /// exercises the functions as written.
    ///
    /// ⚠️ DEBUG only. A release build always talks to the project.
    static var functionsBase: URL {
        #if DEBUG
        if let s = Bundle.main.object(forInfoDictionaryKey: "NBFunctionsBase") as? String,
           !s.isEmpty, let u = URL(string: s) { return u }
        #endif
        return url.appendingPathComponent("functions/v1")
    }
}

actor SupabaseClient {
    static let shared = SupabaseClient()
    private static let snapshotLock = NSLock()
    private static var snapshotUserId: String?
    private static var snapshotUserEmail: String?

    private var accessToken: String?
    private var refreshToken: String?
    private var refreshTask: Task<RefreshResult, Never>?
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

    nonisolated static func currentUserIdSnapshot() -> String? {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshotUserId
    }

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
        adopt(session: out)
        return token
    }

    /// Sign in with Apple. The identity token the system sheet handed back is exchanged for
    /// a session of this project's own (`/auth/v1/token?grant_type=id_token`); the raw nonce
    /// goes along so the server can prove the token was minted for this very request and
    /// not replayed. Nothing about the user reaches us before the server has said yes.
    @discardableResult
    func signInWithApple(idToken: String, nonce: String) async throws -> String {
        var r = URLRequest(url: SupabaseConfig.url
            .appendingPathComponent("auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "id_token")]))
        r.httpMethod = "POST"
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: [
            "provider": "apple", "id_token": idToken, "nonce": nonce,
        ])

        let (data, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code),
              let out = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = out["access_token"] as? String else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        adopt(session: out)
        return token
    }

    /// 01 rule 04 · sessions slide 90 days. The refresh token outlives the process in the
    /// Keychain; on the next launch it is traded for a fresh session before anything else
    /// is allowed to sign in, so a real account is never quietly replaced by the demo one.
    /// Returns false when there was nothing to restore or the server refused it.
    func restoreSession() async -> Bool {
        if accessToken != nil { return true }
        guard let stored = SessionKeychain.refreshToken else { return false }
        var r = URLRequest(url: SupabaseConfig.url
            .appendingPathComponent("auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")]))
        r.httpMethod = "POST"
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": stored])
        guard let (data, resp) = try? await session.data(for: r) else { return false }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code),
              let out = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              out["access_token"] is String else {
            // A refused refresh token is dead (used, revoked, or the account is gone);
            // a transport failure is not, and the token is kept for the next try.
            if (400..<500).contains(code) { SessionKeychain.refreshToken = nil }
            return false
        }
        adopt(session: out)
        // A restored session is never a registration, however fresh the account is.
        isNewUser = false
        return true
    }

    /// Every authenticated request gets one bounded recovery from an expired access token.
    /// The refresh operation is single-flight, so a foreground sync's parallel chunk uploads
    /// cannot consume the rotating refresh token several times at once.
    private func authenticatedData(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        let first = try await session.data(for: request)
        guard (first.1 as? HTTPURLResponse)?.statusCode == 401 else { return first }
        guard await refreshExpiredSession() else { return first }
        request.setValue("Bearer \(accessToken ?? SupabaseConfig.publishableKey)",
                         forHTTPHeaderField: "Authorization")
        return try await session.data(for: request)
    }

    private func refreshExpiredSession() async -> Bool {
        let token = refreshToken ?? SessionKeychain.refreshToken
        guard let token else { return false }
        let task: Task<RefreshResult, Never>
        if let running = refreshTask {
            task = running
        } else {
            let session = self.session
            task = Task {
                var request = URLRequest(url: SupabaseConfig.url
                    .appendingPathComponent("auth/v1/token")
                    .appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")]))
                request.httpMethod = "POST"
                request.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": token])
                guard let (data, response) = try? await session.data(for: request) else {
                    return RefreshResult(payload: nil, status: 0)
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                return RefreshResult(payload: payload, status: status)
            }
            refreshTask = task
        }
        let result = await task.value
        refreshTask = nil
        if let payload = result.payload, payload["access_token"] is String {
            adopt(session: payload)
            isNewUser = false
            return true
        }
        if (400..<500).contains(result.status) {
            accessToken = nil
            refreshToken = nil
            userId = nil
            userEmail = nil
            SessionKeychain.refreshToken = nil
            Self.storeSnapshot(userId: nil, userEmail: nil)
        }
        return false
    }

    private struct RefreshResult: @unchecked Sendable {
        let payload: [String: Any]?
        let status: Int
    }

    /// Forget the session on this device. The server's row is revoked when it can be
    /// reached; the Keychain copy goes either way, so the next launch starts at the gate.
    func signOut() async {
        if let token = accessToken {
            var r = URLRequest(url: SupabaseConfig.url.appendingPathComponent("auth/v1/logout"))
            r.httpMethod = "POST"
            r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await session.data(for: r)
        }
        accessToken = nil
        refreshToken = nil
        userId = nil
        userEmail = nil
        SessionKeychain.refreshToken = nil
        Self.storeSnapshot(userId: nil, userEmail: nil)
    }

    /// 01 · 「the server decides new vs returning, not the user」. A session whose account was
    /// created in this very exchange is a first registration — that, and only that, is what
    /// 02M's film plays for. Read off the grant reply, never off a local flag.
    private(set) var isNewUser = false

    /// One place that reads a session reply, whichever grant produced it.
    private func adopt(session out: [String: Any]) {
        accessToken = out["access_token"] as? String
        refreshToken = out["refresh_token"] as? String
        let user = out["user"] as? [String: Any]
        userId = user?["id"] as? String
        userEmail = user?["email"] as? String
        isNewUser = Self.looksLikeFirstRegistration(user)
        SessionKeychain.refreshToken = refreshToken
        Self.storeSnapshot(userId: userId, userEmail: userEmail)
    }

    private nonisolated static func storeSnapshot(userId: String?, userEmail: String?) {
        snapshotLock.lock()
        snapshotUserId = userId
        snapshotUserEmail = userEmail
        snapshotLock.unlock()
    }

    /// GoTrue stamps `last_sign_in_at` with this very grant, so on a first registration it
    /// lands within a breath of `created_at`. A returning address is minutes to months apart.
    private nonisolated static func looksLikeFirstRegistration(_ user: [String: Any]?) -> Bool {
        guard let created = (user?["created_at"] as? String).flatMap(timestamp) else { return false }
        guard let last = (user?["last_sign_in_at"] as? String).flatMap(timestamp) else { return true }
        return abs(last.timeIntervalSince(created)) < 5
    }

    /// GoTrue returns fractional seconds; the plain ISO parser rejects them.
    private nonisolated static func timestamp(_ raw: String) -> Date? {
        let strict = ISO8601DateFormatter()
        strict.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return strict.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
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
        adopt(session: out)
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
        let (data, resp) = try await authenticatedData(for: r)
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
        let (data, resp) = try await authenticatedData(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    /// An insert that leaves rows already there alone. Collected data is insert-only and a
    /// band only accumulates: every sync after the first carried the same ticks again, and
    /// without this the whole 400-row chunk was refused on its first duplicate key — the
    /// new points behind it never arrived. `onConflict` names the key's columns.
    @discardableResult
    func insert(_ table: String, rows: [[String: Any]],
                ignoringDuplicatesOn onConflict: String) async throws -> [[String: Any]] {
        var r = URLRequest(url: SupabaseConfig.url
            .appendingPathComponent("rest/v1/\(table)")
            .appending(queryItems: [URLQueryItem(name: "on_conflict", value: onConflict)]))
        r.httpMethod = "POST"
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(accessToken ?? SupabaseConfig.publishableKey)",
                   forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("resolution=ignore-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        r.httpBody = try JSONSerialization.data(withJSONObject: rows)
        let (data, resp) = try await authenticatedData(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return []
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
        let (data, resp) = try await authenticatedData(for: r)
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
        let (data, resp) = try await authenticatedData(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    /// A PATCH filtered on any column, for tables whose primary key is not `id`.
    @discardableResult
    func patchWhere(_ table: String, column: String, equals value: String,
                    row: [String: Any]) async throws -> [[String: Any]] {
        var r = URLRequest(url: SupabaseConfig.url
            .appendingPathComponent("rest/v1/\(table)")
            .appending(queryItems: [URLQueryItem(name: column, value: "eq.\(value)")]))
        r.httpMethod = "PATCH"
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(accessToken ?? SupabaseConfig.publishableKey)",
                   forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("return=representation", forHTTPHeaderField: "Prefer")
        r.httpBody = try JSONSerialization.data(withJSONObject: row)
        let (data, resp) = try await authenticatedData(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    /// An exact row count, from the Content-Range header rather than by pulling the rows.
    /// ⚠️ 11's delete confirmation counts out what is about to be lost, and counting what
    /// happens to be in memory counts the page size instead — 60 weigh-ins for an account
    /// that has 151.
    func count(_ table: String, query: [URLQueryItem] = []) async -> Int? {
        var r = URLRequest(url: SupabaseConfig.url
            .appendingPathComponent("rest/v1/\(table)")
            .appending(queryItems: query + [URLQueryItem(name: "select", value: "user_id")]))
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(accessToken ?? SupabaseConfig.publishableKey)",
                   forHTTPHeaderField: "Authorization")
        r.setValue("count=exact", forHTTPHeaderField: "Prefer")
        r.setValue("0-0", forHTTPHeaderField: "Range")
        guard let (_, resp) = try? await authenticatedData(for: r),
              let http = resp as? HTTPURLResponse,
              let range = http.value(forHTTPHeaderField: "content-range"),
              let total = range.split(separator: "/").last else { return nil }
        return Int(total)
    }

    /// A PostgREST RPC. F4's eight endpoints are Edge Functions because that is where the
    /// model-facing surface lives; account.delete and export are database work that happens
    /// to be listed among them, and they are reachable this way without a deploy.
    @discardableResult
    func rpc(_ name: String, args: [String: Any] = [:]) async throws -> Any {
        var r = URLRequest(url: SupabaseConfig.url.appendingPathComponent("rest/v1/rpc/\(name)"))
        r.httpMethod = "POST"
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(accessToken ?? SupabaseConfig.publishableKey)",
                   forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: args)
        let (data, resp) = try await authenticatedData(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
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
            ? SupabaseConfig.functionsBase
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
            let (out, resp) = try await authenticatedData(for: req)
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

    /// A multipart POST to an Edge Function. `asr` is the only endpoint that takes a file,
    /// and it wants the clip under the field name `audio`.
    func uploadFunction(_ name: String, fileURL: URL,
                        field: String, filename: String, mime: String) async throws -> [String: Any] {
        let boundary = "nb-\(UUID().uuidString)"
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        append("\r\n--\(boundary)--\r\n")

        var r = try request(name, method: "POST", body: body, isFunction: true)
        // request() sets JSON; multipart has to say its own boundary or the far side sees one
        // undifferentiated blob and answers E_SCHEMA.
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (out, resp) = try await authenticatedData(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(data: out, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: out) as? [String: Any]) ?? [:]
    }

    /// Streams an Edge Function's SSE response line by line.
    /// nonisolated because the stream is consumed on the caller's side: the actor's job is
    /// to build the request, not to hold the connection open for the length of a turn.
    nonisolated func streamFunction(_ name: String, payload: [String: Any]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try JSONSerialization.data(withJSONObject: payload)
                    let req = try await self.request(name, method: "POST", body: data, isFunction: true)
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(code) else {
                        continuation.finish(throwing: Failure.http(code, ""))
                        return
                    }
                    // ⚠️ The event name matters as much as the payload. F4's stream is
                    // state → tool… → screen.render → done, and a reader that keeps only the
                    // data lines cannot tell an envelope from an error's fallback frame.
                    // Each is yielded as "<event>\n<data>".
                    var event = "message"
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            event = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                            continue
                        }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        continuation.yield("\(event)\n\(payload)")
                        event = "message"
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

/// The refresh token, and only that, in the Keychain. The access token is short-lived and
/// stays in memory; the user id and email come back with every refresh.
enum SessionKeychain {
    private static let service = "app.nextbody.hoop.supabase"
    private static let account = "refresh_token"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static var refreshToken: String? {
        get {
            var q = query
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            SecItemDelete(query as CFDictionary)
            guard let value = newValue, let data = value.data(using: .utf8) else { return }
            var q = query
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}
