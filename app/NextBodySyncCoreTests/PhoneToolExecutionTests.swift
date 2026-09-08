import Foundation
import XCTest
@testable import NextBodySyncCore

@MainActor
private final class PhoneFixture {
    @MainActor final class Gate {
        var waiting: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { waiting = $0 } }
        func release() { let pending = waiting; waiting = nil; pending?.resume() }
    }

    @MainActor final class Clock {
        var waiting: [CheckedContinuation<Void, Never>?] = []
        func sleep(_: TimeInterval) async { await withCheckedContinuation { waiting.append($0) } }
        func fire(_ index: Int) {
            guard waiting.indices.contains(index) else { return }
            let pending = waiting[index]; waiting[index] = nil; pending?.resume()
        }
        func finish() { for index in waiting.indices { fire(index) } }
    }

    @MainActor final class BandAdapter {
        var readGate: Gate?
        var written: [BandAlarm] = []
        var deleted: [BandAlarm] = []
        var alarms: [BandAlarm] = []
        func read() async -> [BandAlarm] { await readGate?.wait(); return alarms }
        func write(_ alarm: BandAlarm) async -> [BandAlarm] {
            written.append(alarm); alarms.append(alarm); return alarms
        }
        func delete(_ alarm: BandAlarm) async -> [BandAlarm] {
            deleted.append(alarm); alarms.removeAll { $0.id == alarm.id }; return alarms
        }
    }

    var scope = PhoneToolExecution.Scope(session: .init(owner: "alice", generation: UUID()),
                                         turnID: UUID(), binding: "band-a")
    var consent = true
    var foreground = true
    var prompt: PhoneToolExecution.Prompt?
    var running: String?
    let clock = Clock()
    let band = BandAdapter()
    var execution: PhoneToolExecution!
    init() {
        execution = PhoneToolExecution(current: { [unowned self] in
            .init(scope: scope, consent: consent, foreground: foreground)
        }, sleep: { [clock] seconds in await clock.sleep(seconds) }, changed: { [weak self] prompt, running in
            self?.prompt = prompt; self?.running = running
        })
    }
    let draft = BandAlarm(id: 0, hour: 9, minute: 30, on: true, repeatMask: 127,
                          date: BandAlarm.onceDatePlaceholder, scene: 0, text: "Morning")

    func setAlarm(callID: String = "call-1", confirm: Bool = true,
                  scope pinned: PhoneToolExecution.Scope? = nil) -> Task<String, Never> {
        let pinned = pinned ?? scope
        return Task { @MainActor in
            do {
                let result = try await execution.run(scope: pinned, callID: callID, name: callID,
                    confirmation: confirm ? ("Set alarm?", "09:30") : nil) { permit in
                    try await permit.setAlarm(draft, read: { await self.band.read() },
                                              write: { await self.band.write($0) })
                }
                return "OK:\(result.id)"
            } catch let error as PhoneToolExecution.Failure { return error.rawValue }
            catch { return "UNEXPECTED" }
        }
    }

    func changing(session: RequestSession? = nil, turn: UUID? = nil, binding: String? = nil) {
        scope = .init(session: session ?? scope.session, turnID: turn ?? scope.turnID,
                      binding: binding ?? scope.binding)
    }
}

final class PhoneToolExecutionTests: XCTestCase {
    @MainActor private func until(_ condition: @MainActor () -> Bool,
                                  file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1_000 { if condition() { return }; await Task.yield() }
        XCTFail("Operation did not reach its controlled suspension", file: file, line: line)
    }

    @MainActor func testOverlappingConfirmationOldAnswerAndTimeoutCannotDismissSuccessor() async {
        let f = PhoneFixture()
        let first = f.setAlarm()
        await until { f.prompt != nil && f.clock.waiting.count == 1 }
        let oldID = f.prompt!.id
        let second = f.setAlarm(callID: "call-2")
        await until { f.prompt?.id != oldID && f.clock.waiting.count == 2 }
        let newID = f.prompt!.id
        let firstResult = await first.value
        XCTAssertEqual(firstResult, "CANCELLED")
        f.execution.resolve(id: oldID, approved: true)
        f.clock.fire(0)
        await Task.yield()
        XCTAssertEqual(f.prompt?.id, newID)
        f.execution.resolve(id: newID, approved: true)
        f.execution.resolve(id: newID, approved: true)
        let secondResult = await second.value
        XCTAssertEqual(secondResult, "OK:1")
        XCTAssertEqual(f.band.written.count, 1)
        XCTAssertNil(f.prompt)
        f.clock.finish()
    }

    @MainActor func testTimeoutCompletesOnlyItsCallAndNeverExecutes() async {
        let f = PhoneFixture()
        let task = f.setAlarm()
        await until { f.clock.waiting.count == 1 }
        let id = f.prompt!.id
        f.clock.fire(0)
        let result = await task.value
        XCTAssertEqual(result, "CANCELLED")
        f.execution.resolve(id: id, approved: true)
        XCTAssertTrue(f.band.written.isEmpty)
    }

    @MainActor func testAccountChangeWakesConfirmationAndOldApprovalCannotWrite() async {
        let f = PhoneFixture()
        let task = f.setAlarm()
        await until { f.prompt != nil }
        let id = f.prompt!.id
        f.changing(session: .init(owner: "bob", generation: UUID()))
        f.execution.refreshEligibility()
        f.execution.resolve(id: id, approved: true)
        let result = await task.value
        XCTAssertEqual(result, "SESSION_CHANGED")
        XCTAssertTrue(f.band.written.isEmpty)
        f.clock.finish()
    }

