import XCTest
import GraphiteCore
@testable import GraphiteIndex
@testable import GraphiteApple
@testable import GraphiteUI

/// Versions kept by a file provider, in the workspace: which files are asked about and
/// marked, and what each of the person's three choices does to the files and to the open
/// documents. Most tests use `TestConflictVersionStore`; the last ones use real
/// `NSFileVersion` objects, which only macOS can make.
@MainActor
final class WorkspaceConflictVersionsTests: XCTestCase {
    private var temporaryFolders: [URL] = []
    private let lecture = VaultPath.unchecked("Course/Lecture.md")
    private var savedGraphitePreferences: [String: Any] = [:]
    private var vaultIdentifiersBeforeTest: Set<UUID> = []

    override func setUp() async throws {
        savedGraphitePreferences = UserDefaults.standard.dictionaryRepresentation().filter { key, _ in key.hasPrefix("Graphite") }
        vaultIdentifiersBeforeTest = Set(VaultLibrary().vaults.map(\.id))
    }

    override func tearDown() async throws {
        // Opening a vault records it, with an index of its own.
        for vault in VaultLibrary().vaults where !vaultIdentifiersBeforeTest.contains(vault.id) {
            VaultIndex.removeIndex(forVault: vault.id)
        }
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("Graphite") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        for (key, storedValue) in savedGraphitePreferences { UserDefaults.standard.set(storedValue, forKey: key) }
        for folder in temporaryFolders { try? FileManager.default.removeItem(at: folder) }
        temporaryFolders = []
    }

    // MARK: Finding

    func testANoteIsMarkedWhenItOpensWithAnotherVersionKept() async throws {
        let (workspace, store, vault) = try await makeWorkspace(files: ["Course/Lecture.md": "current\n", "Course/Other.md": "other\n"])
        try store.addVersion(of: vault.appendingPathComponent("Course/Lecture.md"), contents: Data("from the Mac\n".utf8), deviceName: "MacBook", modified: .now)

        await workspace.open(lecture)
        await workspace.open(try VaultPath("Course/Other.md"), placement: .newTab)
        try await waitUntil { store.pathsAskedAbout.count >= 2 && workspace.conflictCheckTask == nil }

        XCTAssertEqual(workspace.conflictedPaths, [lecture], "Only the file with a kept version is marked.")
        XCTAssertFalse(store.wasEverAskedOnTheMainThread, "The provider is never asked on the main thread.")
    }

    func testOnlyFilesTheSidebarListsAreAskedAbout() async throws {
        var files = ["Top.md": "top\n", "Top image.png": "not really an image", "Course/Lecture.md": "current\n"]
        for number in 0..<300 { files["Archive/Deep/Note \(number).md"] = "archived\n" }
        let (workspace, store, vault) = try await makeWorkspace(files: files)
        try store.addVersion(of: vault.appendingPathComponent("Top image.png"), contents: Data("other".utf8), deviceName: nil, modified: nil)

        // What the sidebar does when the vault opens: it lists the top folder.
        await workspace.refreshDirectory()
        try await waitUntil { workspace.conflictCheckTask == nil && !store.pathsAskedAbout.isEmpty }

        XCTAssertEqual(Set(store.pathsAskedAbout.map { path in URL(fileURLWithPath: path).lastPathComponent }), ["Top.md", "Top image.png"],
                       "Folders and the files inside folders that are not open are left alone: there is no scan of the vault.")
        XCTAssertEqual(workspace.conflictedPaths, [try VaultPath("Top image.png")])
    }

    func testTheTopFolderIsCheckedWhenAVaultOpens() async throws {
        let vault = try makeFolder("ConflictVersionsOpenedVault")
        try Data("current\n".utf8).write(to: vault.appendingPathComponent("Syllabus.md"))
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Course"), withIntermediateDirectories: true)
        try Data("inside a folder\n".utf8).write(to: vault.appendingPathComponent("Course/Lecture.md"))
        let store = try TestConflictVersionStore()
        try store.addVersion(of: vault.appendingPathComponent("Syllabus.md"), contents: Data("from the iPhone\n".utf8), deviceName: "iPhone", modified: .now)
        let workspace = WorkspaceModel()
        workspace.conflictVersionStore = store

        try await workspace.openFolderAsVault(vault)

        try await waitUntil { workspace.conflictedPaths == [VaultPath.unchecked("Syllabus.md")] }
        XCTAssertFalse(store.pathsAskedAbout.contains { path in path.hasSuffix("Course/Lecture.md") }, "A folder that is not open is not looked into.")
    }

