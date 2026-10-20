import Foundation
import XCTest

/// A `UserDefaults` suite of its own, named with a fresh identifier, for a test whose
/// subject reads and writes its preferences through a `UserDefaults` it is given. It is
/// emptied when the test ends.
public struct IsolatedDeviceState: @unchecked Sendable {
    // `UserDefaults` is documented as thread-safe, and nothing here is mutable.
    public let suiteName: String
    public let preferences: UserDefaults

    /// Creates the suite. `prefix` says which test made one that a crashed run left behind.
    public init(prefix: String = "GraphiteTests") throws {
        let name = "\(prefix)-\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: name) else {
            throw IsolatedDeviceStateError.suiteCannotBeCreated(name)
        }
        suiteName = name
        preferences = suite
    }

    /// A suite that is emptied after the test, whatever the test does (before `tearDown()`
    /// runs, as XCTest runs registered teardown blocks first).
    @discardableResult
    public static func make(prefix: String = "GraphiteTests", for testCase: XCTestCase) throws -> IsolatedDeviceState {
        let state = try IsolatedDeviceState(prefix: prefix)
        testCase.addTeardownBlock { state.remove() }
        return state
    }

    public func remove() {
        preferences.removePersistentDomain(forName: suiteName)
    }
}

public enum IsolatedDeviceStateError: Error, CustomStringConvertible {
    case suiteCannotBeCreated(String)

    public var description: String {
        switch self {
        case .suiteCannotBeCreated(let name): "UserDefaults could not create the suite \(name)."
        }
    }
}
