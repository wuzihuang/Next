package com.nextbody.hoop.features.home

import androidx.compose.ui.graphics.Color
import com.nextbody.hoop.app.Destination
import com.nextbody.hoop.band.CompositionScan
import com.nextbody.hoop.band.HomeTimeline
import com.nextbody.hoop.band.SportSessionRecap
import com.nextbody.hoop.band.UserDay
import com.nextbody.hoop.data.MealEntry
import com.nextbody.hoop.data.WeighIn
import com.nextbody.hoop.design.NB
import com.nextbody.hoop.features.vitals.VitalsMetric
import com.nextbody.hoop.features.vitals.VitalsReadout
import com.nextbody.hoop.l10n.L
import com.nextbody.hoop.model.DailyMetrics
import com.nextbody.hoop.model.Fmt
import com.nextbody.hoop.model.FuelState
import com.nextbody.hoop.model.MeasurementRecord
import com.nextbody.hoop.model.SleepSummary
import com.nextbody.hoop.model.TrainingSegment
import com.nextbody.hoop.model.currentZone
import com.nextbody.hoop.model.swiftFormat
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

/**
 * Homepage V2 · Planet / Body / Instruments.
 *
 * Numbers come from the day the band and the meal ledger already settled.
 * A missing input stays null so the screen can print ——. Nothing here invents
 * a calorie, a glow, or a delta to fill an empty slot.
 */
object HomeV2Model {
    const val macroHitFraction = 0.95

    enum class FoodFace(val raw: String) { unlogged("A"), recovery("B"), complete("C"), remaining("D") }

    enum class ReadinessBand { unknown, recover, steady, peak }

    data class Macro(val eaten: Int?, val target: Int?) {
        val left: Int? get() = if (eaten != null && target != null) target - eaten else null

        /** Met when intake reaches 95% of the target. 118/120 is a hit; 96/120 is not. */
        val met: Boolean
            get() {
                if (eaten == null || target == null || target <= 0) return false
                return eaten.toDouble() >= target.toDouble() * macroHitFraction
            }
    }

    data class Food(
        val face: FoodFace,
        val meals: Int,
        val eatenKcal: Int?,
        val targetKcal: Int?,
        val protein: Macro,
        val carb: Macro,
        val fat: Macro,
        /** Guide copy. Present only while nothing has been logged. */
        val guide: String?,
    ) {
        val kcalLeft: Int? get() = if (eatenKcal != null && targetKcal != null) targetKcal - eatenKcal else null
        val kcalMet: Boolean
            get() {
                if (eatenKcal == null || targetKcal == null || targetKcal <= 0) return false
                return eatenKcal.toDouble() >= targetKcal.toDouble() * macroHitFraction
            }
    }

    data class Planet(
        val readiness: Int?,
        val vsAverage: Int?,
        val band: ReadinessBand,
        val orbitPlace: String,
        val orbitState: String,
        val statusWord: String,
        val statusPhrase: String,
        val sleepScore: Int?,
        val sleepMinutes: Int?,
        val sleepDeepMinutes: Int?,
        val sleepFoot: String,
        val load: Double?,
        val loadTarget: Double?,
        val food: Food,
    )

    /**
     * Categorical status ramp for sleep, heart and calorie allowance. The leg tint is
     * a separate movement-volume ramp; `dim` remains the neutral off-ramp.
     */
    enum class BodyStatus(val raw: Int) {
        dim(-1), good(0), ok(1), watch(2), poor(3), bad(4);

        fun escalated(): BodyStatus = entries.firstOrNull { it.raw == minOf(bad.raw, raw + 1) } ?: bad
    }

    private fun maxStatus(a: BodyStatus, b: BodyStatus): BodyStatus = if (a.raw >= b.raw) a else b

    data class BodyGlow(
        val lit: Boolean,
        /** 0.35…1 when the domain has data. 0 when it does not. */
        val intensity: Double,
        val eyebrow: String,
        val value: String,
        /** Short second lines under the value — the rest of the part's readings. */
        val details: List<String> = emptyList(),
        /** Only meaningful while `lit`; an unlit part draws in dim white. */
        val status: BodyStatus = BodyStatus.ok,
        /** A data-specific hue can replace the shared status ramp (e.g. macros or step volume). */
        val tint: Color? = null,
    )

    data class BodyMetric(
        val id: String,
        val label: String,
        val value: String,
        val unit: String,
        val delta: String,
        val tint: Tint,
    ) {
        enum class Tint { lime, violet, ember, cyan, white }
    }

    data class Body(
        val scannedAt: Instant?,
        val head: BodyGlow,
        val heart: BodyGlow,
        val gut: BodyGlow,
        val legs: BodyGlow,
        val primary: List<BodyMetric>,
        val more: List<BodyMetric>,
    )

    /** The four lit parts, top to bottom. `BodyCloud.zones` paints its motes in this order. */
    enum class Zone(val raw: String) {
        head("head"), heart("heart"), gut("gut"), legs("legs");
        val id: String get() = raw
    }

    data class Stat(val id: String, val label: String, val value: String, val unit: String, val foot: String)

    data class Detail(
        val zone: Zone,
        val eyebrow: String,
        val hero: String,
        val heroUnit: String,
        val aside: String,
        val verdict: String,
        val stats: List<Stat>,
        val noteLabel: String,
        val note: String?,
        /** The part's light as it stood on the map. null keeps the page in neutral white. */
        val status: BodyStatus?,
        val tint: Color? = null,
    )

    /**
     * The page a home card opens. Empty numbers still open it — the detail
     * page is where a missing night or an unlogged day is allowed to say so.
     */
    fun destination(zone: Zone): Destination = when (zone) {
        Zone.head -> Destination.Vitals(VitalsMetric.sleep)
        Zone.heart -> Destination.Vitals(VitalsMetric.heart)
        Zone.gut -> Destination.Fuel
        Zone.legs -> Destination.Vitals(VitalsMetric.steps)
    }

