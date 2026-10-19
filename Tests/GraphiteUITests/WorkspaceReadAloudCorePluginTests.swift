import XCTest
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// A speech engine that only records how it was stopped.
@MainActor
private final class StopRecordingSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    let voices = [ReadAloudVoice(id: "test", name: "Test", language: "en-US", quality: 3)]
    private(set) var stopCount = 0
    private(set) var audioReleaseCount = 0
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws {}
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() { stopCount += 1 }
    func releaseAudio() { audioReleaseCount += 1 }
}

/// Makes the controllers a workspace asks for and counts them, in place of the app's speech.
@MainActor
private final class CountingReadAloudFactory {
    private let preferences: UserDefaults
    let speech = StopRecordingSpeech()
    private(set) var madeControllers: [ReadAloudController] = []

    init(preferences: UserDefaults) { self.preferences = preferences }

    var makeCount: Int { madeControllers.count }

    func makeController() -> ReadAloudController {
        let session = ReadAloudSession(speech: speech, preferences: preferences)
        session.chooseVoice("test")
        let controller = ReadAloudController(session: session, preferences: preferences)
        madeControllers.append(controller)
        return controller
    }
}

/// Read Aloud as a core plugin that is off by default: the workspace builds no speech while it
/// is off, builds it when the plugin is turned on and ends it, mid-playback included, when
/// the plugin is turned off, and keeps what the person has stored for it.
@MainActor
final class WorkspaceReadAloudCorePluginTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!
    private var factory: CountingReadAloudFactory!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
        factory = CountingReadAloudFactory(preferences: device.defaults)
    }

    override func tearDown() async throws {
        factory = nil
        device = nil
    }

    private func makeWorkspace() -> WorkspaceModel {
        let factory = factory!
        return device.makeWorkspace(makeReadAloudController: { factory.makeController() })
    }

    private func makeVault(files: [String: String]) throws -> URL {
        let vault = try TemporaryVault.make(prefix: "ReadAloudCorePluginVault", files: files, for: self)
        return vault.root.resolvingSymlinksInPath()
    }

    func testReadAloudIsOffByDefaultAndBuildsNothing() {
        let workspace = makeWorkspace()

        XCTAssertEqual(factory.makeCount, 0)
        XCTAssertNil(workspace.readAloud)
        XCTAssertNil(workspace.readAloudNavigator)
        XCTAssertFalse(workspace.preferences.isEnabled(.readAloud))
    }

    func testTurningTheOtherPluginsOnOrOffBuildsNoReadAloud() {
        let workspace = makeWorkspace()

        workspace.setCorePluginEnabled(.graph, false)
        workspace.setCorePluginEnabled(.graph, true)

        XCTAssertEqual(factory.makeCount, 0)
        XCTAssertNil(workspace.readAloud)
        XCTAssertTrue(workspace.preferences.isEnabled(.graph))
    }

    func testTurningReadAloudOnBuildsTheControllerAndTheNavigatorOnceWithoutARelaunch() {
        let workspace = makeWorkspace()

        workspace.setCorePluginEnabled(.readAloud, true)
        workspace.setCorePluginEnabled(.readAloud, true)

        XCTAssertEqual(factory.makeCount, 1)
        XCTAssertTrue(workspace.readAloud === factory.madeControllers.first)
        XCTAssertNotNil(workspace.readAloudNavigator)
        XCTAssertTrue(workspace.preferences.isEnabled(.readAloud))
    }

    func testTheControllerBuiltWhenTurnedOnReadsFromTheOpenVault() async throws {
        let vault = try makeVault(files: ["Note.md": "A note."])
        let workspace = makeWorkspace()
        try await workspace.openFolderAsVault(vault)
        let openRoot = try XCTUnwrap(workspace.folderAccess?.root)

        workspace.setCorePluginEnabled(.readAloud, true)

        XCTAssertEqual(workspace.readAloud?.vaultRoot, openRoot)
    }

    func testTurningReadAloudOffDuringPlaybackStopsItAndDropsTheController() async throws {
        let workspace = makeWorkspace()
        workspace.setCorePluginEnabled(.readAloud, true)
        let reader = try XCTUnwrap(workspace.readAloud)
        reader.readMarkdown("## Heading\n\nSome words to read aloud.", path: try VaultPath("Note.md"))
        try await waitUntil("the note is prepared") { reader.session.document != nil }
        reader.session.play()
        XCTAssertEqual(reader.session.state, .speaking)
        reader.showsReader = true
        let stopsBefore = factory.speech.stopCount
        let releasesBefore = factory.speech.audioReleaseCount

        workspace.setCorePluginEnabled(.readAloud, false)

        XCTAssertEqual(reader.session.state, .idle)
        XCTAssertFalse(reader.showsReader)
        XCTAssertNil(reader.session.document)
        XCTAssertGreaterThan(factory.speech.stopCount, stopsBefore, "The speech was stopped.")
        XCTAssertGreaterThan(factory.speech.audioReleaseCount, releasesBefore, "The audio session was given back.")
        XCTAssertNil(workspace.readAloud)
        XCTAssertNil(workspace.readAloudNavigator)
        XCTAssertFalse(workspace.preferences.isEnabled(.readAloud))
    }

    func testTurningReadAloudBackOnBuildsANewControllerAndKeepsTheStoredPlaces() {
        let workspace = makeWorkspace()
        workspace.setCorePluginEnabled(.readAloud, true)
        let firstController = workspace.readAloud
        device.defaults.set(["a remembered place"], forKey: "GraphiteReadAloudPositions")

        workspace.setCorePluginEnabled(.readAloud, false)
        workspace.setCorePluginEnabled(.readAloud, true)

        XCTAssertEqual(factory.makeCount, 2)
        XCTAssertNotNil(workspace.readAloud)
        XCTAssertFalse(workspace.readAloud === firstController)
        XCTAssertEqual(device.defaults.stringArray(forKey: "GraphiteReadAloudPositions"), ["a remembered place"])
    }

    func testAnotherLaunchWithReadAloudTurnedOnBuildsItAtOnce() {
        makeWorkspace().setCorePluginEnabled(.readAloud, true)
        XCTAssertEqual(factory.makeCount, 1)

        let laterWorkspace = makeWorkspace()

        XCTAssertEqual(factory.makeCount, 2)
        XCTAssertNotNil(laterWorkspace.readAloud)
        XCTAssertNotNil(laterWorkspace.readAloudNavigator)
    }

    func testTheSettingsSidebarListsReadAloudOnlyWhileItIsOnAfterTheAudioRecorder() {
        let workspace = makeWorkspace()
        let whileOff = SettingsView.pluginPages(isEnabled: workspace.preferences.isEnabled)
        workspace.setCorePluginEnabled(.readAloud, true)

        let whileOn = SettingsView.pluginPages(isEnabled: workspace.preferences.isEnabled)

        XCTAssertFalse(whileOff.contains(.readAloud))
        XCTAssertTrue(whileOff.contains(.audioRecorder))
        let audioRecorderPosition = whileOn.firstIndex(of: .audioRecorder)
        let readAloudPosition = whileOn.firstIndex(of: .readAloud)
        XCTAssertNotNil(readAloudPosition)
        XCTAssertEqual(readAloudPosition, audioRecorderPosition.map { position in position + 1 })
    }

    func testTheReadLinkWhileReadAloudIsOffSaysWhereToTurnItOnAndReadsNothing() async throws {
        let vault = try makeVault(files: ["Target.md": "The linked note."])
        let workspace = makeWorkspace()
        try await workspace.openFolderAsVault(vault)

        await workspace.handle(try XCTUnwrap(URL(string: "graphite://read?file=Target")))

        XCTAssertTrue(workspace.errorMessage?.contains("Settings › Core Plugins") == true, "The message names Settings › Core Plugins.")
        XCTAssertNil(workspace.readAloud)
        XCTAssertEqual(factory.makeCount, 0)
    }
}
