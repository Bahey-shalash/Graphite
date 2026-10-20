import Foundation

/// Where the checked-in fixtures are, found once from this file's own place in the
/// repository (`Tests/GraphiteFixtures/`), so that no test counts `deletingLastPathComponent`
/// calls from its own file. A test that changes a fixture works on a copy
/// (`TemporaryVault` in `GraphiteTestSupport` can hold one).
public enum FixtureFolders {
    public static let repositoryRoot = URL(fileURLWithPath: #filePath, isDirectory: false)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// The vault of `.base` files and notes the Bases tests run through a real index.
    public static let baseSampleVault = repositoryRoot.appendingPathComponent("Tests/BaseSampleVault", isDirectory: true)

    /// Notes with awkward names, for the tests of name matching.
    public static let namingTestVault = repositoryRoot.appendingPathComponent("Tests/test_vault", isDirectory: true)

    /// The Mac and iPad application's property lists.
    public static let applicationFolder = repositoryRoot.appendingPathComponent("App", isDirectory: true)

    /// The voice manifest the app ships.
    public static let shippedNeuralVoiceManifest = repositoryRoot.appendingPathComponent("Sources/GraphiteVoices/Resources/NeuralVoices.json")
}
