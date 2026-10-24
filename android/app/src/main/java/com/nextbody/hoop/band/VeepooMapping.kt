package com.nextbody.hoop.band

import com.nextbody.hoop.model.SleepInterval
import java.time.Instant
import java.util.Locale
import kotlin.math.roundToInt

/**
 * The pure half of [VeepooBand]: every conversion from what Veepoo's Android SDK hands back
 * into the app's band types, free of vendor classes so the rules stay testable on the JVM.
 * Each function mirrors a private helper of iOS `VeepooBand.swift` (named in its comment).
 */
object VeepooMapping {

    /** "HH:mm" for a vendor clock. */
    fun clock(hour: Int, minute: Int): String = String.format(Locale.US, "%02d:%02d", hour, minute)

    /** "yyyy-MM-dd" for a vendor date — the key every per-day table uses. */
    fun dayKey(year: Int, month: Int, day: Int): String = String.format(Locale.US, "%04d-%02d-%02d", year, month, day)

    /** "yyyy-MM-dd HH:mm" — the sleep stamp `HealthSampleMapping.sleepInstant` reads. */
    fun stamp(year: Int, month: Int, day: Int, hour: Int, minute: Int): String =
        "${dayKey(year, month, day)} ${clock(hour, minute)}"

    // MARK: five-minute origin data

    /** One five-minute slot of `OriginData` / `OriginData3`, vendor-free. */
    data class OriginSlot(
        val time: String,
        val rateValue: Int,
        val ppgs: List<Int> = emptyList(),
        val ecgs: List<Int> = emptyList(),
        val steps: Int,
        val calories: Double,
        /** The SDK's `disValue`, kilometres. */
        val distanceKm: Double,
        val met: Double? = null,
        val temperature: Double? = null,
        val pressure: Int? = null,
        val resRates: List<Int> = emptyList(),
        val bloodGlucose: Double? = null,
    )

    /**
     * Swift `point(time:_:)`. 「如果有heartValue用heartValue, 如果没有则优先使用ppgs, 如果
     * heartValue和ppgs都没有就用ecgs」. On the NEXTBODY the slot's beats sit in `ppgs`, one array
     * per five minutes; the slot's heart rate is their mean. ⚠️ 0 is the band's "nothing on
     * the wrist", not a reading — dropped here at the bridge. Steps and distance keep their
     * zeros: a still hour is a fact.
     */
    fun point(slot: OriginSlot): OriginPoint {
        fun beats(values: List<Int>): Int? {
            val v = values.filter { it > 0 }
            return if (v.isEmpty()) null else (v.sum().toDouble() / v.size).roundedAway().toInt()
        }
        val heart = slot.rateValue.takeIf { it > 0 } ?: beats(slot.ppgs) ?: beats(slot.ecgs)
        return OriginPoint(
            time = slot.time,
            heart = heart,
            step = slot.steps,
            // ⚠️ calValue is never used for E_ACTIVE: it already contains the vendor's own
            // basal figure, and adding it to our BMR double-counts. It is stored, not summed.
            cal = slot.calories.toInt(),
            // The SDK's `disValue` is kilometres; the bridge converts before this is stored.
            distance = distanceMeters(slot.distanceKm),
            met = slot.met,
            temperature = slot.temperature?.takeIf { it > 0 },
            // HRV is its own history domain, joined on in OriginDataSync.
            hrv = null,
            stress = slot.pressure?.takeIf { it > 0 },
            // NEXTBODY's accurate stages come from the sleep record, exactly as on iOS.
            sleepState = null,
        )
    }

    fun distanceMeters(km: Double): Int? {
        if (!km.isFinite() || km < 0) return null
        val m = (km * 1000).roundedAway()
        return if (m <= Int.MAX_VALUE) m.toInt() else null
    }

    /** Mean breaths-per-minute of a slot's `resRates`, 0 and 255 being the band's empty marks. */
    fun respiration(slot: OriginSlot): RespirationSample? {
        val v = slot.resRates.filter { it in 1..254 }
        if (v.isEmpty()) return null
        return RespirationSample(slot.time, v.sum().toDouble() / v.size)
    }

    /** The optical response the RESPONSE card reads; the vendor's 0 is an empty slot. */
    fun optical(slot: OriginSlot): OpticalResponseSample? {
        val value = slot.bloodGlucose ?: return null
        if (!value.isFinite() || value <= 0) return null
        return OpticalResponseSample(slot.time, value)
    }

