import XCTest
import GraphiteCore
@testable import GraphiteApple

@MainActor
final class VaultLocatorTests: XCTestCase {
    private var parentFolder: URL!

    override func setUp() async throws {
        parentFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parentFolder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: parentFolder)
    }

    func testNewVaultIsAnEmptyFolderFoundAgainThroughItsParent() throws {
        let location = try VaultLocator.createVaultFolder(named: " Physics ", in: parentFolder)
        XCTAssertEqual(location.relativePath, "Physics")
        let vaultFolder = parentFolder.appendingPathComponent("Physics")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vaultFolder.path), [])
        let reopened = try VaultLocator.access(location)
        XCTAssertEqual(reopened.access.root.standardizedFileURL.resolvingSymlinksInPath(), vaultFolder.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testNewVaultNeverReusesAnExistingItem() throws {
        try FileManager.default.createDirectory(at: parentFolder.appendingPathComponent("Physics"), withIntermediateDirectories: false)
        try Data("notes".utf8).write(to: parentFolder.appendingPathComponent("Physics/Optics.md"))
        XCTAssertThrowsError(try VaultLocator.createVaultFolder(named: "Physics", in: parentFolder))
        XCTAssertThrowsError(try VaultLocator.createVaultFolder(named: ".hidden", in: parentFolder))
        XCTAssertEqual(try String(contentsOf: parentFolder.appendingPathComponent("Physics/Optics.md"), encoding: .utf8), "notes")
    }

    func testPickedFolderIsFollowedWhenRenamedAndReportedWhenDeleted() throws {
        let vaultFolder = parentFolder.appendingPathComponent("Chemistry", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: false)
        let location = try VaultLocator.location(forPickedFolder: vaultFolder)
        XCTAssertEqual(try VaultLocator.access(location).access.root.lastPathComponent, "Chemistry")

        let renamedFolder = parentFolder.appendingPathComponent("Chemistry 2026", isDirectory: true)
        try FileManager.default.moveItem(at: vaultFolder, to: renamedFolder)
        XCTAssertEqual(try VaultLocator.access(location).access.root.lastPathComponent, "Chemistry 2026")

        try FileManager.default.removeItem(at: renamedFolder)
        XCTAssertThrowsError(try VaultLocator.access(location))
    }

    #if !os(macOS)
    func testFolderPickedInsideGraphitesFolderIsRememberedByItsPathThere() throws {
        let vaultFolder = parentFolder.appendingPathComponent("Courses/Physics", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultFolder, withIntermediateDirectories: true)
        let location = try VaultLocator.location(forPickedFolder: vaultFolder, applicationDocumentsFolder: parentFolder)
        XCTAssertEqual(location, VaultLocation(anchor: .applicationDocuments, relativePath: "Courses/Physics"))
    }
    #endif
}
