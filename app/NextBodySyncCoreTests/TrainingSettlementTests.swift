import XCTest
@testable import NextBodySyncCore

final class TrainingSettlementTests: XCTestCase {
    private let sessionID = UUID(uuidString: "A8C8CB12-4BF2-4000-A830-605A5F1EE236")!
    private var day: UserDay { UserDay.containing(Date(timeIntervalSince1970: 1_789_473_600)) }

    private var target: [String: Any] {
        ["version": "target-1.0", "target": 12.4, "lower": 10.9, "upper": 13.9,
         "sleep_score": 84, "sleep_minutes": 450, "recovery_score": 86,
         "wake_reserve": 76, "recent_load": 11.6, "history_days": 12,
         "readiness": 82, "limited": false]
    }

    private var session: [String: Any] {
        let iso = ISO8601DateFormatter()
        return ["session_id": sessionID.uuidString, "sport_mode": 25,
                "started_at": iso.string(from: day.start.addingTimeInterval(3600)),
                "ended_at": iso.string(from: day.start.addingTimeInterval(5400)),
                "observed_seconds": 1200, "raw_load": 22.5, "load_delta": 1.23,
                "load_before": 6.0, "load_after": 10.0, "displayed_delta": 1.2]
    }

    func testSavedWorkoutWithoutMeasurementsRemainsVisibleWithoutInventingAContribution() throws {
        var missing = session
        missing["source"] = "manual"
        missing["data_status"] = "missing"
        missing["observed_seconds"] = 0
        for key in ["raw_load", "load_delta", "load_before", "load_after", "displayed_delta"] {
            missing[key] = NSNull()
        }
        let settlement = TrainingSettlement(evidence: ["sessions": [missing]])
        XCTAssertTrue(settlement.sessions.isEmpty)
        XCTAssertEqual(settlement.unmeasuredSessions?.map(\.id), [sessionID])
        XCTAssertEqual(try JSONDecoder().decode(TrainingSettlement.self,
            from: JSONEncoder().encode(settlement)), settlement)
        var completed = session
        completed["source"] = "manual"
        completed["data_status"] = "partial"
        let filled = TrainingSettlement(evidence: ["sessions": [completed]])
        XCTAssertEqual(filled.sessions.count, 1)
        XCTAssertEqual(filled.unmeasuredSessions, [])
        let legacy = try JSONDecoder().decode(TrainingSettlement.self, from: Data("{\"sessions\":[]}".utf8))
        XCTAssertNil(legacy.unmeasuredSessions)
    }

    func testAuthoritativeTargetUsesPublishedRangeWithoutRecomputingFromWakeBattery() throws {
        let settled = TrainingSettlement(evidence: ["target": target])
        let value = try XCTUnwrap(settled.target)
        XCTAssertEqual(value.target, 12.4)
        XCTAssertEqual(value.optimalZone, 10.9...13.9)
        XCTAssertEqual(value.sleepScore, 84)
        XCTAssertEqual(value.recoveryScore, 86)
        XCTAssertEqual(value.recentLoad, 11.6)
        let recommendation = settled.recommendation(legacyTarget: 18, legacyZone: 16...20)
        XCTAssertEqual(recommendation.target, 12.4)
        XCTAssertEqual(recommendation.zone, 10.9...13.9)
    }

    func testMissingTargetWithinVersionedObjectAndExplicitNullNeverReviveLegacyTarget() {
        for object: Any in [["version": "target-1.0"], ["target": NSNull()], NSNull()] {
            let settled = TrainingSettlement(evidence: ["target": object])
            XCTAssertNotNil(settled.target)
            let recommendation = settled.recommendation(legacyTarget: 18, legacyZone: 16...20)
            XCTAssertNil(recommendation.target)
            XCTAssertNil(recommendation.zone)
        }
        let legacy = TrainingSettlement(evidence: ["elapsed_minutes": 600])
        XCTAssertEqual(legacy.recommendation(legacyTarget: 18, legacyZone: 16...20).target, 18)
    }

