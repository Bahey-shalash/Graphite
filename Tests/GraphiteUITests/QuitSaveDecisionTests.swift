import XCTest
@testable import GraphiteUI

/// Whether Graphite quits once saving the open documents has ended.
final class QuitSaveDecisionTests: XCTestCase {
    private struct RefusedWrite: Error, LocalizedError {
        var errorDescription: String? { "The file is locked." }
    }

    func testQuitsWhenEverySaveSucceeded() {
        let decision = QuitSaveDecision(outcome: .succeeded)
        XCTAssertTrue(decision.allowsTermination)
        XCTAssertNil(decision.blockingReason)
    }

    func testStaysOpenWhenASaveFailedAndCarriesTheFailureToShow() {
        let decision = QuitSaveDecision(outcome: .failed(RefusedWrite()))
        XCTAssertFalse(decision.allowsTermination)
        XCTAssertEqual(decision.blockingReason, .saveFailed(errorDescription: "The file is locked."))
    }

    func testStaysOpenWhenTheDeadlinePassedWhileASaveWasUnfinished() {
        let decision = QuitSaveDecision(outcome: .timedOut)
        XCTAssertFalse(decision.allowsTermination)
        XCTAssertEqual(decision.blockingReason, .saveTooSlow)
    }

    func testEveryBlockingReasonHasAMessageForThePerson() {
        XCTAssertFalse(QuitBlockingReason.saveTooSlow.presentedMessage.isEmpty)
        XCTAssertTrue(QuitBlockingReason.saveFailed(errorDescription: "The file is locked.").presentedMessage.contains("The file is locked."))
    }
}
