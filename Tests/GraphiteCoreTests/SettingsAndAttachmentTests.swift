import XCTest
@testable import GraphiteCore

final class SettingsAndAttachmentTests: XCTestCase {
    func testObsidianAttachmentValuesMapBothWays() {
        let expectations: [(String?, AttachmentLocation, String)] = [
            (nil, .vaultFolder, "/"),
            ("/", .vaultFolder, "/"),
            ("", .vaultFolder, "/"),
            ("./", .sameFolderAsNote, "./"),
            (".", .sameFolderAsNote, "./"),
            ("./attachments", .subfolderUnderNote("attachments"), "./attachments"),
            ("Files/Images/", .specifiedFolder("Files/Images"), "Files/Images"),
        ]
        for (storedValue, location, writtenValue) in expectations {
            XCTAssertEqual(AttachmentLocation(obsidianValue: storedValue), location, "Reading \(String(describing: storedValue))")
            XCTAssertEqual(location.obsidianValue, writtenValue)
        }
    }

    func testMissingKeysUseObsidianDefaults() throws {
        let settings = try ObsidianSettings(applicationConfigurationData: Data("{\"vimMode\": true}".utf8))
        XCTAssertEqual(settings, ObsidianSettings(attachmentLocation: .vaultFolder, linkFormat: .shortest, usesWikilinks: true))
    }

    func testSavingSettingsPreservesEveryOtherObsidianKey() throws {
        let existing = Data("""
        {"vimMode": true, "attachmentFolderPath": "/", "showLineNumber": false, "nested": {"a": [1, 2]}, "useMarkdownLinks": false}
        """.utf8)
        let settings = ObsidianSettings(attachmentLocation: .subfolderUnderNote("attachments"), linkFormat: .relative, usesWikilinks: false)
        let merged = try settings.mergedApplicationConfigurationData(existingData: existing)
        let configuration = try XCTUnwrap(JSONSerialization.jsonObject(with: merged) as? [String: Any])
        XCTAssertEqual(configuration["vimMode"] as? Bool, true)
        XCTAssertEqual(configuration["showLineNumber"] as? Bool, false)
        XCTAssertEqual((configuration["nested"] as? [String: Any])?["a"] as? [Int], [1, 2])
        XCTAssertEqual(configuration["attachmentFolderPath"] as? String, "./attachments")
        XCTAssertEqual(configuration["newLinkFormat"] as? String, "relative")
        XCTAssertEqual(configuration["useMarkdownLinks"] as? Bool, true)
        XCTAssertEqual(try ObsidianSettings(applicationConfigurationData: merged), settings)
        XCTAssertFalse(String(decoding: merged, as: UTF8.self).contains("\\/"), "Slashes stay readable, as Obsidian writes them.")
    }

