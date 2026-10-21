import GraphiteTestSupport
import XCTest
@testable import GraphiteCore

final class VaultTests: XCTestCase {
    func testPathEscapeAndSymbolicLinkAreRejected() throws {
        XCTAssertThrowsError(try VaultPath("../../secret"))
        XCTAssertThrowsError(try VaultPath("/outside"))
        let directory = try TemporaryVault.make(prefix: "TemporaryFolder", for: self).root
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("escape"), withDestinationURL: directory.deletingLastPathComponent())
        XCTAssertThrowsError(try VaultPath("escape/secret").url(in: directory))
    }

    func testPathsAreAlwaysInComposedForm() throws {
        let decomposed = "Library/L'E\u{301}tranger.md"
        let composed = "Library/L'\u{C9}tranger.md"
        XCTAssertEqual(Array(try VaultPath(decomposed).rawValue.utf8), Array(composed.utf8), "A file URL's É becomes the typed one.")
        XCTAssertEqual(try VaultPath(decomposed).name, "L'\u{C9}tranger.md")
        let stored = try JSONEncoder().encode(["path": decomposed])
        let decoded = try JSONDecoder().decode([String: String].self, from: stored)
        XCTAssertEqual(try VaultPath(decoded["path"] ?? "").rawValue.utf8.count, composed.utf8.count)
        // A path saved before normalization, such as in a tab layout, comes back composed.
        let savedPath = try JSONDecoder().decode(VaultPath.self, from: Data(#"{"rawValue":"Library/L'E\u0301tranger.md"}"#.utf8))
        XCTAssertEqual(Array(savedPath.rawValue.utf8), Array(composed.utf8))
        XCTAssertThrowsError(try JSONDecoder().decode(VaultPath.self, from: Data(#"{"rawValue":"../outside.md"}"#.utf8)), "Stored paths are checked too.")
    }

    func testHiddenPaths() throws {
        XCTAssertTrue(try VaultPath(".obsidian/bookmarks.json").isHidden)
        XCTAssertTrue(try VaultPath("Course/.trash/Old.md").isHidden)
        XCTAssertFalse(try VaultPath("Course/Lecture.md").isHidden)
        XCTAssertFalse(try VaultPath("Notes/v1.2 draft.md").isHidden)
    }

    func testAtomicWriteDetectsSameSizeExternalEditAndDeletion() throws {
        let directory = try TemporaryVault.make(prefix: "TemporaryFolder", for: self).root
        let location = directory.appendingPathComponent("Lecture µ.md")
        let writer = AtomicFileWriter()
        let revision = try writer.write(Data("first".utf8), to: location, expecting: .absent)
        try Data("other".utf8).write(to: location)
        XCTAssertThrowsError(try writer.write(Data("mine".utf8), to: location, expecting: .revision(revision)))
        XCTAssertEqual(try String(contentsOf: location, encoding: .utf8), "other")
        XCTAssertThrowsError(try writer.write(Data(), to: location, expecting: .absent))
        try FileManager.default.removeItem(at: location)
        XCTAssertThrowsError(try writer.write(Data("mine".utf8), to: location, expecting: .revision(revision)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.path))
    }

    func testSuccessfulReplacementPreservesExactBytes() throws {
        let directory = try TemporaryVault.make(prefix: "TemporaryFolder", for: self).root
        let location = directory.appendingPathComponent("note.md")
        let writer = AtomicFileWriter()
        let original = Data("---\r\naliases: [µ]\r\n---\r\n# Hello  \r\n".utf8)
        let revision = try writer.write(original, to: location, expecting: .absent)
        XCTAssertEqual(try writer.read(location).data, original)
        let changed = original + Data("Content".utf8)
        let nextRevision = try writer.write(changed, to: location, expecting: .revision(revision))
        XCTAssertEqual(try writer.read(location).data, changed)
        XCTAssertNotEqual(revision, nextRevision)
    }

    /// A provider's stored version and a file shared read-only keep their permissions when
    /// copied; the staged copy must still be flushed and published.
    func testCopyOfAReadOnlyFileIsPublished() throws {
        let directory = try TemporaryVault.make(prefix: "TemporaryFolder", for: self).root
        let source = directory.appendingPathComponent("Handout.pdf")
        let contents = Data("%PDF-1.7 read only".utf8)
        try contents.write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: source.path)
        let destination = directory.appendingPathComponent("Handout 1.pdf")
        try AtomicFileWriter().copy(from: source, to: destination, expecting: .absent)
        XCTAssertEqual(try Data(contentsOf: destination), contents)
    }

    func testMarkdownSemanticsExcludeCodeAndPreserveSourceRanges() throws {
        let source = "---\naliases: [ADC, '转换']\ntags: [course]\n---\n# Sampling\n\n🙂 [[Quantization|Noise]] ![[Slide deck.pdf]] #signals\n\n`[[ignored]]`\n\n```swift\n[[also ignored]]\n```\n\n[Normal](../normal.md)\n"
        let semantics = try MarkdownSemantics.parse(source)
        XCTAssertEqual(semantics.headings, ["Sampling"])
        XCTAssertEqual(semantics.aliases, ["ADC", "转换"])
        XCTAssertEqual(semantics.tags, ["course", "signals"])
        XCTAssertEqual(semantics.links.map(\.target), ["Quantization", "Slide deck.pdf", "../normal.md"])
        guard semantics.links.count == 3 else { return }
        XCTAssertEqual((source as NSString).substring(with: semantics.links[0].range), "[[Quantization|Noise]]")
        XCTAssertTrue(semantics.links[1].isEmbed)
        XCTAssertFalse(semantics.links[2].isWiki)
    }

    func testFrontmatterWithWindowsLineEndingsKeepsAliasesAndTags() throws {
        let semantics = try MarkdownSemantics.parse("---\r\naliases: [ADC]\r\ntags: [course]\r\n---\r\n# Title\r\n")
        XCTAssertEqual(semantics.aliases, ["ADC"])
        XCTAssertEqual(semantics.tags, ["course"])
        XCTAssertEqual(semantics.headings, ["Title"])
    }

    func testTableEscapedPipeIsNotPartOfTheLinkTarget() throws {
        let semantics = try MarkdownSemantics.parse("| a | [[Lecture 3\\|third]] | [[Plain|alias]] |")
        XCTAssertEqual(semantics.links.map(\.target), ["Lecture 3", "Plain"])
        XCTAssertEqual(semantics.links.map(\.label), ["third", "alias"])
    }

    func testTagsFollowObsidianRules() throws {
        let semantics = try MarkdownSemantics.parse("#2026-exam #1984 #y1984 #inbox/to-read #📚 [[#Heading]] a#b `#code` https://x.org/#anchor #über")
        XCTAssertEqual(semantics.tags, ["2026-exam", "inbox/to-read", "y1984", "über", "📚"].sorted())
        XCTAssertTrue(TagSyntax.isValidTag("2026-exam"))
        XCTAssertFalse(TagSyntax.isValidTag("1984"))
        XCTAssertFalse(TagSyntax.isValidTag("two words"))
        XCTAssertTrue(TagSyntax.tag("Inbox/To-read", isWithin: "inbox"))
        XCTAssertFalse(TagSyntax.tag("myjob/inbox", isWithin: "inbox"))
        XCTAssertFalse(TagSyntax.tag("inboxes", isWithin: "inbox"))
    }

    func testFrontmatterTagsWithNumbersAndCommaSeparatedText() throws {
        XCTAssertEqual(try MarkdownSemantics.parse("---\ntags: [fiction, 2024, \"#classic\"]\n---\n").tags, ["2024", "classic", "fiction"])
        XCTAssertEqual(try MarkdownSemantics.parse("---\ntags: fiction, classic\n---\n").tags, ["classic", "fiction"])
        XCTAssertEqual(try MarkdownSemantics.parse("---\ntags: single\n---\n").tags, ["single"])
    }

    func testEmptyFrontmatterIsNotBody() throws {
        let semantics = try MarkdownSemantics.parse("---\n---\n# Title\n")
        XCTAssertEqual(semantics.frontmatter, "")
        XCTAssertEqual(semantics.body, "# Title\n")
    }

    func testCoordinateTransformWithNonzeroCropOrigin() throws {
        for size in [CGSize(width: 595, height: 842), CGSize(width: 1200, height: 600)] {
            let coordinates = try PageCoordinates(cropBox: CGRect(x: 31, y: 72, width: size.width, height: size.height), overlaySize: CGSize(width: size.width * 2, height: size.height * 2))
            let point = CGPoint(x: 145, y: 200)
            let restored = coordinates.overlayPoint(fromPDF: coordinates.pdfPoint(fromOverlay: point))
            XCTAssertEqual(restored.x, point.x, accuracy: 0.0001)
            XCTAssertEqual(restored.y, point.y, accuracy: 0.0001)
        }
    }

    /// An interior point and different horizontal and vertical scales, so swapped width
    /// and height ratios give a different answer.
    func testCoordinateTransformOfAnInteriorPointWithUnequalScales() throws {
        let coordinates = try PageCoordinates(cropBox: CGRect(x: 31, y: 72, width: 600, height: 800), overlaySize: CGSize(width: 300, height: 1600))
        let pdfPoint = CGPoint(x: 131, y: 272)
        let overlayPoint = CGPoint(x: 50, y: 1200)
        func assertPoint(_ actual: CGPoint, equals expected: CGPoint, _ message: String, line: UInt = #line) {
            XCTAssertEqual(actual.x, expected.x, accuracy: 0.0001, message, line: line)
            XCTAssertEqual(actual.y, expected.y, accuracy: 0.0001, message, line: line)
        }
        assertPoint(coordinates.overlayPoint(fromPDF: pdfPoint), equals: overlayPoint, "PDF to overlay")
        assertPoint(coordinates.pdfPoint(fromOverlay: overlayPoint), equals: pdfPoint, "Overlay to PDF")
    }
}
