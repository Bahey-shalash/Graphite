import Foundation
import XCTest

/// The timing budgets of the hosted suite (a number of seconds or a longest frame gap) mean something only on the
/// owner's iPad: GitHub's shared virtual Macs run the simulator several times slower and unevenly. The hosted job of
/// the CI workflow sets `GRAPHITE_SKIP_TIMING_BUDGETS` (as `TEST_RUNNER_GRAPHITE_SKIP_TIMING_BUDGETS`, which `xcodebuild`
/// hands to the tests); the nightly device job does not, and runs them.
enum TimingBudgets {
    static let skipVariableName = "GRAPHITE_SKIP_TIMING_BUDGETS"

    /// Skips the test where a timing budget cannot be measured, saying why.
    static func requireTheOwnersDevice() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment[skipVariableName] == "1",
                      "Timing budgets are measured on the owner's iPad (nightly), not on GitHub's shared runners.")
    }
}
