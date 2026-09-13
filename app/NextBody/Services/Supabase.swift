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

/// The mailbox-free account that carries `supabase/seed/demo.sql`. Simulator walk-through
/// only — a real phone must never land on it, even from a leftover Keychain session.
enum DemoAccount {
    static let email = "demo@nextbody.app"
    static let password = "nextbody-demo"

    static func matches(_ email: String) -> Bool {
        email.lowercased().trimmingCharacters(in: .whitespaces) == Self.email
    }
}

actor SupabaseClient {
    static let shared = SupabaseClient()
    private static let snapshotLock = NSLock()
    private static var snapshotUserId: String?
    private static var snapshotUserEmail: String?
    private static var snapshotSession = RequestSession(owner: nil, generation: UUID())

    private var sessionGeneration = UUID()
    private var requestSession: RequestSession { RequestSession(owner: userId, generation: sessionGeneration) }
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
        // Waiting for the radio to wake used to add seconds to the first Home read.
        // Offline is a snapshot plus a failed fetch, not a 30 s hang.
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()
    /// A turn's SSE stream is silent while the server runs a tool, and the server now
    /// writes a comment line every 15 s to say it is still alive. This session's timeout
    /// is the gap between two bytes, so three missed heartbeats means the connection is
    /// dead, not that the model is slow. The 30 s read session above hung up on every
    /// web-backed meal estimate.
    private let streamSession: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 45
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    func setAccessToken(_ token: String?) {
        sessionGeneration = UUID()
        accessToken = token
        userId = token.flatMap(HomeLaunchPolicy.jwtSubject)
        refreshTask?.cancel()
        refreshTask = nil
        Self.storeSnapshot(userId: userId, userEmail: userEmail, generation: sessionGeneration)
    }

    nonisolated static func currentUserIdSnapshot() -> String? {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshotUserId
    }

    nonisolated static func currentRequestSessionSnapshot() -> RequestSession {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshotSession
    }

    var isSignedIn: Bool { accessToken != nil }

    /// Email + password. The gate's real flow is a six-digit code (`signInWithOtp`);
    /// this path exists so the seeded demo account can be reached without a mailbox.
    @discardableResult
    func signIn(email: String, password: String) async throws -> String {
        let startingGeneration = sessionGeneration
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
        guard sessionGeneration == startingGeneration else { throw CancellationError() }
        adopt(session: out)
        return token
    }

    /// Sign in with Apple. The identity token the system sheet handed back is exchanged for
    /// a session of this project's own (`/auth/v1/token?grant_type=id_token`); the raw nonce
    /// goes along so the server can prove the token was minted for this very request and
    /// not replayed. Nothing about the user reaches us before the server has said yes.
    @discardableResult
    func signInWithApple(idToken: String, nonce: String) async throws -> String {
        try await signInWithIDToken(provider: "apple", idToken: idToken, nonce: nonce)
    }

    @discardableResult
    func signInWithGoogle(idToken: String, nonce: String) async throws -> String {
        try await signInWithIDToken(provider: "google", idToken: idToken, nonce: nonce)
    }

    /// One endpoint for both native providers: the app already holds a signed identity token,
    /// so there is no browser round trip and no client secret — Supabase verifies the
    /// signature, checks the audience against the client ID configured for that provider, and
    /// hashes the raw nonce back to what the token carries. What comes back is an ordinary
    /// session, indistinguishable downstream from the six-digit path.
    private func signInWithIDToken(provider: String, idToken: String, nonce: String) async throws -> String {
        let startingGeneration = sessionGeneration
        var r = URLRequest(url: SupabaseConfig.url
            .appendingPathComponent("auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "id_token")]))
        r.httpMethod = "POST"
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: [
            "provider": provider, "id_token": idToken, "nonce": nonce,
        ])

        let (data, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code),
              let out = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = out["access_token"] as? String else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        guard sessionGeneration == startingGeneration else { throw CancellationError() }
        adopt(session: out)
        return token
    }

    /// Restore a session without waiting on the network when a still-valid access token is
    /// already on this phone. Otherwise the refresh token is traded for a fresh grant.
    /// Returns false when there was nothing to restore or the server refused it.
    func restoreSession() async -> Bool {
        let restoringGeneration = sessionGeneration
        if accessToken != nil { return true }
        #if DEBUG && targetEnvironment(simulator)
        // `SIMCTL_CHILD_NB_DEBUG_REFRESH_TOKEN=<token>` seeds a simulator with a real
        // account's session (minted with the admin magic-link path), so the AI paths can be
        // walked end to end without OTP mail. Simulator only; the keychain is the app's own.
        if SessionKeychain.refreshToken == nil,
           let seeded = ProcessInfo.processInfo.environment["NB_DEBUG_REFRESH_TOKEN"], !seeded.isEmpty {
            SessionKeychain.refreshToken = seeded
        }
        #endif
        if let stored = SessionKeychain.accessToken,
           HomeLaunchPolicy.isAccessTokenUsable(stored),
           let sub = HomeLaunchPolicy.jwtSubject(stored) {
            accessToken = stored
            refreshToken = SessionKeychain.refreshToken
            userId = sub
            userEmail = HomeLaunchPolicy.jwtEmail(stored) ?? SessionKeychain.userEmail
            SessionKeychain.userId = sub
            SessionKeychain.userEmail = userEmail
            Self.storeSnapshot(userId: userId, userEmail: userEmail, generation: sessionGeneration)
            return true
        }
        guard let stored = SessionKeychain.refreshToken else { return false }
        var r = URLRequest(url: SupabaseConfig.url
            .appendingPathComponent("auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")]))
        r.httpMethod = "POST"
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": stored])
        guard let (data, resp) = try? await session.data(for: r) else { return false }
        guard sessionGeneration == restoringGeneration else { return false }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code),
              let out = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              out["access_token"] is String else {
            // A refused refresh token is dead (used, revoked, or the account is gone);
            // a transport failure is not, and the token is kept for the next try.
            if (400..<500).contains(code) {
                SessionKeychain.refreshToken = nil
                SessionKeychain.accessToken = nil
                SessionKeychain.userId = nil
                SessionKeychain.userEmail = nil
            }
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
    private func authenticatedData(for request: URLRequest, expectedOwner: String? = nil) async throws -> (Data, URLResponse) {
        if let expectedOwner, userId != expectedOwner { throw CancellationError() }
        let pinned = requestSession
        return try await SessionBoundTransport.perform(request, session: pinned,
            current: { await self.requestSession },
            send: { [session] in try await session.data(for: $0) },
            refresh: { await self.refreshedToken(for: pinned) })
    }

    private func refreshedToken(for pinned: RequestSession) async -> String? {
        guard requestSession == pinned, await refreshExpiredSession(), requestSession == pinned else { return nil }
        return accessToken
    }

    private func refreshExpiredSession() async -> Bool {
        let pinned = requestSession
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
        guard requestSession == pinned else { return false }
        // Another waiter may already have adopted this rotating refresh token.
        if let current = refreshToken, current != token { return accessToken != nil }
        refreshTask = nil
        if let payload = result.payload, payload["access_token"] is String {
            guard let user = payload["user"] as? [String: Any], user["id"] as? String == pinned.owner else { return false }
            adopt(session: payload, preservingSession: true)
            isNewUser = false
            return true
        }
        if (400..<500).contains(result.status) {
            accessToken = nil
            refreshToken = nil
            userId = nil
            userEmail = nil
            SessionKeychain.refreshToken = nil
            SessionKeychain.accessToken = nil
            SessionKeychain.userId = nil
            SessionKeychain.userEmail = nil
            Self.storeSnapshot(userId: nil, userEmail: nil, generation: sessionGeneration)
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
        await GoogleAuth.signOut()
        let departingToken = accessToken
        sessionGeneration = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        accessToken = nil
        refreshToken = nil
        userId = nil
        userEmail = nil
        SessionKeychain.refreshToken = nil
        SessionKeychain.accessToken = nil
        SessionKeychain.userId = nil
        SessionKeychain.userEmail = nil
        Self.storeSnapshot(userId: nil, userEmail: nil, generation: sessionGeneration)
        if let token = departingToken {
            var r = URLRequest(url: SupabaseConfig.url.appendingPathComponent("auth/v1/logout"))
            r.httpMethod = "POST"
            r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await session.data(for: r)
        }
    }

    /// 01 · 「the server decides new vs returning, not the user」. A session whose account was
    /// created in this very exchange is a first registration — that, and only that, is what
    /// 02M's film plays for. Read off the grant reply, never off a local flag.
    private(set) var isNewUser = false

    /// One place that reads a session reply, whichever grant produced it.
    private func adopt(session out: [String: Any], preservingSession: Bool = false) {
        if !preservingSession {
            sessionGeneration = UUID()
            refreshTask?.cancel()
            refreshTask = nil
        }
        accessToken = out["access_token"] as? String
        refreshToken = out["refresh_token"] as? String
        let user = out["user"] as? [String: Any]
        userId = user?["id"] as? String
        userEmail = user?["email"] as? String
        isNewUser = Self.looksLikeFirstRegistration(user)
        SessionKeychain.refreshToken = refreshToken
        SessionKeychain.accessToken = accessToken
        SessionKeychain.userId = userId
        SessionKeychain.userEmail = userEmail
        Self.storeSnapshot(userId: userId, userEmail: userEmail, generation: sessionGeneration)
    }

    nonisolated static let accountDidChange = Notification.Name("NextBody.accountDidChange")

    nonisolated static let requestSessionDidChange = Notification.Name("NextBody.requestSessionDidChange")

    private nonisolated static func storeSnapshot(userId: String?, userEmail: String?, generation: UUID) {
        snapshotLock.lock()
        let changed = snapshotUserId != userId
        let nextSession = RequestSession(owner: userId, generation: generation)
        let sessionChanged = snapshotSession != nextSession
        snapshotSession = nextSession
        snapshotUserId = userId
        snapshotUserEmail = userEmail
        snapshotLock.unlock()
        if changed { NotificationCenter.default.post(name: accountDidChange, object: nil) }
        if sessionChanged { NotificationCenter.default.post(name: requestSessionDidChange, object: nil) }
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
        let (data, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
    }

    @discardableResult
    func verifyCode(email: String, token: String) async throws -> String {
        let startingGeneration = sessionGeneration
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
        guard sessionGeneration == startingGeneration else { throw CancellationError() }
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
                returning: Bool = true, expectedOwner: String? = nil) async throws -> [[String: Any]] {
        try validateOwner(expectedOwner)
        for row in rows { try validateOwner(row["user_id"] as? String) }
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
                ignoringDuplicatesOn onConflict: String, expectedOwner: String? = nil) async throws -> [[String: Any]] {
        try validateOwner(expectedOwner)
        for row in rows { try validateOwner(row["user_id"] as? String) }
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
    func upsert(_ table: String, row: [String: Any], onConflict: String, expectedOwner: String? = nil) async throws -> [[String: Any]] {
        try validateOwner(expectedOwner ?? row["user_id"] as? String)
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
    func patch(_ table: String, id: String, row: [String: Any], expectedOwner: String? = nil) async throws -> [[String: Any]] {
        try validateOwner(expectedOwner ?? row["user_id"] as? String)
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
                    row: [String: Any], expectedOwner: String? = nil) async throws -> [[String: Any]] {
        try validateOwner(expectedOwner ?? row["user_id"] as? String)
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

    /// A DELETE filtered on one column. RLS keeps it to the caller's own rows; the owner
    /// check keeps a late reply from a previous account out.
    func deleteWhere(_ table: String, column: String, equals value: String, expectedOwner: String? = nil) async throws {
        try validateOwner(expectedOwner)
        var r = URLRequest(url: SupabaseConfig.url
            .appendingPathComponent("rest/v1/\(table)")
            .appending(queryItems: [URLQueryItem(name: column, value: "eq.\(value)")]))
        r.httpMethod = "DELETE"
        r.setValue(SupabaseConfig.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("Bearer \(accessToken ?? SupabaseConfig.publishableKey)",
                   forHTTPHeaderField: "Authorization")
        let (data, resp) = try await authenticatedData(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw Failure.http(code, String(data: data, encoding: .utf8) ?? "")
        }
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
    func rpc(_ name: String, args: [String: Any] = [:], expectedOwner: String? = nil,
             timeout: TimeInterval = 30) async throws -> Any {
        if let expectedOwner, userId != expectedOwner { throw CancellationError() }
        var r = URLRequest(url: SupabaseConfig.url.appendingPathComponent("rest/v1/rpc/\(name)"))
        r.timeoutInterval = timeout
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

    typealias Failure = SupabaseFailure

    private func validateOwner(_ owner: String?) throws {
        if let owner, owner != userId { throw CancellationError() }
    }

    private func request(_ path: String, method: String, body: Data?, isFunction: Bool, expectedOwner: String? = nil) throws -> URLRequest {
        try validateOwner(expectedOwner)
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

    func callFunction(_ name: String, payload: [String: Any], expectedOwner: String? = nil) async throws -> [String: Any] {
        if let expectedOwner, userId != expectedOwner { throw CancellationError() }
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
                        field: String, filename: String, mime: String, requestID: UUID = UUID()) async throws -> [String: Any] {
        let boundary = "nb-\(UUID().uuidString)"
        var body = Data()
        func append(_ s: String) { body.append(Data(s.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(try Data(contentsOf: fileURL))
        append("\r\n--\(boundary)--\r\n")

        var r = SessionBoundTransport.identifying(try request(name, method: "POST", body: body, isFunction: true), requestID: requestID)
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

    /// Opens the authenticated push-to-talk socket before recording begins. Unlike browser
    /// WebSockets, URLSession can carry the normal Authorization header through the upgrade.
    func asrStreamingSession(requestID: UUID = UUID()) throws -> ASRStreamingSession {
        let request = try request("asr", method: "GET", body: nil, isFunction: true)
        return ASRStreamingSession(request: SessionBoundTransport.identifying(request, requestID: requestID))
    }

    private func openStream(_ name: String, payload: [String: Any], expectedOwner: String?, requestID: UUID)
        async throws -> (URLSession.AsyncBytes, RequestSession) {
        try validateOwner(expectedOwner)
        let pinned = requestSession
        let data = try JSONSerialization.data(withJSONObject: payload)
        let base = try request(name, method: "POST", body: data, isFunction: true, expectedOwner: expectedOwner)
        let identified = SessionBoundTransport.identifying(base, requestID: requestID)
        let (bytes, response) = try await SessionBoundTransport.perform(identified, session: pinned,
            current: { await self.requestSession }, send: { [streamSession] in try await streamSession.bytes(for: $0) },
            refresh: { await self.refreshedToken(for: pinned) })
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            var errorBody = Data()
            for try await byte in bytes {
                errorBody.append(byte)
                if errorBody.count >= 16_384 { break }
            }
            throw Failure.http(code, String(data: errorBody, encoding: .utf8) ?? "")
        }
        return (bytes, pinned)
    }

    /// Streams an Edge Function's SSE response line by line.
    /// nonisolated because the stream is consumed on the caller's side: the actor's job is
    /// to build the request, not to hold the connection open for the length of a turn.
    nonisolated func streamFunction(_ name: String, payload: [String: Any], expectedOwner: String? = nil, requestID: UUID = UUID()) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, pinned) = try await self.openStream(name, payload: payload,
                        expectedOwner: expectedOwner, requestID: requestID)
                    // ⚠️ The event name matters as much as the payload. F4's stream is
                    // state → tool… → screen.render → done, and a reader that keeps only the
                    // data lines cannot tell an envelope from an error's fallback frame.
                    // Each is yielded as "<event>\n<data>".
                    var event = "message"
                    for try await line in bytes.lines {
                        guard !Task.isCancelled, await self.requestSession == pinned else { throw CancellationError() }
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
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func signedInEmail() -> String? { userEmail }
}

/// Session material in the Keychain. The refresh token outlives the process; a still-valid
/// access token is kept so the next launch can read today's row without a grant round trip.
enum SessionKeychain {
    private static let service = "app.nextbody.hoop.supabase"

    static var refreshToken: String? {
        get { string(for: "refresh_token") }
        set { set(newValue, account: "refresh_token") }
    }

    static var accessToken: String? {
        get { string(for: "access_token") }
        set { set(newValue, account: "access_token") }
    }

    static var userId: String? {
        get { string(for: "user_id") }
        set { set(newValue, account: "user_id") }
    }

    static var userEmail: String? {
        get { string(for: "user_email") }
        set { set(newValue, account: "user_email") }
    }

    private static func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func string(for account: String) -> String? {
        var q = query(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func set(_ value: String?, account: String) {
        let q = query(account: account)
        SecItemDelete(q as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
