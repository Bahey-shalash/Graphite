import XCTest
import GraphiteCore
import GraphiteTestSupport

/// What every `ApplicationClock` promises, run against the live clock and the manual one.
final class ApplicationClockContractTests: XCTestCase {
    /// Moves the clock's time by about `duration`: the manual clock is told, and the live one,
    /// whose subject is real time, is slept on.
    private func passTime(_ duration: Duration, on clock: any ApplicationClock) async throws {
        if let manualClock = clock as? ManualClock {
            manualClock.advance(by: duration)
        } else {
            try await clock.sleep(for: duration + .milliseconds(20))
        }
    }

    private func clocksUnderTest() -> [(name: String, clock: any ApplicationClock)] {
        [("LiveApplicationClock", LiveApplicationClock()), ("ManualClock", ManualClock())]
    }

    func testTimeNeverGoesBackwardsAndAdvancesWithTheTimePassed() async throws {
        for (name, clock) in clocksUnderTest() {
            let before = clock.now
            try await passTime(.milliseconds(30), on: clock)
            let after = clock.now
            XCTAssertGreaterThanOrEqual(after - before, .milliseconds(30), name)
        }
    }

    func testASleepEndsOnceItsTimeHasPassed() async throws {
        for (_, clock) in clocksUnderTest() {
            let sleeper = Task { try await clock.sleep(for: .milliseconds(30)) }
            if let manualClock = clock as? ManualClock { try await manualClock.awaitPendingSleepers() }
            try await passTime(.milliseconds(30), on: clock)
            try await sleeper.value
        }
    }

    func testCancellingATaskEndsItsSleepAtOnceWithACancellationError() async throws {
        for (name, clock) in clocksUnderTest() {
            let sleeper = Task { try await clock.sleep(for: .seconds(3_600)) }
            if let manualClock = clock as? ManualClock { try await manualClock.awaitPendingSleepers() }
            sleeper.cancel()
            do {
                try await sleeper.value
                XCTFail("\(name): a cancelled sleep must throw.")
            } catch {
                XCTAssertTrue(error is CancellationError, "\(name): \(error)")
            }
        }
    }

    func testASleepBeginningInACancelledTaskThrowsWithoutWaiting() async throws {
        for (name, clock) in clocksUnderTest() {
            let sleeper = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try await clock.sleep(for: .seconds(3_600))
            }
            do {
                try await sleeper.value
                XCTFail("\(name): a sleep in a cancelled task must throw.")
            } catch {
                XCTAssertTrue(error is CancellationError, "\(name): \(error)")
            }
        }
    }
}

/// `ManualClock` is a test tool that every injected-clock test leans on, so its own promises are tested.
@MainActor
final class ManualClockTests: XCTestCase {
    /// Records the order in which sleepers resumed. The sleepers run on the main actor, so no lock is needed.
    private final class ResumeLog {
        var labels: [String] = []
    }

    func testTimeStartsWhereItWasToldAndMovesOnlyWhenAdvanced() async throws {
        let clock = ManualClock(startingAt: .seconds(5))
        XCTAssertEqual(clock.now, .seconds(5))
        try await LiveApplicationClock().sleep(for: .milliseconds(10))
        XCTAssertEqual(clock.now, .seconds(5), "Real time passing changes nothing.")
        clock.advance(by: .milliseconds(250))
        XCTAssertEqual(clock.now, .milliseconds(5_250))
    }

    func testASleeperStaysSuspendedUntilItsDeadlineAndThenResumes() async throws {
        let clock = ManualClock()
        let log = ResumeLog()
        let sleeper = Task { @MainActor in
            try await clock.sleep(for: .milliseconds(900))
            log.labels.append("woke")
        }
        try await clock.awaitPendingSleepers()
        XCTAssertEqual(clock.pendingSleepDurations, [.milliseconds(900)])

        clock.advance(by: .milliseconds(899))
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(log.labels, [])
        XCTAssertEqual(clock.pendingSleepDurations, [.milliseconds(1)], "The time left is counted down.")

        clock.advance(by: .milliseconds(1))
        try await sleeper.value
        XCTAssertEqual(log.labels, ["woke"])
        XCTAssertEqual(clock.pendingSleepCount, 0)
    }