    func testCurrentReserveAdjustmentRetainsSleepBasisAndUsesThePublishedFinalTarget() throws {
        var adjusted = target
        adjusted["version"] = "target-1.1"
        adjusted["target"] = 8
        adjusted["lower"] = 6
        adjusted["upper"] = 10
        adjusted["base_target"] = 12.4
        adjusted["current_reserve"] = 25
        adjusted["reserve_limit"] = 8
        adjusted["reserve_fresh"] = true
        adjusted["reserve_adjustment"] = -4.4
        let settlement = TrainingSettlement(evidence: ["target": adjusted])
        XCTAssertEqual(settlement.target?.sleepScore, 84)
        XCTAssertEqual(settlement.target?.baseTarget, 12.4)
        XCTAssertEqual(settlement.target?.currentReserve, 25)
        XCTAssertEqual(settlement.target?.reserveAdjustment, -4.4)
        XCTAssertEqual(settlement.target?.reserveFresh, true)
        XCTAssertEqual(settlement.target?.followsCurrentReserve, true)
        XCTAssertEqual(settlement.recommendation(legacyTarget: 18, legacyZone: 16...20).target, 8)
        let reopened = try JSONDecoder().decode(TrainingSettlement.self, from: JSONEncoder().encode(settlement))
        XCTAssertEqual(reopened, settlement)
        XCTAssertNil(TrainingSettlement(evidence: ["target": target]).target?.currentReserve)
    }

    func testUnavailableCurrentReserveLimitKeepsTheSleepTargetAndItsExplanation() {
        var sleepBased = target
        sleepBased["version"] = "target-1.1"
        sleepBased["base_target"] = 12.4
        sleepBased["current_reserve"] = 25
        sleepBased["reserve_limit"] = NSNull()
        sleepBased["reserve_adjustment"] = 0
        let settlement = TrainingSettlement(evidence: ["target": sleepBased])
        XCTAssertEqual(settlement.target?.followsCurrentReserve, false)
        let recommendation = settlement.recommendation(legacyTarget: 18, legacyZone: 16...20)
        XCTAssertEqual(recommendation.target, 12.4)
        XCTAssertEqual(recommendation.zone, 10.9...13.9)
    }

    func testOlderReserveLimitIsRetainedWithoutClaimingACurrentReading() throws {
        for freshFlag: Any in [false, NSNull()] {
            var limited = target
            limited["version"] = "target-1.1"
            limited["target"] = 8
            limited["lower"] = 6
            limited["upper"] = 10
            limited["base_target"] = 12.4
            limited["current_reserve"] = 25
            limited["reserve_limit"] = 8
            limited["reserve_fresh"] = freshFlag
            limited["observed_at"] = "2026-09-15T07:15:00Z"
            limited["reserve_adjustment"] = -4.4
            let settlement = TrainingSettlement(evidence: ["target": limited])
            XCTAssertEqual(settlement.target?.hasReserveLimit, true)
            XCTAssertEqual(settlement.target?.followsCurrentReserve, false)
            XCTAssertEqual(settlement.target?.observedAt,
                ISO8601DateFormatter().date(from: "2026-09-15T07:15:00Z"))
            XCTAssertEqual(settlement.recommendation(legacyTarget: 18, legacyZone: 16...20).target, 8)
            let reopened = try JSONDecoder().decode(TrainingSettlement.self, from: JSONEncoder().encode(settlement))
            XCTAssertEqual(reopened, settlement)
            XCTAssertEqual(reopened.target?.followsCurrentReserve, false)
        }
    }

    func testAnOpenPageCannotKeepAnOldReserveCurrentWithoutNewEvidence() throws {
        let observed = Date(timeIntervalSince1970: 1_789_473_600)
        var evidence = target
        evidence["version"] = "target-1.1"
        evidence["reserve_limit"] = 8
        evidence["current_reserve"] = 40
        evidence["reserve_fresh"] = true
        evidence["observed_at"] = ISO8601DateFormatter().string(from: observed)
        var published = try XCTUnwrap(TrainingSettlement(evidence: ["target": evidence]).target)
        XCTAssertTrue(published.followsCurrentReserve(at: observed.addingTimeInterval(89 * 60)))
        XCTAssertFalse(published.followsCurrentReserve(at: observed.addingTimeInterval(90 * 60)))
        XCTAssertFalse(published.followsCurrentReserve(at: observed.addingTimeInterval(-1)))
        XCTAssertTrue(published.hasReserveLimit, "The old reading still limits the recommendation.")
        published.observedAt = nil
        XCTAssertFalse(published.followsCurrentReserve(at: observed))
    }