    @MainActor func testReadThenWriteRechecksSessionConsentTurnBindingAndForegroundWithoutNotification() async {
        for change in 0..<5 {
            let f = PhoneFixture()
            let gate = PhoneFixture.Gate()
            f.band.readGate = gate
            let task = f.setAlarm(confirm: false)
            await until { gate.waiting != nil }
            let expected: String
            switch change {
            case 0:
                f.changing(session: .init(owner: "alice", generation: UUID()))
                expected = "SESSION_CHANGED"
            case 1: f.consent = false; expected = "CONSENT_REQUIRED"
            case 2: f.changing(turn: UUID()); expected = "CANCELLED"
            case 3: f.changing(binding: "band-b"); expected = "BAND_DISCONNECTED"
            default: f.foreground = false; expected = "APP_BACKGROUND"
            }
            gate.release()
            let result = await task.value
            XCTAssertEqual(result, expected)
            XCTAssertTrue(f.band.written.isEmpty)
        }
    }

    @MainActor func testBackgroundThenForegroundNeverReauthorizesTheOldConfirmation() async {
        let f = PhoneFixture()
        let task = f.setAlarm()
        await until { f.prompt != nil }
        let id = f.prompt!.id
        f.execution.invalidateAll(.background)
        f.foreground = true
        f.execution.resolve(id: id, approved: true)
        let result = await task.value
        XCTAssertEqual(result, "APP_BACKGROUND")
        XCTAssertTrue(f.band.written.isEmpty)
        f.clock.finish()
    }

    @MainActor func testCancellationWhileConfirmingWakesWaiterWithoutTimeout() async {
        let f = PhoneFixture()
        let task = f.setAlarm()
        await until { f.prompt != nil }
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result, "CANCELLED")
        XCTAssertNil(f.prompt)
        XCTAssertTrue(f.band.written.isEmpty)
        f.clock.finish()
    }

    @MainActor func testCancellationDuringAlarmReadPreventsWrite() async {
        let f = PhoneFixture()
        let gate = PhoneFixture.Gate()
        f.band.readGate = gate
        let task = f.setAlarm(confirm: false)
        await until { gate.waiting != nil }
        task.cancel()
        gate.release()
        let result = await task.value
        XCTAssertEqual(result, "CANCELLED")
        XCTAssertTrue(f.band.written.isEmpty)
    }

    @MainActor func testStaleTurnCannotReplaceCurrentConfirmation() async {
        let f = PhoneFixture()
        let oldScope = f.scope
        f.changing(turn: UUID())
        let current = f.setAlarm(callID: "current")
        await until { f.prompt != nil }
        let id = f.prompt!.id
        let stale = f.setAlarm(callID: "old", scope: oldScope)
        let staleResult = await stale.value
        XCTAssertEqual(staleResult, "CANCELLED")
        XCTAssertEqual(f.prompt?.id, id)
        f.execution.resolve(id: id, approved: true)
        let result = await current.value
        XCTAssertEqual(result, "OK:1")
        f.clock.finish()
    }

    @MainActor func testOldInFlightCompletionCannotClearNewRunningCall() async {
        let f = PhoneFixture()
        let gate = PhoneFixture.Gate()
        f.band.readGate = gate
        let old = f.setAlarm(confirm: false)
        await until { gate.waiting != nil }
        let next = f.setAlarm(callID: "next")
        await until { f.prompt != nil }
        gate.release()
        let oldResult = await old.value
        XCTAssertEqual(oldResult, "CANCELLED")
        XCTAssertEqual(f.running, "next")
        f.band.readGate = nil
        f.execution.resolve(id: f.prompt!.id, approved: true)
        let result = await next.value
        XCTAssertEqual(result, "OK:1")
        XCTAssertEqual(f.band.written.count, 1)
        f.clock.finish()
    }

    @MainActor func testDeleteUsesTheReadRowAndAlsoRechecksBeforeWriting() async {
        let f = PhoneFixture()
        var alarm = f.draft; alarm.id = 7; alarm.text = "Existing"
        f.band.alarms = [alarm]
        let result = try? await f.execution.run(scope: f.scope, callID: "delete", name: "delete", confirmation: nil) { permit in
            try await permit.deleteAlarm(7, read: { await f.band.read() }, delete: { await f.band.delete($0) })
        }
        XCTAssertEqual(result, [])
        XCTAssertEqual(f.band.deleted, [alarm])
    }

    @MainActor func testCompletedExecutionCannotIssueDetachedFollowUp() async {
        let f = PhoneFixture()
        var captured: PhoneToolExecution.Execution?
        _ = try? await f.execution.run(scope: f.scope, callID: "one", name: "one", confirmation: nil) { permit in
            captured = permit
        }
        XCTAssertFalse(captured!.isAuthorized)
        do {
            _ = try await captured!.perform { await f.band.write(f.draft) }
            XCTFail("A completed call cannot issue another command")
        } catch { XCTAssertTrue(f.band.written.isEmpty) }
    }

    @MainActor func testDuplicateCallNeverRepeatsAnAcknowledgedSideEffect() async {
        let f = PhoneFixture()
        let first = await f.setAlarm(confirm: false).value
        let duplicate = await f.setAlarm(confirm: false).value
        XCTAssertEqual(first, "OK:1")
        XCTAssertEqual(duplicate, "CALL_ALREADY_EXECUTED")
        XCTAssertEqual(f.band.written.count, 1)
    }
}