    // MARK: HRV / oxygen / temperature rows, in the dictionary shape the shared mapping reads

    /** `HRVOriginData` → the iOS database row `HealthSampleMapping.hrv` reads: `hearts` are the
     *  ten scatter values (×10 ms each), `hrvValue` the vendor scalar. */
    fun hrvRow(time: String, hearts: List<Int>, hrvValue: Int): Map<String, Any?> =
        mapOf("time" to time, "hearts" to hearts, "hrvValue" to hrvValue)

    /** The row's RR intervals in the iOS unit (x10 ms, VPDataBaseOperation.h `VPHRVHeartsKey`).
     *  `HRVOriginData.rate` is the band's bytes as "80,76,75,95,84" — that same x10 ms unit.
     *  ⚠️ `rrValue` is NOT the same numbers: the SDK's private `setRr` multiplies each by 10,
     *  so it is already milliseconds. Feeding it on would be x10 twice (8000 ms) and every
     *  interval would fall out of `HealthSampleMapping.hrv`'s 250–2500 ms window. */
    fun hearts(rate: String?, rrValue: IntArray?): List<Int> {
        val fromRate = rate.orEmpty().split(",").mapNotNull { it.trim().toIntOrNull() }
        if (fromRate.isNotEmpty()) return fromRate
        return rrValue?.map { it / 10 }.orEmpty()
    }

    /** `Spo2hOriginData` → the oxygen-table row both `HealthSampleMapping.oxygen` and
     *  `.respiration` read. */
    fun oxygenRow(time: String, oxygen: Int, respirationRate: Int): Map<String, Any?> =
        mapOf("Time" to time, "OxygenValue" to oxygen, "RespirationRate" to respirationRate)

    /** `TemptureData` → the temperature row. The product stores skin temperature, which
     *  Veepoo names the base value. */
    fun temperatureRow(hour: Int, minute: Int, baseCelsius: Double): Map<String, Any?> =
        mapOf("hour" to hour, "minute" to minute, "originalValue" to baseCelsius)

    // MARK: sleep

    /** One sleep record as the SDK reports it (`SleepData` / `SleepPrecisionData`). */
    data class SleepInput(
        val sleepStamp: String?,
        val wakeStamp: String?,
        val total: Int,
        val deep: Int,
        val light: Int,
        val other: Int,
        val wakes: Int,
        val line: String,
        /** Precision sleep: one character per minute, 0 deep · 1 light · 2 REM · 3 insomnia ·
         *  4 awake. Plain sleep is five-minute characters the iOS adapter never staged. */
        val precise: Boolean,
    )

    data class SleepRecord(
        val start: Instant,
        val end: Instant,
        val total: Int,
        val deep: Int,
        val light: Int,
        val wakes: Int,
        /** null retains the minute occupied by an unknown SDK stage. */
        val stages: List<Int?>,
    )

    /** Swift `sleepRecords(_:)` for accurate models; plain records carry no stages. */
    fun sleepRecords(inputs: List<SleepInput>): List<SleepRecord> = inputs.mapNotNull { input ->
        val start = HealthSampleMapping.sleepInstant(input.sleepStamp) ?: return@mapNotNull null
        val end = HealthSampleMapping.sleepInstant(input.wakeStamp) ?: return@mapNotNull null
        if (start >= end) return@mapNotNull null
        val stages: List<Int?> = if (input.precise) input.line.map { ch ->
            ch.digitToIntOrNull()?.takeIf { it in 0..4 }
        } else emptyList()
        SleepRecord(start = start, end = end,
            total = if (input.total > 0) input.total else input.deep + input.light + input.other,
            deep = input.deep, light = input.light, wakes = input.wakes, stages = stages)
    }

    /** Prefer complete records to duplicate/contained fragments before counting. */
    fun distinctSleep(records: List<SleepRecord>): List<SleepRecord> {
        val sorted = records.sortedWith(Comparator { a, b ->
            when {
                a.start != b.start -> a.start.compareTo(b.start)
                a.end != b.end -> b.end.compareTo(a.end)
                else -> b.stages.count { it != null }.compareTo(a.stages.count { it != null })
            }
        })
        return sorted.filterIndexed { index, record ->
            sorted.take(index).none { it.start <= record.start && it.end >= record.end }
        }
    }

