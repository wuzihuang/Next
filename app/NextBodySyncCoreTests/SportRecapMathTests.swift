import XCTest
@testable import NextBodySyncCore

final class SportRecapMathTests: XCTestCase {
    func testEmptyBeatsStayUnknownAndAddNoLoad() {
        let recap = SportRecapMath.recap(beats: [], restHR: 60, maxHR: 190, seconds: 600)
        XCTAssertNil(recap.avgHR)
        XCTAssertNil(recap.peakHR)
        XCTAssertTrue(recap.curve.isEmpty)
        XCTAssertEqual(recap.loadDelta, 0)
        XCTAssertEqual(recap.conclusion, .noHeart)
        XCTAssertEqual(recap.zoneMinutes.reduce(0, +), 0)
    }

    func testGapsOverFifteenSecondsDoNotAddDuration() {
        let start = Date(timeIntervalSince1970: 0)
        let beats = [
            SportRecapMath.Beat(at: start, bpm: 160),
            SportRecapMath.Beat(at: start.addingTimeInterval(16), bpm: 165),
        ]
        let recap = SportRecapMath.recap(beats: beats, restHR: 60, maxHR: 190, seconds: 16)
        XCTAssertEqual(recap.zoneMinutes.reduce(0, +), 0, accuracy: 0.01)
        XCTAssertEqual(recap.loadDelta, 0)
        XCTAssertEqual(recap.peakHR, 165)
    }

    func testOneHertzWorkingRateIsAerobicAndAddsLoad() {
        let start = Date(timeIntervalSince1970: 0)
        let beats = (0..<120).map { i in
            SportRecapMath.Beat(at: start.addingTimeInterval(Double(i)), bpm: 130)
        }
        let recap = SportRecapMath.recap(beats: beats, restHR: 60, maxHR: 190, seconds: 120)
        XCTAssertEqual(recap.avgHR, 130)
        XCTAssertEqual(recap.peakHR, 130)
        XCTAssertGreaterThan(recap.loadDelta, 0)
        XCTAssertEqual(recap.conclusion, .aerobic)
        XCTAssertGreaterThan(recap.aerobicMinutes, recap.anaerobicMinutes)
        XCTAssertFalse(recap.curve.isEmpty)
    }

    func testHighHeartRateIsAnaerobic() {
        let start = Date(timeIntervalSince1970: 0)
        let beats = (0..<60).map { i in
            SportRecapMath.Beat(at: start.addingTimeInterval(Double(i)), bpm: 185)
        }
        let recap = SportRecapMath.recap(beats: beats, restHR: 60, maxHR: 190, seconds: 60)
        XCTAssertEqual(recap.conclusion, .anaerobic)
        XCTAssertGreaterThan(recap.anaerobicMinutes, 0)
    }
    func testZonesMatchTrainingAndDoNotCountBelowZ1() {
        XCTAssertEqual(SportRecapMath.zoneIndex(bpm: 89, rest: 60, maxHR: 160), 0)
        for (heart, zone) in [(90, 1), (100, 2), (115, 3), (130, 4), (145, 5)] {
            XCTAssertEqual(SportRecapMath.zoneIndex(bpm: heart, rest: 60, maxHR: 160), zone)
        }
        XCTAssertEqual(SportRecapMath.zoneIndex(bpm: 100, rest: nil, maxHR: 200), 1)
        let start = Date(timeIntervalSince1970: 0)
        let recap = SportRecapMath.recap(beats: [.init(at: start, bpm: 70),
            .init(at: start.addingTimeInterval(10), bpm: 70)], restHR: 60, maxHR: 160, seconds: 10)
        XCTAssertEqual(recap.conclusion, .belowZones)
        XCTAssertEqual(recap.observedSeconds, 10)
        XCTAssertEqual(recap.zoneMinutes.reduce(0, +), 0)
    }

    func testPauseDoesNotBridgeCurveOrZonesAndSparseBeatsDoNotInventConclusion() {
        let start = Date(timeIntervalSince1970: 0)
        let recap = SportRecapMath.recap(beats: [.init(at: start, bpm: 130, segment: 0),
            .init(at: start.addingTimeInterval(5), bpm: 130, segment: 1)], restHR: 60, maxHR: 190, seconds: 5)
        XCTAssertEqual(recap.observedSeconds, 0)
        XCTAssertEqual(recap.conclusion, .insufficient)
        XCTAssertEqual(recap.curvePoints.map(\.segment), [0, 1])
    }

    func testShortValidIntervalClassifiesBeforeRoundingMinutes() {
        let start = Date(timeIntervalSince1970: 0)
        let recap = SportRecapMath.recap(beats: [.init(at: start, bpm: 185),
            .init(at: start.addingTimeInterval(5), bpm: 185)], restHR: 60, maxHR: 190, seconds: 5)
        XCTAssertEqual(recap.anaerobicMinutes, 0)
        XCTAssertEqual(recap.conclusion, .anaerobic)
    }

    func testAllDayCurveIsBoundedAndStillBreaksAtRealGaps() throws {
        let start = Date(timeIntervalSince1970: 0)
        let beats = (0..<86_400).map { i in
            SportRecapMath.Beat(at: start.addingTimeInterval(Double(i)), bpm: 130,
                segment: i < 43_200 ? 0 : 1)
        }
        let points = SportRecapMath.displayPoints(beats)
        XCTAssertEqual(points.count, 4_000)
        XCTAssertEqual(points.first?.at, start)
        XCTAssertEqual(points.last?.at, start.addingTimeInterval(86_399))
        XCTAssertEqual(Set(points.map(\.segment)), [0, 1])
        XCTAssertLessThan(try JSONEncoder().encode(points).count, 800_000)
    }

}
