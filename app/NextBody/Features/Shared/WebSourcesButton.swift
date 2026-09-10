import SwiftUI

struct WebReference: Identifiable, Hashable {
    var id: URL { url }
    let title: String
    let url: URL
}

extension PanelWidget {
    var webSources: [WebReference] {
        guard let envelopeData,
              let envelope = try? JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
              let data = envelope["data"] as? [String: Any],
              let rows = data["web_sources"] as? [[String: Any]] else { return [] }
        var seen = Set<URL>()
        return rows.prefix(12).compactMap { row in
            guard let text = row["url"] as? String, let url = URL(string: text),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil, url.user == nil, url.password == nil,
                  seen.insert(url).inserted else { return nil }
            return WebReference(title: String((row["title"] as? String ?? url.host ?? "").prefix(160)), url: url)
        }
    }
}

struct WebSourcesButton: View {
    let sources: [WebReference]
    @State private var showingSources = false

    var body: some View {
        if !sources.isEmpty {
            Button { showingSources = true } label: {
                Label(L("Sources"), systemImage: "link")
                    .font(NBFont.ui(500, 12))
                    .foregroundStyle(NB.text2)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(NB.panelInk.opacity(0.95), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("ai.web-sources")
            .sheet(isPresented: $showingSources) {
                NavigationStack {
                    List(sources) { source in
                        Link(destination: source.url) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title)
                                Text(source.url.host ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .navigationTitle(L("Sources"))
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(L("Done")) { showingSources = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }
}
