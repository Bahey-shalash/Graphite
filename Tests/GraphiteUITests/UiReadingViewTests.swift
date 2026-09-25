import XCTest
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import Textual
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

@MainActor
final class UiReadingViewTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("ReadingVault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault)
    }

    private func write(_ text: String, to path: String) throws {
        let location = vault.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: location)
    }

    private func build(_ source: String, note: String) async throws -> ReadingViewBuild {
        try await ReadingViewBuilder().build(source: source, note: try VaultPath(note), root: vault, index: index, configuration: ReadingConfiguration())
    }

    /// The Markdown text of every block, callout and embedded note bodies included.
    private func markdownTexts(_ blocks: [RenderedBlock]) -> [String] {
        blocks.flatMap { block -> [String] in
            switch block {
            case .markdown(_, let text), .displayMath(_, let text), .heading(_, _, let text, _): [text]
            case .callout(_, _, let title, _, let body): [title] + markdownTexts(body)
            case .transclusion(_, _, _, let body): markdownTexts(body)
            default: []
            }
        }
    }

    /// The links of rendered text, in order, with their text.
    private func links(in markdown: String) throws -> [(text: String, location: URL)] {
        let attributed = try ObsidianMarkdownParser(baseURL: vault, textSize: 17).attributedString(for: markdown)
        return attributed.runs.compactMap { run in run.link.map { location in (String(attributed[run.range].characters), location) } }
    }

    /// What following a rendered link does: the target and whether it is a Wikilink, or the
    /// heading scrolled to.
    private func follow(_ location: URL) -> (navigated: [(target: String, isWiki: Bool)], scrolled: [String]) {
        var navigated: [(target: String, isWiki: Bool)] = []
        var scrolled: [String] = []
        let action = ObsidianMarkdownText.linkAction(root: vault, navigate: { target, isWiki in navigated.append((target, isWiki)) },
                                                     scrollToHeading: { anchor in scrolled.append(anchor) })
        action(location)
        return (navigated, scrolled)
    }

    // MARK: Markdown links (F190, F297)

    func testMarkdownLinksAreFollowedFromTheNotesOwnFolder() async throws {
        let source = "[Syllabus](../Syllabus.md) and [see](#Some%20Heading) and [slides](Lecture.pdf#page=12) and [web](https://example.com/page)\n"
        let build = try await build(source, note: "Course/Week 1/Notes.md")
        let renderedLinks = try links(in: markdownTexts(build.blocks).joined(separator: "\n"))
        XCTAssertEqual(renderedLinks.map(\.text), ["Syllabus", "see", "slides", "web"])

        let syllabus = follow(renderedLinks[0].location)
        XCTAssertEqual(syllabus.navigated.map(\.target), ["../Syllabus.md"])
        XCTAssertEqual(syllabus.navigated.map(\.isWiki), [false])
        XCTAssertEqual(WikiLinkResolver.directCandidates(target: "../Syllabus.md", source: try VaultPath("Course/Week 1/Notes.md"), isWiki: false).first?.rawValue,
                       "Course/Syllabus.md")

        let heading = follow(renderedLinks[1].location)
        XCTAssertTrue(heading.navigated.isEmpty)
        XCTAssertEqual(heading.scrolled, [NotePreviewDocument.anchor(forHeading: "Some Heading")])

        let slides = follow(renderedLinks[2].location)
        XCTAssertEqual(slides.navigated.map(\.target), ["Lecture.pdf#page=12"])

        XCTAssertEqual(renderedLinks[3].location.absoluteString, "https://example.com/page")
    }

    func testMarkdownLinkInAnEmbeddedNoteIsFollowedFromThatNote() async throws {
        try write("[Other](../Other.md) and [[#Summary]] and [top](#Summary) and [sharp](C%23%20notes.md#Part%20Two)\n\n# Summary\n", to: "Sub/Embedded.md")
        let host = try VaultPath("Notes/Host.md")
        let build = try await build("![[Sub/Embedded]]\n", note: host.rawValue)
        let renderedLinks = try links(in: markdownTexts(build.blocks).joined(separator: "\n"))
        let targets = renderedLinks.flatMap { link in follow(link.location).navigated }
        XCTAssertEqual(targets.map(\.target), ["../Other.md", "../Sub/Embedded.md#Summary", "../Sub/Embedded.md#Summary", "../Sub/C%23%20notes.md#Part Two"])
        XCTAssertEqual(targets.map(\.isWiki), [false, false, false, false])
        // Following resolves each target from the host note to exactly the file the embedded note names.
        let resolvedPaths = targets.map { target in WikiLinkResolver.directCandidates(target: target.target, source: host, isWiki: target.isWiki).first?.rawValue }
        XCTAssertEqual(resolvedPaths, ["Other.md", "Sub/Embedded.md", "Sub/Embedded.md", "Sub/C# notes.md"])
    }

    func testDestinationIsFoundAfterTheLabelAndBeforeTheTitle() async throws {
        let build = try await build("[Plan.md](Plan.md \"Plan.md\") and [see (Plan.md)](<Plan.md>)\n", note: "Folder/Note.md")
        let renderedLinks = try links(in: markdownTexts(build.blocks).joined(separator: "\n"))
        XCTAssertEqual(renderedLinks.map(\.text), ["Plan.md", "see (Plan.md)"])
        XCTAssertEqual(renderedLinks.compactMap { link in GraphiteOpenLink.target(of: link.location)?.target }, ["Plan.md", "Plan.md"])
        XCTAssertEqual(renderedLinks.compactMap { link in GraphiteOpenLink.target(of: link.location)?.isWiki }, [false, false])
    }

    func testFileLinkToAMissingNoteUnderTheVaultIsFollowed() throws {
        let missing = vault.appendingPathComponent("Folder/Missing.md")
        let result = follow(missing)
        XCTAssertEqual(result.navigated.map(\.target), ["Folder/Missing.md"])
    }

    // MARK: Frontmatter-like blocks (F192)

    func testBlockStartingWithARuleKeepsItsWikilinks() async throws {
        let build = try await build("# Section\n---\nSee [[Other Note]] for details.\n---\nMore text [[Third]]\n", note: "Note.md")
        let renderedLinks = try links(in: markdownTexts(build.blocks).joined(separator: "\n"))
        XCTAssertEqual(renderedLinks.map(\.text), ["Other Note", "Third"])
        XCTAssertEqual(renderedLinks.compactMap { link in GraphiteOpenLink.target(of: link.location)?.target }, ["Other Note", "Third"])
    }

    // MARK: Destinations and labels (F191, F708)

    func testTargetWithAnUnbalancedParenthesisStaysWhole() async throws {
        let build = try await build("See [[1) Introduction]] here\n", note: "Note.md")
        let text = markdownTexts(build.blocks).joined()
        let renderedLinks = try links(in: text)
        XCTAssertEqual(renderedLinks.map(\.text), ["1) Introduction"])
        XCTAssertEqual(renderedLinks.first.flatMap { link in GraphiteOpenLink.target(of: link.location)?.target }, "1) Introduction")
    }

    func testLabelEndingInABackslashStaysALink() async throws {
        let build = try await build("See [[Notes\\]] here\n", note: "Note.md")
        let renderedLinks = try links(in: markdownTexts(build.blocks).joined())
        XCTAssertEqual(renderedLinks.map(\.text), ["Notes\\"])
        XCTAssertEqual(renderedLinks.first.flatMap { link in GraphiteOpenLink.target(of: link.location)?.target }, "Notes\\")
    }

    func testImageNameWithAnUnbalancedParenthesisKeepsItsWholeLocation() async throws {
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: vault.appendingPathComponent("Scan 2) final.png"))
        let build = try await build("Figure ![[Scan 2) final.png]] inline\n", note: "Note.md")
        let text = markdownTexts(build.blocks).joined()
        let attributed = try AttributedString(markdown: text)
        let imageLocations = attributed.runs.compactMap(\.imageURL)
        XCTAssertEqual(imageLocations.map(\.lastPathComponent), ["Scan 2) final.png"])
        XCTAssertFalse(String(attributed.characters).contains("final.png"))
    }

    // MARK: Task markers (F189)

    func testLongTaskListIsRenderedInLinearTime() throws {
        let taskCount = 3000
        let lines = (0..<taskCount).map { number in number % 2 == 0 ? "- [x] done \(number)" : "- [ ] open \(number)" }
        let markdown = ObsidianInlineMarkup.preparedForReading(lines.joined(separator: "\n"), colorsEnabled: true, paletteHexByName: [:])
        let start = Date()
        let attributed = try ObsidianMarkdownParser(baseURL: nil, textSize: 17).attributedString(for: markdown)
        // Replacing the markers one search at a time took about 40 seconds for this list.
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)

        let checkboxes = attributed.runs.compactMap { run in run[AttributeScopes.TextualAttributes.AttachmentAttribute.self] }
        XCTAssertEqual(checkboxes.count, taskCount)
        XCTAssertEqual(checkboxes.filter { checkbox in checkbox == AnyAttachment(TaskCheckboxAttachment(isChecked: true, pointSize: 17)) }.count, taskCount / 2)
        XCTAssertFalse(String(attributed.characters).contains(ObsidianInlineMarkup.checkedTaskMarker))
        let struckText = attributed.runs.filter { run in run.strikethroughStyle != nil }.map { run in String(attributed[run.range].characters) }.joined()
        XCTAssertTrue(struckText.contains("done 0"))
        XCTAssertFalse(struckText.contains("open 1"))
    }

    func testCompletedTaskTextIsStruckThroughAfterItsCheckbox() throws {
        let markdown = ObsidianInlineMarkup.preparedForReading("- [x] done\n- [ ] open\n  - [x] nested", colorsEnabled: true, paletteHexByName: [:])
        let attributed = try ObsidianMarkdownParser(baseURL: nil, textSize: 17).attributedString(for: markdown)
        let struckRuns = attributed.runs.filter { run in run.strikethroughStyle != nil }.map { run in String(attributed[run.range].characters) }
        XCTAssertEqual(struckRuns.joined(separator: "|"), "done|nested")
        let checkboxRuns = attributed.runs.filter { run in run[AttributeScopes.TextualAttributes.AttachmentAttribute.self] != nil }
        XCTAssertEqual(checkboxRuns.count, 3)
        XCTAssertTrue(checkboxRuns.allSatisfy { run in run.strikethroughStyle == nil })
    }

    // MARK: Private-use characters (F538)

    func testPrivateUseCharactersInTheNoteAreKept() async throws {
        let build = try await build("Icon \u{E005} and glyph \u{E000}X \u{E007}\u{E010} here\n- [ ] task\n", note: "Note.md")
        let text = markdownTexts(build.blocks).joined()
        let attributed = try ObsidianMarkdownParser(baseURL: nil, textSize: 17).attributedString(for: text)
        XCTAssertTrue(String(attributed.characters).contains("Icon \u{E005} and glyph \u{E000}X \u{E007}\u{E010} here"))
        let checkboxes = attributed.runs.compactMap { run in run[AttributeScopes.TextualAttributes.AttachmentAttribute.self] }
        XCTAssertEqual(checkboxes.count, 1)
    }

    // MARK: Embedded notes (F537, F542, F543)

    func testEmbeddedNoteTooLargeIsShownAsALink() async throws {
        try write(String(repeating: "x", count: NotePreviewDocument.maximumEmbeddedNoteBytes + 1), to: "Big Log.md")
        let build = try await build("![[Big Log]]\n", note: "Note.md")
        XCTAssertFalse(MarkdownPreview.containsMissingEmbed(build.blocks))
        let renderedLinks = try links(in: markdownTexts(build.blocks).joined())
        XCTAssertEqual(renderedLinks.map(\.text), ["Big Log"])
        let target = try XCTUnwrap(renderedLinks.first.flatMap { link in GraphiteOpenLink.target(of: link.location) })
        XCTAssertEqual(target.target, "Big%20Log.md")
        XCTAssertFalse(target.isWiki)
    }

    func testUnresolvedInlineEmbedAsksForABuildOnceIndexed() async throws {
        let unresolved = try await build("- Figure: ![[plot.png]]\n", note: "Note.md")
        XCTAssertTrue(unresolved.hasUnresolvedEmbeds)
        let plain = try await build("- Figure: [[Other]]\n", note: "Note.md")
        XCTAssertFalse(plain.hasUnresolvedEmbeds)
    }

    func testOnlyTheNotesFirstHeadingOfANameIsAScrollTarget() async throws {
        try write("## Summary\nEmbedded text\n", to: "Template.md")
        let build = try await build("![[Template]]\n\n## Summary\nFirst\n\n## Summary\nSecond\n", note: "Note.md")
        func anchors(_ blocks: [RenderedBlock]) -> [String?] {
            blocks.flatMap { block -> [String?] in
                switch block {
                case .heading(_, _, _, let anchor): [anchor]
                case .transclusion(_, _, _, let body), .callout(_, _, _, _, let body): anchors(body)
                default: []
                }
            }
        }
        // The repeated heading is a scroll target of its own, numbered as in the outline,
        // which a link to the heading never names.
        let anchor = NotePreviewDocument.anchor(forHeading: "Summary")
        XCTAssertEqual(anchors(build.blocks), [nil, anchor, HeadingScrollRequest.readingScrollTarget(anchor: anchor, occurrence: 1)])
        XCTAssertNotEqual(HeadingScrollRequest.readingScrollTarget(anchor: anchor, occurrence: 1), anchor)
    }

    // MARK: Media (F196)

    func testMediaPlayersOutliveRowsAndEndWithTheirEmbeds() throws {
        let players = ReadingMediaPlayers()
        let recording = vault.appendingPathComponent("Lecture.m4a")
        let clip = vault.appendingPathComponent("Clip.mp4")
        let recordingPlayback = players.playback(for: recording)
        XCTAssertTrue(players.playback(for: recording) === recordingPlayback)
        XCTAssertNil(players.existingPlayback(for: clip))
        _ = players.playback(for: clip)
        players.keepPlaybacks(for: [recording])
        XCTAssertTrue(players.existingPlayback(for: recording) === recordingPlayback)
        XCTAssertNil(players.existingPlayback(for: clip))

        // A row's own player is kept once it plays, and does not replace one the note keeps.
        let clipPlayback = EmbeddedMediaPlayback(location: clip)
        XCTAssertFalse(players.isKept(clipPlayback))
        players.keep(clipPlayback)
        XCTAssertTrue(players.isKept(clipPlayback))
        let otherRecordingPlayback = EmbeddedMediaPlayback(location: recording)
        players.keep(otherRecordingPlayback)
        XCTAssertFalse(players.isKept(otherRecordingPlayback))
        XCTAssertTrue(players.isKept(recordingPlayback))
    }

    func testMediaLocationsIncludeCalloutsAndEmbeddedNotes() throws {
        let recording = vault.appendingPathComponent("Lecture.m4a")
        let clip = vault.appendingPathComponent("Clip.mp4")
        let blocks: [RenderedBlock] = [
            .audio(id: 1, location: recording, name: "Lecture.m4a"),
            .callout(id: 2, type: "note", title: "Clip", folding: .notFoldable, body: [.video(id: 3, location: clip)]),
        ]
        XCTAssertEqual(MarkdownPreview.mediaLocations(in: blocks), [recording, clip])
    }

    // MARK: Markers next to combining marks (F539)

    func testHighlightStartingWithACombiningMarkIsApplied() throws {
        let markdown = ObsidianInlineMarkup.preparedForReading("==\u{0301}e accent== after", colorsEnabled: true, paletteHexByName: [:])
        let attributed = try ObsidianMarkdownParser(baseURL: nil, textSize: 17).attributedString(for: markdown)
        let scalarValues = attributed.unicodeScalars.map(\.value)
        XCTAssertFalse(scalarValues.contains(0xE003))
        XCTAssertFalse(scalarValues.contains(0xE004))
        let highlightedText = attributed.runs.filter { run in run.backgroundColor != nil }.map { run in String(attributed[run.range].characters) }.joined()
        XCTAssertEqual(highlightedText, "\u{0301}e accent")
        XCTAssertTrue(String(attributed.characters).hasSuffix(" after"))
    }

    // MARK: Build reuse (P11, P47)

    func testBuildKeyDescribesOnlyAnEqualBuild() throws {
        let path = try VaultPath("Note.md")
        let configuration = ReadingConfiguration()
        let key = ReadingBuildKey(source: "Text", path: path, root: vault, configuration: configuration, dependsOnIndex: false)
        XCTAssertTrue(key.describesBuild(of: "Text", path: path, root: vault, configuration: configuration))
        var laterIndex = configuration
        laterIndex.indexVersion += 1
        XCTAssertTrue(key.describesBuild(of: "Text", path: path, root: vault, configuration: laterIndex))
        var largerText = configuration
        largerText.textSize = 30
        XCTAssertTrue(key.describesBuild(of: "Text", path: path, root: vault, configuration: largerText))

        XCTAssertFalse(key.describesBuild(of: "Changed", path: path, root: vault, configuration: configuration))
        XCTAssertFalse(key.describesBuild(of: "Text", path: try VaultPath("Other.md"), root: vault, configuration: configuration))
        var savedDrawing = configuration
        savedDrawing.drawingVersion += 1
        XCTAssertFalse(key.describesBuild(of: "Text", path: path, root: vault, configuration: savedDrawing))
        var withoutColors = configuration
        withoutColors.colorsEnabled = false
        XCTAssertFalse(key.describesBuild(of: "Text", path: path, root: vault, configuration: withoutColors))

        let indexedKey = ReadingBuildKey(source: "Text", path: path, root: vault, configuration: configuration, dependsOnIndex: true)
        XCTAssertTrue(indexedKey.describesBuild(of: "Text", path: path, root: vault, configuration: configuration))
        XCTAssertFalse(indexedKey.describesBuild(of: "Text", path: path, root: vault, configuration: laterIndex))
    }

    func testFrontmatterBecomesPropertiesAndTheBodyKeepsItsLinks() async throws {
        let build = try await build("---\ntitle: Lecture\n---\n# Heading\n\nSee [[Other]] and **bold** text\n", note: "Note.md")
        guard case .properties(let properties) = build.blocks.first else { return XCTFail("The note's properties are not shown first.") }
        XCTAssertEqual(properties.map(\.key), ["title"])
        let texts = markdownTexts(build.blocks)
        XCTAssertFalse(texts.joined().contains("title: Lecture"))
        let renderedLinks = try links(in: texts.joined(separator: "\n"))
        XCTAssertEqual(renderedLinks.map(\.text), ["Other"])
        XCTAssertTrue(texts.contains { text in text.contains("**bold** text") })
    }

    // MARK: Thumbnails (F541, P23)

    private func writePNG(width: Int, height: Int, to location: URL) throws {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return XCTFail("Cannot make a test image.")
        }
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let imageData = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(imageData, UTType.png.identifier as CFString, 1, nil) else {
            return XCTFail("Cannot encode a test image.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try (imageData as Data).write(to: location)
    }

    func testThumbnailIsMadeAgainOnlyWhenItsFileChanges() async throws {
        let cache = ReadingImageCache()
        let location = vault.appendingPathComponent("Photo.png")
        try writePNG(width: 40, height: 20, to: location)
        // A whole second, which setting the date again below keeps exactly.
        let modificationDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: location.path)
        XCTAssertNil(cache.lastThumbnail(for: location, kind: .block))
        let first = try await cache.thumbnail(for: location, kind: .block)
        XCTAssertEqual(first.aspectRatio, 2)
        // Decoded when loaded, so the embed draws these pixels without decoding them again.
        XCTAssertEqual(first.image.width, 40)
        XCTAssertEqual(first.image.height, 20)
        XCTAssertFalse(first.isEditableDrawing)
        XCTAssertTrue(cache.lastThumbnail(for: location, kind: .block)?.image === first.image)

        // Unreadable bytes of the same size and date: only the cached thumbnail can be shown.
        let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
        let byteCount = try XCTUnwrap((attributes[.size] as? NSNumber)?.intValue)
        try Data(count: byteCount).write(to: location)
        try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: location.path)
        let cached = try await cache.thumbnail(for: location, kind: .block)
        XCTAssertTrue(cached.image === first.image)

        // A new modification date means the file changed, so it is read again.
        try FileManager.default.setAttributes([.modificationDate: modificationDate.addingTimeInterval(5)], ofItemAtPath: location.path)
        do {
            _ = try await cache.thumbnail(for: location, kind: .block)
            XCTFail("A changed file was not read again.")
        } catch {}

        try writePNG(width: 30, height: 60, to: location)
        let replaced = try await cache.thumbnail(for: location, kind: .block)
        XCTAssertEqual(replaced.aspectRatio, 0.5)
    }

    func testInlineThumbnailIsDecodedWhenLoaded() async throws {
        let cache = ReadingImageCache()
        let location = vault.appendingPathComponent("Figure.png")
        try writePNG(width: 50, height: 25, to: location)
        let thumbnail = try await cache.thumbnail(for: location, kind: .inline)
        let image = thumbnail.image
        XCTAssertEqual(image.width, 50)
        XCTAssertEqual(image.height, 25)
        XCTAssertNil(cache.lastThumbnail(for: location, kind: .block))
    }
}