    func testTheNumberOfFilesWaitingToBeCheckedIsBounded() async throws {
        let (workspace, store, _) = try await makeWorkspace(files: ["Lecture.md": "current\n"])
        store.answerSlowly(secondsPerAnswer: 0.002)
        let manyPaths = (0..<(WorkspaceModel.maximumPendingConflictChecks * 3)).map { number in VaultPath.unchecked("Huge folder/Note \(number).md") }

        workspace.checkConflictVersions(of: manyPaths)

        XCTAssertLessThanOrEqual(workspace.pendingConflictChecks.count, WorkspaceModel.maximumPendingConflictChecks)
        XCTAssertEqual(workspace.pendingConflictChecks.last, manyPaths.last, "The newest requests are the ones kept.")
        workspace.resetConflictVersions()
        XCTAssertEqual(workspace.pendingConflictChecks, [])
    }

    func testACheckStopsWhenAnotherVaultOpens() async throws {
        let (workspace, store, _) = try await makeWorkspace(files: ["Lecture.md": "current\n"])
        store.answerSlowly(secondsPerAnswer: 0.005)
        workspace.checkConflictVersions(of: (0..<2_000).map { number in VaultPath.unchecked("Folder/Note \(number).md") })
        try await waitUntil { store.pathsAskedAbout.count >= 3 }

        // What opening another vault does.
        workspace.resetConflictVersions()
        let askedWhenCancelled = store.pathsAskedAbout.count
        try await Task.sleep(for: .milliseconds(400))

        XCTAssertLessThanOrEqual(store.pathsAskedAbout.count, askedWhenCancelled + 1, "At most the file being asked about is finished.")
        XCTAssertEqual(workspace.conflictedPaths, [])
        XCTAssertFalse(store.wasEverAskedOnTheMainThread)
    }

    func testAFileReportedChangedIsAskedAboutAgain() async throws {
        let (workspace, store, vault) = try await makeWorkspace(files: ["Course/Lecture.md": "current\n"])
        await workspace.open(lecture)
        try await waitUntil { workspace.conflictCheckTask == nil && !store.pathsAskedAbout.isEmpty }
        XCTAssertEqual(workspace.conflictedPaths, [])

        // The provider keeps a version later, and reports the file to its presenter.
        try store.addVersion(of: vault.appendingPathComponent("Course/Lecture.md"), contents: Data("from the Mac\n".utf8), deviceName: "MacBook", modified: .now)
        workspace.checkConflictVersions(of: [lecture])
        try await waitUntil { workspace.conflictedPaths == [self.lecture] }
    }

    // MARK: Deciding

    func testReplacingReloadsTheOpenNoteWithTheVersionChosen() async throws {
        let (workspace, store, vault) = try await makeWorkspace(files: ["Course/Lecture.md": "# Lecture\ncurrent line\n"])
        let location = vault.appendingPathComponent("Course/Lecture.md")
        let macVersion = try store.addVersion(of: location, contents: Data("# Lecture\nline from the Mac\n".utf8), deviceName: "MacBook", modified: Date(timeIntervalSince1970: 1_790_000_000))
        let phoneVersion = try store.addVersion(of: location, contents: Data("# Lecture\nline from the phone\n".utf8), deviceName: "iPhone", modified: Date(timeIntervalSince1970: 1_780_000_000))
        await workspace.open(lecture)
        let session = try XCTUnwrap(workspace.markdownSession)
        let listing = try await workspace.conflictVersionListing(of: lecture)
        XCTAssertEqual(listing.versions.map(\.id), [macVersion.id, phoneVersion.id], "Newest first.")

        try await workspace.replaceCurrentVersion(of: lecture, with: macVersion, listedIn: listing)

        XCTAssertEqual(fileText("Course/Lecture.md", in: vault), "# Lecture\nline from the Mac\n")
        XCTAssertEqual(session.text, "# Lecture\nline from the Mac\n", "The open note shows the version that replaced it.")
        XCTAssertFalse(session.hasExternalConflict)
        XCTAssertFalse(session.hasUnsavedChanges)
        XCTAssertNil(session.errorMessage)
        XCTAssertEqual(try store.conflictVersions(of: location).map(\.id), [phoneVersion.id], "The other version stays until it is decided about.")
        XCTAssertEqual(workspace.conflictedPaths, [lecture])

        // Editing goes on from the new text without a conflict.
        session.text += "typed afterwards\n"
        try await session.save()
        XCTAssertEqual(fileText("Course/Lecture.md", in: vault), "# Lecture\nline from the Mac\ntyped afterwards\n")
    }

