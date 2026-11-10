import Foundation
import XCTest
@testable import LofiAudioCore

final class GainTests: XCTestCase {
    func testEqualPowerKeepsTheSummedPowerLevel() {
        for step in 0...100 {
            let gains = Gain.equalPower(Double(step) / 100)
            XCTAssertEqual(gains.a * gains.a + gains.b * gains.b, 1, accuracy: 1e-12)
        }
        XCTAssertEqual(Gain.equalPower(0).a, 1)
        XCTAssertEqual(Gain.equalPower(1).b, 1)
        XCTAssertEqual(Gain.equalPower(0.5).a, sqrt(0.5), accuracy: 1e-12)
        XCTAssertEqual(Gain.equalPower(-1).a, 1, "positions are clamped")
    }

    func testDecibelConversions() {
        XCTAssertEqual(Gain.linear(fromDB: -6), 0.501, accuracy: 1e-3)
        XCTAssertEqual(Gain.linear(fromDB: 0), 1)
        XCTAssertEqual(Gain.linear(fromDB: -200), 0)
        XCTAssertEqual(Gain.decibels(fromLinear: 0.5), -6.02, accuracy: 1e-2)
        XCTAssertEqual(Gain.decibels(fromLinear: 0), -.infinity)
    }

    func testRampsMoveSmoothlyAndCanBeRedirected() {
        var ramp = Ramp(value: 0)
        ramp.go(to: 1, over: 2, at: 10, shape: .linear)
        XCTAssertEqual(ramp.value(at: 9), 0)
        XCTAssertEqual(ramp.value(at: 11), 0.5, accuracy: 1e-12)
        XCTAssertTrue(ramp.isRunning(at: 11))
        ramp.go(to: 0, over: 1, at: 11, shape: .linear)
        XCTAssertEqual(ramp.value(at: 11), 0.5, accuracy: 1e-12, "a new target starts from the current value")
        XCTAssertEqual(ramp.value(at: 12), 0)
        XCTAssertFalse(ramp.isRunning(at: 12))

        var fade = Ramp(value: 0)
        fade.go(to: 1, over: 2, at: 0, shape: .equalPower)
        XCTAssertEqual(fade.value(at: 1), sin(.pi / 4), accuracy: 1e-12)
        fade.go(to: 0, over: 2, at: 2, shape: .equalPower)
        XCTAssertEqual(fade.value(at: 3), cos(.pi / 4), accuracy: 1e-12)
    }
}

final class SchedulerTests: XCTestCase {
    func testManualSchedulerRunsInTimeOrder() {
        let scheduler = ManualScheduler()
        var log: [String] = []
        _ = scheduler.schedule(after: 2) { log.append("b") }
        _ = scheduler.schedule(after: 1) { log.append("a") }
        _ = scheduler.schedule(after: 2) { log.append("c") }
        let cancelled = scheduler.schedule(after: 1.5) { log.append("x") }
        cancelled.cancel()
        scheduler.advance(by: 3)
        XCTAssertEqual(log, ["a", "b", "c"])
        XCTAssertEqual(scheduler.now, 3)
    }

    func testRepeatingTimerCanCancelItself() {
        let scheduler = ManualScheduler()
        var count = 0
        var handle: LofiCancellable?
        handle = scheduler.scheduleRepeating(every: 0.5) {
            count += 1
            if count == 3 { handle?.cancel() }
        }
        scheduler.advance(by: 10)
        XCTAssertEqual(count, 3)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testActionsScheduledFromActionsRunInTheSameAdvance() {
        let scheduler = ManualScheduler()
        var fired: [TimeInterval] = []
        _ = scheduler.schedule(after: 1) {
            fired.append(scheduler.now)
            _ = scheduler.schedule(after: 1) { fired.append(scheduler.now) }
        }
        scheduler.advance(by: 5)
        XCTAssertEqual(fired, [1, 2])
    }

    func testDispatchSchedulerRunsOnItsQueue() {
        let scheduler = DispatchScheduler(label: "test")
        let done = expectation(description: "ran")
        _ = scheduler.schedule(after: 0.01) {
            XCTAssertTrue(scheduler.isCurrent)
            var nested = false
            scheduler.perform { nested = true }
            XCTAssertTrue(nested, "perform runs inline when already on the queue")
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        XCTAssertFalse(scheduler.isCurrent)
    }
}