    func testEachAdvanceWakesExactlyTheSleepersWhoseDeadlinesItReaches() async throws {
        let clock = ManualClock()
        let log = ResumeLog()
        var sleepers: [String: Task<Void, Error>] = [:]
        for (label, delay) in [("three seconds", 3), ("one second", 1), ("two seconds, first", 2), ("two seconds, second", 2)] {
            sleepers[label] = Task { @MainActor in
                try await clock.sleep(for: .seconds(delay))
                log.labels.append(label)
            }
            try await clock.awaitPendingSleepers(count: sleepers.count)
        }
        XCTAssertEqual(clock.pendingSleepDurations, [.seconds(1), .seconds(2), .seconds(2), .seconds(3)])

        clock.advance(by: .seconds(1))
        try await sleepers["one second"]?.value
        XCTAssertEqual(log.labels, ["one second"])
        XCTAssertEqual(clock.pendingSleepDurations, [.seconds(1), .seconds(1), .seconds(2)])

        clock.advance(by: .seconds(1))
        try await sleepers["two seconds, first"]?.value
        try await sleepers["two seconds, second"]?.value
        XCTAssertEqual(Set(log.labels), ["one second", "two seconds, first", "two seconds, second"])
        XCTAssertEqual(clock.pendingSleepDurations, [.seconds(1)])

        clock.advance(by: .seconds(1))
        try await sleepers["three seconds"]?.value
        XCTAssertEqual(log.labels.last, "three seconds")
        XCTAssertEqual(clock.pendingSleepCount, 0)
    }

    func testOnlySleepersWhoseDeadlinesHavePassedResume() async throws {
        let clock = ManualClock()
        let log = ResumeLog()
        let shortSleeper = Task { @MainActor in
            try await clock.sleep(for: .seconds(1))
            log.labels.append("short")
        }
        let longSleeper = Task { @MainActor in
            try await clock.sleep(for: .seconds(5))
            log.labels.append("long")
        }
        try await clock.awaitPendingSleepers(count: 2)

        clock.advance(by: .seconds(1))
        try await shortSleeper.value
        XCTAssertEqual(log.labels, ["short"])
        XCTAssertEqual(clock.pendingSleepDurations, [.seconds(4)])

        clock.advance(by: .seconds(4))
        try await longSleeper.value
        XCTAssertEqual(log.labels, ["short", "long"])
    }

    func testACancelledSleeperLeavesTheClockAndTheOthersAreUnaffected() async throws {
        let clock = ManualClock()
        let cancelled = Task { try await clock.sleep(for: .seconds(1)) }
        let kept = Task { try await clock.sleep(for: .seconds(2)) }
        try await clock.awaitPendingSleepers(count: 2)

        cancelled.cancel()
        do {
            try await cancelled.value
            XCTFail("A cancelled sleep must throw.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(clock.pendingSleepDurations, [.seconds(2)])

        clock.advance(by: .seconds(2))
        try await kept.value
    }

    func testASleepOfNoTimeReturnsWithoutWaitingForTheClock() async throws {
        let clock = ManualClock()
        try await clock.sleep(for: .zero)
        try await clock.sleep(for: .seconds(-1))
        XCTAssertEqual(clock.pendingSleepCount, 0)
    }

    func testASleeperThatSleepsAgainIsGivenADeadlineFromTheNewTime() async throws {
        let clock = ManualClock()
        let sleeper = Task { @MainActor in
            try await clock.sleep(for: .seconds(1))
            try await clock.sleep(for: .seconds(1))
        }
        try await clock.awaitPendingSleepers()
        clock.advance(by: .seconds(1))
        try await clock.awaitPendingSleepers()
        XCTAssertEqual(clock.pendingSleepDurations, [.seconds(1)])
        clock.advance(by: .seconds(1))
        try await sleeper.value
        XCTAssertEqual(clock.now, .seconds(2))
    }
}
