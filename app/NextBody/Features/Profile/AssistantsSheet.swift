import SwiftUI
import UIKit

/// ADR 0032 · ChatGPT, Claude, Cursor or Grok reading this account's own data over MCP.
///
/// The address carries no key. Each assistant signs in through mcp.nextbody.ai and gets its
/// own OAuth grant, so there is nothing secret to copy and every assistant can be cut off on
/// its own. Two records make a connection: Supabase Auth's grant (the refresh token) and our
/// `mcp_grants` row (what the gate checks on every request). Disconnecting removes both, the
/// Auth grant first — the other order leaves a grant that skips consent and then is refused.
struct AssistantsSheet: View {
    static let address = "https://mcp.nextbody.ai/mcp"

    @Environment(\.dismiss) private var dismiss
    @State private var connections: [Connection] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var copied = false
    @State private var busy: Set<String> = []
    @State private var actionFailed = false

    struct Connection: Identifiable, Equatable {
        let id: String
        var name: String
        var canWrite: Bool
        var active: Bool
        var since: Date?
        var lastUsed: Date?
    }

    var body: some View {
        SheetFrame(title: L("AI assistants")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("Let ChatGPT, Claude, Cursor or Grok read your own NextBody data and log meals you describe. Add this address as a connector or MCP server, then sign in with this account."))
                        .font(NBFont.ui(400, 13.5))
                        .foregroundStyle(NB.text1)
                        .fixedSize(horizontal: false, vertical: true)

                    addressCard

                    VStack(alignment: .leading, spacing: 10) {
                        clientStep("CHATGPT", L("Settings › Apps & Connectors › Create. Paste the address."))
                        clientStep("CLAUDE", L("Settings › Connectors › Add custom connector. Paste the address."))
                        clientStep("CURSOR", L("Settings › MCP › Add server. Paste the address as the URL."))
                        clientStep("GROK", L("Settings › Connectors › Add MCP server. Paste the address."))
                    }

                    Text(L("CONNECTED"))
                        .font(NBFont.dot(600, 10)).tracking(0.14 * 10)
                        .foregroundStyle(NB.text3Prod)
                        .padding(.top, 6)

                    connectionList

                    Text(L("Assistants can read your metrics, sleep and meals. Logging meals is off until you turn it on for one. What an assistant reads is sent to its provider."))
                        .font(NBFont.ui(300, 12.5)).tracking(0.02 * 12.5)
                        .foregroundStyle(NB.white.opacity(0.38))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: NB.Layout.contentWidth, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        } footer: {
            LimePillButton(title: L("Done"), enabled: true) { dismiss() }
        }
        .task { await load() }
        .alert(L("Couldn't update the connection"), isPresented: $actionFailed) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(L("Check your connection and try again."))
        }
    }

    private var addressCard: some View {
        Button {
            UIPasteboard.general.string = Self.address
            HoldHaptics.shared.release()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                copied = false
            }
        } label: {
            HStack(spacing: 12) {
                Text("mcp.nextbody.ai/mcp")
                    .font(NBFont.dot(600, 13)).tracking(0.04 * 13)
                    .foregroundStyle(NB.text1)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(copied ? L("COPIED") : L("COPY"))
                    .font(NBFont.dot(600, 11)).tracking(0.14 * 11)
                    .foregroundStyle(NB.lime1)
            }
            .padding(.horizontal, 16)
            .frame(width: NB.Layout.contentWidth, height: 56)
            .cardSkin()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("Copy the MCP address"))
    }

    @ViewBuilder private var connectionList: some View {
        if loading {
            ProgressView()
                .tint(NB.text3Prod)
                .frame(width: NB.Layout.contentWidth, height: 62)
        } else if loadFailed {
            Button { Task { await load() } } label: {
                notice(L("Couldn't load connections. Tap to retry."), tint: NB.ember1)
            }
            .buttonStyle(.plain)
        } else if connections.isEmpty {
            notice(L("Nothing connected yet."), tint: NB.text3Prod)
        } else {
            VStack(spacing: 10) {
                ForEach(connections) { connection in
                    row(connection)
                }
            }
        }
    }

    private func notice(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(NBFont.ui(400, 13))
            .foregroundStyle(tint)
            .padding(.horizontal, 16)
            .frame(width: NB.Layout.contentWidth, height: 56, alignment: .leading)
            .cardSkin()
    }

    private func row(_ connection: Connection) -> some View {
        let working = busy.contains(connection.id)
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(connection.name)
                        .font(NBFont.ui(500, 14)).tracking(0.02 * 14)
                        .foregroundStyle(NB.text1)
                        .lineLimit(1)
                    Text(detail(connection))
                        .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                        .foregroundStyle(connection.active ? NB.text3Prod : NB.ember1)
                }
                Spacer(minLength: 0)
                Button(L("DISCONNECT")) { Task { await disconnect(connection) } }
                    .font(NBFont.dot(600, 10)).tracking(0.14 * 10)
                    .foregroundStyle(NB.ember1)
                    .buttonStyle(.plain)
                    .disabled(working)
            }
            .padding(.horizontal, 16).frame(height: 62)

            if connection.active {
                Hairline().padding(.leading, 16)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("Log meals"))
                            .font(NBFont.ui(500, 14)).tracking(0.02 * 14)
                            .foregroundStyle(NB.text1)
                        Text(L("WRITES TO YOUR FOOD LOG"))
                            .font(NBFont.dot(500, 10)).tracking(0.14 * 10)
                            .foregroundStyle(NB.text3Prod)
                    }
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { connection.canWrite },
                        set: { value in Task { await setWrite(connection, value) } }
                    ))
                    .labelsHidden()
                    .tint(NB.lime1)
                    .disabled(working)
                }
                .padding(.horizontal, 16).frame(height: 62)
            }
        }
        .frame(width: NB.Layout.contentWidth)
        .cardSkin()
        .opacity(working ? 0.5 : 1)
    }

    private func clientStep(_ client: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(client)
                .font(NBFont.dot(600, 10)).tracking(0.14 * 10)
                .foregroundStyle(NB.lime1)
                .frame(width: 64, alignment: .leading)
                .padding(.top, 2)
            Text(text)
                .font(NBFont.ui(400, 13))
                .foregroundStyle(NB.text1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func detail(_ connection: Connection) -> String {
        guard connection.active else { return L("NOT ACTIVE · DISCONNECT TO RESET") }
        if let used = connection.lastUsed {
            return L("LAST USED %@", Fmt.displayDate(used, format: "MMM d").uppercased())
        }
        if let since = connection.since {
            return L("CONNECTED %@", Fmt.displayDate(since, format: "MMM d").uppercased())
        }
        return L("CONNECTED")
    }

    /// Union of the two records. An Auth grant with no live row is shown paused; a live row
    /// whose Auth grant is gone still holds an access token for up to an hour, so it stays
    /// listed until it is disconnected here.
    private func load() async {
        loading = connections.isEmpty
        loadFailed = false
        do {
            async let authGrants = SupabaseClient.shared.oauthGrants()
            async let rows = SupabaseClient.shared.select("mcp_grants", query: [
                URLQueryItem(name: "select", value: "client_id,client_name,can_write,granted_at,revoked_at,last_used_at"),
            ])
            let (grants, grantRows) = try await (authGrants, rows)
            var merged: [String: Connection] = [:]
            for grant in grants {
                let client = grant["client"] as? [String: Any]
                guard let id = (client?["id"] as? String) ?? (grant["client_id"] as? String) else { continue }
                let name = (client?["name"] as? String) ?? (grant["client_name"] as? String) ?? id
                let since = (grant["granted_at"] as? String).flatMap(HealthSnapshotRead.timestamp)
                merged[id] = Connection(id: id, name: name, canWrite: false, active: false, since: since, lastUsed: nil)
            }
            for row in grantRows {
                guard let id = row["client_id"] as? String, row["revoked_at"] is NSNull || row["revoked_at"] == nil else { continue }
                var connection = merged[id] ?? Connection(id: id, name: id, canWrite: false, active: false, since: nil, lastUsed: nil)
                if let name = row["client_name"] as? String, !name.isEmpty { connection.name = name }
                connection.canWrite = row["can_write"] as? Bool ?? false
                connection.active = true
                connection.since = connection.since ?? (row["granted_at"] as? String).flatMap(HealthSnapshotRead.timestamp)
                connection.lastUsed = (row["last_used_at"] as? String).flatMap(HealthSnapshotRead.timestamp)
                merged[id] = connection
            }
            connections = merged.values.sorted {
                ($0.lastUsed ?? $0.since ?? .distantPast) > ($1.lastUsed ?? $1.since ?? .distantPast)
            }
        } catch {
            loadFailed = true
        }
        loading = false
    }

    private func setWrite(_ connection: Connection, _ value: Bool) async {
        busy.insert(connection.id)
        defer { busy.remove(connection.id) }
        do {
            _ = try await SupabaseClient.shared.rpc("set_mcp_grant_write", args: [
                "p_client_id": connection.id, "p_can_write": value,
            ])
            if let i = connections.firstIndex(where: { $0.id == connection.id }) {
                connections[i].canWrite = value
            }
        } catch {
            actionFailed = true
        }
    }

    private func disconnect(_ connection: Connection) async {
        busy.insert(connection.id)
        defer { busy.remove(connection.id) }
        do {
            try await SupabaseClient.shared.revokeOAuthGrant(clientId: connection.id)
            _ = try await SupabaseClient.shared.rpc("revoke_mcp_grant", args: ["p_client_id": connection.id])
            connections.removeAll { $0.id == connection.id }
        } catch {
            actionFailed = true
        }
    }
}