    fun destination(item: HomeTimeline.Item): Destination? = when (item.accent) {
        HomeTimeline.Accent.meal -> Destination.FuelDay(item.day)
        HomeTimeline.Accent.stress -> Destination.Vitals(VitalsMetric.stress)
        HomeTimeline.Accent.workout, HomeTimeline.Accent.activity -> Destination.Training
        HomeTimeline.Accent.sleep, HomeTimeline.Accent.wake -> Destination.Vitals(VitalsMetric.sleep)
        HomeTimeline.Accent.bodyScan -> Destination.Composition(item.at.atZone(currentZone()).toLocalDate())
        HomeTimeline.Accent.balanceCheck -> Destination.Measurements
        HomeTimeline.Accent.weighIn -> null
    }

    fun planet(metrics: DailyMetrics, history: List<DailyMetrics>, meals: List<MealEntry>): Planet {
        val readiness = metrics.bodyBatteryForDisplay()
        val band = readinessBand(readiness)
        val food = food(metrics, meals)
        val orbit = orbit(band, food)
        val status = status(band)
        val night = metrics.sleep
        return Planet(
            readiness = readiness,
            vsAverage = versusAverage(readiness, history),
            band = band,
            orbitPlace = orbit.first,
            orbitState = orbit.second,
            statusWord = status.first,
            statusPhrase = status.second,
            sleepScore = metrics.sleepScore?.score,
            sleepMinutes = night?.totalMinutes,
            sleepDeepMinutes = night?.let { if (it.deepMinutes > 0) it.deepMinutes else null },
            sleepFoot = sleepFoot(night, metrics.sleepScore?.score),
            load = metrics.trainingLoad,
            loadTarget = metrics.targetLoad,
            food = food,
        )
    }

    fun readinessBand(score: Int?): ReadinessBand {
        if (score == null) return ReadinessBand.unknown
        if (score < 50) return ReadinessBand.recover
        if (score >= 80) return ReadinessBand.peak
        return ReadinessBand.steady
    }

    fun versusAverage(score: Int?, history: List<DailyMetrics>): Int? {
        if (score == null) return null
        val prior = history.mapNotNull { it.bbWake ?: it.bodyBattery }
        if (prior.size < 3) return null
        val mean = prior.sum().toDouble() / prior.size
        return swiftRound(score.toDouble() - mean)
    }

    fun orbit(band: ReadinessBand, food: Food): Pair<String, String> {
        if (band == ReadinessBand.recover) return L("LOW ORBIT") to L("RECOVERY HOLD")
        if (food.face == FoodFace.complete) return L("ORBIT LOCKED") to L("ALL TARGETS MET")
        return L("HOME BASE") to L("STEADY")
    }

    fun status(band: ReadinessBand): Pair<String, String> = when (band) {
        ReadinessBand.recover -> L("RECOVER") to L("REST TODAY")
        ReadinessBand.peak -> L("PEAK") to L("FULL CHARGE")
        ReadinessBand.steady -> L("STEADY") to L("READY TO TRAIN")
        ReadinessBand.unknown -> Fmt.dash to Fmt.dash
    }

    fun sleepFoot(night: SleepSummary?, score: Int?): String {
        val deep = night?.deepMinutes
        if (deep != null && deep > 0) return L("DEEP %@", Fmt.duration(deep))
        if (score != null && score >= 85) return L("OPTIMAL")
        val minutes = night?.totalMinutes
        if (minutes != null && minutes < 7 * 60) return L("SHORT")
        if (night == null) return L("NO NIGHT YET")
        return Fmt.dash
    }

    fun food(metrics: DailyMetrics, meals: List<MealEntry>): Food {
        val plates = meals.filter { it.day == metrics.day && it.status == MealEntry.Status.confirmed }
        val rawAllowance = metrics.targetBasis
            ?: metrics.bmrFull?.let { it + (metrics.eActive ?: 0.0) }
            ?: metrics.targetIn
        val targetKcal = rawAllowance?.let { swiftRound(it) }
        val logged = intake(metrics, plates)
        val protein = Macro(if (logged.logged) logged.protein else null, metrics.protein?.target)
        val carb = Macro(if (logged.logged) logged.carb else null, metrics.carb?.target)
        val fat = Macro(if (logged.logged) logged.fat else null, metrics.fat?.target)
        val face = when {
            !logged.logged ->
                if (readinessBand(metrics.bodyBatteryForDisplay()) == ReadinessBand.recover) FoodFace.recovery else FoodFace.unlogged
            protein.met && carb.met && fat.met -> FoodFace.complete
            else -> FoodFace.remaining
        }
        val guide = when (face) {
            FoodFace.unlogged, FoodFace.recovery -> L("Connect MCP, then type what you eat in your personal agent.")
            FoodFace.complete, FoodFace.remaining -> null
        }
        return Food(
            face = face,
            meals = plates.size,
            eatenKcal = if (logged.logged) logged.kcal else null,
            targetKcal = targetKcal,
            protein = protein, carb = carb, fat = fat,
            guide = guide,
        )
    }

    private data class Intake(val logged: Boolean, val kcal: Int?, val protein: Int?, val carb: Int?, val fat: Int?)

    /**
     * Confirmed plates win. A fasted day is a real zero. Server totals are used only
     * when the day is marked logged and no plate rows are on the phone.
     */
    private fun intake(metrics: DailyMetrics, plates: List<MealEntry>): Intake {
        if (plates.isNotEmpty()) {
            return Intake(
                logged = true,
                kcal = swiftRound(plates.sumOf { it.kcal }),
                protein = swiftRound(plates.sumOf { it.protein }),
                carb = swiftRound(plates.sumOf { it.carb }),
                fat = swiftRound(plates.sumOf { it.fat }),
            )
        }
        if (metrics.fuelState == FuelState.Fasted) return Intake(true, 0, 0, 0, 0)
        if (metrics.fuelState == FuelState.Unlogged || (metrics.eIn == null && metrics.proteinIn == null)) {
            return Intake(false, null, null, null, null)
        }
        return Intake(
            logged = true,
            kcal = metrics.eIn?.let { swiftRound(it) },
            protein = metrics.proteinIn,
            carb = metrics.carbIn,
            fat = metrics.fatIn,
        )
    }

