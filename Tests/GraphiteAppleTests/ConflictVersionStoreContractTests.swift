#if os(macOS)
import XCTest
import GraphiteCore
import GraphiteApple
import GraphiteTestSupport

/// What every `ConflictVersionStore` promises, run against the production store on real
/// `NSFileVersion` objects (listed with `.everyOtherVersion`, since no version on a local
/// volume is ever marked as a conflict) and against `FakeConflictVersionStore`. The
/// workspace's tests are built on the fake, so a case the fake passes and production
/// fails (or the other way) makes those tests say something false; the cases here are
/// the rows the two have to agree on (`LSP-VAULT-02`).
final class ConflictVersionStoreContractTests: XCTestCase {
    /// A store under test, with the means to give a file a version of its own making.
    private struct Subject {
        let name: String
        let store: any ConflictVersionStore
        /// Keeps `text` as a version of the file at `location`, saved at `modified`.
        let addVersion: (_ location: URL, _ text: String, _ modified: Date?) throws -> Void
        /// Forgets what the store kept for the file, for stores whose versions live outside the folder.
        let forgetVersions: (_ location: URL) -> Void
    }

    private var folder: URL!
    private var note: URL!
    private let writer = AtomicFileWriter()

    override func setUpWithError() throws {
        folder = try TemporaryVault.make(prefix: "ConflictVersionContract", for: self).root
        note = folder.appendingPathComponent("Lecture.md")
        try Data("current text\n".utf8).write(to: note)
    }

