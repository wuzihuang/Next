import XCTest
@testable import NextBodySyncCore

final class SamplePageReadTests: XCTestCase {
    @MainActor
    func testReadsMoreThanTheServerCapIncludingTheNewestDay() async throws {
        let source = Array(0..<8_064)
        var offsets: [Int] = []
        let rows = try await SamplePageRead.all { offset in
            offsets.append(offset)
            return Array(source.dropFirst(offset).prefix(1_000))
        }
        XCTAssertEqual(rows, source)
        XCTAssertEqual(offsets, [0, 1_000, 2_000, 3_000, 4_000, 5_000, 6_000, 7_000, 8_000, 8_064])
    }

    @MainActor
    func testASmallerServerCapDoesNotSilentlyEndTheWindow() async throws {
        let rows = try await SamplePageRead.all { offset in
            Array((0..<27).dropFirst(offset).prefix(3))
        }
        XCTAssertEqual(rows, Array(0..<27))
    }

    @MainActor
    func testALaterPageFailureDoesNotPublishAPartialWindow() async {
        enum Failure: Error { case unavailable }
        do {
            _ = try await SamplePageRead.all { offset in
                if offset > 0 { throw Failure.unavailable }
                return [1, 2, 3]
            }
            XCTFail("Incomplete history must fail as one read")
        } catch { }
    }
}
