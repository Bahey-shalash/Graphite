import Foundation
import XCTest

/// What a shared GitHub runner cannot do the way the owner's iPad does. The hosted job of the CI workflow sets the variable
/// of each limit it has (as `TEST_RUNNER_<name>`, which `xcodebuild` hands to the tests); the nightly device job sets none,
/// and runs everything. Each limit is a named capability, and every test that needs it says so by calling its function.
enum RunnerLimits {
    /// Skips the test when the CI job set `variable`, saying why.
    fileprivate static func skip(whenSet variable: String, because reason: String) throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment[variable] == "1", reason)
    }
}

/// The timing budgets of the hosted suite (a number of seconds, a share of the main thread or a longest frame gap) mean
/// something only on the owner's iPad: GitHub's shared virtual Macs run the simulator several times slower and unevenly.
enum TimingBudgets {
    static let skipVariableName = "GRAPHITE_SKIP_TIMING_BUDGETS"

    /// Skips the test where a timing budget cannot be measured, saying why.
    static func requireTheOwnersDevice() throws {
        try RunnerLimits.skip(whenSet: skipVariableName,
                              because: "Timing budgets are measured on the owner's iPad (nightly), not on GitHub's shared runners.")
    }
}

/// MapKit composes the tiles of an overlay into its picture only after its own map service has answered or failed, and a
/// runner without a dependable connection to Apple's servers leaves that unfinished (its map tile requests ended in
/// "-1001" timeouts, and the picture never filled).
enum MapServices {
    static let skipVariableName = "GRAPHITE_SKIP_MAPKIT_COMPOSITING"

    /// Skips the test where MapKit's picture of a map cannot be waited for, saying why.
    static func requireAppleMapService() throws {
        try RunnerLimits.skip(whenSet: skipVariableName,
                              because: "MapKit draws a map only once Apple's map service answers, which GitHub's runners cannot do dependably; the owner's iPad (nightly) can.")
    }
}
