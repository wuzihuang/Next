package com.nextbody.hoop.model

import com.nextbody.hoop.l10n.L
import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID

/**
 * ADR 0010 · 一次**成功完成**的主动测量留下的一行。
 *
 * 主动测量 = 用户从加号菜单发起、手指按住侧键、有开始有结束的一次手环测量。第一版只有两种：
 * 身体扫描（30 秒 BIA）与平衡检查（40 秒脉律）。被动 tick（心率、压力、皮温）不是主动测量，
 * 体重录入是记录不是测量——两者都不进这个类型。
 *
 * ⚠️ 失败、没读到、中途摘表的尝试不产生记录。测量屏上那句 NOTHING KEPT 是字面意思，这里
 * 没有「失败的一行」这种东西可以构造。
 *
 * Port note: Swift's `Detail` enum (`.bodyScan(BodyScan)` / `.balanceCheck(BalanceCheck)`)
 * is a sealed interface the two payload types implement directly: `when (detail) { is BodyScan -> }`.
 */
data class MeasurementRecord(
    val id: UUID,
    val at: Instant,
    val detail: Detail,
) {
    sealed interface Detail

    /** 手环 BIA 的一次读数。落在 `body_composition` 里 `measurement_source = device_bia` 的行；
     *  health_scale 与 manual 的行不是主动测量，不进清单。 */
    data class BodyScan(
        var bodyFatPercent: Double? = null,
        var fatMassKg: Double? = null,
        var leanMassKg: Double? = null,
        var bmrKcal: Int? = null,
        /** ⚠️ 手环不产生体重。BIA 是拿我们通过 syncPersonalInfo 推下去的体重算出来的，所以
         *  这个数必须和它的来源一起显示，否则读起来像手环称出来的。 */
        var inputWeightKg: Double? = null,
        var muscleMassKg: Double? = null,
        var bodyWaterPercent: Double? = null,
        var boneMassKg: Double? = null,
        var proteinPercent: Double? = null,
    ) : Detail

    /** 一次平衡检查的摘要。**没有逐拍序列**：产品不呈现也不解读心律波形。 */
    data class BalanceCheck(
        var lead: Lead,
        /** 0–100 · SD1 / (SD1 + SD2) 的百分数。 */
        var restShare: Int,
        var sd1Ms: Double,
        var sd2Ms: Double,
        var sdnnMs: Double,
        var heartRate: Int?,
        var beatCount: Int,
    ) : Detail {
        enum class Lead(val raw: String) {
            rest("rest"), drive("drive"), even("even");

            /** 行上和 sheet 顶部那个词。 */
            val word: String
                get() = when (this) {
                    rest -> L("REST")
                    drive -> L("DRIVE")
                    even -> L("EVEN")
                }

            companion object {
                fun fromRaw(raw: String): Lead? = entries.firstOrNull { it.raw == raw }
            }
        }

        /** 屏幕上那个 SPREAD。⚠️ 它是这次四十秒采样的 SD1，不叫 HRV 也不叫 RMSSD——夜间 HRV
         *  是睡眠页的词，一个白天四十秒的离散度不能借那个名字，也不能和它比大小。 */
        val spreadMs: Double get() = sd1Ms
    }

    // MARK: 行上要用的三样东西
    //
    // 模块和清单画的是同一种行，所以这三个属性只在这里算一次。两处各自再推一遍，是这两块
    // 早晚说出不同的话的方式。

    /** 类型名。 */
    val title: String
        get() = when (detail) {
            is BodyScan -> L("BODY SCAN")
            is BalanceCheck -> L("BALANCE CHECK")
        }

    /** 行右列那两个数。身体扫描是体脂率与瘦体重，平衡检查是结论词与心率。 */
    val summary: String
        get() = when (val d = detail) {
            is BodyScan -> {
                val fat = d.bodyFatPercent?.let { "${Fmt.kg(it)} %" } ?: Fmt.dash
                val lean = d.leanMassKg?.let { "${Fmt.kg(it)} KG" } ?: Fmt.dash
                "$fat · $lean"
            }
            is BalanceCheck -> {
                val hr = d.heartRate
                if (hr == null) d.lead.word else "${d.lead.word} · $hr BPM"
            }
        }

    /** 实心点是身体扫描，空心点是平衡检查。没有第三种点——因为没有第三种主动测量。 */
    val isFilledDot: Boolean get() = detail is BodyScan

    companion object {
        /** 模拟器种子。板上那几条，好让这块卡和记录页不接手环也能走通。⚠️ 真机永不走这里：
         *  一条没有来源的测量记录比空卡糟得多。 */
        val seed: List<MeasurementRecord>
            get() {
                fun at(daysAgo: Int, hour: Int, minute: Int): Instant =
                    Instant.now().addingDays(-daysAgo).settingHour(hour, minute, 0)

                fun scan(daysAgo: Int, h: Int, m: Int, fat: Double, lean: Double,
                         fatMass: Double, bmr: Int = 1_640): MeasurementRecord =
                    MeasurementRecord(id = UUID.randomUUID(), at = at(daysAgo, h, m), detail = BodyScan(
                        bodyFatPercent = fat, fatMassKg = fatMass, leanMassKg = lean,
                        bmrKcal = bmr, inputWeightKg = 75.5))

                fun balance(daysAgo: Int, h: Int, m: Int, lead: BalanceCheck.Lead,
                            rest: Int, hr: Int): MeasurementRecord =
                    MeasurementRecord(id = UUID.randomUUID(), at = at(daysAgo, h, m), detail = BalanceCheck(
                        lead = lead, restShare = rest, sd1Ms = 62.0, sd2Ms = 74.0, sdnnMs = 71.0,
                        heartRate = hr, beatCount = 44))

                return listOf(
                    scan(0, 7, 10, fat = 17.7, lean = 62.2, fatMass = 13.3, bmr = 1_642),
                    scan(2, 7, 12, fat = 17.8, lean = 62.1, fatMass = 13.4),
                    balance(3, 22, 10, lead = BalanceCheck.Lead.rest, rest = 58, hr = 58),
                    scan(4, 7, 30, fat = 18.0, lean = 62.3, fatMass = 13.6),
                    scan(5, 7, 5, fat = 18.1, lean = 62.4, fatMass = 13.7),
                    balance(8, 21, 48, lead = BalanceCheck.Lead.even, rest = 50, hr = 63),
                    scan(9, 7, 18, fat = 18.2, lean = 62.1, fatMass = 13.8, bmr = 1_636),
                    scan(10, 7, 22, fat = 18.3, lean = 62.0, fatMass = 13.9),
                    balance(14, 8, 3, lead = BalanceCheck.Lead.drive, rest = 41, hr = 71),
                    scan(14, 7, 8, fat = 18.4, lean = 61.9, fatMass = 14.0, bmr = 1_632),
                    scan(18, 7, 15, fat = 18.5, lean = 61.8, fatMass = 14.1, bmr = 1_628),
                    scan(23, 7, 6, fat = 18.6, lean = 61.7, fatMass = 14.2, bmr = 1_624),
                    scan(27, 7, 20, fat = 18.8, lean = 61.5, fatMass = 14.4, bmr = 1_618),
                )
            }
    }
}

/** 卡头右侧那句话的原料：距最近一次多少天。今天测的是 0。 */
fun List<MeasurementRecord>.daysSinceLatest(now: Instant = Instant.now()): Int? {
    val latest = firstOrNull()?.at ?: return null
    return ChronoUnit.DAYS.between(latest.localDate(), now.localDate()).toInt()
}