    func testFileSettingsAreReadAndWrittenOnlyWhenChanged() throws {
        let untouched = try ObsidianSettings().mergedApplicationConfigurationData(existingData: Data("{\"vimMode\": true}".utf8))
        let untouchedKeys = try XCTUnwrap(JSONSerialization.jsonObject(with: untouched) as? [String: Any]).keys
        for key in ["trashOption", "alwaysUpdateLinks", "promptDelete", "fileSortOrder", "newFileLocation"] {
            XCTAssertFalse(untouchedKeys.contains(key), "\(key) is written only when it differs from Obsidian's default.")
        }
        var settings = ObsidianSettings()
        settings.deletionMethod = .vaultTrash
        settings.updatesLinksAutomatically = true
        settings.confirmsDeletion = false
        settings.fileSortOrder = .byModifiedTime
        settings.newNoteLocation = .specifiedFolder("Inbox")
        let written = try settings.mergedApplicationConfigurationData(existingData: nil)
        let configuration = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any])
        XCTAssertEqual(configuration["trashOption"] as? String, "local")
        XCTAssertEqual(configuration["fileSortOrder"] as? String, "byModifiedTime")
        XCTAssertEqual(configuration["newFileLocation"] as? String, "folder")
        XCTAssertEqual(configuration["newFileFolderPath"] as? String, "Inbox")
        XCTAssertEqual(try ObsidianSettings(applicationConfigurationData: written), settings)
        XCTAssertEqual(try settings.newNoteLocation.directory(currentFile: VaultPath("Courses/Note.md")).rawValue, "Inbox")
        XCTAssertEqual(try NewNoteLocation.sameFolderAsCurrentFile.directory(currentFile: VaultPath("Courses/Note.md")).rawValue, "Courses")
    }

    func testFileSortOrdersKeepFoldersFirst() {
        let old = Date(timeIntervalSince1970: 1), new = Date(timeIntervalSince1970: 2)
        let entries = [VaultEntry(path: try! VaultPath("b.md"), isDirectory: false, size: 0, modified: old, created: new),
                       VaultEntry(path: try! VaultPath("a.md"), isDirectory: false, size: 0, modified: new, created: old),
                       VaultEntry(path: try! VaultPath("Folder"), isDirectory: true, size: 0, modified: old)]
        XCTAssertEqual(FileSortOrder.alphabetical.sorted(entries).map(\.path.name), ["Folder", "a.md", "b.md"])
        XCTAssertEqual(FileSortOrder.alphabeticalReverse.sorted(entries).map(\.path.name), ["Folder", "b.md", "a.md"])
        XCTAssertEqual(FileSortOrder.byModifiedTime.sorted(entries).map(\.path.name), ["Folder", "a.md", "b.md"])
        XCTAssertEqual(FileSortOrder.byCreatedTime.sorted(entries).map(\.path.name), ["Folder", "b.md", "a.md"])
    }

    func testMalformedSettingsFileIsNeverOverwritten() {
        XCTAssertThrowsError(try ObsidianSettings().mergedApplicationConfigurationData(existingData: Data("[1, 2]".utf8)))
        XCTAssertThrowsError(try ObsidianSettings().mergedApplicationConfigurationData(existingData: Data("{broken".utf8)))
    }

    func testVaultStoreWritesAppJSONAndRereadsIt() async throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        try Data("{\"theme\": \"obsidian\"}".utf8).write(to: vault.appendingPathComponent(".obsidian/app.json"))
        let store = VaultStore(root: vault)
        let settings = ObsidianSettings(attachmentLocation: .specifiedFolder("Attachments"), linkFormat: .absolute, usesWikilinks: true)
        try await store.saveSettings(settings)
        let reloaded = try await store.settings()
        XCTAssertEqual(reloaded, settings)
        let configuration = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: vault.appendingPathComponent(".obsidian/app.json"))) as? [String: Any])
        XCTAssertEqual(configuration["theme"] as? String, "obsidian")
    }

    func testVaultStoreCreatesSettingsWhenVaultHasNoObsidianFolder() async throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("Vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let store = VaultStore(root: vault)
        let noSettings = try await store.settings()
        XCTAssertEqual(noSettings, ObsidianSettings())
        try await store.saveSettings(ObsidianSettings(attachmentLocation: .sameFolderAsNote))
        let reloaded = try await store.settings()
        XCTAssertEqual(reloaded.attachmentLocation, .sameFolderAsNote)
    }

    func testAttachmentDirectoryForEveryLocation() throws {
        let note = try VaultPath("ETH/转换/Lecture 01.md")
        let resolver = AttachmentResolver()
        XCTAssertEqual(try resolver.directory(for: .vaultFolder, note: note), .root)
        XCTAssertEqual(try resolver.directory(for: .sameFolderAsNote, note: note).rawValue, "ETH/转换")
        XCTAssertEqual(try resolver.directory(for: .specifiedFolder("Attachments"), note: note).rawValue, "Attachments")
        XCTAssertEqual(try resolver.directory(for: .subfolderUnderNote("attachments"), note: note).rawValue, "ETH/转换/attachments")
        XCTAssertThrowsError(try resolver.directory(for: .specifiedFolder("../../Outside"), note: note))
    }

    func testEmbedsFollowLinkFormatAndWikilinkSettings() throws {
        let note = try VaultPath("ETH/转换/Lecture 01.md")
        let attachment = try VaultPath("ETH/转换/attachments/ADC architecture.png")
        let resolver = AttachmentResolver()
        func embed(_ settings: ObsidianSettings, unique: Bool = true) -> String {
            resolver.embed(attachment: attachment, note: note, settings: settings, isNameUniqueInVault: unique)
        }
        XCTAssertEqual(embed(ObsidianSettings(linkFormat: .shortest)), "![[ADC architecture.png]]")
        XCTAssertEqual(embed(ObsidianSettings(linkFormat: .shortest), unique: false), "![[ETH/转换/attachments/ADC architecture.png]]")
        XCTAssertEqual(embed(ObsidianSettings(linkFormat: .absolute)), "![[ETH/转换/attachments/ADC architecture.png]]")
        XCTAssertEqual(embed(ObsidianSettings(linkFormat: .relative)), "![[attachments/ADC architecture.png]]")
        XCTAssertEqual(embed(ObsidianSettings(linkFormat: .relative, usesWikilinks: false)), "![](attachments/ADC%20architecture.png)")
        let otherFolderNote = try VaultPath("Notes/Summary.md")
        XCTAssertEqual(resolver.embed(attachment: attachment, note: otherFolderNote, settings: ObsidianSettings(linkFormat: .relative), isNameUniqueInVault: true),
                       "![[../ETH/转换/attachments/ADC architecture.png]]")
        let reservedName = try VaultPath("Figures/Result #1.png")
        XCTAssertEqual(resolver.embed(attachment: reservedName, note: note, settings: ObsidianSettings(linkFormat: .absolute), isNameUniqueInVault: true),
                       "![](Figures/Result%20%231.png)")
    }

    func testDrawingNamesAreReadableAndSortable() throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12, minute: 37, second: 6)))
        XCTAssertEqual(AttachmentResolver().drawingFileStem(createdAt: date, calendar: calendar), "Drawing 2026-09-23 12.37.06")
    }

    func testEmbedLocatorFindsEmbedAtCursorAndObsidianWidth() {
        let text = "Before\n![[Drawing 2026.png|400]] and ![alt](attachments/x%20y.svg)\nAfter" as NSString
        let wikiEmbed = EmbedLocator.embed(at: 12, in: text)
        XCTAssertEqual(wikiEmbed?.target, "Drawing 2026.png")
        XCTAssertEqual(wikiEmbed?.displayWidth, 400)
        XCTAssertEqual(wikiEmbed?.isWiki, true)
        let markdownEmbed = EmbedLocator.embed(at: text.range(of: "alt").location, in: text)
        XCTAssertEqual(markdownEmbed?.target, "attachments/x%20y.svg")
        XCTAssertEqual(markdownEmbed?.isWiki, false)
        XCTAssertNil(EmbedLocator.embed(at: 2, in: text))
        XCTAssertEqual(EmbedDisplaySize.parse(label: "300x200"), EmbedDisplaySize(width: 300, height: 200))
        XCTAssertNil(EmbedDisplaySize.parse(label: "caption"))
    }

    func testImageSizeFollowsTheLastPipeAndKeepsTheImageShape() throws {
        let text = "![Caption|150](image.png) ![[photo.jpg|Caption|300x100]]" as NSString
        XCTAssertEqual(EmbedLocator.embed(at: 3, in: text)?.displaySize, EmbedDisplaySize(width: 150, height: nil))
        let sized = try XCTUnwrap(EmbedLocator.embed(at: text.range(of: "photo").location, in: text)?.displaySize)
        XCTAssertEqual(sized, EmbedDisplaySize(width: 300, height: 100))
        // A square image in a 300×100 box is drawn 100 wide; a wide one is limited by the width.
        XCTAssertEqual(sized.fittedWidth(aspectRatio: 1), 100)
        XCTAssertEqual(sized.fittedWidth(aspectRatio: 4), 300)
        XCTAssertNil(EmbedDisplaySize.parse(label: "1e3"))
        XCTAssertNil(EmbedDisplaySize.parse(label: "300x"))
        XCTAssertNil(EmbedDisplaySize.parse(label: "0"))
    }
}

