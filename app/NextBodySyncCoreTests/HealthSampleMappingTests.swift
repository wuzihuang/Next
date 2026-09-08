import XCTest
@testable import NextBodySyncCore

final class HealthSampleMappingTests: XCTestCase {
    func testAutomaticMeasurementIntervalsOfferSubStepProbesBelowTheDeviceStep() {
        XCTAssertEqual(
            AutoMeasurementIntervalPolicy.options(minimumStepMinutes: 5),
            [1, 2, 3, 4] + Array(stride(from: 5, through: 180, by: 5))
        )
        XCTAssertEqual(
            AutoMeasurementIntervalPolicy.options(minimumStepMinutes: 1),
            Array(1...180)
        )
        XCTAssertEqual(
            AutoMeasurementIntervalPolicy.options(minimumStepMinutes: 7),
            [1, 2, 3, 4, 5, 6] + Array(stride(from: 7, through: 175, by: 7))
        )
    }

    func testZeroStepMeansEveryWholeMinuteValueIncludingZeroIsSupported() {
        let options = AutoMeasurementIntervalPolicy.options(minimumStepMinutes: 0)

        XCTAssertEqual(options.first, 0)
        XCTAssertEqual(options.last, 180)
        XCTAssertEqual(options.count, 181)
    }

    func testAutomaticMeasurementIntervalValidationRejectsOutOfRangeValues() {
        XCTAssertTrue(AutoMeasurementIntervalPolicy.isValid(1, minimumStepMinutes: 1))
        XCTAssertTrue(AutoMeasurementIntervalPolicy.isValid(15, minimumStepMinutes: 5))
        XCTAssertTrue(AutoMeasurementIntervalPolicy.isValid(3, minimumStepMinutes: 5))
        XCTAssertFalse(AutoMeasurementIntervalPolicy.isValid(185, minimumStepMinutes: 5))
        XCTAssertFalse(AutoMeasurementIntervalPolicy.isValid(-1, minimumStepMinutes: 0))
        XCTAssertTrue(AutoMeasurementIntervalPolicy.isValid(180, minimumStepMinutes: 0))
        XCTAssertFalse(AutoMeasurementIntervalPolicy.isValid(181, minimumStepMinutes: 0))
    }

    func testSwitchFallbackReadsVendorByteTablesAndSkipsAbsentFlags() {
        var switchData = [UInt8](repeating: 0, count: 20)
        switchData[4] = 1
        switchData[5] = 2
        switchData[12] = 1
        switchData[16] = 2
        var switchTwoData = [UInt8](repeating: 0, count: 20)
        switchTwoData[4] = 2
        switchTwoData[9] = 1

        let readings = AutoMeasurementSwitchFallback.readings(
            switchData: switchData,
            switchTwoData: switchTwoData,
            oxygenSupported: true,
            oxygenOn: false)

        XCTAssertEqual(readings.map(\.kind), [
            .heartRate, .bloodPressure, .hrv, .scientificSleep,
            .bloodOxygen, .temperature, .stress
        ])
        XCTAssertEqual(readings.map(\.on), [true, false, true, false, false, false, true])
    }

    func testSwitchFallbackTreatsShortBlobsAsMissingTables() {
        XCTAssertFalse(AutoMeasurementSwitchFallback.hasSwitchTables(switchData: [0, 1], switchTwoData: []))
        XCTAssertTrue(AutoMeasurementSwitchFallback.hasSwitchTables(
            switchData: [UInt8](repeating: 0, count: 13),
            switchTwoData: []))
        XCTAssertEqual(
            AutoMeasurementSwitchFallback.readings(
                switchData: [0, 1, 2],
                switchTwoData: [],
                oxygenSupported: false,
                oxygenOn: false),
            [])
    }

    func testHistoricalUserDayReadsItsCalendarDayAndTheFollowingCalendarDay() {
        XCTAssertEqual(HealthSampleMapping.deviceDayOffsets(daysBack: 1, straddles: true), [1, 0])
        XCTAssertEqual(HealthSampleMapping.deviceDayOffsets(daysBack: 2, straddles: true), [2, 1])
        XCTAssertEqual(HealthSampleMapping.deviceDayOffsets(daysBack: 0, straddles: true), [0, 1])
        XCTAssertEqual(HealthSampleMapping.deviceDayOffsets(daysBack: 0, straddles: false), [0])
    }