    fun body(
        metrics: DailyMetrics, history: List<DailyMetrics>, meals: List<MealEntry>,
        scans: List<CompositionScan>, heightCm: Double,
    ): Body {
        val food = food(metrics, meals)
        val latest = scans.maxByOrNull { it.at }
        val fields = compositionFields(latest, scans, heightCm)
        return Body(
            scannedAt = latest?.at,
            head = headGlow(metrics),
            heart = heartGlow(metrics),
            gut = gutGlow(food),
            legs = legsGlow(metrics),
            primary = listOf(fields.fat, fields.muscle, fields.lean),
            more = listOf(fields.fatMass, fields.water, fields.protein, fields.bone, fields.bmr, fields.bmi),
        )
    }

    /** The glow burns with the status, not with the number: fine reads at a third, a bad reading at full. */
    private fun glowIntensity(lit: Boolean, status: BodyStatus): Double =
        if (lit) 0.35 + 0.65 * maxOf(0, status.raw).toDouble() / BodyStatus.bad.raw.toDouble() else 0.0

    private fun latestStress(metrics: DailyMetrics): Int? = metrics.vitalsCurve.lastOrNull { it.stress != null }?.stress

    /**
     * Head owns the night: the sleep numbers plus the day's stress index. HRV is a
     * heart measurement and lives on the chest, not here.
     */
    fun headGlow(metrics: DailyMetrics): BodyGlow {
        val night = metrics.sleep
        val minutes = night?.totalMinutes
        val stress = latestStress(metrics)
        val status = sleepStatus(metrics)
        val lit = (minutes ?: 0) > 0 || stress != null
        val details = mutableListOf<String>()
        val nightBits = mutableListOf<String>()
        metrics.sleepScore?.score?.let { nightBits.add(L("SCORE %d", it)) }
        night?.deepMinutes?.let { if (it > 0) nightBits.add(L("DEEP %@", sleepHours(it))) }
        val rem = night?.remMinutes ?: 0
        if (rem > 0) nightBits.add(L("REM %@", sleepHours(rem)))
        if (nightBits.isNotEmpty()) details.add(nightBits.joinToString(" · "))
        return BodyGlow(
            lit = lit,
            intensity = glowIntensity(lit, status),
            eyebrow = L("HEAD"),
            value = stress?.let { L("STRESS %d", it) } ?: Fmt.dash,
            details = details,
            status = status,
        )
    }

    /**
     * The head's light is the night's light: the settled score when it exists, duration
     * when it does not, pushed one stop worse by a high stress index.
     */
    fun sleepStatus(metrics: DailyMetrics): BodyStatus {
        val score = metrics.sleepScore?.score
        val minutes = metrics.sleep?.totalMinutes
        val status = if (score != null) {
            when {
                score >= 85 -> BodyStatus.good
                score >= 70 -> BodyStatus.ok
                score >= 55 -> BodyStatus.watch
                score >= 40 -> BodyStatus.poor
                else -> BodyStatus.bad
            }
        } else if (minutes != null && minutes > 0) {
            when {
                minutes >= 570 -> BodyStatus.ok
                minutes >= 450 -> BodyStatus.good
                minutes >= 390 -> BodyStatus.ok
                minutes >= 300 -> BodyStatus.watch
                minutes >= 240 -> BodyStatus.poor
                else -> BodyStatus.bad
            }
        } else {
            BodyStatus.watch
        }
        val stress = latestStress(metrics)
        if (stress == null || stress < 75) return status
        return status.escalated()
    }

    /**
     * Every pulse-derived reading in one place: the live rate, the resting rate against
     * its seven-day base, the night's oxygen floor and the sleeping breath rate.
     */
    data class HeartInputs(
        val live: Int?,
        val rhr: Double?,
        val rhrBase: Double?,
        val spo2: Int?,
        val resp: Double?,
        val hrv: Double?,
        val hrvBase: Double?,
    ) {
        val hasAny: Boolean get() = live != null || rhr != null || spo2 != null || resp != null
    }

    fun heartInputs(metrics: DailyMetrics): HeartInputs {
        val breaths = metrics.sleep?.respiration?.map { it.breathsPerMinute } ?: emptyList()
        return HeartInputs(
            live = metrics.vitalsCurve.lastOrNull { it.hr != null }?.hr,
            rhr = metrics.nightInputs?.rhr,
            rhrBase = metrics.nightInputs?.rhrBase,
            spo2 = metrics.sleep?.spo2?.map { it.percent }?.minOrNull(),
            resp = if (breaths.isEmpty()) null else breaths.sum() / breaths.size,
            hrv = metrics.nightInputs?.hrv,
            hrvBase = metrics.nightInputs?.hrvBase,
        )
    }

    /** Worst signal wins: one bad reading is enough to pull the light down. */
    fun heartStatus(inputs: HeartInputs): BodyStatus {
        var status: BodyStatus? = null
        if (inputs.rhr != null && inputs.rhrBase != null) {
            val delta = inputs.rhr - inputs.rhrBase
            status = when {
                delta <= 2 -> BodyStatus.good
                delta <= 6 -> BodyStatus.watch
                delta <= 10 -> BodyStatus.poor
                else -> BodyStatus.bad
            }
        }
        inputs.spo2?.let { spo2 ->
            val s = when {
                spo2 >= 95 -> BodyStatus.good
                spo2 >= 93 -> BodyStatus.watch
                spo2 >= 90 -> BodyStatus.poor
                else -> BodyStatus.bad
            }
            status = maxStatus(status ?: s, s)
        }
        inputs.resp?.let { resp ->
            val s = when {
                resp in 12.0..20.0 -> BodyStatus.good
                resp in 8.0..26.0 -> BodyStatus.watch
                else -> BodyStatus.poor
            }
            status = maxStatus(status ?: s, s)
        }
        return status ?: BodyStatus.ok
    }

