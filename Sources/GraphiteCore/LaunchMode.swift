import Foundation

/// How this launch of the app was asked to run, read once from the process's arguments and
/// environment as the app starts. Everything that depends on it (what the app restores,
/// what it starts, where its device state lives) is decided from this value by the app's
/// composition, never by a view or a model reading the process itself.
public enum LaunchMode: Equatable, Sendable {
    /// A person's launch: the last vault reopens, diagnostics run, the app's preferences and
    /// the system's folders are used.
    case normal
    /// The app is the host of the hosted test target: no vault is restored, no diagnostics
    /// start, and the device state is a private preferences suite and temporary Caches and
    /// Application Support folders (`ARCH-INV-17`).
    case hostedTests

    /// The launch argument that asks for `hostedTests` explicitly, for a test run that
    /// starts the app without XCTest.
    public static let hostedTestsArgument = "-GraphiteHostedTests"

    /// The variables XCTest sets in a process that hosts tests; any one of them selects
    /// `hostedTests`.
    public static let testHostEnvironmentKeys: [String] = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]

    public init(arguments: [String], environment: [String: String]) {
        let isAskedForByArgument = arguments.contains(Self.hostedTestsArgument)
        let isTestHost = Self.testHostEnvironmentKeys.contains { key in environment[key] != nil }
        self = isAskedForByArgument || isTestHost ? .hostedTests : .normal
    }

    /// Whether the last vault is reopened when the app starts.
    public var restoresLastVault: Bool { self == .normal }

    /// Whether hang and crash diagnostics start with the app.
    public var startsDiagnostics: Bool { self == .normal }

    /// Whether the welcome tour opens by itself the first time the app starts on a device.
    public var presentsWelcomeTour: Bool { self == .normal }
}

/// Where sound goes. A person's launch plays through the speakers; a process that hosts tests
/// renders and discards, so a test run never speaks, plays a recording or sounds a tone aloud.
/// Speech, rendered voices and embedded media take this at their initializers, and a test that
/// builds one passes `.silent` or leaves the default, which is decided from the process.
public enum AudioOutputRoute: Equatable, Sendable {
    case speakers
    /// Audio is produced and timed as for the speakers, and nothing is heard.
    case silent

    public init(launchMode: LaunchMode) {
        self = launchMode == .normal ? .speakers : .silent
    }

    /// The route of this process: silent when the launch hosts tests (its arguments and
    /// environment) or XCTest is loaded, which a package test run (`swift test`) does without
    /// setting the host variables. Read once.
    public static let thisProcess: AudioOutputRoute = {
        let launchMode = LaunchMode(arguments: ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment)
        return AudioOutputRoute(launchMode: launchMode) == .speakers && NSClassFromString("XCTestCase") == nil ? .speakers : .silent
    }()
}