    private func subjects() throws -> [Subject] {
        let fake = try FakeConflictVersionStore()
        return [
            Subject(name: "FileProviderConflictVersions", store: FileProviderConflictVersions(listing: .everyOtherVersion),
                    addVersion: { location, text, modified in
                        let contents = location.deletingLastPathComponent().appendingPathComponent("version-\(UUID().uuidString).md")
                        try Data(text.utf8).write(to: contents)
                        if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: contents.path) }
                        defer { try? FileManager.default.removeItem(at: contents) }
                        try NSFileVersion.addOfItem(at: location, withContentsOf: contents, options: [])
                    },
                    // Versions live in the volume's version store, not in the folder.
                    forgetVersions: { location in try? NSFileVersion.removeOtherVersionsOfItem(at: location) }),
            Subject(name: "FakeConflictVersionStore", store: fake,
                    addVersion: { location, text, modified in
                        try fake.addVersion(of: location, contents: Data(text.utf8), deviceName: nil, modified: modified)
                    },
                    forgetVersions: { _ in })
        ]
    }

    /// Runs `body` once per store, each time on a note that has no version yet and holds
    /// "current text", so that what one store did cannot show in the other's result.
    private func forEachStore(_ body: (Subject) throws -> Void) throws {
        for subject in try subjects() {
            try Data("current text\n".utf8).write(to: note)
            defer { subject.forgetVersions(note) }
            try body(subject)
        }
    }

    private func noteText() throws -> String { String(decoding: try Data(contentsOf: note), as: UTF8.self) }

    private func assertThrowsUnavailable(_ subject: Subject, _ message: String, _ attempt: () throws -> Void) {
        XCTAssertThrowsError(try attempt(), "\(subject.name): \(message)") { error in
            XCTAssertEqual(error as? GraphiteError, .unavailable("That version is no longer kept. It may have been resolved on another device."), subject.name)
        }
    }

    // MARK: Listing and reading

    func testAFileWithoutVersionsHasNone() throws {
        try forEachStore { subject in
            XCTAssertFalse(subject.store.hasConflictVersions(at: note), subject.name)
            XCTAssertEqual(try subject.store.conflictVersions(of: note), [], subject.name)
        }
    }

    func testVersionsAreListedNewestFirstAndTheirContentsCanBeRead() throws {
        try forEachStore { subject in
            try subject.addVersion(note, "older version\n", Date(timeIntervalSince1970: 1_700_000_000))
            try subject.addVersion(note, "the newer version of the text\n", Date(timeIntervalSince1970: 1_750_000_000))

            XCTAssertTrue(subject.store.hasConflictVersions(at: note), subject.name)
            let versions = try subject.store.conflictVersions(of: note)
            XCTAssertEqual(versions.map(\.byteCount), [30, 14], subject.name)
            XCTAssertEqual(versions.map(\.modified), [Date(timeIntervalSince1970: 1_750_000_000), Date(timeIntervalSince1970: 1_700_000_000)], subject.name)
            let newest = try XCTUnwrap(versions.first)
            let contentsLocation = try subject.store.contentsLocation(ofVersion: newest.id, ofFileAt: note)
            XCTAssertEqual(String(decoding: try Data(contentsOf: contentsLocation), as: UTF8.self), "the newer version of the text\n", subject.name)
            XCTAssertEqual(contentsLocation.pathExtension, "md", "\(subject.name): a version keeps the file's type, so a preview knows what it is.")
            XCTAssertEqual(try noteText(), "current text\n", "\(subject.name): listing and reading change nothing.")
        }
    }

    // MARK: Replacing

    func testReplacingPutsTheVersionInPlaceAndKeepsTheOthers() throws {
        try forEachStore { subject in
            try subject.addVersion(note, "first other version\n", Date(timeIntervalSince1970: 1_700_000_000))
            try subject.addVersion(note, "second other version\n", Date(timeIntervalSince1970: 1_750_000_000))
            let versions = try subject.store.conflictVersions(of: note)
            let chosen = try XCTUnwrap(versions.last)

            let replacedLocation = try subject.store.replaceFile(at: note, withVersion: chosen.id, expecting: FileChangeStamp.of(note), using: writer)

            XCTAssertEqual(replacedLocation.resolvingSymlinksInPath().path, note.path, subject.name)
            XCTAssertEqual(try noteText(), "first other version\n", subject.name)
            XCTAssertEqual(try subject.store.conflictVersions(of: note).map(\.id), [try XCTUnwrap(versions.first).id],
                           "\(subject.name): the version that became the file is no longer kept beside it; the other one is.")
        }
    }

    func testReplacingIsRefusedWhenTheFileChangedSinceItWasListed() throws {
        try forEachStore { subject in
            try subject.addVersion(note, "other version\n", nil)
            let version = try XCTUnwrap(try subject.store.conflictVersions(of: note).first)
            let stampWhenListed = FileChangeStamp.of(note)
            try Data("edited on this device meanwhile\n".utf8).write(to: note)

            XCTAssertThrowsError(try subject.store.replaceFile(at: note, withVersion: version.id, expecting: stampWhenListed, using: writer), subject.name) { error in
                XCTAssertEqual(error as? GraphiteError, .conflict, subject.name)
            }
            XCTAssertEqual(try noteText(), "edited on this device meanwhile\n", "\(subject.name): the newer edit is not overwritten.")
            XCTAssertEqual(try subject.store.conflictVersions(of: note).count, 1, "\(subject.name): the version is still kept.")
        }
    }

    // MARK: Keeping as a separate file

    func testKeepingAVersionWritesASeparateFileOnlyWhereNothingIs() throws {
        try forEachStore { subject in
            try subject.addVersion(note, "text saved on another device\n", nil)
            let version = try XCTUnwrap(try subject.store.conflictVersions(of: note).first)
            let taken = folder.appendingPathComponent("Taken.md")
            try Data("someone else's note\n".utf8).write(to: taken)
            defer { try? FileManager.default.removeItem(at: taken) }

            XCTAssertThrowsError(try subject.store.keepVersion(version.id, ofFileAt: note, asSeparateFileAt: taken, using: writer), subject.name) { error in
                XCTAssertEqual(error as? GraphiteError, .conflict, subject.name)
            }
            XCTAssertEqual(String(decoding: try Data(contentsOf: taken), as: UTF8.self), "someone else's note\n", "\(subject.name): the file that was there is not written over.")
            XCTAssertEqual(try subject.store.conflictVersions(of: note).count, 1, "\(subject.name): a version that could not be copied is not removed.")

            let copy = folder.appendingPathComponent("Lecture (Conflicted copy).md")
            defer { try? FileManager.default.removeItem(at: copy) }
            try subject.store.keepVersion(version.id, ofFileAt: note, asSeparateFileAt: copy, using: writer)

            XCTAssertEqual(String(decoding: try Data(contentsOf: copy), as: UTF8.self), "text saved on another device\n", subject.name)
            XCTAssertTrue(FileManager.default.isWritableFile(atPath: copy.path), "\(subject.name): the copy is an ordinary file that can be edited.")
            XCTAssertEqual(try noteText(), "current text\n", "\(subject.name): the current file is untouched.")
            XCTAssertEqual(try subject.store.conflictVersions(of: note), [], "\(subject.name): the version kept as a file stops being kept beside the note.")
        }
    }

    // MARK: A version that is not kept

    func testAVersionThatIsNotKeptIsReportedAndNothingIsWritten() throws {
        try forEachStore { subject in
            try subject.addVersion(note, "other version\n", nil)
            let copy = folder.appendingPathComponent("Copy.md")

            assertThrowsUnavailable(subject, "contents") { _ = try subject.store.contentsLocation(ofVersion: "no such version", ofFileAt: note) }
            assertThrowsUnavailable(subject, "replace") { _ = try subject.store.replaceFile(at: note, withVersion: "no such version", expecting: nil, using: writer) }
            assertThrowsUnavailable(subject, "keep") { try subject.store.keepVersion("no such version", ofFileAt: note, asSeparateFileAt: copy, using: writer) }
            XCTAssertEqual(try noteText(), "current text\n", subject.name)
            XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path), subject.name)
            XCTAssertEqual(try subject.store.conflictVersions(of: note).count, 1, "\(subject.name): the version that is kept stays.")
        }
    }

    // MARK: Removing

    func testRemovingRemovesOnlyTheVersionsNamed() throws {
        try forEachStore { subject in
            try subject.addVersion(note, "first other version\n", Date(timeIntervalSince1970: 1_700_000_000))
            try subject.addVersion(note, "second other version\n", Date(timeIntervalSince1970: 1_750_000_000))
            let versions = try subject.store.conflictVersions(of: note)

            try subject.store.removeVersions([try XCTUnwrap(versions.first).id], ofFileAt: note, using: writer)
            XCTAssertEqual(try subject.store.conflictVersions(of: note).map(\.id), [try XCTUnwrap(versions.last).id], subject.name)
            XCTAssertEqual(try noteText(), "current text\n", "\(subject.name): the current file is untouched.")

            try subject.store.removeVersions(["no such version"], ofFileAt: note, using: writer)
            XCTAssertEqual(try subject.store.conflictVersions(of: note).count, 1, "\(subject.name): a name that matches nothing removes nothing.")

            try subject.store.removeVersions(versions.map(\.id), ofFileAt: note, using: writer)
            XCTAssertFalse(subject.store.hasConflictVersions(at: note), subject.name)
        }
    }

    // MARK: Coordination

    /// Every write goes through file coordination, which is how a provider or another app
    /// that presents the file learns that it is about to change and gets to refuse. The
    /// presenter of the note is asked to give the note up to a writer for each of the
    /// three operations that change it, removal included (the fake once removed versions
    /// without it). What a coordinator that refuses does cannot be asked of the production
    /// store today: `AtomicFileWriter` makes its `NSFileCoordinator` itself, so no test can
    /// make one refuse (a presenter that fails `savePresentedItemChanges` is not consulted
    /// for writers). That row waits for a coordination port (see `Docs/solid/testing.md`).
    func testEveryWriteToTheFileIsCoordinatedWithItsPresenters() throws {
        try forEachStore { subject in
            let witness = WriteWitnessPresenter(presentedItemURL: note)
            witness.start()
            defer { witness.stop() }
            for text in ["to replace the file", "to keep as a copy", "to remove"] { try subject.addVersion(note, "\(text)\n", nil) }
            let versions = try subject.store.conflictVersions(of: note)
            XCTAssertEqual(versions.count, 3, subject.name)
            let copy = folder.appendingPathComponent("Lecture (Conflicted copy).md")
            defer { try? FileManager.default.removeItem(at: copy) }

            var relinquishCountBefore = witness.relinquishCount
            _ = try subject.store.replaceFile(at: note, withVersion: versions[0].id, expecting: nil, using: writer)
            XCTAssertGreaterThan(witness.relinquishCount, relinquishCountBefore, "\(subject.name): replacing")

            relinquishCountBefore = witness.relinquishCount
            try subject.store.keepVersion(versions[1].id, ofFileAt: note, asSeparateFileAt: copy, using: writer)
            XCTAssertGreaterThan(witness.relinquishCount, relinquishCountBefore, "\(subject.name): keeping as a separate file")

            relinquishCountBefore = witness.relinquishCount
            try subject.store.removeVersions([versions[2].id], ofFileAt: note, using: writer)
            XCTAssertGreaterThan(witness.relinquishCount, relinquishCountBefore, "\(subject.name): removing")
        }
    }
}

/// A presenter of one file that counts the times a writer asked it to give the file up,
/// and lets the writer have it at once.
private final class WriteWitnessPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    // `presentedItemURL` is set once; the count is behind `lock`.
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let lock = NSLock()
    private var timesRelinquished = 0

    init(presentedItemURL: URL) {
        self.presentedItemURL = presentedItemURL
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
    }

    var relinquishCount: Int { lock.withLock { timesRelinquished } }

    func start() { NSFileCoordinator.addFilePresenter(self) }
    func stop() { NSFileCoordinator.removeFilePresenter(self) }

    func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        lock.withLock { timesRelinquished += 1 }
        writer {}
    }
}
#endif
