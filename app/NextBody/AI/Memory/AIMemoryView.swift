import SwiftUI

/// ADR 0018 · what the AI remembers about this person: one summary paragraph and dated
/// facts, written by the summarizer after each session. Visible here, erasable in one tap;
/// withdrawing consent or deleting the account erases it without a visit.
struct AIMemoryView: View {
    @EnvironmentObject private var router: Router

    @State private var summary: String = ""
    @State private var facts: [(text: String, at: String, source: String)] = []
    @State private var updatedAt: String?
    @State private var loading = true
    @State private var errorLine: String?
    @State private var confirmingClear = false

    var body: some View {
        DetailScroll(glow: NB.lime1, title: L("AI MEMORY")) {
            Text(facts.isEmpty && summary.isEmpty ? L("NOTHING YET") : L("%d FACTS", facts.count))
                .font(NBFont.dot(500, 12)).tracking(0.04 * 12)
                .foregroundStyle(NB.macroValue)
        } content: {
            VStack(alignment: .leading, spacing: 16) {
                if loading {
                    Text(L("READING…"))
                        .font(NBFont.dot(500, 12)).tracking(0.16 * 12)
                        .foregroundStyle(NB.text3Prod)
                        .padding(.top, 24)
                } else if let errorLine {
                    Text(errorLine)
                        .font(NBFont.ui(400, 14))
                        .foregroundStyle(NB.text2)
                        .padding(.top, 24)
                } else if summary.isEmpty && facts.isEmpty {
                    empty
                } else {
                    if !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("WHO YOU ARE"))
                                .font(NBFont.dot(600, 10)).tracking(0.24 * 10)
                                .foregroundStyle(NB.lime1.opacity(0.7))
                            Text(summary)
                                .font(NBFont.ui(400, 15))
                                .foregroundStyle(NB.text1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSkin()
                    }
                    if !facts.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(fact.at)
                                        .font(NBFont.dot(500, 11)).tracking(0.06 * 11)
                                        .foregroundStyle(NB.text3Prod)
                                        .frame(width: 84, alignment: .leading)
                                    Text(fact.text)
                                        .font(NBFont.ui(400, 14))
                                        .foregroundStyle(NB.text1)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 16)
                                Divider().overlay(NB.carbon4)
                            }
                        }
                        .cardSkin()
                    }
                    if let updatedAt {
                        Text(L("UPDATED %@", updatedAt))
                            .font(NBFont.dot(500, 11)).tracking(0.12 * 11)
                            .foregroundStyle(NB.text3Prod)
                    }
                    Button { confirmingClear = true } label: {
                        Text(L("CLEAR MEMORY"))
                            .font(NBFont.dot(700, 13)).tracking(0.16 * 13)
                            .foregroundStyle(NB.alert2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(HotZoneTap())
                    .accessibilityIdentifier("memory.clear")
                }
                Text(L("Memory is what the AI keeps from earlier conversations: stable facts like injuries, food you avoid, and goals. It never stores your measurements. It is erased when you withdraw consent or delete your account."))
                    .font(NBFont.ui(400, 12))
                    .foregroundStyle(NB.text3Prod)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        } onBack: {
            router.back()
        }
        .task { await load() }
        .alert(L("Clear everything the AI remembers?"), isPresented: $confirmingClear) {
            Button(L("CLEAR"), role: .destructive) { Task { await clear() } }
            Button(L("CANCEL"), role: .cancel) {}
        } message: {
            Text(L("The next conversations start from nothing."))
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("NOTHING YET"))
                .font(NBFont.brand(700, 22)).tracking(em: -0.03, size: 22)
                .foregroundStyle(NB.text1)
            Text(L("After a conversation ends, what matters from it lands here."))
                .font(NBFont.ui(400, 14))
                .foregroundStyle(NB.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 24)
    }

    private func load() async {
        #if DEBUG
        if DebugEdge.on("empty") {
            loading = false
            summary = ""
            facts = []
            errorLine = nil
            return
        }
        #endif
        loading = true
        defer { loading = false }
        do {
            let rows = try await SupabaseClient.shared.select("user_memory", query: [
                URLQueryItem(name: "select", value: "summary,facts,updated_at"),
                URLQueryItem(name: "limit", value: "1"),
            ])
            guard let row = rows.first else { summary = ""; facts = []; return }
            summary = row["summary"] as? String ?? ""
            facts = ((row["facts"] as? [[String: Any]]) ?? []).compactMap { f in
                guard let text = f["text"] as? String else { return nil }
                return (text: text, at: f["at"] as? String ?? "", source: f["source"] as? String ?? "")
            }.sorted { $0.at > $1.at }
            updatedAt = (row["updated_at"] as? String).map { String($0.prefix(10)) }
        } catch {
            errorLine = L("Could not load memory. Please try again.")
        }
    }

    private func clear() async {
        do {
            _ = try await SupabaseClient.shared.rpc("forget_user_memory")
            summary = ""
            facts = []
            updatedAt = nil
        } catch {
            errorLine = L("Could not clear memory. Please try again.")
        }
    }
}