    func testInvalidTargetRangeDoesNotCrashOrCreateARecommendation() {
        var invalid = target
        invalid["target"] = "NaN"
        invalid["lower"] = 18
        invalid["upper"] = 4
        let settled = TrainingSettlement(evidence: ["target": invalid])
        XCTAssertNil(settled.target?.target)
        XCTAssertNil(settled.target?.optimalZone)
    }

    func testSessionWithoutHeartRateAppearsAfterSettlementAndUsesItsOwnContribution() throws {
        var settled = TrainingSettlement(evidence: ["sessions": []])
        XCTAssertNil(settled.session(sessionID, on: day))
        settled = TrainingSettlement(evidence: ["sessions": [session]])
        let contribution = try XCTUnwrap(settled.session(sessionID, on: day))
        XCTAssertEqual(contribution.sportMode, 25)
        XCTAssertEqual(contribution.observedSeconds, 1200)
        XCTAssertEqual(contribution.deltaText, "+1.2")
        XCTAssertEqual(contribution.loadAfter - contribution.loadBefore, 4)
        XCTAssertEqual(contribution.loadDelta, 1.23)
        XCTAssertNil(settled.session(UUID(), on: day))
    }

    func testTinyContributionsAndSaturationRemainVisible() throws {
        var tiny = session
        tiny["load_delta"] = 0.021
        tiny["displayed_delta"] = 0
        var contribution = try XCTUnwrap(TrainingSettlement(evidence: ["sessions": [tiny]]).sessions.first)
        XCTAssertEqual(contribution.deltaText, "+<0.1")
        XCTAssertFalse(contribution.reachesScaleLimit)
        tiny["load_before"] = 20.9
        tiny["load_after"] = 20.9
        tiny["load_delta"] = 0
        contribution = try XCTUnwrap(TrainingSettlement(evidence: ["sessions": [tiny]]).sessions.first)
        XCTAssertEqual(contribution.deltaText, "+0.0")
        XCTAssertTrue(contribution.reachesScaleLimit)
    }

    func testYesterdayRecapIsExcludedButCrossBoundarySessionCanContributeToBothDays() {
        XCTAssertFalse(TrainingSessionContribution.overlaps(
            startedAt: day.start.addingTimeInterval(-3600), endedAt: day.start, day: day))
        XCTAssertTrue(TrainingSessionContribution.overlaps(
            startedAt: day.start.addingTimeInterval(-3600), endedAt: day.start.addingTimeInterval(600), day: day))
        XCTAssertNil(TrainingSettlement(evidence: ["sessions": [session]])
            .session(sessionID, on: day.adding(days: -1)))
    }

    func testCacheRoundTripRetainsTargetNullAndPerSessionContribution() throws {
        let settled = TrainingSettlement(evidence: ["target": ["version": "target-1.0", "target": NSNull()],
                                                    "sessions": [session]])
        let reopened = try JSONDecoder().decode(TrainingSettlement.self, from: JSONEncoder().encode(settled))
        XCTAssertEqual(reopened, settled)
        XCTAssertNil(reopened.recommendation(legacyTarget: 18, legacyZone: 16...20).target)
        XCTAssertEqual(reopened.session(sessionID, on: day)?.deltaText, "+1.2")
    }

    func testMalformedSessionCannotReplaceValidEvidenceOrInventLoad() {
        var invalid = session
        invalid["session_id"] = "wrong"
        var unknownMode = session
        unknownMode["sport_mode"] = NSNull()
        let settled = TrainingSettlement(evidence: ["sessions": [invalid, unknownMode]])
        XCTAssertEqual(settled.sessions.count, 1)
        XCTAssertNil(settled.sessions.first?.sportMode)
    }
}