    func testReplacingIsRefusedWhenTheNoteWasEditedAfterTheVersionsWereListed() async throws {
        let (workspace, store, vault) = try await makeWorkspace(files: ["Course/Lecture.md": "current\n"])
        let location = vault.appendingPathComponent("Course/Lecture.md")
        let version = try store.addVersion(of: location, contents: Data("from the Mac\n".utf8), deviceName: "MacBook", modified: .now)
        await workspace.open(lecture)
        let session = try XCTUnwrap(workspace.markdownSession)
        let listing = try await workspace.conflictVersionListing(of: lecture)

        session.text = "current\nand a sentence typed while the sheet was open\n"
        do {
            try await workspace.replaceCurrentVersion(of: lecture, with: version, listedIn: listing)
            XCTFail("The typed sentence was never compared with the version.")
        } catch {
            XCTAssertEqual(error as? GraphiteError, .conflict)
        }

        XCTAssertEqual(fileText("Course/Lecture.md", in: vault), "current\nand a sentence typed while the sheet was open\n", "The edit is saved, not replaced.")
        XCTAssertEqual(session.text, "current\nand a sentence typed while the sheet was open\n")
        XCTAssertEqual(try store.conflictVersions(of: location).count, 1)
    }

    func testTheSheetSaysWhyAReplacementWasRefusedAndListsAgain() async throws {
        let (workspace, store, vault) = try await makeWorkspace(files: ["Course/Lecture.md": "current\n"])
        let location = vault.appendingPathComponent("Course/Lecture.md")
        let version = try store.addVersion(of: location, contents: Data("from the Mac\n".utf8), deviceName: "MacBook", modified: .now)
        let model = ConflictVersionsModel(path: lecture, workspace: workspace)
        await model.load()
        XCTAssertEqual(model.versions, [version])
        let stampWhenListed = try XCTUnwrap(model.listing?.currentStamp)

        // Another device's change arrives while the sheet is open.
        try Data("current, changed on another device meanwhile\n".utf8).write(to: location)
        await model.replaceCurrentVersion(with: version)

        XCTAssertTrue(try XCTUnwrap(model.problem).contains("changed after these versions were listed"), model.problem ?? "")
        XCTAssertEqual(fileText("Course/Lecture.md", in: vault), "current, changed on another device meanwhile\n")
        XCTAssertNotEqual(model.listing?.currentStamp, stampWhenListed, "The sheet shows the file as it is now.")
        XCTAssertEqual(model.versions, [version])

        await model.replaceCurrentVersion(with: version)
        XCTAssertNil(model.problem)
        XCTAssertEqual(fileText("Course/Lecture.md", in: vault), "from the Mac\n")
        XCTAssertEqual(model.versions, [])
    }

