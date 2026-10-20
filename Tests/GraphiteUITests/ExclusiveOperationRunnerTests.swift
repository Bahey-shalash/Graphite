import XCTest
@testable import GraphiteUI

@MainActor
final class ExclusiveOperationRunnerTests: XCTestCase {
    private struct OperationFailure: Error, Equatable {}

    /// Suspends an operation until the test lets it finish.
    @MainActor private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var isReleased = false

        func suspend() async {
            guard !isReleased else { return }
            await withCheckedContinuation { continuation in self.continuation = continuation }
        }

        /// Lets the operation finish, whether it has reached `suspend` yet or not.
        func release() {
            isReleased = true
            continuation?.resume()
            continuation = nil
        }
    }

    func testASecondOperationStartedWhileOneRunsIsNotRun() async throws {
        let runner = ExclusiveOperationRunner()
        let gate = Gate()
        var completedOperations: [String] = []

        let firstWasStarted = runner.start({ await gate.suspend(); completedOperations.append("first") }, onFailure: { _ in })
        let secondWasStarted = runner.start({ completedOperations.append("second") }, onFailure: { _ in })
        XCTAssertTrue(firstWasStarted)
        XCTAssertFalse(secondWasStarted)
        XCTAssertTrue(runner.isRunning)

        gate.release()
        await runner.finishCurrentOperation()

        XCTAssertEqual(completedOperations, ["first"])
        XCTAssertFalse(runner.isRunning)
    }

    func testAnOperationCanStartAgainAfterThePreviousOneFinished() async throws {
        let runner = ExclusiveOperationRunner()
        var completedOperations: [String] = []

        XCTAssertTrue(runner.start({ completedOperations.append("first") }, onFailure: { _ in }))
        await runner.finishCurrentOperation()
        XCTAssertTrue(runner.start({ completedOperations.append("second") }, onFailure: { _ in }))
        await runner.finishCurrentOperation()

        XCTAssertEqual(completedOperations, ["first", "second"])
    }

    func testAFailureIsReportedAndEndsTheRunningState() async throws {
        let runner = ExclusiveOperationRunner()
        var reportedFailures: [OperationFailure] = []

        _ = runner.start({ throw OperationFailure() }, onFailure: { error in
            if let failure = error as? OperationFailure { reportedFailures.append(failure) }
        })
        await runner.finishCurrentOperation()

        XCTAssertEqual(reportedFailures, [OperationFailure()])
        XCTAssertFalse(runner.isRunning)
    }

    func testCancellingStopsTheRunningOperationAndFreesTheRunner() async throws {
        let runner = ExclusiveOperationRunner()
        let gate = Gate()
        var sawCancellation = false

        _ = runner.start({
            await gate.suspend()
            sawCancellation = Task.isCancelled
        }, onFailure: { _ in })
        runner.cancel()
        XCTAssertFalse(runner.isRunning)
        gate.release()
        await runner.finishCurrentOperation()

        XCTAssertTrue(sawCancellation)
    }
}
