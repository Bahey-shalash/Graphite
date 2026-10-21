import Foundation
import XCTest

/// Waits until `condition` is true, for the work a test does not own: a web view that
/// loads, a callback from a framework, a background task that publishes its result. It
/// checks at once, then every `pollingIntervalSeconds`, and fails the test with the
/// description of what it waited for when `timeoutSeconds` pass first. A test that can
/// tell its own work to proceed (an injected clock, a continuation) does not poll.
///
/// It runs on the actor of its caller, so a main-actor test's condition reads main-actor
/// state directly. The hosted iPad target compiles this file as one of its own sources, so
/// both suites wait the same way.
public func waitUntil(_ description: String = "the condition", timeoutSeconds: TimeInterval = 20, pollingIntervalSeconds: TimeInterval = 0.02,
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
