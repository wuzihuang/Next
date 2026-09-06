import XCTest
@testable import NextBodyPlanCore

final class PlanFaceMathTests: XCTestCase {

    func testPhaseWrapsThroughOne() {
        XCTAssertEqual(PlanFaceMath.phase(0.9, offset: 0.2), 0.1, accuracy: 1e-9)
        XCTAssertEqual(PlanFaceMath.phase(0.25, offset: 0.5), 0.75, accuracy: 1e-9)
    }

    func testOffsetYTravelsUpThenInvertsDown() {
        XCTAssertEqual(PlanFaceMath.offsetY(phase: 0, up: true), 3.2, accuracy: 1e-9)
        XCTAssertEqual(PlanFaceMath.offsetY(phase: 1, up: true), -3.2, accuracy: 1e-9)
        XCTAssertEqual(PlanFaceMath.offsetY(phase: 0, up: false), -3.2, accuracy: 1e-9)
        XCTAssertEqual(PlanFaceMath.offsetY(phase: 1, up: false), 3.2, accuracy: 1e-9)
    }

    func testAlphaFadesInAndOut() {
        XCTAssertEqual(PlanFaceMath.alpha(phase: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(PlanFaceMath.alpha(phase: 0.24), 1, accuracy: 1e-9)
        XCTAssertEqual(PlanFaceMath.alpha(phase: 0.5), 1, accuracy: 1e-9)
        XCTAssertEqual(PlanFaceMath.alpha(phase: 1), 0, accuracy: 1e-9)
    }

    func testFlattenCapsAtTheOpenThreshold() {
        XCTAssertEqual(PlanFaceMath.flatten(translation: 0), 0)
        XCTAssertEqual(PlanFaceMath.flatten(translation: -20), 0.5, accuracy: 1e-9)
        XCTAssertEqual(PlanFaceMath.flatten(translation: -80), 1)
    }

    func testIdleStopsAfterSixCyclesOrOnceOpened() {
        XCTAssertFalse(PlanFaceMath.idlePlaying(elapsed: 2, openedThisLaunch: false, reduceMotion: false))
        XCTAssertTrue(PlanFaceMath.idlePlaying(elapsed: 4, openedThisLaunch: false, reduceMotion: false))
        XCTAssertFalse(PlanFaceMath.idlePlaying(elapsed: 20, openedThisLaunch: false, reduceMotion: false))
        XCTAssertFalse(PlanFaceMath.idlePlaying(elapsed: 4, openedThisLaunch: true, reduceMotion: false))
        XCTAssertFalse(PlanFaceMath.idlePlaying(elapsed: 4, openedThisLaunch: false, reduceMotion: true))
    }

    func testHintKeepsPlayingAfterThePlanHasOpened() {
        XCTAssertTrue(PlanFaceMath.hintPlaying(reduceMotion: false))
        XCTAssertFalse(PlanFaceMath.hintPlaying(reduceMotion: true))
    }

    func testCommitUsesFortyPointsOrAFling() {
        XCTAssertTrue(PlanFaceMath.shouldCommit(translation: -40, velocity: 0, opening: true))
        XCTAssertTrue(PlanFaceMath.shouldCommit(translation: -10, velocity: -301, opening: true))
        XCTAssertFalse(PlanFaceMath.shouldCommit(translation: -20, velocity: -100, opening: true))
        XCTAssertTrue(PlanFaceMath.shouldCommit(translation: 40, velocity: 0, opening: false))
        XCTAssertFalse(PlanFaceMath.shouldCommit(translation: 10, velocity: 100, opening: false))
    }

    func testSuggestedBedDoesNotGoBeforeNine() {
        let late = PlanFaceMath.suggestedBed(offset: 317)
        XCTAssertEqual(late.clock, "22:32")
        XCTAssertEqual(late.minutesLate, 45)

        let alreadyEarly = PlanFaceMath.suggestedBed(offset: 190)
        XCTAssertEqual(alreadyEarly.clock, "21:00")
        XCTAssertEqual(alreadyEarly.minutesLate, 10)
    }

    func testEmptyNightWritesNoScoreAndKeepsFiveRows() {
        let face = PlanFaceMath.face(
            night: nil,
            load: .init(yesterday: 14, dayBefore: 16, target: 6, activeMinutes: 68),
            mealsLogged: false,
            scoredNightCount: 0,
            readyFrom: nil,
            readyTo: nil,
            now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(face.empty)
        XCTAssertNil(face.score)
        XCTAssertEqual(face.actions.map(\.kind), PlanFaceMath.catalog)
        XCTAssertEqual(face.actions.count, 5)
        XCTAssertEqual(face.actions[0].trailing, PlanFaceMath.dash)
        XCTAssertEqual(face.actions[3].trailing, "UNLOGGED")
        XCTAssertEqual(face.actions[4].kind, .quiet)
        XCTAssertEqual(face.actions[4].trailing, "16:00")
        XCTAssertEqual(face.reads.first?.value, PlanFaceMath.dash)
    }

    func testWeakestPrefersTheLowestPresentGroup() {
        let night = PlanFaceMath.Night(
            score: 61, duration: 84, architecture: 76, recovery: 63,
            regularity: 60, personalWeight: 0.4, hrvMs: 34,
            bedOffset: 317, nightIndex: 9)
        XCTAssertEqual(PlanFaceMath.weakest(of: night), .regularity)

        let recoveryNight = PlanFaceMath.Night(
            score: 61, duration: 84, architecture: 76, recovery: 40,
            regularity: 70, personalWeight: 0.4, hrvMs: 34,
            bedOffset: 317, nightIndex: 9)
        XCTAssertEqual(PlanFaceMath.weakest(of: recoveryNight), .recovery)
    }

    func testFaceBuildsFiveRealActionsFromAScoredNight() {
        let night = PlanFaceMath.Night(
            score: 61, duration: 84, architecture: 76, recovery: 40,
            regularity: 60, personalWeight: 0.4, hrvMs: 34,
            bedOffset: 317, nightIndex: 9)
        let face = PlanFaceMath.face(
            night: night,
            load: .init(yesterday: 14, dayBefore: 16, target: 6, activeMinutes: 68),
            mealsLogged: false,
            scoredNightCount: 7,
            readyFrom: "08-30",
            readyTo: "09-05",
            now: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(face.empty)
        XCTAssertEqual(face.score, 61)
        XCTAssertEqual(face.actions.map(\.kind), [.bed, .load, .strength, .meal, .quiet])
        XCTAssertEqual(face.actions[0].trailing, "22:32")
        XCTAssertEqual(face.actions[1].trailing, "6.0")
        XCTAssertEqual(face.actions[3].trailing, "UNLOGGED")
        XCTAssertEqual(face.actions[4].trailing, "16:00")
        XCTAssertEqual(face.reads[1].value, "34 MS · NIGHT 9")
    }

    func testMealActionStaysOffWhenTheDayIsLogged() {
        let night = PlanFaceMath.Night(
            score: 80, duration: 90, architecture: 88, recovery: 86,
            regularity: 84, personalWeight: 1, hrvMs: 50,
            bedOffset: 240, nightIndex: 20)
        let face = PlanFaceMath.face(
            night: night,
            load: .init(yesterday: 4, dayBefore: 5, target: 6, activeMinutes: 20),
            mealsLogged: true,
            scoredNightCount: 20,
            readyFrom: "08-16",
            readyTo: "09-05",
            now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(face.actions.map(\.kind), PlanFaceMath.catalog)
        XCTAssertEqual(face.actions[2].trailing, PlanFaceMath.dash)
        XCTAssertEqual(face.actions[3].trailing, "LOGGED")
    }

    func testWeightedPrintsTheBoardFraction() {
        XCTAssertEqual(PlanFaceMath.weighted(63, weight: 35), 22)
        XCTAssertEqual(PlanFaceMath.weighted(84, weight: 25), 21)
        XCTAssertNil(PlanFaceMath.weighted(nil, weight: 15))
    }
}