    fun heartGlow(metrics: DailyMetrics): BodyGlow {
        val inputs = heartInputs(metrics)
        val status = heartStatus(inputs)
        val lit = inputs.hasAny
        val details = mutableListOf<String>()
        val resting = mutableListOf<String>()
        inputs.rhr?.let { resting.add(L("RHR %d", swiftRound(it))) }
        inputs.spo2?.let { resting.add(L("SpO2 %d%%", it)) }
        if (resting.isNotEmpty()) details.add(resting.joinToString(" · "))
        inputs.resp?.let { details.add(L("RESP %@", swiftFormat("%.1f", it))) }
        return BodyGlow(
            lit = lit,
            intensity = glowIntensity(lit, status),
            eyebrow = L("HEART"),
            value = inputs.live?.let { L("%d BPM", it) }
                ?: inputs.rhr?.let { L("RHR %d", swiftRound(it)) } ?: Fmt.dash,
            details = details,
            status = status,
        )
    }

    fun gutGlow(food: Food): BodyGlow {
        val status = gutStatus(food)
        val eaten = food.eatenKcal
        val target = food.targetKcal
        if (!(food.face == FoodFace.complete || food.face == FoodFace.remaining) || eaten == null || target == null || target <= 0) {
            return BodyGlow(lit = false, intensity = 0.0, eyebrow = L("GUT"), value = Fmt.dash, status = status)
        }
        val delta = eaten - target
        val text = if (delta == 0) L("ON ALLOWANCE") else L("%@ KCAL", Fmt.signedKcal(delta.toDouble()))
        return BodyGlow(
            lit = true, intensity = glowIntensity(true, status),
            eyebrow = L("GUT"), value = text,
            details = listOf(L("%@ / %@ EATEN", Fmt.kcal(eaten.toDouble()), Fmt.kcal(target.toDouble()))),
            status = status, tint = gutTint(food),
        )
    }

    /**
     * Mixes the established protein, carbohydrate and fat colours by their share of
     * recorded macro calories. Missing macros do not contribute a made-up zero.
     */
    fun gutTint(food: Food): Color? =
        BodyTintMath.gut(
            food.protein.eaten, food.carb.eaten, food.fat.eaten,
            rgb(NB.optimal2), rgb(NB.lime1), rgb(NB.run1),
        )?.let { color(it) }

    /**
     * How far the plate sits from the allowance. Overshooting advances through amber
     * and orange before orange-red; it is not a clinical warning.
     */
    fun gutStatus(food: Food): BodyStatus {
        val eaten = food.eatenKcal
        val target = food.targetKcal
        if (!(food.face == FoodFace.complete || food.face == FoodFace.remaining) || eaten == null || target == null || target <= 0) {
            return BodyStatus.ok
        }
        val fraction = (eaten - target).toDouble() / target.toDouble()
        return when {
            fraction > 0.30 -> BodyStatus.bad
            fraction > 0.15 -> BodyStatus.poor
            fraction > 0.02 -> BodyStatus.watch
            fraction < -0.30 -> BodyStatus.poor
            fraction < -0.15 -> BodyStatus.watch
            fraction < -0.03 -> BodyStatus.ok
            else -> BodyStatus.good
        }
    }

    /**
     * Legs own the day's ground: step volume sets the colour; distance and movement kcal
     * remain supporting readouts, not substitutes for an unreported step count.
     */
    fun legsGlow(metrics: DailyMetrics): BodyGlow {
        val steps = VitalsReadout.daySteps(metrics)
        val metres = VitalsReadout.dayMetres(metrics)
        val active = VitalsReadout.dayActiveKcal(metrics)
        val status = legsStatus(steps)
        val lit = steps != null || metres != null
        val details = mutableListOf<String>()
        metres?.let { details.add(L("DIST %@ KM", swiftFormat("%.1f", it / 1000))) }
        active?.let { details.add(L("ACTIVE %@", Fmt.kcal(it))) }
        return BodyGlow(
            lit = lit,
            intensity = if (lit) BodyTintMath.legsIntensity(steps) else 0.0,
            eyebrow = L("LEGS"),
            value = steps?.let { L("%@ STEPS", Fmt.kcal(it)) }
                ?: metres?.let { L("%@ KM", swiftFormat("%.1f", it / 1000)) } ?: Fmt.dash,
            details = details,
            status = status, tint = legsTint(steps),
        )
    }

    /**
     * Low steps are neutral, not a warning. At 10k the hue is yellow; 20–30k
     * moves from orange toward orange-red as activity volume rises.
     */
    fun legsTint(steps: Double?): Color = color(
        BodyTintMath.legs(
            steps, BodyTintMath.LegPalette(
                neutral = BodyRGB(1.0, 1.0, 1.0, 0.28),
                green = rgb(NB.optimal2), yellow = rgb(NB.filmYellow),
                orange = rgb(NB.ember1), orangeRed = rgb(NB.ember2),
            ),
        ),
    )

    private fun rgb(c: Color): BodyRGB = BodyRGB(c.red.toDouble(), c.green.toDouble(), c.blue.toDouble(), c.alpha.toDouble())

    private fun color(rgb: BodyRGB): Color = Color(
        rgb.red.toFloat().coerceIn(0f, 1f), rgb.green.toFloat().coerceIn(0f, 1f),
        rgb.blue.toFloat().coerceIn(0f, 1f), rgb.alpha.toFloat().coerceIn(0f, 1f),
    )

    /** Walking volume is not a body-status warning; only zero or unavailable stays neutral. */
    fun legsStatus(steps: Double?): BodyStatus = if (steps == null || steps <= 0) BodyStatus.dim else BodyStatus.good

