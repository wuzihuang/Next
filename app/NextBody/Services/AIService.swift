import Foundation
import SwiftUI

/// The agent side. In production every AI call is an Edge Function on Supabase running the
/// Vercel AI SDK against qwen3.8-flash; the app never talks to a model directly and never
/// holds a model key.
///
/// ⚠️ DEBUG only: when the Edge Functions have not been deployed yet, the same prompt,
/// the same envelope contract and the same validators run here against the DashScope
/// endpoint, so the flow is demonstrable on a simulator. The frame it produces is marked
/// provisional and it is compiled out of release builds.
@MainActor
final class AIService: ObservableObject {
    static let shared = AIService()

    @Published var lastError: String?
    @Published var dailyCallsUsed = 0
    @Published var thinking = false

    /// F4 · the app is free forever, so the cost ceiling is a rate limit, not a paywall.
    let hourlyCap = 60
    let dailyCap = 150

    // MARK: a conversational turn

    func turn(_ text: String, day: UserDay, store: DataStore) async -> PanelWidget? {
        guard dailyCallsUsed < dailyCap else {
            lastError = "今天的对话次数用完了，明天 04:00 重置。"
            return nil
        }
        dailyCallsUsed += 1
        thinking = true
        defer { thinking = false }

        let dayKey = Self.dayFormatter.string(from: day.start)

        do {
            let out = try await SupabaseClient.shared.callFunction("turn", payload: [
                "text": text, "dayKey": dayKey,
            ])
            if let envelope = out["envelope"] as? [String: Any] {
                return widget(from: envelope)
            }
            if let fallback = (out["fallback_frame"] as? [String: Any]) {
                return widget(from: fallback)
            }
        } catch {
            #if DEBUG
            if let local = await debugTurn(text, day: day, store: store) { return local }
            #endif
            lastError = error.localizedDescription
        }
        return offlineFrame(text)
    }

    /// Turns "半碗面加一个鸡蛋" into a logged meal.
    @discardableResult
    func estimate(entry: MealEntry, into store: DataStore) async -> PanelWidget? {
        do {
            let out = try await SupabaseClient.shared.callFunction("meal", payload: [
                "text": entry.text,
                "slot": entry.slot.rawValue,
                "locale": "zh-CN",
            ])
            if let kcal = numberOf(out["kcal"]) {
                store.updateMeal(entry.id, kcal: kcal, text: out["name"] as? String ?? entry.text)
                return loggedFrame(name: out["name"] as? String ?? entry.text, kcal: kcal, store: store)
            }
        } catch {
            #if DEBUG
            if let local = await debugEstimate(entry: entry, into: store) { return local }
            #endif
            lastError = error.localizedDescription
        }
        return offlineFrame(entry.text)
    }

    // MARK: envelope decoding

    func widget(from env: [String: Any]) -> PanelWidget? {
        guard let typeRaw = env["type"] as? String,
              let type = PanelType(rawValue: typeRaw),
              let title = env["title"] as? String,
              let sentence = env["sentence"] as? String else { return nil }

        var accent: Color?
        if let hex = env["accent"] as? String, hex.hasPrefix("#"),
           let v = UInt32(hex.dropFirst(), radix: 16) { accent = Color(hex: v) }

        return PanelWidget(
            type: type,
            title: String(title.prefix(18)),
            tag: (env["tag"] as? String).flatMap(PanelTag.init(rawValue:)),
            sentence: String(sentence.prefix(48)),
            footer: (env["footer"] as? String).map { String($0.prefix(42)) },
            action: (env["action"] as? String).map { String($0.prefix(32)) },
            accentOverride: accent,
            data: Self.decodeData(env["data"] as? [String: Any] ?? [:], type: type),
            ttlMinutes: (env["ttl_min"] as? Int) ?? 20,
            priority: (env["priority"] as? String) == "alert" ? .alert : .normal)
    }

    static func decodeData(_ d: [String: Any], type: PanelType) -> PanelData {
        switch type.renderer {
        case .curve:
            let s = (d["series"] as? [[Double]])?.compactMap { $0.last }
                ?? (d["series"] as? [Double]) ?? []
            return .series(s)
        case .pair:
            return .pair(hi: (d["hi"] as? [[Double]])?.compactMap { $0.last } ?? [],
                         lo: (d["lo"] as? [[Double]])?.compactMap { $0.last } ?? [])
        case .column:
            let bins = (d["bins"] as? [[Any]])?.compactMap { row -> (String, Double)? in
                guard row.count >= 2, let v = row[1] as? Double else { return nil }
                return ("\(row[0])", v)
            } ?? []
            return .bins(bins)
        case .arc:
            return .ring(value: (d["value"] as? Double) ?? (d["level"] as? Double) ?? 0,
                         goal: (d["goal"] as? Double) ?? 100,
                         unit: (d["unit"] as? String) ?? "")
        case .stack:
            let parts = (d["parts"] as? [[String: Any]])?.enumerated().map { i, p in
                (p["label"] as? String ?? "",
                 (p["min"] as? Double) ?? (p["kcal"] as? Double) ?? 0,
                 [NB.cyan1, NB.violet1, NB.optimal2, NB.ember1][i % 4])
            } ?? []
            return .parts(parts)
        case .grid:
            let cells = (d["cells"] as? [[Int]])?.flatMap { $0 } ?? []
            return .cells(rows: (d["rows"] as? Int) ?? 7, cols: (d["cols"] as? Int) ?? 12,
                          values: cells, levels: (d["scale"] as? Int) ?? 4)
        case .strip:
            let stages = (d["minutes"] as? [Double]) ?? []
            return .strip(stages.enumerated().map { ($0.offset, $0.element) })
        case .trace:
            return .trace(samples: (d["samples"] as? [Double]) ?? [], hz: (d["hz"] as? Double) ?? 125)
        case .rows:
            let rows = (d["rows"] as? [[String: Any]])?.map {
                PanelData.RowItem(label: $0["label"] as? String ?? "",
                                  value: "\($0["value"] ?? "")",
                                  spark: $0["spark"] as? [Double])
            } ?? []
            return .rows(rows)
        case .number:
            return .none
        }
    }

    // MARK: honest failure

    /// Offline the app still has to say something true: it logs the words and does not
    /// invent a number.
    private func offlineFrame(_ text: String) -> PanelWidget {
        PanelWidget(type: .text, title: "OFFLINE", tag: .fuel,
                    sentence: "记下了，等联网再算成 kcal。",
                    footer: String(text.prefix(42)), action: nil, data: .none)
    }

    private func loggedFrame(name: String, kcal: Double, store: DataStore) -> PanelWidget {
        let left = store.today.nextMeal
        return PanelWidget(
            type: .meal, title: "LOGGED", tag: .fuel,
            sentence: "\(Fmt.kcal(kcal)) KCAL。剩 \(Fmt.kcal(left))。",
            footer: String(name.prefix(42)), action: "OPEN FUEL",
            data: .rows([.init(label: name, value: Fmt.kcal(kcal))]))
    }

    private func numberOf(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
}