    fun sleepIntervals(records: List<SleepRecord>): List<SleepInterval> {
        val intervals = mutableListOf<SleepInterval>()
        for (record in records) {
            val last = intervals.lastOrNull()
            if (last != null && record.start <= last.end) {
                intervals[intervals.size - 1] = SleepInterval(start = last.start, end = maxOf(last.end, record.end))
            } else {
                intervals.add(SleepInterval(start = record.start, end = record.end))
            }
        }
        return intervals
    }

    /** One entry per real minute. Earlier complete records win overlapping conflicts;
     *  unknown stages occupy time but never create a fabricated sleep stage. */
    fun sleepMinutes(records: List<SleepRecord>): Map<Instant, Int> {
        val minutes = HashMap<Instant, Int>()
        for (record in records) {
            for ((offset, stage) in record.stages.withIndex()) {
                val at = record.start.plusSeconds(offset * 60L)
                if (at >= record.end || stage == null || minutes.containsKey(at)) continue
                minutes[at] = stage
            }
        }
        return minutes
    }

    fun stageRuns(minutes: Map<Instant, Int>, start: Instant): List<SleepStageRun> {
        val result = mutableListOf<SleepStageRun>()
        for (at in minutes.keys.sorted()) {
            val stage = minutes[at] ?: continue
            val offset = (BandTime.interval(at, start) / 60).toInt()
            val last = result.lastOrNull()
            if (last != null && last.stage == stage && (last.offsetMinutes ?: 0) + last.minutes == offset) {
                result[result.size - 1] = SleepStageRun(stage = stage, minutes = last.minutes + 1, offsetMinutes = last.offsetMinutes)
            } else {
                result.add(SleepStageRun(stage = stage, minutes = 1, offsetMinutes = offset))
            }
        }
        return result
    }

    fun summarizeSleep(source: List<SleepRecord>): SleepNight? {
        val records = distinctSleep(source)
        val intervals = sleepIntervals(records)
        val start = intervals.firstOrNull()?.start ?: return null
        val end = intervals.last().end
        val minutes = sleepMinutes(records)
        val line = stageRuns(minutes, start)
        val duration = intervals.sumOf { (BandTime.interval(it.end, it.start) / 60).toInt() }
        val individualDuration = records.sumOf { (BandTime.interval(it.end, it.start) / 60).toInt() }
        val overlaps = duration < individualDuration
        // Disjoint records retain vendor totals (including the single-record 550-minute
        // convention). Overlaps cannot add their aggregate totals a second time.
        val total = if (overlaps) duration else records.sumOf { it.total }
        val deep = if (overlaps) minutes.values.count { it == 0 } else records.sumOf { it.deep }
        val light = if (overlaps) minutes.values.count { it == 1 } else records.sumOf { it.light }
        val wakes = if (overlaps) line.count { it.stage == 3 || it.stage == 4 } else records.sumOf { it.wakes }
        return SleepNight(totalMinutes = total, deepMinutes = deep, lightMinutes = light, wakeCount = wakes,
            line = line, sleepStart = start, wakeAt = end, intervals = intervals)
    }

    /** The night that woke on `morning` ("yyyy-MM-dd"): accurate records first, plain second,
     *  matched by wake date exactly like the iOS two-page query. */
    fun night(inputs: List<SleepInput>, morning: String, now: Instant = Instant.now()): SleepNight? {
        val accurate = inputs.filter { it.precise }
        val accurateNight = HealthSampleMapping.sleepRecordIndices(
            accurate.map { it.sleepStamp to it.wakeStamp }, wakeDay = morning, now = now).map { accurate[it] }
        if (accurateNight.isNotEmpty()) return summarizeSleep(sleepRecords(accurateNight))
        val plain = inputs.filter { !it.precise }
        val plainNight = HealthSampleMapping.sleepRecordIndices(
            plain.map { it.sleepStamp to it.wakeStamp }, wakeDay = morning, now = now).map { plain[it] }
        if (plainNight.isEmpty()) return null
        return summarizeSleep(sleepRecords(plainNight))
    }

    // MARK: pulse study