    /**
     * The nine figures the band's BIA scan really returns, drawn from the latest scan only.
     * Weight is not here: the band has no scale, so it is the weight we sent down, not a result.
     */
    data class CompositionFields(
        val fat: BodyMetric,
        val muscle: BodyMetric,
        val lean: BodyMetric,
        val fatMass: BodyMetric,
        val water: BodyMetric,
        val bone: BodyMetric,
        val protein: BodyMetric,
        val bmr: BodyMetric,
        val bmi: BodyMetric,
    )

    fun compositionFields(latest: CompositionScan?, scans: List<CompositionScan>, heightCm: Double): CompositionFields {
        val prior = scans.filter { scan ->
            latest != null && scan.at <= latest.at.minusSeconds(30L * 24 * 3600)
        }.maxByOrNull { it.at }
        fun bmi(scan: CompositionScan?): Double? {
            val weight = scan?.inputWeightKg ?: return null
            if (heightCm <= 0) return null
            val metres = heightCm / 100
            return weight / (metres * metres)
        }
        fun metric(
            id: String, label: String, unit: String, tint: BodyMetric.Tint,
            now: Double?, then: Double?, digits: Int = 1,
        ): BodyMetric {
            val change = if (now != null && then != null)
                L("%@ / 30D", Fmt.signedKg(now - then, decimals = digits)) else L("—— / 30D")
            val value = if (digits == 0) now?.let { Fmt.kcal(it) } else now?.let { Fmt.kg(it) }
            return BodyMetric(id, label, value ?: Fmt.dash, unit, change, tint)
        }
        return CompositionFields(
            fat = metric("fat", L("BODY FAT"), "%", BodyMetric.Tint.violet, latest?.bodyFatPercent, prior?.bodyFatPercent),
            muscle = metric("muscle", L("MUSCLE"), L("KG"), BodyMetric.Tint.lime, latest?.muscleMassKg, prior?.muscleMassKg),
            lean = metric("lean", L("LEAN MASS"), L("KG"), BodyMetric.Tint.lime, latest?.leanMassKg, prior?.leanMassKg),
            fatMass = metric("fatMass", L("FAT MASS"), L("KG"), BodyMetric.Tint.violet, latest?.fatMassKg, prior?.fatMassKg),
            water = metric("water", L("WATER"), "%", BodyMetric.Tint.cyan, latest?.bodyWaterPercent, prior?.bodyWaterPercent),
            bone = metric("bone", L("BONE"), L("KG"), BodyMetric.Tint.cyan, latest?.boneMassKg, prior?.boneMassKg),
            protein = metric("protein", L("PROTEIN"), "%", BodyMetric.Tint.cyan, latest?.proteinPercent, prior?.proteinPercent),
            bmr = metric("bmr", L("BMR"), "", BodyMetric.Tint.white, latest?.bmrKcal, prior?.bmrKcal, digits = 0),
            bmi = metric("bmi", L("BMI"), "", BodyMetric.Tint.white, bmi(latest), bmi(prior)),
        )
    }

    fun detail(zone: Zone, metrics: DailyMetrics, history: List<DailyMetrics>, meals: List<MealEntry>): Detail = when (zone) {
        Zone.head -> sleepDetail(metrics, history)
        Zone.heart -> heartDetail(metrics)
        Zone.gut -> foodDetail(metrics, meals)
        Zone.legs -> legsDetail(metrics, history)
    }

    fun sleepDetail(metrics: DailyMetrics, history: List<DailyMetrics>): Detail {
        val night = metrics.sleep
        val minutes = night?.totalMinutes
        val prior = history.mapNotNull { it.sleep?.totalMinutes }
        val versus = if (minutes == null || prior.size < 3) Fmt.dash else {
            val mean = prior.sum().toDouble() / prior.size
            val delta = swiftRound(minutes.toDouble() - mean)
            L("%@ VS AVG", Fmt.signed(delta.toDouble() / 60))
        }
        val verdict = if ((minutes ?: 0) > 0 && (minutes ?: 0) < 7 * 60) L("SHORT ON SLEEP") else L("LAST NIGHT")
        val stress = latestStress(metrics)
        val stressPeak = metrics.vitalsCurve.mapNotNull { it.stress }.maxOrNull()
        var note: String? = null
        if (minutes != null) {
            val shortNights = (listOf(minutes) + prior.take(1)).count { it < 7 * 60 }
            note = if (shortNights >= 2) L("Two short nights in a row. Last night was %@.", Fmt.duration(minutes))
            else L("Last night was %@.", Fmt.duration(minutes))
        }
        return Detail(
            zone = Zone.head,
            eyebrow = L("LAST NIGHT"),
            hero = minutes?.let { sleepHours(it) } ?: Fmt.dash,
            heroUnit = L("H"),
            aside = versus,
            verdict = verdict,
            stats = listOf(
                Stat("deep", L("DEEP SLEEP"), night?.let { sleepHours(it.deepMinutes) } ?: Fmt.dash,
                    L("H"), averageFoot(night?.deepMinutes, history.mapNotNull { it.sleep?.deepMinutes })),
                Stat("rem", L("REM"), night?.let { if (it.line.isEmpty()) null else sleepHours(it.remMinutes) } ?: Fmt.dash,
                    L("H"), averageFoot(night?.remMinutes, history.mapNotNull { it.sleep?.remMinutes })),
                Stat("light", L("LIGHT SLEEP"), night?.let { sleepHours(it.lightMinutes) } ?: Fmt.dash,
                    L("H"), averageFoot(night?.lightMinutes, history.mapNotNull { it.sleep?.lightMinutes })),
                Stat("score", L("SLEEP SCORE"), metrics.sleepScore?.score?.toString() ?: Fmt.dash,
                    "", if (metrics.sleepScore?.isCalibrating == true) L("CALIBRATING") else Fmt.dash),
                Stat("stress", L("STRESS"), stress?.toString() ?: Fmt.dash,
                    "", stressPeak?.let { if (it >= 60) L("PEAK %d", it) else L("TODAY") } ?: Fmt.dash),
                Stat("bed", L("BEDTIME"), night?.sleepStart?.let { Fmt.clock(it) } ?: Fmt.dash,
                    "", bedtimeFoot(night?.sleepStart)),
            ),
            noteLabel = L("TONIGHT"),
            note = note,
            status = sleepStatus(metrics),
        )
    }

