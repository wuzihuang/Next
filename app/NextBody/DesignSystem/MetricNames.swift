import Foundation

/// F0 law 02 · 「指标名做成 token，不许硬编在组件里。全部从一处读 (METRIC_NAMES)。改一个指标名的
/// 成本必须是改一行。」 Every metric name the product says out loud lives here, so renaming one is
/// a one-line change rather than a grep across every view.
///
/// ⚠️ Display names only, and that boundary is F3's ruling rather than a convenience:
/// 「显示名走 METRIC_NAMES，存储层用中性名，法律 01 的「字面一致」只约束界面文案与板上文字」.
/// The wire keeps its own vocabulary — `reserve_*` in Postgres, and DEFICIT / LEVEL / SURPLUS as
/// `DailyDirection`'s raw values, which are parsed from the server and must not move when a
/// label does. Renaming a column is the expensive kind of rename; renaming a label is this file.
enum MetricNames {
    /// Was "Recovery" until F0 §02 renamed it. 08's card reads BODY BATTERY DECIDES IT because
    /// of that rename, and nothing may reintroduce the old word.
    static let bodyBattery = "BODY BATTERY"

    /// Was "Strain". The full name is the metric; `training` is the short form board 04 prints
    /// on the 174 × 136 card, where the long one does not fit. Two spellings of one concept,
    /// both drawn from the boards — not a sixth synonym.
    static let trainingLoad = "TRAINING LOAD"
    static let training = "TRAINING"

    static let calories = "CALORIES"

    /// Daily Direction's three buckets, as 11's legend prints them.
    static let deficit = "DEFICIT"
    static let level = "LEVEL"
    static let surplus = "SURPLUS"
}