    /**
     * Swift `intervals(rrs:hearts:)` · work out what the band actually sent, rather than assuming.
     *  · milliseconds — a resting interval is 600–1200, so anything in 300…2000 is already right.
     *  · hundredths, or any other scaling — a median of 60–200 is the same intervals in a
     *    smaller unit; multiplied back it lands in the physiological range.
     *  · counts — single digits; nothing recoverable, the per-second heart rates are used.
     * ⚠️ The last is NOT beat-to-beat data, and the result says so.
     */
    fun pulseIntervals(rrs: List<Double>, hearts: List<Double>): Pair<List<Double>, PulseStudy.Source> {
        val usable = rrs.filter { it > 0 }
        if (usable.size >= 8) {
            val sorted = usable.sorted()
            val median = sorted[sorted.size / 2]
            if (median in 300.0..2000.0) {
                return usable.filter { it in 300.0..2000.0 } to PulseStudy.Source.intervals
            }
            for (factor in listOf(10.0, 100.0, 1000.0)) {
                if (median * factor !in 300.0..2000.0) continue
                val scaled = usable.map { it * factor }.filter { it in 300.0..2000.0 }
                if (scaled.size >= 8) return scaled to PulseStudy.Source.intervals
            }
        }
        val beats = hearts.filter { it in 30.0..220.0 }
        if (beats.size >= 8) return beats.map { 60_000 / it } to PulseStudy.Source.perSecondRates
        return emptyList<Double>() to PulseStudy.Source.intervals
    }

    // MARK: alarms

    /** `Alarm2Setting.repeatStatus` is seven 0/1 characters, right to left Monday…Sunday —
     *  exactly the bits of `BandAlarm.repeatMask` (LSB Monday … bit 6 Sunday). */
    fun repeatString(mask: Int): String =
        (6 downTo 0).joinToString("") { bit -> if (mask and (1 shl bit) != 0) "1" else "0" }

    fun repeatMask(string: String?): Int? {
        val s = string?.trim() ?: return null
        if (s.length != 7 || s.any { it != '0' && it != '1' }) return null
        return s.foldIndexed(0) { index, acc, ch -> if (ch == '1') acc or (1 shl (6 - index)) else acc }
    }

    // MARK: status enums (by vendor enum name, so no vendor type crosses)

    /** `EFunctionStatus` → [FunctionStatus], carried through verbatim. */
    fun functionStatus(vendorName: String?): FunctionStatus = when (vendorName) {
        "UNSUPPORT" -> FunctionStatus.unsupported
        "SUPPORT" -> FunctionStatus.support
        "SUPPORT_OPEN" -> FunctionStatus.open
        "SUPPORT_CLOSE" -> FunctionStatus.close
        else -> FunctionStatus.unknown
    }

    /** `BatteryData.powerModel`: 0 normal · 1 charging · 2 low voltage · 3 full. */
    fun chargeState(powerModel: Int): BandBattery.ChargeState = when (powerModel) {
        0, 2 -> BandBattery.ChargeState.unplugged
        1 -> BandBattery.ChargeState.charging
        3 -> BandBattery.ChargeState.full
        else -> BandBattery.ChargeState.unknown
    }

    /** `EHealthLightStatus` name ↔ [BandHealthLightState]. */
    fun healthLight(vendorName: String?): BandHealthLightState? = when (vendorName) {
        "OFF" -> BandHealthLightState.off
        "SLOW_FLASH" -> BandHealthLightState.slowFlash
        "RAPID_FLASHING" -> BandHealthLightState.continuousFlashing
        "ALWAYS_ON" -> BandHealthLightState.stayOn
        else -> null
    }

    fun healthLightVendorName(state: BandHealthLightState): String = when (state) {
        BandHealthLightState.off -> "OFF"
        BandHealthLightState.slowFlash -> "SLOW_FLASH"
        BandHealthLightState.continuousFlashing -> "RAPID_FLASHING"
        BandHealthLightState.stayOn -> "ALWAYS_ON"
    }

    /** `EAutoMeasureType` name → [AutoMonitorSlot.Kind]. */
    fun autoMeasureKind(vendorName: String?): AutoMonitorSlot.Kind? = when (vendorName) {
        "PULSE_RATE" -> AutoMonitorSlot.Kind.heartRate
        "BLOOD_PRESSURE" -> AutoMonitorSlot.Kind.bloodPressure
        "BLOOD_GLUCOSE" -> AutoMonitorSlot.Kind.bloodGlucose
        "STRESS" -> AutoMonitorSlot.Kind.stress
        "BLOOD_OXYGEN" -> AutoMonitorSlot.Kind.bloodOxygen
        "BODY_TEMPERATURE" -> AutoMonitorSlot.Kind.temperature
        "LORENZ" -> AutoMonitorSlot.Kind.lorentz
        "HRV" -> AutoMonitorSlot.Kind.hrv
        "BLOOD_COMPOSITION" -> AutoMonitorSlot.Kind.bloodComponents
        else -> null
    }