    fun heartDetail(metrics: DailyMetrics): Detail {
        val inputs = heartInputs(metrics)
        val status = heartStatus(inputs)
        val verdict = when (status) {
            BodyStatus.dim -> Fmt.dash
            BodyStatus.good, BodyStatus.ok -> L("IN RANGE")
            BodyStatus.watch -> L("WATCH")
            BodyStatus.poor -> L("ELEVATED")
            BodyStatus.bad -> L("ATTENTION")
        }
        return Detail(
            zone = Zone.heart,
            eyebrow = L("HEART · TODAY"),
            hero = (inputs.live ?: inputs.rhr?.let { swiftRound(it) })?.toString() ?: Fmt.dash,
            heroUnit = L("BPM"),
            aside = Fmt.dash,
            verdict = verdict,
            stats = listOf(
                Stat("now", L("NOW"), inputs.live?.toString() ?: Fmt.dash,
                    L("BPM"), if (inputs.live == null) Fmt.dash else L("TODAY")),
                Stat("rhr", L("RESTING HR"), inputs.rhr?.let { swiftRound(it).toString() } ?: Fmt.dash,
                    L("BPM"), deltaFoot(inputs.rhr, inputs.rhrBase, L("BPM"))),
                Stat("peak", L("PEAK HR"), metrics.peakHR?.toString() ?: Fmt.dash,
                    L("BPM"), if (metrics.peakHR == null) Fmt.dash else L("TODAY")),
                Stat("hrv", L("HRV"), inputs.hrv?.let { swiftRound(it).toString() } ?: Fmt.dash,
                    L("MS"), deltaFoot(inputs.hrv, inputs.hrvBase, L("MS"))),
                Stat("spo2", L("SPO2 MIN"), inputs.spo2?.toString() ?: Fmt.dash,
                    "%", if (inputs.spo2 == null) Fmt.dash else L("LAST NIGHT")),
                Stat("resp", L("BREATH / MIN"), inputs.resp?.let { swiftFormat("%.1f", it) } ?: Fmt.dash,
                    "", if (inputs.resp == null) Fmt.dash else L("STEADY")),
            ),
            noteLabel = L("TODAY"),
            note = null,
            status = status,
        )
    }

    fun legsDetail(metrics: DailyMetrics, history: List<DailyMetrics>): Detail {
        val steps = VitalsReadout.daySteps(metrics)
        val metres = VitalsReadout.dayMetres(metrics)
        val active = VitalsReadout.dayActiveKcal(metrics)
        val status = legsStatus(steps)
        val prior = history.takeLast(8).dropLast(1).mapNotNull { VitalsReadout.daySteps(it) }
        val versus = if (steps == null || prior.size < 3) Fmt.dash else {
            val mean = prior.sum() / prior.size
            L("%@ VS AVG", Fmt.signed(steps - mean))
        }
        val sessions = metrics.segments.count { !it.allDay }
        val verdict = when (status) {
            BodyStatus.dim -> Fmt.dash
            BodyStatus.good -> L("ON PACE")
            BodyStatus.ok -> L("YOUR USUAL RANGE")
            BodyStatus.watch -> L("BELOW USUAL")
            BodyStatus.poor, BodyStatus.bad -> L("WELL BELOW")
        }
        return Detail(
            zone = Zone.legs,
            eyebrow = L("MOVEMENT · TODAY"),
            hero = steps?.let { Fmt.kcal(it) } ?: metres?.let { swiftFormat("%.1f", it / 1000) } ?: Fmt.dash,
            heroUnit = if (steps != null) L("STEPS") else L("KM"),
            aside = versus,
            verdict = verdict,
            stats = listOf(
                Stat("dist", L("DISTANCE"), metres?.let { swiftFormat("%.2f", it / 1000) } ?: Fmt.dash,
                    L("KM"), metres?.let { L("%@ M WALKED", Fmt.kcal(it)) } ?: L("NO DISTANCE YET")),
                Stat("active", L("ACTIVE"), active?.let { Fmt.kcal(it) } ?: Fmt.dash,
                    L("KCAL"), if (active == null) L("NEEDS YOUR WEIGHT") else L("MOVEMENT ONLY")),
                Stat("time", L("ACTIVE TIME"), Fmt.duration(metrics.activeMinutes),
                    "", if (metrics.activeMinutes == null) Fmt.dash else L("TODAY")),
                Stat("load", L("STRAIN"), Fmt.load(metrics.trainingLoad), "/21", L("TODAY")),
                Stat("sessions", L("SESSIONS"), if (sessions > 0) sessions.toString() else Fmt.dash, "", L("TODAY")),
            ),
            noteLabel = L("TODAY"),
            note = null,
            status = if (status == BodyStatus.dim) null else status,
            tint = legsTint(steps),
        )
    }

