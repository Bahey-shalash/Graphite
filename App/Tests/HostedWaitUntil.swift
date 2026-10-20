import Foundation
import XCTest

/// The hosted iPad tests' copy of `waitUntil` in `Tests/GraphiteTestSupport/WaitUntil.swift`
/// (this target cannot import the package's test-support target): the same parameters, the
/// same polling, the same failure. Change both together.
func waitUntil(_ description: String = "the condition", timeoutSeconds: TimeInterval = 20, pollingIntervalSeconds: TimeInterval = 0.02,
               file: StaticString = #filePath, line: UInt = #line, isolation: isolated (any Actor)? = #isolation,
               _ condition: () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(timeoutSeconds)
    while !(try await condition()) {
        guard ContinuousClock.now < deadline else {
            XCTFail("Timed out after \(timeoutSeconds) seconds waiting until \(description).", file: file, line: line)
            return
        }
        try await Task.sleep(for: .seconds(pollingIntervalSeconds))
    }
}