    func testKeepingAVersionAsASeparateFilePutsAConflictCopyBesideTheNote() async throws {
        let (workspace, store, vault) = try await makeWorkspace(files: ["Course/Lecture.md": "current\n"])
        let location = vault.appendingPathComponent("Course/Lecture.md")
        let saved = Date(timeIntervalSince1970: 1_790_770_540)
        let version = try store.addVersion(of: location, contents: Data("from the Mac\n".utf8), deviceName: "Anna's MacBook [work]", modified: saved)
        await workspace.open(lecture)
        let session = try XCTUnwrap(workspace.markdownSession)
        try await waitUntil { workspace.conflictedPaths == [self.lecture] }

        let copyPath = try await workspace.keepAsSeparateFile(version, of: lecture)

        let expectedStem = ConflictCopyName.stem(forVersionOf: "Lecture", deviceName: "Anna's MacBook [work]", date: saved, isNote: true)
        XCTAssertEqual(copyPath, try VaultPath("Course/\(expectedStem).md"))
        XCTAssertTrue(copyPath.name.hasPrefix("Lecture (Conflicted copy Anna's MacBook work 2026"), copyPath.name)
        XCTAssertEqual(fileText(copyPath.rawValue, in: vault), "from the Mac\n")
        XCTAssertEqual(fileText("Course/Lecture.md", in: vault), "current\n", "The current note is untouched.")
        XCTAssertEqual(session.text, "current\n")
        XCTAssertEqual(try store.conflictVersions(of: location), [], "The version is a file of its own now, not a version.")
        XCTAssertEqual(workspace.conflictedPaths, [], "The mark goes once nothing is left to decide.")
        let indexed = try await waitForIndexedText(of: copyPath, in: workspace)
        XCTAssertEqual(indexed, true, "The copy can be searched and linked like any note.")
    }

    func testTwoVersionsKeptSeparatelyGetTwoNames() async throws {
        let (workspace, store, vault) = try await makeWorkspace(files: ["Scan.pdf": "current"])
        let location = vault.appendingPathComponent("Scan.pdf")
        let path = try VaultPath("Scan.pdf")
        let first = try store.addVersion(of: location, contents: Data("first".utf8), deviceName: nil, modified: nil)
        let second = try store.addVersion(of: location, contents: Data("second".utf8), deviceName: nil, modified: nil)

        let firstCopy = try await workspace.keepAsSeparateFile(first, of: path)
        let secondCopy = try await workspace.keepAsSeparateFile(second, of: path)

        XCTAssertEqual(firstCopy.name, "Scan (Conflicted copy).pdf")
        XCTAssertEqual(secondCopy.name, "Scan (Conflicted copy) 1.pdf", "An existing copy is never written over.")
        XCTAssertEqual(fileText(firstCopy.rawValue, in: vault), "first")
        XCTAssertEqual(fileText(secondCopy.rawValue, in: vault), "second")
        XCTAssertEqual(fileText("Scan.pdf", in: vault), "current")
        XCTAssertTrue(workspace.rootEntries.map(\.path).contains(secondCopy), "The sidebar lists the copies.")
    }