    fun foodDetail(metrics: DailyMetrics, meals: List<MealEntry>): Detail {
        val deck = food(metrics, meals)
        val plates = meals.filter { it.day == metrics.day && it.status == MealEntry.Status.confirmed }
        val last = plates.maxByOrNull { it.at }
        val delta = deck.kcalLeft?.let { -it }
        val verdict = when {
            delta == null -> Fmt.dash
            delta > ((deck.targetKcal ?: 0).toDouble() * 0.02).toInt() -> L("OVER ALLOWANCE")
            delta < 0 -> L("UNDER ALLOWANCE")
            else -> L("ON ALLOWANCE")
        }
        var note: String? = null
        if (deck.eatenKcal != null && deck.targetKcal != null) {
            note = L("Eaten %@ of %@ kcal.", Fmt.kcal(deck.eatenKcal.toDouble()), Fmt.kcal(deck.targetKcal.toDouble()))
        }
        return Detail(
            zone = Zone.gut,
            eyebrow = L("EATEN TODAY"),
            hero = delta?.let { Fmt.signedKcal(it.toDouble()) } ?: Fmt.dash,
            heroUnit = L("KCAL"),
            aside = "",
            verdict = verdict,
            stats = listOf(
                Stat("kcal", L("KCAL EATEN"), Fmt.kcal(deck.eatenKcal?.toDouble()),
                    "", deck.targetKcal?.let { L("ALLOWANCE %@", Fmt.kcal(it.toDouble())) } ?: Fmt.dash),
                Stat("protein", L("PROTEIN"), Fmt.int(deck.protein.eaten), L("G"), macroFoot(deck.protein)),
                Stat("carbs", L("CARBS"), Fmt.int(deck.carb.eaten), L("G"), macroFoot(deck.carb)),
                Stat("fat", L("FAT"), Fmt.int(deck.fat.eaten), L("G"), macroFoot(deck.fat)),
                Stat("last", L("LAST MEAL"), last?.let { Fmt.clock(it.at) } ?: Fmt.dash,
                    "", last?.let { if (mealLate(it.at)) L("LATE") else L("TODAY") } ?: Fmt.dash),
                Stat("meals", L("MEALS"),
                    if (deck.face == FoodFace.unlogged || deck.face == FoodFace.recovery) Fmt.dash else deck.meals.toString(),
                    "", L("TODAY")),
            ),
            noteLabel = L("TODAY"),
            note = note,
            status = if (deck.face == FoodFace.complete || deck.face == FoodFace.remaining) gutStatus(deck) else null,
            tint = gutTint(deck),
        )
    }

    fun timeline(
        day: UserDay, metrics: DailyMetrics, history: List<DailyMetrics>,
        meals: List<MealEntry>, recaps: List<SportSessionRecap>,
        weighIns: List<WeighIn>, measurements: List<MeasurementRecord>, usesMetric: Boolean,
        earlier: Boolean, now: Instant = Instant.now(), lookbackDays: Int = 6,
    ): List<HomeTimeline.Item> {
        val seenDays = HashSet<UserDay>()
        val firstDay = if (earlier) day.adding(-maxOf(0, lookbackDays)) else day
        val pool = (listOf(metrics) + history).filter {
            it.day >= firstDay && it.day <= day.adding(1) && seenDays.add(it.day)
        }
        val items = pool.flatMap { dayItems(it, now) }.toMutableList()
        val seenMeals = HashSet<UUID>()
        for (plate in meals) {
            if (!(seenMeals.add(plate.id) && plate.status == MealEntry.Status.confirmed)) continue
            items.add(
                HomeTimeline.Item(
                    id = "meal-${plate.id.toString().uppercase()}",
                    at = plate.at,
                    title = L("%@ · %@", capitalized(L(plate.slot.raw)), if (plate.text.isEmpty()) L("Meal") else plate.text),
                    detail = "",
                    accent = HomeTimeline.Accent.meal,
                    meal = HomeTimeline.Meal(
                        kcal = swiftRound(plate.kcal), protein = swiftRound(plate.protein),
                        carb = swiftRound(plate.carb), fat = swiftRound(plate.fat), photoPath = plate.photoPath,
                    ),
                    trailing = null,
                ),
            )
        }
        for (recap in recaps) {
            if (!recap.isValid) continue
            val delta = recap.loadAfter?.let { after -> recap.loadBefore?.let { after - it } }
            items.add(
                HomeTimeline.Item(
                    id = "sport-${recap.id}",
                    at = recap.startedAt,
                    title = recap.title,
                    detail = listOfNotNull(
                        "${Fmt.clock(recap.startedAt)}–${timelineClock(recap.endedAt, UserDay.containing(recap.startedAt))}",
                        if (recap.seconds < 60) L("%d SEC", recap.seconds) else Fmt.duration(recap.seconds / 60),
                        recap.avgHR?.let { L("HR %d", it) },
                        if (recap.hasEnergy) L("%@ kcal", Fmt.kcal(recap.kcal)) else null,
                    ).joinToString(" · "),
                    accent = HomeTimeline.Accent.workout,
                    meal = null,
                    trailing = delta?.let { swiftFormat("%+.1f", it) },
                    endAt = recap.endedAt,
                ),
            )
        }
        for (entry in weighIns) {
            if (entry.origin == WeighIn.Origin.band || !entry.weightKg.isFinite() || entry.weightKg <= 0) continue
            val weight = if (usesMetric) entry.weightKg else entry.weightKg * 2.2046226
            val unit = if (usesMetric) L("KG") else L("LB")
            items.add(
                HomeTimeline.Item(
                    id = "weight-${entry.id.toString().uppercase()}",
                    at = entry.date,
                    title = L("Weigh-in"),
                    detail = "${Fmt.kg(weight)} $unit · ${if (entry.origin == WeighIn.Origin.health) L("Health Connect") else L("Manual entry")}",
                    accent = HomeTimeline.Accent.weighIn,
                    meal = null,
                    trailing = null,
                ),
            )
        }
        for (record in measurements) {
            val accent: HomeTimeline.Accent
            val detail: String
            when (val d = record.detail) {
                is MeasurementRecord.BodyScan -> {
                    accent = HomeTimeline.Accent.bodyScan
                    val fat = d.bodyFatPercent?.let { "${Fmt.kg(it)}%" } ?: Fmt.dash
                    val lean = d.leanMassKg?.let {
                        "${Fmt.kg(if (usesMetric) it else it * 2.2046226)} ${if (usesMetric) L("KG") else L("LB")}"
                    } ?: Fmt.dash
                    detail = L("Body fat %@ · Lean mass %@", fat, lean)
                }
                is MeasurementRecord.BalanceCheck -> {
                    accent = HomeTimeline.Accent.balanceCheck
                    detail = record.summary
                }
            }
            items.add(
                HomeTimeline.Item(
                    id = "measurement-${record.id.toString().uppercase()}",
                    at = record.at,
                    title = record.title,
                    detail = detail,
                    accent = accent,
                    meal = null,
                    trailing = null,
                    recordID = record.id,
                ),
            )
        }
        return HomeTimeline.visible(items, day, earlier, now, lookbackDays)
    }