    func testSameClockOnAdjacentDevicePagesKeepsDistinctCalendarDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let secondDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: firstDay))

        let first = try XCTUnwrap(HealthSampleMapping.instant(time: "01:30", calendarDay: firstDay,
                                                               calendar: calendar))
        let second = try XCTUnwrap(HealthSampleMapping.instant(time: "01:30", calendarDay: secondDay,
                                                                calendar: calendar))
        XCTAssertEqual(second.timeIntervalSince(first), 24 * 60 * 60, accuracy: 0.1)
    }

    func testTemperatureUsesSkinValueAndNormalizesTenths() {
        let sample = HealthSampleMapping.temperature(from: [
            "hour": 6,
            "minute": 5,
            "value": 368,
            "originalValue": 342,
        ])

        let value = try? XCTUnwrap(sample)
        XCTAssertEqual(value?.time, "06:05")
        XCTAssertEqual(value?.celsius ?? 0, 34.2, accuracy: 0.001)
    }

    func testTemperatureRejectsMissingAndOutOfRangeSkinValues() {
        XCTAssertNil(HealthSampleMapping.temperature(from: ["hour": 6, "minute": 5, "value": 36.8]))
        XCTAssertNil(HealthSampleMapping.temperature(from: [
            "hour": 24, "minute": 5, "originalValue": 34.2,
        ]))
        XCTAssertNil(HealthSampleMapping.temperature(from: [
            "hour": 6, "minute": 5, "originalValue": 99.0,
        ]))
    }

    func testOxygenReadsTimeAndPercentAndIgnoresApneaFlags() {
        let sample = HealthSampleMapping.oxygen(from: [
            "Time": "02:15",
            "OxygenValue": 96,
            "ApneaResult": 2,
        ])
        XCTAssertEqual(sample?.time, "02:15")
        XCTAssertEqual(sample?.percent, 96)
    }

    func testOxygenRejectsEmptyAndOutOfRangePercents() {
        XCTAssertNil(HealthSampleMapping.oxygen(from: ["Time": "02:15", "OxygenValue": 0]))
        XCTAssertNil(HealthSampleMapping.oxygen(from: ["Time": "02:15", "OxygenValue": 49]))
        XCTAssertNil(HealthSampleMapping.oxygen(from: ["Time": "02:15", "OxygenValue": 101]))
        XCTAssertNil(HealthSampleMapping.oxygen(from: ["OxygenValue": 96]))
    }

    func testOvernightOxygenSummaryIsNilWhenEmpty() {
        XCTAssertNil(HealthSampleMapping.overnightOxygenSummary([]))
        let summary = HealthSampleMapping.overnightOxygenSummary([96, 94, 91, 97])
        XCTAssertEqual(summary?.mean, 95)
        XCTAssertEqual(summary?.min, 91)
    }

    func testHRVComputesRMSSDFromTenMillisecondRRUnits() {
        let sample = HealthSampleMapping.hrv(from: [
            "time": "01:03",
            "hrvValue": 47,
            "hearts": ["80", "82", "79"],
        ])

        let value = try? XCTUnwrap(sample)
        XCTAssertEqual(value?.time, "01:03")
        XCTAssertEqual(value?.vendorValue, 47)
        XCTAssertEqual(value?.rmssdMS ?? 0, sqrt(650), accuracy: 0.001)
        XCTAssertEqual(value?.rrCount, 3)
    }

    func testHRVNeverLabelsVendorOnlyValueAsRMSSD() {
        let sample = HealthSampleMapping.hrv(from: [
            "time": "01:03",
            "hrvValue": 47,
            "hearts": [],
        ])

        XCTAssertEqual(sample?.vendorValue, 47)
        XCTAssertNil(sample?.rmssdMS)
    }

    func testHRVBySlotFloorsAMeasuredMinuteOntoItsFiveMinuteSlot() {
        let slots = HealthSampleMapping.hrvBySlot([
            HrvMinuteSample(time: "00:00", rmssdMS: 44, vendorValue: 43, rrCount: 4),
            HrvMinuteSample(time: "00:12", rmssdMS: 51, vendorValue: 43, rrCount: 4),
            HrvMinuteSample(time: "23:57", rmssdMS: 35, vendorValue: 33, rrCount: 4),
        ])

        XCTAssertEqual(slots["00:00"], 44)
        XCTAssertEqual(slots["00:10"], 51)
        XCTAssertEqual(slots["23:55"], 35)
        XCTAssertEqual(slots.count, 3)
    }

    func testHRVBySlotKeepsTheMedianWhenOneSlotCaughtSeveralMinutes() {
        let slots = HealthSampleMapping.hrvBySlot([
            HrvMinuteSample(time: "06:00", rmssdMS: 30, vendorValue: nil, rrCount: 4),
            HrvMinuteSample(time: "06:01", rmssdMS: 90, vendorValue: nil, rrCount: 4),
            HrvMinuteSample(time: "06:02", rmssdMS: 40, vendorValue: nil, rrCount: 4),
        ])

        XCTAssertEqual(slots["06:00"], 40)
    }

    func testHRVBySlotDropsVendorOnlyAndImplausibleMinutes() {
        let slots = HealthSampleMapping.hrvBySlot([
            HrvMinuteSample(time: "07:00", rmssdMS: nil, vendorValue: 47, rrCount: 1),
            HrvMinuteSample(time: "07:05", rmssdMS: 900, vendorValue: 47, rrCount: 4),
            HrvMinuteSample(time: "07:10", rmssdMS: 0, vendorValue: 47, rrCount: 4),
            HrvMinuteSample(time: "07:15", rmssdMS: 48, vendorValue: 47, rrCount: 4),
        ])

        XCTAssertEqual(slots, ["07:15": 48])
    }

    func testOriginDistanceKilometresBecomeMetres() {
        XCTAssertEqual(HealthSampleMapping.distanceMeters(from: 0.036), 36)
        XCTAssertEqual(HealthSampleMapping.distanceMeters(from: "0.036"), 36)
        XCTAssertEqual(HealthSampleMapping.distanceMeters(from: NSNumber(value: 1.2)), 1_200)
        XCTAssertEqual(HealthSampleMapping.distanceMeters(from: 0), 0)
        XCTAssertEqual(HealthSampleMapping.distanceMeters(from: "0.000"), 0)
    }

    func testOriginDistanceAlreadyInMetresIsLeftAlone() {
        XCTAssertEqual(HealthSampleMapping.distanceMeters(from: 36), 36)
        XCTAssertEqual(HealthSampleMapping.distanceMeters(from: "40"), 40)
    }

    func testOriginDistanceRejectsMissingAndNegativeValues() {
        XCTAssertNil(HealthSampleMapping.distanceMeters(from: nil))
        XCTAssertNil(HealthSampleMapping.distanceMeters(from: -0.1))
        XCTAssertNil(HealthSampleMapping.distanceMeters(from: "nope"))
    }

    func testBodyBatteryTreatsSDKStageZeroAsDeepSleepAndRecovers() {
        let tick = BodyBatteryEngine.Tick(
            heartRate: 50, hrvMS: 58, stress: 18, steps: 0, met: 0.9,
            sleepStage: 0
        )
        let result = BodyBatteryEngine.replay(
            anchor: 20,
            ticks: Array(repeating: tick, count: 67),
            baseline: .init(restingHeartRate: 52, maximumHeartRate: 190,
                            hrvMS: 50, recoveryMultiplier: 1)
        )

        XCTAssertGreaterThan(result.value, 20)
        XCTAssertGreaterThan(result.drivers.recovery, 0)
        XCTAssertEqual(result.drivers.awake, 0, accuracy: 0.001)
    }

    func testServerReplayUsesVeepooStageZeroMapping() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let migration = repository
            .appending(path: "supabase/migrations/20260903140000_body_battery_realtime.sql")
        let sql = try String(contentsOf: migration, encoding: .utf8)

        XCTAssertTrue(sql.contains("when 0 then 1.25"))
        XCTAssertFalse(sql.contains("stage <> 0 as asleep"))
        XCTAssertTrue(sql.contains("nullif(n.sleep_line, '')"))
        XCTAssertTrue(sql.contains("between p_user_day and p_user_day + 1"))
        XCTAssertTrue(sql.contains("count(*) filter (where m.stage <> 4)"))
        XCTAssertTrue(sql.contains("fallback_minute as"))
        XCTAssertTrue(sql.contains("interval '1 minute'"))
        XCTAssertTrue(sql.contains("where r.n > 0 and r.observed"))
    }

    func testServerReserveCanStartFromDaytimeSignalsWithoutSleep() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let migration = repository
            .appending(path: "supabase/migrations/20260903140000_body_battery_realtime.sql")
        let sql = try String(contentsOf: migration, encoding: .utf8)
        let client = repository
            .appending(path: "app/NextBody/Services/Repository.swift")
        let clientSource = try String(contentsOf: client, encoding: .utf8)

        XCTAssertTrue(sql.contains("else 50::numeric"))
        XCTAssertTrue(sql.contains("and s.sleep_start is not null and s.wake_at is not null"))
        XCTAssertTrue(sql.contains("create or replace function nb.compute_reserve"))
        XCTAssertFalse(sql.contains("if v_sleep is null"))
        XCTAssertTrue(sql.contains("if v_reserve.current_value is not null then"))
        XCTAssertTrue(clientSource.contains("number(row[\"reserve_score\"])"))
    }

    func testBodyBatteryCorrectionMigrationRebasesAndCleansStaleZeroes() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let migration = repository
            .appending(path: "supabase/migrations/20260903150000_recompute_body_battery_v2.sql")
        let sql = try String(contentsOf: migration, encoding: .utf8)

        XCTAssertTrue(sql.contains("dr.algo_version like '%bb-2.0%'"))
        XCTAssertTrue(sql.contains("from public.reserve_samples rs"))
        XCTAssertTrue(sql.contains("create or replace function nb.clear_unknown_reserve_artifacts()"))
        XCTAssertTrue(sql.contains("when (new.reserve_score is null)"))
        XCTAssertTrue(sql.contains("delete from public.reserve_daily rd"))
        XCTAssertTrue(sql.contains("delete from public.reserve_samples rs"))
        XCTAssertTrue(sql.contains("v_today,\n      v_today,"))
        XCTAssertTrue(sql.contains("'bb-2.0 migration'"))
    }

    func testBodyBatteryUsesHeartHRVStressAndMovementTogether() {
        let baseline = BodyBatteryEngine.Baseline(
            restingHeartRate: 55, maximumHeartRate: 190,
            hrvMS: 52, recoveryMultiplier: 1
        )
        let quiet = BodyBatteryEngine.Tick(
            heartRate: 60, hrvMS: 58, stress: 25, steps: 0, met: 1.0
        )
        let strained = BodyBatteryEngine.Tick(
            heartRate: 145, hrvMS: 24, stress: 82, steps: 620, met: 6.0
        )

        let quietResult = BodyBatteryEngine.replay(anchor: 70, ticks: [quiet], baseline: baseline)
        let strainedResult = BodyBatteryEngine.replay(anchor: 70, ticks: [strained], baseline: baseline)

        XCTAssertLessThan(strainedResult.value, quietResult.value)
        XCTAssertGreaterThan(strainedResult.drivers.movement, quietResult.drivers.movement)
        XCTAssertGreaterThan(strainedResult.drivers.stress, quietResult.drivers.stress)
    }

    func testBodyBatteryDoesNotDrainWhenBandIsOffWrist() {
        let result = BodyBatteryEngine.replay(
            anchor: 64,
            ticks: [.init()],
            baseline: .init(restingHeartRate: 55, maximumHeartRate: 190,
                            hrvMS: 50, recoveryMultiplier: 1)
        )

        XCTAssertEqual(result.value, 64, accuracy: 0.001)
        XCTAssertEqual(result.wornMinutes, 0)
    }

    func testBodyBatterySleepRecoverySaturatesInsteadOfDriftingToOneHundred() {
        let tick = BodyBatteryEngine.Tick(
            heartRate: 48, hrvMS: 55, stress: 15, steps: 0, met: 0.9,
            sleepStage: 0
        )
        let baseline = BodyBatteryEngine.Baseline(
            restingHeartRate: 52, maximumHeartRate: 190,
            hrvMS: 50, recoveryMultiplier: 1
        )

        let fromLow = BodyBatteryEngine.replay(
            anchor: 20, ticks: Array(repeating: tick, count: 96), baseline: baseline
        )
        let fromHigh = BodyBatteryEngine.replay(
            anchor: 90, ticks: Array(repeating: tick, count: 96), baseline: baseline
        )

        XCTAssertLessThan(fromLow.value, 96)
        XCTAssertLessThan(fromHigh.value, 96)
        XCTAssertGreaterThan(fromLow.drivers.recovery, fromHigh.drivers.recovery)
    }

    func testBodyBatteryOneMinutePreviewMatchesOneFiveMinuteTick() {
        let baseline = BodyBatteryEngine.Baseline(
            restingHeartRate: 55, maximumHeartRate: 190,
            hrvMS: 52, recoveryMultiplier: 1
        )
        let full = BodyBatteryEngine.Tick(
            durationMinutes: 5, heartRate: 145, hrvMS: 24,
            stress: 82, steps: 620, met: 6
        )
        let minute = BodyBatteryEngine.Tick(
            durationMinutes: 1, heartRate: 145, hrvMS: 24,
            stress: 82, steps: 124, met: 6
        )

        let oneTick = BodyBatteryEngine.replay(anchor: 70, ticks: [full], baseline: baseline)
        let fiveMinutes = BodyBatteryEngine.replay(
            anchor: 70, ticks: Array(repeating: minute, count: 5), baseline: baseline
        )

        // The drain is scaled by the charge remaining at the start of each tick, so five
        // one-minute steps recompute that scale four more times than one five-minute step.
        // The two agree to first order; the residual is thousandths of a point.
        XCTAssertEqual(oneTick.value, fiveMinutes.value, accuracy: 0.01)
        XCTAssertEqual(oneTick.drivers.stress, fiveMinutes.drivers.stress, accuracy: 0.01)
    }

    func testBodyBatteryStageFourIsAwakeRatherThanFrozenSleep() {
        let baseline = BodyBatteryEngine.Baseline(
            restingHeartRate: 55, maximumHeartRate: 190,
            hrvMS: 52, recoveryMultiplier: 1
        )
        let awakeInBed = BodyBatteryEngine.Tick(
            heartRate: 62, hrvMS: 48, stress: 30, steps: 0, met: 1,
            sleepStage: 4
        )
        let result = BodyBatteryEngine.replay(anchor: 70, ticks: [awakeInBed], baseline: baseline)

        XCTAssertLessThan(result.value, 70)
        XCTAssertGreaterThan(result.drivers.awake, 0)
        XCTAssertEqual(result.drivers.recovery, 0)
    }

    func testBodyBatteryCarriesQuietRunAcrossOneMinutePreviewTicks() {
        let baseline = BodyBatteryEngine.Baseline(
            restingHeartRate: 55, maximumHeartRate: 190,
            hrvMS: 52, recoveryMultiplier: 1
        )
        let quietMinute = BodyBatteryEngine.Tick(
            durationMinutes: 1, heartRate: 58, hrvMS: 55,
            stress: 20, steps: 0, met: 1
        )
        let result = BodyBatteryEngine.replay(
            anchor: 60,
            ticks: Array(repeating: quietMinute, count: 21),
            baseline: baseline
        )

        XCTAssertGreaterThan(result.drivers.restorativeRest, 0)
    }

    func testBodyBatteryQuietThresholdIsIndependentOfTickDuration() {
        let baseline = BodyBatteryEngine.Baseline(
            restingHeartRate: 55, maximumHeartRate: 190,
            hrvMS: 52, recoveryMultiplier: 1
        )
        let minute = BodyBatteryEngine.Tick(
            durationMinutes: 1, heartRate: 58, hrvMS: 55,
            stress: 20, steps: 0, met: 1.5
        )
        let fiveMinutes = BodyBatteryEngine.Tick(
            durationMinutes: 5, heartRate: 58, hrvMS: 55,
            stress: 20, steps: 0, met: 1.5
        )

        let minuteResult = BodyBatteryEngine.replay(
            anchor: 60, ticks: Array(repeating: minute, count: 20), baseline: baseline
        )
        let fiveMinuteResult = BodyBatteryEngine.replay(
            anchor: 60, ticks: Array(repeating: fiveMinutes, count: 4), baseline: baseline
        )

        XCTAssertEqual(minuteResult.drivers.restorativeRest, 0)
        XCTAssertEqual(minuteResult.value, fiveMinuteResult.value, accuracy: 0.001)
    }

    func testFreshBandTickAdvancesAStaleEightAMCurveImmediately() throws {
        let eightAM = Date(timeIntervalSince1970: 1_788_436_800)
        let twelveFortyFive = eightAM.addingTimeInterval(4.75 * 60 * 60)
        let stored = [VitalSample(ts: eightAM, hr: 61, stress: 18)]
        let fresh = [VitalSample(ts: twelveFortyFive, hr: 78, stress: 31)]

        let merged = VitalSample.merging(stored, with: fresh)

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(try XCTUnwrap(merged.last).ts, twelveFortyFive)
        XCTAssertEqual(merged.last?.hr, 78)
    }

    func testFreshPartialTickKeepsFieldsAlreadyLoadedFromServer() throws {
        let timestamp = Date(timeIntervalSince1970: 1_788_453_900)
        let stored = VitalSample(
            ts: timestamp, hr: 62, stress: 17,
            temp: 33.8, steps: 24, vendorCalories: 1.2, dis: 18, hrv: 51
        )
        let fresh = VitalSample(ts: timestamp, hr: 64, stress: nil)

        let merged = try XCTUnwrap(VitalSample.merging([stored], with: [fresh]).first)

        XCTAssertEqual(merged.hr, 64)
        XCTAssertEqual(merged.stress, 17)
        XCTAssertEqual(merged.temp, 33.8)
        XCTAssertEqual(merged.hrv, 51)
    }

    func testRollingVitalsWindowIsExactlyThePastTwentyFourHours() {
        let now = Date(timeIntervalSince1970: 1_788_453_900)
        let window = VitalsTimelinePolicy.rolling24Hours(endingAt: now)

        XCTAssertEqual(window.start, now.addingTimeInterval(-24 * 60 * 60))
        XCTAssertEqual(window.end, now)
        XCTAssertTrue(window.contains(now.addingTimeInterval(-23 * 60 * 60)))
        XCTAssertFalse(window.contains(now.addingTimeInterval(-25 * 60 * 60)))
        XCTAssertFalse(window.contains(now.addingTimeInterval(1)))
    }

    func testCurrentUserDayWindowStopsAtNowInsteadOfDrawingFutureHours() {
        let start = Date(timeIntervalSince1970: 1_788_422_400)
        let end = start.addingTimeInterval(24 * 60 * 60)
        let now = start.addingTimeInterval(8.75 * 60 * 60)

        let window = VitalsTimelinePolicy.userDay(start: start, end: end, now: now)

        XCTAssertEqual(window.start, start)
        XCTAssertEqual(window.end, now)
        XCTAssertFalse(window.contains(now.addingTimeInterval(60)))
    }

    func testCurrentStressJoinsLastPositiveReadingInside24h() {
        let now = Date(timeIntervalSince1970: 1_788_453_900)
        let earlier = now.addingTimeInterval(-3 * 3600)
        let value = VitalsTimelinePolicy.currentStress(
            latest: nil,
            previous: (28, earlier),
            at: now)

        XCTAssertEqual(value, 28)
    }

    func testCurrentStressDoesNotJoinReadingOlderThan24h() {
        let now = Date(timeIntervalSince1970: 1_788_453_900)
        let earlier = now.addingTimeInterval(-25 * 3600)
        let value = VitalsTimelinePolicy.currentStress(
            latest: nil,
            previous: (28, earlier),
            at: now)

        XCTAssertNil(value)
    }

    func testCurrentStressPrefersTheLatestTick() {
        let now = Date(timeIntervalSince1970: 1_788_453_900)
        let value = VitalsTimelinePolicy.currentStress(
            latest: 41,
            previous: (28, now.addingTimeInterval(-3600)),
            at: now)

        XCTAssertEqual(value, 41)
    }

    func testCurrentHeartJoinsLastPositiveReadingInside24h() {
        let now = Date(timeIntervalSince1970: 1_788_453_900)
        let earlier = now.addingTimeInterval(-3 * 3600)
        let value = VitalsTimelinePolicy.currentHeart(
            latest: nil,
            previous: (72, earlier),
            at: now)

        XCTAssertEqual(value, 72)
    }

    func testCurrentHeartDoesNotJoinReadingOlderThan24h() {
        let now = Date(timeIntervalSince1970: 1_788_453_900)
        let earlier = now.addingTimeInterval(-25 * 3600)
        let value = VitalsTimelinePolicy.currentHeart(
            latest: nil,
            previous: (72, earlier),
            at: now)

        XCTAssertNil(value)
    }

    func testCurrentHeartPrefersTheLatestTick() {
        let now = Date(timeIntervalSince1970: 1_788_453_900)
        let value = VitalsTimelinePolicy.currentHeart(
            latest: 88,
            previous: (72, now.addingTimeInterval(-3600)),
            at: now)

        XCTAssertEqual(value, 88)
    }

    /// Issue #19 · a card labelled TODAY draws today. Yesterday evening is not today,
    /// however recently it was measured.
    func testTodaySamplesDropYesterdayEveningHeart() {
        let day = UserDay.containing(Date())
        let now = day.start.addingTimeInterval(9 * 3600)
        let yesterdayEvening = day.start.addingTimeInterval(-3 * 3600)
        let thisMorning = day.start.addingTimeInterval(8 * 3600)
        let samples = [
            VitalSample(ts: yesterdayEvening, hr: 72, stress: 33),
            VitalSample(ts: thisMorning, hr: 61, stress: 18),
        ]

        let today = VitalSample.today(samples, endingAt: now)

        XCTAssertEqual(today.count, 1)
        XCTAssertEqual(today.compactMap(\.hr), [61])
    }

    func testTodaySamplesStartAtLocalMidnightNotFourAM() {
        let day = UserDay.containing(Date())
        let now = day.start.addingTimeInterval(9 * 3600)
        let smallHours = day.start.addingTimeInterval(2 * 3600)
        let samples = [VitalSample(ts: smallHours, hr: 55, stress: 12)]

        let today = VitalSample.today(samples, endingAt: now)

        XCTAssertEqual(today.compactMap(\.stress), [12],
                       "02:00 is inside today, not the tail of yesterday")
    }

    func testRawVitalsLoadIsNotGatedByDailyResultsSettlement() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repository.appending(path: "app/NextBody/Services/Repository.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("guard !rows.isEmpty else { return }"))
        XCTAssertTrue(source.contains("day.adding(days: -max(days, 1) - 1).start"))
        XCTAssertTrue(source.contains("VitalSample.merging(remoteSamples, with: localSamples)"))
    }

    func testTemperatureRepairFunctionCanOnlyFillNullOwnedRows() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let migration = repository.appending(
            path: "supabase/migrations/20260903171349_fill_temperature.sql"
        )
        let sql = try String(contentsOf: migration, encoding: .utf8)

        XCTAssertTrue(sql.contains("r.user_id = v_user"))
        XCTAssertTrue(sql.contains("r.temp is null"))
        XCTAssertTrue(sql.contains("s.temp between 20 and 45"))
        XCTAssertTrue(sql.contains("revoke execute on function public.fill_temp(jsonb)"))
    }
}
