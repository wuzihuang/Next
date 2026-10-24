package com.nextbody.hoop.design

import com.nextbody.hoop.l10n.L

/**
 * F0 law 02 · 「指标名做成 token，不许硬编在组件里。全部从一处读 (METRIC_NAMES)。」 Every metric
 * name the product says out loud lives here, so renaming one is a one-line change.
 * Display names only — the wire keeps its own vocabulary.
 */
object MetricNames {
    /** Was "Recovery" until F0 §02 renamed it. */
    val bodyBattery: String get() = L("READINESS")
    /** Was "Strain". */
    val trainingLoad: String get() = L("TRAINING LOAD")
    val training: String get() = L("TRAINING")
    val calories: String get() = L("CALORIES")
}