final class PreviewTextTests: XCTestCase {
    func testSingleLineBreaksBecomeHardBreaksOutsideCodeAndMath() {
        let body = "Line one\nLine two\n\n```\ncode\n```\n$$\nx = 1\n$$\n> Quote\nAlready  \n"
        let expected = "Line one  \nLine two  \n\n```\ncode\n```\n$$\nx = 1\n$$\n> Quote  \nAlready  \n"
        XCTAssertEqual(ObsidianPreviewText.applyingSoftLineBreaks(to: body), expected)
    }

    func testStrictLineBreaksRoundTrip() throws {
        let settings = ObsidianSettings(usesStrictLineBreaks: true)
        let merged = try settings.mergedApplicationConfigurationData(existingData: nil)
        XCTAssertEqual(try ObsidianSettings(applicationConfigurationData: merged).usesStrictLineBreaks, true)
        XCTAssertEqual(try ObsidianSettings(applicationConfigurationData: Data("{}".utf8)).usesStrictLineBreaks, false)
    }

    func testFrontmatterLength() {
        XCTAssertEqual(FrontmatterLocator.length(in: "---\na: b\n---\nBody" as NSString), 13)
        XCTAssertEqual(FrontmatterLocator.length(in: "Body\n---\n" as NSString), 0)
    }
}

final class BlockInsertionTests: XCTestCase {
    private func inserting(_ block: String, into source: String, at location: Int) -> String {
        let nsSource = source as NSString
        let range = NSRange(location: location, length: 0)
        return nsSource.replacingCharacters(in: range, with: MarkdownBlockInsertion.text(inserting: block, into: nsSource, replacing: range))
    }

    func testEmptyLineKeepsItsBlankSeparator() {
        let source = "Links\n\n\n---\n"
        XCTAssertEqual(inserting("![[A.svg]]", into: source, at: 6), "Links\n![[A.svg]]\n\n\n---\n")
    }

    /// Regression: two drawings inserted on the blank lines above a rule made a heading.
    func testInsertionNeverCreatesASetextHeading() {
        let once = inserting("![[A.svg]]", into: "Links\n\n---\n", at: 6)
        XCTAssertEqual(once, "Links\n![[A.svg]]\n\n---\n")
        let twice = inserting("![[B.pdf]]", into: once, at: (once as NSString).range(of: "\n\n---").location + 1)
        XCTAssertEqual(twice, "Links\n![[A.svg]]\n![[B.pdf]]\n\n---\n")
        XCTAssertFalse(twice.contains("]]\n---"))
    }

    func testMiddleAndEndOfLine() {
        XCTAssertEqual(inserting("![[A.png]]", into: "abcdef", at: 3), "abc\n![[A.png]]\ndef")
        XCTAssertEqual(inserting("![[A.png]]", into: "abc\ndef", at: 3), "abc\n![[A.png]]\ndef")
        XCTAssertEqual(inserting("![[A.png]]", into: "abc", at: 3), "abc\n![[A.png]]\n")
        XCTAssertEqual(inserting("![[A.png]]", into: "", at: 0), "![[A.png]]\n")
    }
}