    private fun dayItems(metrics: DailyMetrics, now: Instant): List<HomeTimeline.Item> {
        val items = sleepItems(metrics).toMutableList()
        items += metrics.segments.filter { !it.allDay }.map { segmentItem(it) }
        val readings = metrics.vitalsCurve.filter {
            it.ts >= metrics.day.start && it.ts < metrics.day.end && it.ts <= now
        }
        val peak = readings.maxByOrNull { it.stress ?: -1 }
        val stress = peak?.stress
        if (peak != null && stress != null && stress >= 60) {
            items.add(
                HomeTimeline.Item(
                    id = "stress-${metrics.day.key}",
                    at = peak.ts,
                    title = L("Stress peak · %d", stress),
                    detail = L("Highest recorded stress that day."),
                    accent = HomeTimeline.Accent.stress,
                    meal = null,
                    trailing = null,
                ),
            )
        }
        return items
    }

    private fun sleepItems(metrics: DailyMetrics): List<HomeTimeline.Item> {
        val night = metrics.sleep ?: return emptyList()
        val start = night.sleepStart
        val wake = night.wakeAt
        if (start != null && wake != null && wake <= start) return emptyList()
        val source = when {
            night.isUserReported -> L("Manually logged sleep")
            night.isCorrected -> L("Edited sleep times")
            else -> L("Recorded by NEXTBODY")
        }
        val items = mutableListOf<HomeTimeline.Item>()
        if (start != null) {
            items.add(
                HomeTimeline.Item(
                    id = "sleep-start-${metrics.day.key}", at = start, title = L("Fell asleep"),
                    detail = source, accent = HomeTimeline.Accent.sleep, meal = null, trailing = null, endAt = wake,
                ),
            )
        }
        if (wake != null) {
            items.add(
                HomeTimeline.Item(
                    id = "sleep-wake-${metrics.day.key}",
                    at = wake,
                    title = metrics.sleepScore?.let { L("Woke up · sleep %d", it.score) } ?: L("Woke up"),
                    detail = listOfNotNull(
                        if (night.totalMinutes > 0) Fmt.duration(night.totalMinutes) else null,
                        start?.let { L("Asleep at %@", timelineClock(it, UserDay.containing(wake))) },
                        metrics.nightInputs?.hrv?.let { L("HRV %d ms", swiftRound(it)) },
                        night.spo2.map { it.percent }.minOrNull()?.let { L("SpO2 %d%%", it) },
                        if (night.isUserReported || night.isCorrected) source else null,
                    ).joinToString(" · "),
                    accent = HomeTimeline.Accent.wake,
                    meal = null,
                    trailing = null,
                ),
            )
        }
        return items
    }

    private fun timelineClock(at: Instant, day: UserDay): String =
        if (UserDay.containing(at) == day) Fmt.clock(at) else Fmt.displayDate(at, "MMM d HH:mm")

    private fun segmentItem(segment: TrainingSegment): HomeTimeline.Item = HomeTimeline.Item(
        id = "segment-${segment.at.toEpochMilli()}",
        at = segment.at,
        title = L("Activity · %@", segment.name),
        detail = listOfNotNull(
            segment.minutes?.let { Fmt.duration(it) },
            segment.avgHR?.let { L("HR %d", it) },
            segment.steps?.let { L("%@ steps", Fmt.kcal(it.toDouble())) },
        ).joinToString(" · "),
        accent = HomeTimeline.Accent.activity,
        meal = null,
        trailing = swiftFormat("%+.1f", segment.delta),
        endAt = segment.minutes?.let { segment.at.plusSeconds(it.toLong() * 60) },
    )

    fun sleepHours(minutes: Int): String = swiftFormat("%.1f", minutes.toDouble() / 60)

    fun signedInt(value: Int): String = if (value > 0) "+$value" else "$value"

    private fun averageFoot(value: Int?, prior: List<Int>): String {
        if (value == null || prior.size < 3) return Fmt.dash
        val mean = prior.sum().toDouble() / prior.size
        val deltaHours = (value.toDouble() - mean) / 60
        return L("%@ / AVG", swiftFormat("%+.1f", deltaHours))
    }

    private fun deltaFoot(value: Double?, base: Double?, unit: String): String {
        if (value == null || base == null) return Fmt.dash
        val delta = swiftRound(value - base)
        return L("%@ / 7D", "${signedInt(delta)} $unit")
    }

    private fun bedtimeFoot(start: Instant?): String {
        if (start == null) return Fmt.dash
        val hour = start.atZone(ZoneId.systemDefault()).hour
        if (hour >= 23 || hour < 5) return L("LATE")
        return L("ON TIME")
    }

    private fun mealLate(date: Instant): Boolean {
        val hour = date.atZone(ZoneId.systemDefault()).hour
        return hour >= 21 || hour < 4
    }

    private fun macroFoot(macro: Macro): String {
        val left = macro.left ?: return Fmt.dash
        val target = macro.target ?: return Fmt.dash
        if (macro.met) return L("HIT")
        return L("%dg / %dg", target - left, target)
    }

    /** Swift `.rounded()` — half away from zero. */
    internal fun swiftRound(v: Double): Int = if (v >= 0) (v + 0.5).toInt() else -((-v + 0.5).toInt())

    /** Swift `localizedCapitalized`. */
    private fun capitalized(s: String): String =
        s.lowercase(Locale.getDefault()).split(" ").joinToString(" ") { w ->
            w.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString() }
        }
}
