import XCTest
import GraphiteTestSupport
@testable import GraphiteCore

/// How the app is told to run as it starts: normally, or as the host of the hosted tests.
final class LaunchModeTests: XCTestCase {
    func testAPlainLaunchIsNormal() {
        XCTAssertEqual(LaunchMode(arguments: ["/Applications/Graphite.app/Graphite"], environment: ["HOME": "/Users/someone"]), .normal)
        XCTAssertEqual(LaunchMode(arguments: [], environment: [:]), .normal)
    }

    func testTheHostedTestsArgumentSelectsHostedTests() {
        XCTAssertEqual(LaunchMode(arguments: ["Graphite", "-GraphiteHostedTests"], environment: [:]), .hostedTests)
        XCTAssertEqual(LaunchMode.hostedTestsArgument, "-GraphiteHostedTests")
    }

    func testTheVariablesXCTestSetsInAProcessThatHostsTestsSelectHostedTests() {
        for key in ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"] {
            XCTAssertEqual(LaunchMode(arguments: ["Graphite"], environment: [key: "/tmp/anything"]), .hostedTests, key)
        }
    }

    func testOnlyTheExactArgumentSelectsHostedTests() {
        XCTAssertEqual(LaunchMode(arguments: ["Graphite", "-GraphiteHostedTestsLater", "GraphiteHostedTests"], environment: [:]), .normal)
    }

    func testOnlyANormalLaunchRestoresTheLastVaultAndStartsDiagnostics() {
        XCTAssertTrue(LaunchMode.normal.restoresLastVault)
        XCTAssertTrue(LaunchMode.normal.startsDiagnostics)
        XCTAssertFalse(LaunchMode.hostedTests.restoresLastVault)
        XCTAssertFalse(LaunchMode.hostedTests.startsDiagnostics)
    }

    func testTemporaryFoldersAreSeparateFoldersBelowTheParentAndNothingIsCreated() throws {
        let parent = try TemporaryVault.make(prefix: "ApplicationFoldersTests", for: self).root.appendingPathComponent("Root", isDirectory: true)

        let folders = ApplicationFolders.temporary(below: parent)

        XCTAssertEqual(folders.cachesFolder, parent.appendingPathComponent("Caches", isDirectory: true))
        XCTAssertEqual(folders.applicationSupportFolder, parent.appendingPathComponent("Application Support", isDirectory: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.path), "The code that writes into a folder makes it.")
    }

    func testTheSystemsFoldersAreLeftToFileManagerToFind() {
        XCTAssertNil(ApplicationFolders.system.cachesFolder)
        XCTAssertNil(ApplicationFolders.system.applicationSupportFolder)
    }

    func testFileRecoveryAndRecordingRecoveryUseAnApplicationSupportFolderWhenGivenOne() throws {
        let support = try TemporaryVault.make(prefix: "ApplicationFoldersTests", for: self).root
        let vaultIdentifier = UUID()

        let store = try FileRecoveryStore.forVault(identifier: vaultIdentifier, in: support)
        let recordingsFolder = try RecordingRecoveryFolder.location(in: support)

        XCTAssertEqual(store.directory, support.appendingPathComponent("Graphite/File Recovery/" + vaultIdentifier.uuidString, isDirectory: true))
        XCTAssertEqual(recordingsFolder, support.appendingPathComponent("Graphite/Recovery/Recordings", isDirectory: true))
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordingsFolder.path, isDirectory: &isDirectory) && isDirectory.boolValue, "The recordings folder is made.")
    }
}
