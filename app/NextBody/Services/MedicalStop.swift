import Foundation

/// S7 · the medical stop, in a file that is compiled into every build.
///
/// ⚠️ It used to live only inside `AIDebugTurn`, which is wrapped in `#if DEBUG`, and only on
/// the turn path. Two holes came out of that. A release build had no client-side stop at all,
/// and — on either build — the dock's food classifier looks for the marker 吃, which 吃药
/// contains. So "我最近头晕是什么症状要吃药吗" was read as food, written to `meals` before the
/// model was ever called, and came back rendered as `LOGGED · 1 KCAL`. The board's rule is that
/// the stop happens *before any tool call*; that has to mean before the classifier too, because
/// the classifier is what decides which tool runs.
enum MedicalStop {
    /// The same list the server holds in `turn/index.ts`. Both sides check, because either
    /// side alone leaves a path open: the server never sees a turn the client routes to
    /// `meal`, and the client is not the place to trust a rule this one matters.
    private static let pattern = try! NSRegularExpression(
        pattern: "(诊断|症状|吃药|用药|疾病|怀孕|安全吗|癌|糖尿病|高血压|抑郁|medicine|diagnos|pregnan|symptom)",
        options: [.caseInsensitive])

    static func matches(_ text: String) -> Bool {
        pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// S7's fixed frame. It is a legal envelope like any other — the panel never goes empty.
    static var frame: PanelWidget {
        PanelWidget(type: .text, title: "NOT A DOCTOR", tag: .alert,
                    sentence: "这类问题请找医生。这块屏只报告测量到的数字。",
                    footer: "NEXTBODY IS NOT A MEDICAL DEVICE",
                    action: nil, data: .none, priority: .alert)
    }
}