    func testKeepingTheCurrentVersionRemovesTheOthersAndNothingElse() async throws {
        let (workspace, store, vault) = try await makeWorkspace(files: ["Course/Lecture.md": "current\n"])
        let location = vault.appendingPathComponent("Course/Lecture.md")
        try store.addVersion(of: location, contents: Data("from the Mac\n".utf8), deviceName: "MacBook", modified: .now)
        try store.addVersion(of: location, contents: Data("from the phone\n".utf8), deviceName: "iPhone", modified: .now)
        await workspace.open(lecture)
        let session = try XCTUnwrap(workspace.markdownSession)
        session.text = "current\nwith an unsaved sentence\n"
        let model = ConflictVersionsModel(path: lecture, workspace: workspace)
        await model.load()
        XCTAssertEqual(model.versions.count, 2)
        XCTAssertEqual(fileText("Course/Lecture.md", in: vault), "current\nwith an unsaved sentence\n", "Listing the versions saves what was typed, so the current version is what the editor shows.")

        await model.keepCurrentVersion()

        XCTAssertNil(model.problem)
        XCTAssertEqual(model.versions, [])
        XCTAssertEqual(try store.conflictVersions(of: location), [])
        XCTAssertEqual(fileText("Course/Lecture.md", in: vault), "current\nwith an unsaved sentence\n")
        XCTAssertEqual(session.text, "current\nwith an unsaved sentence\n")
        XCTAssertEqual(workspace.conflictedPaths, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.appendingPathComponent("Course").path), ["Lecture.md"], "No file appears or disappears.")
    }

    func testAVersionThatAnotherDeviceResolvedMeanwhileIsReported() async throws {
        let (workspace, store, vault) = try await makeWorkspace(files: ["Course/Lecture.md": "current\n"])
        let location = vault.appendingPathComponent("Course/Lecture.md")
        let version = try store.addVersion(of: location, contents: Data("from the Mac\n".utf8), deviceName: "MacBook", modified: .now)
        let model = ConflictVersionsModel(path: lecture, workspace: workspace)
        await model.load()
        try store.removeVersions([version.id], ofFileAt: location, using: AtomicFileWriter())

        await model.keepAsSeparateFile(version)

        XCTAssertEqual(model.problem, "That version is no longer kept. It may have been resolved on another device.")
        XCTAssertEqual(model.keptCopies, [])
        XCTAssertEqual(model.versions, [], "The list shows what is left.")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.appendingPathComponent("Course").path), ["Lecture.md"])
    }

    // MARK: Previews

    func testANoteVersionIsShownAsTextComparedWithTheCurrentNote() async throws {
        let (workspace, store, vault) = try await makeWorkspace(files: ["Course/Lecture.md": "# Lecture\nshared\ncurrent only\n"])
        let version = try store.addVersion(of: vault.appendingPathComponent("Course/Lecture.md"), contents: Data("# Lecture\nshared\nother only\n".utf8),
                                           deviceName: "MacBook", modified: .now)

        let content = await ConflictVersionContent.load(version, of: lecture, workspace: workspace)

        guard case .note(let text, let comparison) = content else { return XCTFail("\(content)") }
        XCTAssertEqual(text, "# Lecture\nshared\nother only\n")
        XCTAssertEqual(comparison?.lines, [.unchanged("# Lecture"), .unchanged("shared"), .onlyInCurrent("current only"), .onlyInOtherVersion("other only")])
    }

    func testOtherFilesAndNotesThatAreNotTextGoToThePreviewOfTheirKind() async throws {
        let (workspace, store, vault) = try await makeWorkspace(files: ["Figure.png": "current image", "Course/Lecture.md": "current\n"])
        let imageVersion = try store.addVersion(of: vault.appendingPathComponent("Figure.png"), contents: Data("other image".utf8), deviceName: nil, modified: nil)
        let brokenNoteVersion = try store.addVersion(of: vault.appendingPathComponent("Course/Lecture.md"), contents: Data([0xFF, 0xFE, 0x00, 0xD8]), deviceName: nil, modified: nil)

        let imageContent = await ConflictVersionContent.load(imageVersion, of: try VaultPath("Figure.png"), workspace: workspace)
        guard case .file(let imageLocation) = imageContent else { return XCTFail("\(imageContent)") }
        XCTAssertEqual(imageLocation.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: imageLocation), Data("other image".utf8))

        let noteContent = await ConflictVersionContent.load(brokenNoteVersion, of: lecture, workspace: workspace)
        guard case .file = noteContent else { return XCTFail("A version that is not UTF-8 is not shown as text: \(noteContent)") }

        try store.removeVersions([imageVersion.id], ofFileAt: vault.appendingPathComponent("Figure.png"), using: AtomicFileWriter())
        let goneContent = await ConflictVersionContent.load(imageVersion, of: try VaultPath("Figure.png"), workspace: workspace)
        XCTAssertEqual(goneContent, .unavailable("That version is no longer kept. It may have been resolved on another device."))
    }

    func testLongUnchangedStretchesAreFoldedAroundTheChanges() throws {
        var currentLines = (1...40).map { number in "line \(number)" }
        var otherLines = currentLines
        currentLines[19] = "line 20 here"
        otherLines[19] = "line 20 there"
        let comparison = try XCTUnwrap(TextVersionComparison.compare(current: currentLines.joined(separator: "\n"), otherVersion: otherLines.joined(separator: "\n")))

        let rows = TextComparisonRows.rows(for: comparison)

        XCTAssertEqual(rows, [
            .unchangedLines(index: 0, count: 16),
            .line(index: 16, .unchanged("line 17")), .line(index: 17, .unchanged("line 18")), .line(index: 18, .unchanged("line 19")),
            .line(index: 19, .onlyInCurrent("line 20 here")), .line(index: 20, .onlyInOtherVersion("line 20 there")),
            .line(index: 21, .unchanged("line 21")), .line(index: 22, .unchanged("line 22")), .line(index: 23, .unchanged("line 23")),
            .unchangedLines(index: 24, count: 17),
        ])
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, "Every row can be told from the others.")
        XCTAssertEqual(TextComparisonRows.summary(of: comparison), "Green: 1 line only in this version. Red: 1 line only in the current version.")

        let shortComparison = try XCTUnwrap(TextVersionComparison.compare(current: "one\ntwo\nthree\n", otherVersion: "one\ntwo\nthree\nfour\n"))
        XCTAssertEqual(TextComparisonRows.rows(for: shortComparison).count, 4, "A short note is shown whole.")
    }

    func testTheSheetsWording() {
        let named = FileConflictVersion(id: "1", deviceName: "MacBook Pro", modified: nil, byteCount: nil)
        let unnamed = FileConflictVersion(id: "2", deviceName: nil, modified: nil, byteCount: nil)
        XCTAssertEqual(ConflictVersionsText.title(of: named), "Version from MacBook Pro")
        XCTAssertEqual(ConflictVersionsText.title(of: unnamed), "Version from another device")
        XCTAssertEqual(ConflictVersionsText.detail(modified: nil, byteCount: nil, savedBy: nil), "")
        XCTAssertTrue(ConflictVersionsText.detail(modified: nil, byteCount: 2_048, savedBy: "Anna").hasSuffix("· saved by Anna"))
        XCTAssertEqual(ConflictVersionsText.keepCurrentQuestion(versionCount: 1), "Keep the current version and remove the other one?")
        XCTAssertEqual(ConflictVersionsText.removeButtonTitle(versionCount: 3), "Remove 3 Other Versions")
    }

    // MARK: Real versions

    #if os(macOS)
    /// The whole way with real `NSFileVersion` objects: found when the note opens, read,
    /// compared, and the note replaced and reloaded.
    func testARealVersionIsFoundShownAndPutInPlace() async throws {
        let (workspace, _, vault) = try await makeWorkspace(files: ["Course/Lecture.md": "# Lecture\ncurrent line\n"])
        workspace.conflictVersionStore = FileProviderConflictVersions(listing: .everyOtherVersion)
        let location = vault.appendingPathComponent("Course/Lecture.md")
        try addRealVersion("# Lecture\nline from another device\n", of: location)
        defer { try? NSFileVersion.removeOtherVersionsOfItem(at: location) }

        await workspace.open(lecture)
        let session = try XCTUnwrap(workspace.markdownSession)
        try await waitUntil { workspace.conflictedPaths == [self.lecture] }

        let model = ConflictVersionsModel(path: lecture, workspace: workspace)
        await model.load()
        let version = try XCTUnwrap(model.versions.first)
        XCTAssertEqual(version.byteCount, 35)
        let content = await ConflictVersionContent.load(version, of: lecture, workspace: workspace)
        guard case .note(_, let comparison) = content else { return XCTFail("\(content)") }
        XCTAssertEqual(comparison?.lines, [.unchanged("# Lecture"), .onlyInCurrent("current line"), .onlyInOtherVersion("line from another device")])

        await model.replaceCurrentVersion(with: version)

        XCTAssertNil(model.problem)
        XCTAssertEqual(fileText("Course/Lecture.md", in: vault), "# Lecture\nline from another device\n")
        XCTAssertEqual(session.text, "# Lecture\nline from another device\n")
        XCTAssertFalse(session.hasExternalConflict)
        XCTAssertEqual(model.versions, [])
        XCTAssertEqual(workspace.conflictedPaths, [])
        XCTAssertEqual(NSFileVersion.otherVersionsOfItem(at: location)?.count, 0, "The version is removed from the version store.")
    }

    func testARealVersionKeptSeparatelyBecomesAnOrdinaryNote() async throws {
        let (workspace, _, vault) = try await makeWorkspace(files: ["Course/Lecture.md": "current\n"])
        workspace.conflictVersionStore = FileProviderConflictVersions(listing: .everyOtherVersion)
        let location = vault.appendingPathComponent("Course/Lecture.md")
        try addRealVersion("from another device\n", of: location)
        defer { try? NSFileVersion.removeOtherVersionsOfItem(at: location) }
        let model = ConflictVersionsModel(path: lecture, workspace: workspace)
        await model.load()

        await model.keepAsSeparateFile(try XCTUnwrap(model.versions.first))

        XCTAssertNil(model.problem)
        let copyPath = try XCTUnwrap(model.keptCopies.first)
        XCTAssertTrue(copyPath.name.hasPrefix("Lecture (Conflicted copy "), copyPath.name)
        XCTAssertEqual(fileText(copyPath.rawValue, in: vault), "from another device\n")
        XCTAssertEqual(fileText("Course/Lecture.md", in: vault), "current\n")
        XCTAssertEqual(NSFileVersion.otherVersionsOfItem(at: location)?.count, 0)

        // The copy opens and saves like any note.
        await workspace.open(copyPath)
        let copySession = try XCTUnwrap(workspace.markdownSession)
        copySession.text += "edited\n"
        try await copySession.save()
        XCTAssertEqual(fileText(copyPath.rawValue, in: vault), "from another device\nedited\n")
    }

    func testTheMarkFollowsARenamedNoteAndGoesWithADeletedOne() async throws {
        let (workspace, _, vault) = try await makeWorkspace(files: ["Course/Lecture.md": "current\n"])
        workspace.conflictVersionStore = FileProviderConflictVersions(listing: .everyOtherVersion)
        let location = vault.appendingPathComponent("Course/Lecture.md")
        try addRealVersion("from another device\n", of: location)
        await workspace.open(lecture)
        try await waitUntil { workspace.conflictedPaths == [self.lecture] }

        await workspace.rename(lecture, to: "Lecture 1")
        let renamedPath = try VaultPath("Course/Lecture 1.md")
        defer { try? NSFileVersion.removeOtherVersionsOfItem(at: vault.appendingPathComponent("Course/Lecture 1.md")) }
        XCTAssertNil(workspace.errorMessage)
        XCTAssertEqual(workspace.conflictedPaths, [renamedPath], "The versions belong to the file, whatever it is called.")
        let listing = try await workspace.conflictVersionListing(of: renamedPath)
        XCTAssertEqual(listing.versions.count, 1)

        workspace.vaultSettings.deletionMethod = .permanent
        await workspace.delete(renamedPath)
        XCTAssertEqual(workspace.conflictedPaths, [])
    }

    private func addRealVersion(_ text: String, of location: URL) throws {
        let contents = location.deletingLastPathComponent().appendingPathComponent(".version-\(UUID().uuidString).md")
        try Data(text.utf8).write(to: contents)
        defer { try? FileManager.default.removeItem(at: contents) }
        _ = try NSFileVersion.addOfItem(at: location, withContentsOf: contents, options: [])
    }
    #endif

    // MARK: Helpers

    private func makeFolder(_ prefix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        temporaryFolders.append(folder)
        return folder.resolvingSymlinksInPath()
    }

    /// A workspace on a new vault with `files`, whose index has read it, and the store
    /// that holds the conflict versions a test adds.
    private func makeWorkspace(files: [String: String]) async throws -> (workspace: WorkspaceModel, store: TestConflictVersionStore, vault: URL) {
        let vault = try makeFolder("ConflictVersionsVault")
        for (relativePath, contents) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        let index = try VaultIndex(databaseURL: try makeFolder("ConflictVersionsIndex").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        let store = try TestConflictVersionStore()
        workspace.conflictVersionStore = store
        return (workspace, store, vault)
    }

    private func fileText(_ relativePath: String, in vault: URL) -> String? {
        (try? Data(contentsOf: vault.appendingPathComponent(relativePath))).map { data in String(decoding: data, as: UTF8.self) }
    }

    /// Whether the index has taken in a new file, which it does in the background.
    private func waitForIndexedText(of path: VaultPath, in workspace: WorkspaceModel) async throws -> Bool {
        let deadline = Date.now.addingTimeInterval(10)
        while Date.now < deadline {
            if let results = try await workspace.index?.search("\"from the Mac\""), results.results.contains(where: { result in result.path == path }) { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private func waitUntil(timeoutSeconds: Double = 20, _ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeoutSeconds)
        while !condition() {
            guard Date.now < deadline else { return XCTFail("The condition did not become true in time.") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private extension VaultPath {
    /// A path a test knows to be valid.
    static func unchecked(_ rawValue: String) -> VaultPath {
        guard let path = try? VaultPath(rawValue) else { preconditionFailure("Invalid test path \(rawValue)") }
        return path
    }
}
