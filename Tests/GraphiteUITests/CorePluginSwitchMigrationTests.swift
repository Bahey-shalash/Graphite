import XCTest
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// A speech engine that never makes a sound.
@MainActor
private final class SilentSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    let voices = [ReadAloudVoice(id: "test", name: "Test", language: "en-US", quality: 3)]
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws {}
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() {}
}

/// The one-time change that made Read Aloud off by default: a device that used Read Aloud
/// before keeps it on (a Read Aloud preference, or a downloaded voice), a new install starts
/// with it off, a plugin turned off earlier stays off, and the migration runs only once.
@MainActor
final class CorePluginSwitchMigrationTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() async throws {
        defaults = try IsolatedDeviceState.make(prefix: "CorePluginSwitchMigrationTests", for: self).preferences
    }

    override func tearDown() async throws {
        defaults = nil
    }

    /// Counts how often the voice question is asked.
    private final class VoiceQuestionCounter {
        private(set) var askedCount = 0
        func answer(_ hasVoice: Bool) -> Bool {
            askedCount += 1
            return hasVoice
        }
    }

    private func makeVoicesFolder(containing names: [String]) throws -> URL {
        let temporaryFolders = try TemporaryVault.make(prefix: "CorePluginSwitchMigrationVoices", for: self)
        let voicesFolder = try temporaryFolders.createFolder("Voices")
        for name in names {
            if name.hasPrefix(".") {
                try Data().write(to: voicesFolder.appendingPathComponent(name))
            } else {
                try FileManager.default.createDirectory(at: voicesFolder.appendingPathComponent(name, isDirectory: true), withIntermediateDirectories: true)
            }
        }
        return voicesFolder
    }

    private func turnedOnPlugins() -> [String]? { defaults.stringArray(forKey: "GraphiteEnabledCorePlugins") }

    // MARK: The decision

    func testAReadAloudPreferenceKeepsReadAloudOn() {
        let evidence = CorePluginSwitchMigration.ReadAloudUseEvidence(hasReadAloudPreference: true, hasDownloadedVoice: { false })

        XCTAssertEqual(CorePluginSwitchMigration.turnedOnPlugins(alreadyTurnedOff: [], evidence: evidence), [.readAloud])
    }

    func testADownloadedVoiceKeepsReadAloudOn() {
        let evidence = CorePluginSwitchMigration.ReadAloudUseEvidence(hasReadAloudPreference: false, hasDownloadedVoice: { true })

        XCTAssertEqual(CorePluginSwitchMigration.turnedOnPlugins(alreadyTurnedOff: [], evidence: evidence), [.readAloud])
    }

    func testNoEvidenceTurnsNothingOn() {
        let evidence = CorePluginSwitchMigration.ReadAloudUseEvidence(hasReadAloudPreference: false, hasDownloadedVoice: { false })

        XCTAssertEqual(CorePluginSwitchMigration.turnedOnPlugins(alreadyTurnedOff: [], evidence: evidence), [])
    }

    func testReadAloudTurnedOffEarlierStaysOffWhateverTheEvidence() {
        let evidence = CorePluginSwitchMigration.ReadAloudUseEvidence(hasReadAloudPreference: true, hasDownloadedVoice: { true })

        XCTAssertEqual(CorePluginSwitchMigration.turnedOnPlugins(alreadyTurnedOff: [.readAloud], evidence: evidence), [])
    }

    func testOtherPluginsTurnedOffDoNotKeepReadAloudOff() {
        let evidence = CorePluginSwitchMigration.ReadAloudUseEvidence(hasReadAloudPreference: true, hasDownloadedVoice: { false })

        XCTAssertEqual(CorePluginSwitchMigration.turnedOnPlugins(alreadyTurnedOff: [.graph], evidence: evidence), [.readAloud])
    }

    func testTheFolderIsNotListedWhenAPreferenceAlreadyAnswered() {
        let counter = VoiceQuestionCounter()
        let answeredByPreference = CorePluginSwitchMigration.ReadAloudUseEvidence(hasReadAloudPreference: true, hasDownloadedVoice: { counter.answer(true) })
        let turnedOff = CorePluginSwitchMigration.ReadAloudUseEvidence(hasReadAloudPreference: false, hasDownloadedVoice: { counter.answer(true) })

        _ = CorePluginSwitchMigration.turnedOnPlugins(alreadyTurnedOff: [], evidence: answeredByPreference)
        XCTAssertEqual(counter.askedCount, 0)
        _ = CorePluginSwitchMigration.turnedOnPlugins(alreadyTurnedOff: [.readAloud], evidence: turnedOff)
        XCTAssertEqual(counter.askedCount, 0, "A plugin turned off needs no evidence.")
        _ = CorePluginSwitchMigration.turnedOnPlugins(alreadyTurnedOff: [], evidence: turnedOff)
        XCTAssertEqual(counter.askedCount, 1)
    }

    // MARK: Running on a device

    func testARecordedReadAloudSpeedKeepsReadAloudOn() {
        defaults.set(1.5, forKey: "GraphiteReadAloudSpeed")

        CorePluginSwitchMigration.runIfNeeded(in: defaults, voicesFolder: nil)

        XCTAssertEqual(turnedOnPlugins(), ["readAloud"])
        XCTAssertTrue(GraphitePreferences(defaults: defaults).isEnabled(.readAloud))
    }

    func testARecordedMathematicalStyleKeepsReadAloudOn() {
        defaults.set("detailed", forKey: "readAloudMathematicalStyle")

        CorePluginSwitchMigration.runIfNeeded(in: defaults, voicesFolder: nil)

        XCTAssertTrue(GraphitePreferences(defaults: defaults).isEnabled(.readAloud))
    }

    func testADownloadedVoiceFolderKeepsReadAloudOn() throws {
        let voicesFolder = try makeVoicesFolder(containing: ["pocket-tts"])

        CorePluginSwitchMigration.runIfNeeded(in: defaults, voicesFolder: voicesFolder)

        XCTAssertEqual(turnedOnPlugins(), ["readAloud"])
    }

    func testAnEmptyVoicesFolderWithOnlyAHiddenFileLeavesReadAloudOff() throws {
        let voicesFolder = try makeVoicesFolder(containing: [".DS_Store"])

        CorePluginSwitchMigration.runIfNeeded(in: defaults, voicesFolder: voicesFolder)

        XCTAssertEqual(turnedOnPlugins(), [])
        XCTAssertFalse(GraphitePreferences(defaults: defaults).isEnabled(.readAloud))
    }

    func testAVoicesFolderThatDoesNotExistLeavesReadAloudOff() throws {
        let missingFolder = try TemporaryVault.make(prefix: "CorePluginSwitchMigrationMissing", for: self).location(of: "Voices")

        CorePluginSwitchMigration.runIfNeeded(in: defaults, voicesFolder: missingFolder)

        XCTAssertEqual(turnedOnPlugins(), [])
    }

    func testNoVoicesFolderAndNoPreferenceLeavesReadAloudOffAndRecordsTheRun() {
        CorePluginSwitchMigration.runIfNeeded(in: defaults, voicesFolder: nil)

        XCTAssertEqual(turnedOnPlugins(), [])
        XCTAssertFalse(GraphitePreferences(defaults: defaults).isEnabled(.readAloud))
    }

    func testReadAloudTurnedOffBeforeStaysOffDespiteItsPreferences() {
        defaults.set(["readAloud"], forKey: "GraphiteDisabledCorePlugins")
        defaults.set(1.5, forKey: "GraphiteReadAloudSpeed")

        CorePluginSwitchMigration.runIfNeeded(in: defaults, voicesFolder: nil)

        XCTAssertEqual(turnedOnPlugins(), [])
        XCTAssertFalse(GraphitePreferences(defaults: defaults).isEnabled(.readAloud))
    }

    func testTheMigrationRunsOnlyOnce() {
        defaults.set(1.5, forKey: "GraphiteReadAloudSpeed")
        CorePluginSwitchMigration.runIfNeeded(in: defaults, voicesFolder: nil)
        let preferences = GraphitePreferences(defaults: defaults)
        XCTAssertTrue(preferences.isEnabled(.readAloud))

        preferences.setEnabled(.readAloud, false)
        CorePluginSwitchMigration.runIfNeeded(in: defaults, voicesFolder: nil)

        XCTAssertFalse(GraphitePreferences(defaults: defaults).isEnabled(.readAloud), "A later launch must not turn it back on.")
        XCTAssertEqual(turnedOnPlugins(), [])
    }

    func testAnEarlierRunThatFoundNothingIsNotRepeatedWhenAPreferenceAppearsLater() {
        CorePluginSwitchMigration.runIfNeeded(in: defaults, voicesFolder: nil)
        defaults.set(1.5, forKey: "GraphiteReadAloudSpeed")

        CorePluginSwitchMigration.runIfNeeded(in: defaults, voicesFolder: nil)

        XCTAssertFalse(GraphitePreferences(defaults: defaults).isEnabled(.readAloud))
    }

    // MARK: An existing user, end to end

    func testAnExistingUsersWorkspaceHasReadAloudOnAtLaunch() throws {
        let device = try IsolatedWorkspaceDevice.make(for: self)
        device.defaults.set(["a place"], forKey: "GraphiteReadAloudPositions")

        let defaults = device.defaults

        let workspace = device.makeWorkspace(makeReadAloudController: {
            ReadAloudController(session: ReadAloudSession(speech: SilentSpeech(), preferences: defaults), preferences: defaults)
        })

        XCTAssertNotNil(workspace.readAloud)
        XCTAssertNotNil(workspace.readAloudNavigator)
    }

    func testANewUsersWorkspaceHasReadAloudOffAtLaunch() throws {
        let device = try IsolatedWorkspaceDevice.make(for: self)

        let workspace = device.makeWorkspace()

        XCTAssertNil(workspace.readAloud)
        XCTAssertNil(workspace.readAloudNavigator)
    }
}