    /** The interval API's slot, from `AutoMeasureData` (minutes since midnight for its window). */
    fun autoSlot(kind: AutoMonitorSlot.Kind, on: Boolean, slotModify: Boolean, intervalModify: Boolean,
                 startMinute: Int, endMinute: Int, interval: Int, stepUnit: Int): AutoMonitorSlot =
        AutoMonitorSlot(
            kind = kind, on = on, supportsRange = slotModify,
            startHour = (startMinute / 60).coerceIn(0, 24), endHour = (endMinute / 60).coerceIn(0, 24),
            intervalMinutes = interval, intervalStepMinutes = stepUnit,
            slotModifiable = slotModify,
            intervalModifiable = intervalModify && kind != AutoMonitorSlot.Kind.lorentz)

    /** `FunSwitchFlags` 1…17 are `VPHealthFunctionType` 0…16 plus one. */
    fun healthFunctions(states: Map<Int, String?>): List<BandHealthFunction> = (0..16).map { raw ->
        val status = states[raw + 1]
        BandHealthFunction(
            rawValue = raw,
            name = BandHealthFunction.name(forRawValue = raw),
            support = status != null && status != "UNSUPPORT",
            open = status == "SUPPORT_OPEN")
    }

    /** The firmware server joins its release notes with "$". */
    fun firmwareNotes(des: String?): List<String> =
        des.orEmpty().split("$").map { it.trim() }.filter { it.isNotEmpty() }

    /** `IBodyComponentDetectListener.onDetecting(progress, …)` is the packet's byte 4 passed
     *  through raw; the iOS SDK wraps the same byte in an NSProgress of total 100. Percent,
     *  always — so 1 is 1 %, never the whole scan. */
    fun percentFraction(percent: Int): Double = (percent / 100.0).coerceIn(0.0, 1.0)

    /** Swift `identity()`'s sport-mode tier. `saveTimes` is the function packet's byte 5
     *  (iOS `runningSaveTimes`, Android `sportmodelday`); `type` its byte 16 (iOS
     *  `runningType`, Android `sportModelType`). Only 0 (single) and 1 (ten sports) are
     *  documented; anything else is shown raw. */
    fun sportModeLabel(saveTimes: Int?, type: Int?): String = when {
        saveTimes == null || saveTimes == 0 -> "NONE"
        type == 0 -> "SINGLE"
        type == 1 -> "10 TYPES"
        else -> "T${type ?: "?"} · UNDOCUMENTED"
    }

    /** SDK progress has been seen both as 0…1 and 0…100; on screen it is a fraction. */
    fun progressFraction(p: Double): Double = (if (p > 1) p / 100 else p).coerceIn(0.0, 1.0)

    /** `BodyComponent` floats → the reading; a zero is the firmware leaving a field empty. */
    fun bodyComposition(
        bmi: Float, bodyFatRate: Float, fatMass: Float, ffm: Float, muscleRate: Float, muscleMass: Float,
        subcutaneousFat: Float, bodyWater: Float, waterContent: Float, skeletalMuscleRate: Float,
        boneMass: Float, proteinProportion: Float, proteinMass: Float, bmr: Float, inputWeightKg: Double,
    ): BodyCompositionReading {
        fun opt(v: Float): Double? = v.toDouble().takeIf { it.isFinite() && it > 0 }
        return BodyCompositionReading(
            bodyFatPercent = opt(bodyFatRate) ?: 0.0,
            fatMassKg = opt(fatMass) ?: 0.0,
            leanMassKg = opt(ffm) ?: 0.0,
            muscleKg = opt(muscleMass),
            boneKg = opt(boneMass),
            bodyWaterPercent = opt(bodyWater),
            proteinPercent = opt(proteinProportion),
            subcutaneousFatPercent = opt(subcutaneousFat),
            skeletalMusclePercent = opt(skeletalMuscleRate),
            // A device estimate, kept as a reference; the ledger uses its own Mifflin BMR.
            bmrKcal = opt(bmr)?.roundToInt(),
            bmi = opt(bmi),
            inputWeightKg = inputWeightKg,
            muscleRatePercent = opt(muscleRate),
            waterKg = opt(waterContent),
            proteinKg = opt(proteinMass),
        )
    }
}
