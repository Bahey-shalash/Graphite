#if os(macOS)
import XCTest
import Synchronization
import GraphiteCore
@testable import GraphiteApple

/// `FileProviderConflictVersions` against real `NSFileVersion` objects on this Mac's
/// volume. Versions can be added there (`NSFileVersion.addOfItem`, which iOS lacks), but
/// nothing marks one as a conflict: only a file provider does that. So the store lists
/// every other version here, and what it does with a version (reading it, replacing the
/// file with it, keeping it as a separate file, marking it resolved and removing it
/// under file coordination) is the code that runs for a provider's conflict versions.
final class FileVersionConflictTests: XCTestCase {
    private var folder: URL!
    private var note: URL!
    private let store = FileProviderConflictVersions(listing: .everyOtherVersion)
    private let writer = AtomicFileWriter()

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("FileVersions-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        note = folder.appendingPathComponent("Lecture.md")
        try Data("current text\n".utf8).write(to: note)
    }

    override func tearDownWithError() throws {
        // Versions live in the volume's version store, not in the folder.
        try? NSFileVersion.removeOtherVersionsOfItem(at: note)
        try? FileManager.default.removeItem(at: folder)
    }

    /// Adds a version of the note holding `text`, as another device's save would be kept.
    @discardableResult
    private func addVersion(_ text: String, modified: Date? = nil) throws -> NSFileVersion {
        let contents = folder.appendingPathComponent("version-\(UUID().uuidString).md")
        try Data(text.utf8).write(to: contents)
        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: contents.path) }
        defer { try? FileManager.default.removeItem(at: contents) }
        return try NSFileVersion.addOfItem(at: note, withContentsOf: contents, options: [])
    }

    private func noteText() throws -> String { String(decoding: try Data(contentsOf: note), as: UTF8.self) }

    func testAFileWithoutVersionsHasNone() throws {
        XCTAssertFalse(store.hasConflictVersions(at: note))
        XCTAssertEqual(try store.conflictVersions(of: note), [])
        XCTAssertFalse(store.hasConflictVersions(at: folder.appendingPathComponent("Missing.md")), "A file that does not exist has none either.")
    }

    func testVersionsAreListedNewestFirstWithTheirDateAndSize() throws {
        try addVersion("older version\n", modified: Date(timeIntervalSince1970: 1_700_000_000))
        try addVersion("the newer version of the text\n", modified: Date(timeIntervalSince1970: 1_750_000_000))

        XCTAssertTrue(store.hasConflictVersions(at: note))
        let versions = try store.conflictVersions(of: note)
        XCTAssertEqual(versions.map(\.byteCount), [30, 14])
        XCTAssertEqual(versions.map(\.modified), [Date(timeIntervalSince1970: 1_750_000_000), Date(timeIntervalSince1970: 1_700_000_000)])
        XCTAssertTrue(versions.allSatisfy(\.hasLocalContents))
        XCTAssertEqual(Set(versions.map(\.id)).count, 2, "Each version can be told from the other.")
        XCTAssertEqual(try noteText(), "current text\n", "Listing changes nothing.")
    }

    /// The reason a provider is needed to see the feature end to end.
    func testAVersionOnALocalVolumeIsNeverAnUnresolvedConflict() throws {
        let version = try addVersion("another version\n")
        XCTAssertFalse(version.isConflict)
        let productionStore = FileProviderConflictVersions()
        XCTAssertFalse(productionStore.hasConflictVersions(at: note))
        XCTAssertEqual(try productionStore.conflictVersions(of: note), [])
    }

    func testAVersionsContentsCanBeRead() throws {
        try addVersion("text saved on another device\n")
        let version = try XCTUnwrap(try store.conflictVersions(of: note).first)
        let contentsLocation = try store.contentsLocation(ofVersion: version.id, ofFileAt: note)
        XCTAssertEqual(String(decoding: try Data(contentsOf: contentsLocation), as: UTF8.self), "text saved on another device\n")
        XCTAssertEqual(contentsLocation.pathExtension, "md", "The version keeps the file's type, so a preview knows what it is.")
    }

    func testReplacingPutsTheVersionInPlaceAndKeepsTheOthers() throws {
        try addVersion("first other version\n", modified: Date(timeIntervalSince1970: 1_700_000_000))
        try addVersion("second other version\n", modified: Date(timeIntervalSince1970: 1_750_000_000))
        let versions = try store.conflictVersions(of: note)
        let chosen = try XCTUnwrap(versions.last)

        let replacedLocation = try store.replaceFile(at: note, withVersion: chosen.id, expecting: FileChangeStamp.of(note), using: writer)

        XCTAssertEqual(replacedLocation.resolvingSymlinksInPath().path, note.path)
        XCTAssertEqual(try noteText(), "first other version\n")
        let remaining = try store.conflictVersions(of: note)
        XCTAssertEqual(remaining.map(\.id), [try XCTUnwrap(versions.first).id], "The version that became the file is no longer kept beside it; the other one is.")
    }

    func testReplacingIsRefusedWhenTheFileChangedSinceItWasLookedAt() throws {
        try addVersion("other version\n")
        let version = try XCTUnwrap(try store.conflictVersions(of: note).first)
        let stampWhenListed = FileChangeStamp.of(note)
        try Data("edited on this device meanwhile\n".utf8).write(to: note)

        XCTAssertThrowsError(try store.replaceFile(at: note, withVersion: version.id, expecting: stampWhenListed, using: writer)) { error in
            XCTAssertEqual(error as? GraphiteError, .conflict)
        }
        XCTAssertEqual(try noteText(), "edited on this device meanwhile\n", "The newer edit is not overwritten.")
        XCTAssertEqual(try store.conflictVersions(of: note).count, 1, "The version is still kept.")
    }

    func testKeepingAVersionAsASeparateFileLeavesTheCurrentFileAlone() throws {
        try addVersion("text saved on another device\n")
        try addVersion("a third version\n", modified: Date(timeIntervalSince1970: 1_700_000_000))
        let versions = try store.conflictVersions(of: note)
        let keptVersion = try XCTUnwrap(versions.first { version in version.byteCount == 29 })
        let copy = folder.appendingPathComponent("Lecture (Conflicted copy).md")

        try store.keepVersion(keptVersion.id, ofFileAt: note, asSeparateFileAt: copy, using: writer)

        XCTAssertEqual(String(decoding: try Data(contentsOf: copy), as: UTF8.self), "text saved on another device\n")
        XCTAssertTrue(FileManager.default.isWritableFile(atPath: copy.path), "The copy is an ordinary file that can be edited, unlike the stored version.")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: copy.path)[.posixPermissions] as? Int,
                       try FileManager.default.attributesOfItem(atPath: note.path)[.posixPermissions] as? Int)
        XCTAssertEqual(try noteText(), "current text\n")
        XCTAssertEqual(try store.conflictVersions(of: note).map(\.byteCount), [16], "Only the version kept as a file stops being kept beside the note.")
    }

    func testKeepingAVersionNeverWritesOverAnExistingFile() throws {
        try addVersion("text saved on another device\n")
        let version = try XCTUnwrap(try store.conflictVersions(of: note).first)
        let taken = folder.appendingPathComponent("Taken.md")
        try Data("someone else's note\n".utf8).write(to: taken)

        XCTAssertThrowsError(try store.keepVersion(version.id, ofFileAt: note, asSeparateFileAt: taken, using: writer)) { error in
            XCTAssertEqual(error as? GraphiteError, .conflict)
        }
        XCTAssertEqual(String(decoding: try Data(contentsOf: taken), as: UTF8.self), "someone else's note\n")
        XCTAssertEqual(try store.conflictVersions(of: note).count, 1, "A version that could not be copied is not removed.")
    }

    func testRemovingRemovesOnlyTheVersionsNamed() throws {
        try addVersion("first other version\n", modified: Date(timeIntervalSince1970: 1_700_000_000))
        try addVersion("second other version\n", modified: Date(timeIntervalSince1970: 1_750_000_000))
        let versions = try store.conflictVersions(of: note)

        try store.removeVersions([try XCTUnwrap(versions.first).id], ofFileAt: note, using: writer)
        XCTAssertEqual(try store.conflictVersions(of: note).map(\.id), [try XCTUnwrap(versions.last).id])
        XCTAssertEqual(try noteText(), "current text\n")

        try store.removeVersions(["no such version"], ofFileAt: note, using: writer)
        XCTAssertEqual(try store.conflictVersions(of: note).count, 1, "A name that matches nothing removes nothing.")

        try store.removeVersions(versions.map(\.id), ofFileAt: note, using: writer)
        XCTAssertFalse(store.hasConflictVersions(at: note))
        XCTAssertEqual(try noteText(), "current text\n")
    }

    func testAVersionThatIsNoLongerKeptIsReported() throws {
        try addVersion("other version\n")
        let version = try XCTUnwrap(try store.conflictVersions(of: note).first)
        try store.removeVersions([version.id], ofFileAt: note, using: writer)

        for attempt in [
            { _ = try self.store.contentsLocation(ofVersion: version.id, ofFileAt: self.note) },
            { _ = try self.store.replaceFile(at: self.note, withVersion: version.id, expecting: nil, using: self.writer) },
            { try self.store.keepVersion(version.id, ofFileAt: self.note, asSeparateFileAt: self.folder.appendingPathComponent("Copy.md"), using: self.writer) },
        ] {
            XCTAssertThrowsError(try attempt()) { error in
                XCTAssertEqual(error.localizedDescription, "That version is no longer kept. It may have been resolved on another device.")
            }
        }
        XCTAssertEqual(try noteText(), "current text\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Copy.md").path))
    }

    /// Another app that presents the folder learns of a replacement. (`NSFileVersion`
    /// reports it to Graphite's own presenter too, whatever coordinator is used; the
    /// workspace then refreshes the file a second time, which changes nothing.)
    func testOtherPresentersLearnOfAReplacement() throws {
        try addVersion("other version\n")
        let version = try XCTUnwrap(try store.conflictVersions(of: note).first)
        let otherReports = Mutex<[String]>([])
        let ownPresenter = VaultMonitor(root: folder) { _ in }
        let otherPresenter = VaultMonitor(root: folder) { location in otherReports.withLock { reports in reports.append(location?.lastPathComponent ?? "") } }
        defer { ownPresenter.stop(); otherPresenter.stop() }

        try store.replaceFile(at: note, withVersion: version.id, expecting: nil, using: AtomicFileWriter(filePresenter: ownPresenter))

        let deadline = Date.now.addingTimeInterval(10)
        while otherReports.withLock({ reports in !reports.contains("Lecture.md") }), Date.now < deadline { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertTrue(otherReports.withLock { reports in reports.contains("Lecture.md") })
    }

    /// On this Mac the system does tell a folder's presenter when a file in it gains a
    /// version, which is how a provider's new conflict version reaches the workspace.
    func testAPresenterOfTheFolderIsToldWhenAFileGainsAVersion() throws {
        let reports = Mutex<[String]>([])
        let presenter = VaultMonitor(root: folder) { location in reports.withLock { reports in reports.append(location?.lastPathComponent ?? "") } }
        defer { presenter.stop() }

        try addVersion("other version\n")

        let deadline = Date.now.addingTimeInterval(10)
        while reports.withLock({ reports in !reports.contains("Lecture.md") }), Date.now < deadline { Thread.sleep(forTimeInterval: 0.02) }
        XCTAssertTrue(reports.withLock { reports in reports.contains("Lecture.md") })
    }

    /// A provider tells presenters of a folder when a file in it gains or loses a version.
    func testTheVaultsPresenterReportsAFileThatGainsOrLosesAVersion() throws {
        let version = try addVersion("other version\n")
        let reports = Mutex<[String]>([])
        let presenter = VaultMonitor(root: folder) { location in reports.withLock { reports in reports.append(location?.lastPathComponent ?? "") } }
        defer { presenter.stop() }

        presenter.presentedSubitem(at: note, didGain: version)
        presenter.presentedSubitem(at: note, didResolve: version)
        presenter.presentedSubitem(at: note, didLose: version)
        XCTAssertEqual(reports.withLock { reports in reports }, ["Lecture.md", "Lecture.md", "Lecture.md"])
    }
}
#endif
