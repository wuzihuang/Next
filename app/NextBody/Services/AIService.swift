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

    /// The tool she is reading right now, while she reads it. 07 · 16 · the panel says what
    /// it is doing instead of showing a spinner over an empty box.
    @Published var reading: String?

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
            // ⚠️ `turn` streams. It had been called as though it returned one JSON object,
            // so the parse threw on the very first `event:` line and every server turn —
            // including the ones the server logged as OK — fell through to the offline
            // frame. The DEBUG path masked it by answering in its place.
            var frame: [String: Any]?
            for try await chunk in SupabaseClient.shared.streamFunction("turn", payload: [
                "text": text, "dayKey": dayKey,
            ]) {
                let parts = chunk.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2,
                      let data = parts[1].data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { continue }

                switch String(parts[0]) {
                case "tool":
                    // 07 · 16 · she names what she is reading while she reads it.
                    if let name = obj["name"] as? String { reading = name }
                case "screen.render":
                    frame = obj["envelope"] as? [String: Any]
                case "error":
                    // A degraded frame is still a frame — S4's absence law, not a failure.
                    if let fb = obj["fallback_frame"] as? [String: Any], frame == nil { frame = fb }
                    if let reason = obj["reason"] as? String { lastError = reason }
                default:
                    break
                }
            }
            reading = nil
            if let frame { return widget(from: frame) }
        } catch {
            reading = nil
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
                store.applyMacros(entry.id, protein: Int(numberOf(out["protein_g"]) ?? 0),
                                  carb: Int(numberOf(out["carb_g"]) ?? 0), fat: Int(numberOf(out["fat_g"]) ?? 0))
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

    /// 05 · C · a plate and a caption go as one message. The photo never lands on the page: it
    /// comes back as the source chip on the answer. The meal is logged the way a typed one is.
    func photoMeal(image: UIImage, dataURL: String, caption: String, slot: MealEntry.Slot,
                   into store: DataStore) async -> PanelWidget? {
        let entry = MealEntry(id: UUID(), day: UserDay.containing(Date()), at: Date(), slot: slot,
                              status: .confirmed, text: caption, kcal: 0, protein: 0, carb: 0, fat: 0, source: .typed)
        do {
            let out = try await SupabaseClient.shared.callFunction("meal", payload: [
                "text": caption, "slot": slot.rawValue, "locale": "zh-CN", "image": dataURL,
            ])
            guard let kcal = numberOf(out["kcal"]) else { lastError = "\(out["error"] ?? "MODEL_UNAVAILABLE")"; return nil }
            let name = out["name"] as? String ?? caption
            let protein = Int(numberOf(out["protein_g"]) ?? 0)
            store.logMeal(entry)
            store.updateMeal(entry.id, kcal: kcal, text: name)
            store.applyMacros(entry.id, protein: protein,
                              carb: Int(numberOf(out["carb_g"]) ?? 0), fat: Int(numberOf(out["fat_g"]) ?? 0))
            let target = store.today.protein?.target ?? 0
            let eaten = store.today.protein?.eaten ?? protein
            let left = max(0, target - eaten)
            let pulled = target > 0
                ? "Pulled from photo — PRO \(eaten)/\(target) g · \(left) g still to place"
                : "Pulled from photo — \(protein) g protein · \(Fmt.kcal(kcal)) kcal"
            let footer = target > 0
                ? (left == 0 ? "PROTEIN IS CLOSED FOR TODAY" : "\(left) G STILL TO PLACE")
                : "\(Fmt.kcal(kcal)) KCAL ON THE PLATE"
            return PanelWidget(
                type: .meal, title: "FROM YOUR PHOTO", tag: .fuel,
                sentence: (out["answer"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "\(protein) g protein on that plate.",
                footer: footer, action: nil, targetOverride: .fuel,
                data: .rows([.init(label: name, value: Fmt.kcal(kcal))]),
                photo: PhotoAnswer(thumbnail: image, chip: "IMG · PLATE · PARSED OK", quote: caption,
                                   pulled: pulled, logged: "LOGGED TO TODAY'S FUEL"))
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// 05 · speech in, one sentence out. The clip goes to `asr` and is deleted the moment the
    /// transcript is back; nothing about the audio outlives the turn.
    ///
    /// `NO_SPEECH` is not an error to apologise for — the board's word for it is
    /// 「DIDN'T CATCH THAT」 and the dock simply returns to idle. Silence and a refusal look the
    /// same from here on purpose: both mean there is nothing to say yet.
    func transcribe(_ clip: URL) async -> String? {
        defer { try? FileManager.default.removeItem(at: clip) }
        do {
            let out = try await SupabaseClient.shared.uploadFunction(
                "asr", fileURL: clip, field: "audio", filename: "clip.m4a", mime: "audio/m4a")
            if out["error"] != nil { return nil }
            let text = (out["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (text?.isEmpty == false) ? text : nil
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    // MARK: envelope decoding

    func widget(from env: [String: Any]) -> PanelWidget? {
        guard let typeRaw = env["type"] as? String,
              let type = PanelType(rawValue: typeRaw),
              let title = env["title"] as? String,
              let sentence = env["sentence"] as? String else { return nil }
        // ⚠️ F0 rule 03 · sleep never reaches the screen. The render tool no longer offers
        // the three sleep types, and a frame that carries one anyway is dropped here rather
        // than drawn — one lock on each side of the wire.
        guard !type.isSleepWidget else { return nil }

        // F0 rule 06 · no target, no screen. The server states this on the Envelope schema and
        // enforces it on its own fixed frames; enforcing it here too means a malformed frame is
        // dropped rather than drawn with a destination this side invented.
        guard let targetRaw = env["target"] as? String,
              let target = Destination(envelopeTarget: targetRaw) else { return nil }

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
            hero: ((env["data"] as? [String: Any])?["hero"]).map { "\($0)" },
            accentOverride: accent,
            targetOverride: target,
            data: Self.decodeData(env["data"] as? [String: Any] ?? [:], type: type),
            ttlMinutes: (env["ttl_min"] as? Int) ?? 20,
            priority: (env["priority"] as? String) == "alert" ? .alert : .normal)
    }

    /// ⚠️ Tolerant on purpose, in both directions. The contract's shape is pairs —
    /// `bins[[label, v]]`, `series[[t, v]]` — and a model reaching for clarity sends
    /// `points: [{label, value}]` instead. Insisting on one form meant a frame whose
    /// sentence and footer were perfectly correct drew an empty panel with a 0 in it, which
    /// is a worse outcome than reading both. The tool schema now states the contract; this
    /// reads whichever arrives.
    private static func numbers(_ any: Any?) -> [Double] {
        guard let rows = any as? [Any] else { return [] }
        return rows.compactMap { row in
            if let n = row as? Double { return n }
            if let n = row as? Int { return Double(n) }
            if let pair = row as? [Any] { return (pair.last as? Double) ?? (pair.last as? Int).map(Double.init) }
            if let obj = row as? [String: Any] {
                for k in ["value", "v", "y", "kcal", "load", "level", "minutes"] {
                    if let n = obj[k] as? Double { return n }
                    if let n = obj[k] as? Int { return Double(n) }
                }
            }
            return nil
        }
    }

    private static func labelled(_ any: Any?) -> [(String, Double)] {
        guard let rows = any as? [Any] else { return [] }
        return rows.enumerated().compactMap { i, row in
            if let pair = row as? [Any], pair.count >= 2 {
                let v = (pair[1] as? Double) ?? (pair[1] as? Int).map(Double.init)
                return v.map { ("\(pair[0])", $0) }
            }
            if let obj = row as? [String: Any] {
                let label = (obj["label"] as? String) ?? (obj["dayKey"] as? String)
                    ?? (obj["slot"] as? String) ?? (obj["name"] as? String) ?? "\(i + 1)"
                for k in ["value", "v", "y", "kcal", "load", "minutes"] {
                    if let n = obj[k] as? Double { return (label, n) }
                    if let n = obj[k] as? Int { return (label, Double(n)) }
                }
            }
            return nil
        }
    }

    static func decodeData(_ d: [String: Any], type: PanelType) -> PanelData {
        switch type.renderer {
        case .curve:
            let s = numbers(d["series"] ?? d["points"] ?? d["samples"])
            return .series(s)
        case .pair:
            return .pair(hi: numbers(d["hi"] ?? d["a"]), lo: numbers(d["lo"] ?? d["b"]))
        case .column:
            return .bins(labelled(d["bins"] ?? d["points"] ?? d["days"] ?? d["series"]))
        case .arc:
            let v = ["value", "level", "current", "load"].compactMap { key -> Double? in
                (d[key] as? Double) ?? (d[key] as? Int).map(Double.init)
            }.first ?? 0
            let goal = ["goal", "target", "max"].compactMap { key -> Double? in
                (d[key] as? Double) ?? (d[key] as? Int).map(Double.init)
            }.first ?? 100
            return .ring(value: v, goal: goal, unit: (d["unit"] as? String) ?? "")
        case .stack:
            let source = d["parts"] ?? d["macros"] ?? d["rows"]
            let parts = labelled(source).enumerated().map { i, p in
                (p.0, p.1, [NB.cyan1, NB.violet1, NB.optimal2, NB.ember1][i % 4])
            }
            return .parts(parts)
        case .grid:
            let cells = (d["cells"] as? [[Int]])?.flatMap { $0 }
                ?? (d["cells"] as? [Int])
                ?? numbers(d["grid"] ?? d["points"]).map { Int($0) }
                ?? []
            return .cells(rows: (d["rows"] as? Int) ?? 7, cols: (d["cols"] as? Int) ?? 12,
                          values: cells, levels: (d["scale"] as? Int) ?? 4)
        case .strip:
            let stages = numbers(d["minutes"] ?? d["stages"] ?? d["zones"])
            return .strip(stages.enumerated().map { ($0.offset, $0.element) })
        case .trace:
            return .trace(samples: numbers(d["samples"] ?? d["series"]),
                          hz: (d["hz"] as? Double) ?? 125)
        case .rows:
            let raw = (d["rows"] ?? d["items"] ?? d["logged"] ?? d["events"] ?? d["points"])
            let rows = (raw as? [[String: Any]])?.map { r -> PanelData.RowItem in
                let label = (r["label"] as? String) ?? (r["name"] as? String)
                    ?? (r["slot"] as? String) ?? (r["dayKey"] as? String) ?? ""
                let value = r["value"] ?? r["kcal"] ?? r["v"] ?? r["minutes"] ?? ""
                return PanelData.RowItem(label: label, value: "\(value)",
                                         spark: numbers(r["spark"]).isEmpty ? nil : numbers(r["spark"]))
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
