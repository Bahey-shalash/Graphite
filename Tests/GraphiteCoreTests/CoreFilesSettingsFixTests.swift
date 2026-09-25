import XCTest
@testable import GraphiteCore

/// Regression tests for vault paths, file storage and the Obsidian settings file.
final class CoreFilesSettingsFixTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories { try? FileManager.default.removeItem(at: directory) }
        temporaryDirectories.removeAll()
    }

    private func makeDirectory(_ name: String = "Vault") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func write(_ text: String, to location: URL) throws {
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: location)
    }

    private func applicationConfiguration(in vault: URL) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(".obsidian/app.json"), encoding: .utf8)
    }

    // MARK: Vault paths

    func testBackslashInAFileNameIsListedWithTheRestOfTheFolder() async throws {
        let vault = try makeDirectory()
        try write("good", to: vault.appendingPathComponent("Good.md"))
        try write("pdf", to: vault.appendingPathComponent("Math \\ notes.pdf"))
        let entries = try await VaultStore(root: vault).children(of: .root)
        XCTAssertEqual(entries.map(\.path.name), ["Good.md", "Math \\ notes.pdf"])
        let path = try VaultPath("Math \\ notes.pdf")
        XCTAssertEqual(try String(contentsOf: path.url(in: vault), encoding: .utf8), "pdf")
        XCTAssertNotNil(FileNameRules.problem(with: "a\\b", isNote: false), "New names still avoid a character other systems use as a separator.")
    }

    func testCombiningMarkAfterASlashStillSeparatesComponents() throws {
        let path = try VaultPath("Notes/\u{301}x.md")
        XCTAssertEqual(path.name, "\u{301}x.md")
        XCTAssertEqual(path.parent, try VaultPath("Notes"))
        XCTAssertTrue(path.isInside(try VaultPath("Notes")))
        XCTAssertFalse(try VaultPath("Notes2/x.md").isInside(try VaultPath("Notes")))
        XCTAssertEqual(try path.replacingPrefix(VaultPath("Notes"), with: VaultPath("Archive")).rawValue, "Archive/\u{301}x.md")
        XCTAssertEqual(path.relativePath(from: try VaultPath("Other")), "../Notes/\u{301}x.md")
        XCTAssertThrowsError(try VaultPath("\u{301}/../../outside"))
    }

    func testCombiningMarkPathCannotSkipASymbolicLinkLeavingTheVault() async throws {
        let vault = try makeDirectory()
        let outside = try makeDirectory("Outside")
        try write("SECRET", to: outside.appendingPathComponent("\u{301}secret.md"))
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("Folder"), withDestinationURL: outside)
        XCTAssertThrowsError(try VaultPath("Folder/\u{301}secret.md").url(in: vault)) { error in XCTAssertEqual(error as? GraphiteError, .outsideVault) }
        let store = VaultStore(root: vault)
        do {
            _ = try await store.save(Data("new".utf8), at: VaultPath("Folder/\u{301}new.md"), expecting: .absent)
            XCTFail("A write through the outside link must fail.")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("\u{301}new.md").path))
        // A name that starts with a combining mark is an ordinary file inside the vault.
        try write("inside", to: vault.appendingPathComponent("\u{301}inside.md"))
        let insideSnapshot = try await store.read(VaultPath("\u{301}inside.md"))
        XCTAssertEqual(insideSnapshot.data, Data("inside".utf8))
    }

    func testChainedSymbolicLinksCannotCreateAFileOutsideTheVault() async throws {
        let vault = try makeDirectory()
        let outside = try makeDirectory("Outside")
        try FileManager.default.createSymbolicLink(at: vault.appendingPathComponent("sub"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(atPath: vault.appendingPathComponent("link.md").path, withDestinationPath: "sub/new.md")
        XCTAssertThrowsError(try VaultPath("link.md").url(in: vault)) { error in XCTAssertEqual(error as? GraphiteError, .outsideVault) }
        do {
            _ = try await VaultStore(root: vault).save(Data("new".utf8), at: VaultPath("link.md"), expecting: .absent)
            XCTFail("A write through the chained links must fail.")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("new.md").path))
    }

    func testChainedSymbolicLinksInsideTheVaultStillResolve() throws {
        let vault = try makeDirectory()
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Real"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: vault.appendingPathComponent("Alias").path, withDestinationPath: "Real")
        try FileManager.default.createSymbolicLink(atPath: vault.appendingPathComponent("link.md").path, withDestinationPath: "Alias/new.md")
        let resolved = try VaultPath("link.md").url(in: vault)
        XCTAssertEqual(resolved.lastPathComponent, "new.md")
        XCTAssertEqual(resolved.deletingLastPathComponent().lastPathComponent, "Real")
        // Two links pointing at each other are refused instead of followed forever.
        try FileManager.default.createSymbolicLink(atPath: vault.appendingPathComponent("first.md").path, withDestinationPath: "second.md")
        try FileManager.default.createSymbolicLink(atPath: vault.appendingPathComponent("second.md").path, withDestinationPath: "first.md")
        XCTAssertThrowsError(try VaultPath("first.md").url(in: vault))
    }

    // MARK: File names

    func testNamesWithLineBreaksOrTabsAreRefused() {
        XCTAssertNotNil(FileNameRules.problem(with: "Meeting\nNotes", isNote: true))
        XCTAssertNotNil(FileNameRules.problem(with: "Meeting\tNotes", isNote: false))
        XCTAssertNotNil(FileNameRules.problem(with: "Meeting\u{2028}Notes", isNote: false))
        XCTAssertNil(FileNameRules.problem(with: "Family 👨‍👩‍👧 trip", isNote: true), "The zero-width joiner in emoji stays allowed.")
    }

    func testLengthLimitLeavesRoomForTheExtensionAndANumber() async throws {
        XCTAssertNotNil(FileNameRules.problem(with: String(repeating: "a", count: 254), isNote: true))
        let longestName = String(repeating: "a", count: FileNameRules.maximumFileNameBytes - FileNameRules.reservedSuffixBytes)
        XCTAssertNil(FileNameRules.problem(with: longestName, isNote: true))
        let vault = try makeDirectory()
        let store = VaultStore(root: vault)
        for _ in 0..<2 {
            let path = try await store.uniquePath(directory: .root, stem: longestName, extension: "base")
            _ = try await store.save(Data(), at: path, expecting: .absent)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.path).count, 2)
    }

    func testUniquePathNumbersLikeObsidianAndNeverEndsInADot() async throws {
        let vault = try makeDirectory()
        let store = VaultStore(root: vault)
        let first = try await store.uniquePath(directory: .root, stem: "Untitled", extension: "md")
        _ = try await store.save(Data(), at: first, expecting: .absent)
        let second = try await store.uniquePath(directory: .root, stem: "Untitled", extension: "md")
        XCTAssertEqual([first.rawValue, second.rawValue], ["Untitled.md", "Untitled 1.md"])
        let extensionlessPath = try await store.uniquePath(directory: .root, stem: "README", extension: "")
        XCTAssertEqual(extensionlessPath.rawValue, "README")
        let dotLeadingPath = try await store.uniquePath(directory: .root, stem: ".env", extension: "")
        XCTAssertEqual(dotLeadingPath.rawValue, "env")
        do {
            _ = try await store.uniquePath(directory: .root, stem: "...", extension: "png")
            XCTFail("A stem of dots has no visible name left.")
        } catch {}
    }

    func testDrawingNamesUseGregorianYearsByDefault() throws {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let date = try XCTUnwrap(gregorian.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12, minute: 37, second: 6)))
        XCTAssertEqual(AttachmentResolver().drawingFileStem(createdAt: date), "Drawing 2026-09-23 12.37.06")
    }

    func testVaultNamesRefuseWhatFolderNamesInsideTheVaultRefuse() {
        for invalidName in ["Notes?", "A*B", "Quote\"d", "Less<", "More>", "Pipe|", "Tab\there"] {
            XCTAssertThrowsError(try VaultList.validatedFolderName(invalidName), invalidName)
        }
        XCTAssertEqual(try VaultList.validatedFolderName("Physics (2026) – Optics"), "Physics (2026) – Optics")
    }

    // MARK: File operations

    func testMovingAFolderIntoItselfIsRefusedWhateverTheCapitals() async throws {
        let vault = try makeDirectory()
        try write("note", to: vault.appendingPathComponent("A/n.md"))
        guard FileManager.default.fileExists(atPath: vault.appendingPathComponent("a").path) else { throw XCTSkip("This volume is case-sensitive.") }
        let store = VaultStore(root: vault)
        for destination in ["a/B", "a/B/C"] {
            do {
                try await store.move(VaultPath("A"), to: VaultPath(destination))
                XCTFail("Moving A to \(destination) must fail.")
            } catch {
                XCTAssertEqual(error.localizedDescription, "A folder cannot be moved into itself.")
            }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.appendingPathComponent("A").path), ["n.md"], "No folder is created inside the source.")
        try await store.move(VaultPath("A"), to: VaultPath("a"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.path), ["a"], "A change of capitals alone still renames.")
    }

    func testSystemTrashAsksPresentersToLetGoFirst() async throws {
        let vault = try makeDirectory()
        let name = "Presented \(UUID().uuidString).md"
        let location = vault.appendingPathComponent(name)
        try write("unsaved elsewhere", to: location)
        let presenter = RecordingFilePresenter(url: location.resolvingSymlinksInPath())
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }
        let outcome = try await VaultStore(root: vault).delete(VaultPath(name), method: .systemTrash)
        if outcome == .movedToSystemTrash, let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first {
            // The test's own file: removed from the Trash so the run leaves nothing behind.
            try? FileManager.default.removeItem(at: trash.appendingPathComponent(name))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path))
        XCTAssertTrue(presenter.events.contains("accommodateDeletion"), "Events: \(presenter.events)")
    }

    // MARK: Atomic writes

    func testStagingHappensOutsideTheVaultFolderAndLeavesNothingBehind() throws {
        let vault = try makeDirectory()
        let location = vault.appendingPathComponent("note.md")
        let writer = AtomicFileWriter()
        var stagingLocation: URL?
        let revision = try writer.replace(location, expecting: .absent) { staging in
            stagingLocation = staging
            try Data("first".utf8).write(to: staging)
        }
        let staging = try XCTUnwrap(stagingLocation)
        XCTAssertNotEqual(staging.deletingLastPathComponent().resolvingSymlinksInPath().path, vault.resolvingSymlinksInPath().path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.deletingLastPathComponent().path), "The private staging folder is removed.")
        XCTAssertEqual(try writer.read(location).data, Data("first".utf8))
        XCTAssertThrowsError(try writer.replace(location, expecting: .absent) { staging in
            stagingLocation = staging
            try Data("second".utf8).write(to: staging)
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(stagingLocation).deletingLastPathComponent().path), "A refused write leaves nothing either.")
        _ = try writer.write(Data("second".utf8), to: location, expecting: .revision(revision))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.path), ["note.md"])
        XCTAssertEqual(try writer.read(location).data, Data("second".utf8))
    }

    // MARK: Obsidian settings

    func testSavingKeepsSettingsChangedInObsidianSinceTheyWereRead() async throws {
        let vault = try makeDirectory()
        let store = VaultStore(root: vault)
        var settings = try await store.settings()
        try write("{\"newLinkFormat\": \"relative\", \"attachmentFolderPath\": \"./assets\"}", to: vault.appendingPathComponent(".obsidian/app.json"))
        settings.confirmsDeletion = false
        try await store.saveSettings(settings)
        var reloaded = try await store.settings()
        XCTAssertEqual(reloaded.linkFormat, .relative)
        XCTAssertEqual(reloaded.attachmentLocation, .subfolderUnderNote("assets"))
        XCTAssertFalse(reloaded.confirmsDeletion)
        // A caller that names the copy it changed keeps its stale keys out even after other
        // reads, and turning a setting back on is written although it matches the first read.
        let staleCopy = settings
        settings.confirmsDeletion = true
        try await store.saveSettings(settings, changedFrom: staleCopy)
        reloaded = try await store.settings()
        XCTAssertTrue(reloaded.confirmsDeletion)
        XCTAssertEqual(reloaded.linkFormat, .relative)
        XCTAssertEqual(reloaded.attachmentLocation, .subfolderUnderNote("assets"))
    }

    func testSettingChangedBackAfterAReloadIsWritten() async throws {
        let vault = try makeDirectory()
        let store = VaultStore(root: vault)
        _ = try await store.settings()
        try write("{\"useMarkdownLinks\": true}", to: vault.appendingPathComponent(".obsidian/app.json"))
        // The settings screen reloads when Graphite returns to the foreground, then the user
        // turns wikilinks back on: the value Graphite read first, but not what the file says.
        var settings = try await store.settings()
        XCTAssertFalse(settings.usesWikilinks)
        settings.usesWikilinks = true
        try await store.saveSettings(settings)
        let reloaded = try await store.settings()
        XCTAssertTrue(reloaded.usesWikilinks)
    }

    func testChangingOneSettingWritesOnlyThatKey() async throws {
        let vault = try makeDirectory()
        let store = VaultStore(root: vault)
        var settings = try await store.settings()
        settings.pairsBrackets = false
        try await store.saveSettings(settings)
        XCTAssertEqual(try applicationConfiguration(in: vault), "{\n  \"autoPairBrackets\": false\n}")
        let unchangedVault = try makeDirectory()
        try await VaultStore(root: unchangedVault).saveSettings(ObsidianSettings())
        XCTAssertFalse(FileManager.default.fileExists(atPath: unchangedVault.appendingPathComponent(".obsidian/app.json").path), "Nothing changed, so nothing is written.")
    }

    func testUnrelatedSaveKeepsValuesGraphiteReadsDifferently() throws {
        let existing = Data("{\"tabSize\": 12, \"newFileLocation\": \"folder\", \"newFileFolderPath\": \"Inbox/\", \"newLinkFormat\": \"future\"}".utf8)
        var settings = try ObsidianSettings(applicationConfigurationData: existing)
        XCTAssertEqual(settings.tabSize, 8)
        let loaded = settings
        settings.confirmsDeletion = false
        let merged = try settings.mergedApplicationConfigurationData(existingData: existing, changedFrom: loaded)
        XCTAssertEqual(String(decoding: merged, as: UTF8.self),
                       "{\n  \"tabSize\": 12,\n  \"newFileLocation\": \"folder\",\n  \"newFileFolderPath\": \"Inbox/\",\n  \"newLinkFormat\": \"future\",\n  \"promptDelete\": false\n}")
    }

    func testRewriteKeepsObsidiansLayoutOrderAndNumbers() throws {
        let existing = Data("{\n  \"zeta\": 0.1,\n  \"alpha\": 1.0,\n  \"nested\": {\n    \"list\": [1, 2e3],\n    \"text\": \"a \\\"quoted\\\" }\"\n  },\n  \"vimMode\": true,\n  \"newLinkFormat\": \"shortest\"\n}".utf8)
        var settings = try ObsidianSettings(applicationConfigurationData: existing)
        settings.linkFormat = .relative
        settings.attachmentLocation = .specifiedFolder("Files/Images")
        let merged = try settings.mergedApplicationConfigurationData(existingData: existing)
        XCTAssertEqual(String(decoding: merged, as: UTF8.self),
                       "{\n  \"zeta\": 0.1,\n  \"alpha\": 1.0,\n  \"nested\": {\n    \"list\": [1, 2e3],\n    \"text\": \"a \\\"quoted\\\" }\"\n  },\n  \"vimMode\": true,\n  \"newLinkFormat\": \"relative\",\n  \"attachmentFolderPath\": \"Files/Images\"\n}")
        XCTAssertEqual(try ObsidianSettings(applicationConfigurationData: merged), settings)
        XCTAssertEqual(try settings.mergedApplicationConfigurationData(existingData: merged), merged, "A save with nothing changed leaves the bytes alone.")
    }

    func testDuplicateKeysReadAndWriteLikeObsidian() throws {
        let existing = Data("{\"newLinkFormat\":\"absolute\",\"vimMode\":false,\"newLinkFormat\":\"relative\",\"vimMode\":true}".utf8)
        var settings = try ObsidianSettings(applicationConfigurationData: existing)
        XCTAssertEqual(settings.linkFormat, .relative, "JavaScript's JSON.parse keeps the last value.")
        settings.confirmsDeletion = false
        let merged = try settings.mergedApplicationConfigurationData(existingData: existing)
        XCTAssertEqual(String(decoding: merged, as: UTF8.self), "{\n  \"newLinkFormat\": \"relative\",\n  \"vimMode\": true,\n  \"promptDelete\": false\n}")
    }

    func testEmptyOrBlankSettingsFileMeansDefaults() async throws {
        for blankText in ["", "  \n\t", "\u{FEFF}"] {
            XCTAssertEqual(try ObsidianSettings(applicationConfigurationData: Data(blankText.utf8)), ObsidianSettings(), "“\(blankText)”")
        }
        let vault = try makeDirectory()
        try write("", to: vault.appendingPathComponent(".obsidian/app.json"))
        let store = VaultStore(root: vault)
        var settings = try await store.settings()
        XCTAssertEqual(settings, ObsidianSettings())
        settings.linkFormat = .absolute
        try await store.saveSettings(settings)
        XCTAssertEqual(try applicationConfiguration(in: vault), "{\n  \"newLinkFormat\": \"absolute\"\n}")
    }

    func testSpecifiedFolderKeepsItsMeaningAfterAReload() throws {
        let note = try VaultPath("Courses/Note.md")
        let resolver = AttachmentResolver()
        for (typedFolder, storedValue, expectedDirectory) in [("./Images", "Images", "Images"), (".", "/", ""), ("/Images/", "Images", "Images"), (" Scans ", "Scans", "Scans")] {
            let location = AttachmentLocation.specifiedFolder(typedFolder)
            XCTAssertEqual(location.obsidianValue, storedValue, typedFolder)
            XCTAssertEqual(try resolver.directory(for: location, note: note).rawValue, expectedDirectory, typedFolder)
            let reloaded = AttachmentLocation(obsidianValue: location.obsidianValue)
            XCTAssertEqual(try resolver.directory(for: reloaded, note: note).rawValue, expectedDirectory, typedFolder)
        }
    }

    func testJSONStringsAreEscapedAsJavaScriptWritesThem() {
        XCTAssertEqual(ApplicationConfigurationObject.jsonText(for: "a/b \"c\" \\ \n\u{1}é"), "\"a/b \\\"c\\\" \\\\ \\n\\u0001é\"")
    }
}

/// Records the coordination messages a presenter of one file receives.
private final class RecordingFilePresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let lock = NSLock()
    private var recordedEvents: [String] = []
    var events: [String] { lock.withLock { recordedEvents } }

    init(url: URL) { presentedItemURL = url }

    private func record(_ event: String) { lock.withLock { recordedEvents.append(event) } }
    func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        record("relinquishToWriter")
        writer(nil)
    }
    func accommodatePresentedItemDeletion(completionHandler: @escaping @Sendable (Error?) -> Void) {
        record("accommodateDeletion")
        completionHandler(nil)
    }
}
