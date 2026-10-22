import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// A vault of notes, a picture, a PDF and a note too large to embed, read as preview cards
/// read it.
enum LinkPreviewTestVault {
    static let files: [String: Data] = [
        "Note.md": Data("See [[Other]].\n\n## Here\nLocal section.\n".utf8),
        "Other.md": Data("---\ntags: [x]\n---\n# Other\n\nIntro.\n\n## Plan\nThe plan. ^step\n\n## Later\nLater text.\n".utf8),
        "Pictures/Photo.png": Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        "Lecture.pdf": Data("%PDF-1.4\n%%EOF\n".utf8),
        "Big.md": Data(String(repeating: "Large note text. ", count: 70_000).utf8),
    ]

    @MainActor static func reading(for testCase: XCTestCase) async throws -> LinkPreviewReading {
        let root = try TemporaryVault.make(prefix: "LinkPreviewVault", for: testCase).root
        for (relativePath, contents) in files {
            let location = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: location)
        }
        let indexFolder = try TemporaryVault.make(prefix: "LinkPreviewIndex", for: testCase).root
        let index = try VaultIndex(databaseURL: indexFolder.appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: root)
        let vault = try XCTUnwrap(ReadingVault(root, index, store: VaultStore(root: root)))
        var configuration = ReadingConfiguration()
        configuration.showsProperties = false
        return LinkPreviewReading(vault: vault, configuration: configuration)
    }

    /// The words the blocks show, headings and runs of Markdown, nested ones included.
    static func text(of blocks: [RenderedBlock]) -> String {
        blocks.map { block in
            switch block {
            case .markdown(_, let text), .heading(_, _, let text, _): text
            case .callout(_, _, _, _, let body), .transclusion(_, _, _, let body): text(of: body)
            default: ""
            }
        }.joined(separator: "\n")
    }
}

/// What a link's card shows: what the reading view shows for an embed of the same link.
@MainActor
final class LinkPreviewReadingTests: XCTestCase {
    private var reading: LinkPreviewReading!

    override func setUp() async throws {
        reading = try await LinkPreviewTestVault.reading(for: self)
    }

    private func content(_ target: String, isWiki: Bool = true, from source: String = "Note.md") async throws -> LinkPreviewContent? {
        let request = LinkPreviewRequest(target: target, isWiki: isWiki, sourceNote: try VaultPath(source), anchor: .zero, trigger: .hover, source: .editor)
        return await reading.content(for: request)
    }

    private func requiredContent(_ target: String, isWiki: Bool = true, from source: String = "Note.md") async throws -> LinkPreviewContent {
        let found = try await content(target, isWiki: isWiki, from: source)
        return try XCTUnwrap(found, "\(target) has a card.")
    }

    func testANoteShowsWholeWithoutItsProperties() async throws {
        let content = try await requiredContent("Other")
        XCTAssertEqual(content.path, try VaultPath("Other.md"))
        XCTAssertNil(content.subpath)
        XCTAssertEqual(content.title, "Other")
        let text = LinkPreviewTestVault.text(of: content.blocks)
        XCTAssertTrue(text.contains("Intro.") && text.contains("Later text."), text)
        XCTAssertFalse(text.contains("tags"), "The frontmatter is not shown.")
    }

    func testAHeadingOrABlockShowsOnlyItsPart() async throws {
        let section = try await requiredContent("Other#Plan")
        XCTAssertEqual(section.subpath, "Plan")
        XCTAssertEqual(section.title, "Other › Plan")
        let sectionText = LinkPreviewTestVault.text(of: section.blocks)
        XCTAssertTrue(sectionText.contains("The plan"))
        XCTAssertFalse(sectionText.contains("Later text"))
        let block = try await requiredContent("Other#^step")
        XCTAssertTrue(LinkPreviewTestVault.text(of: block.blocks).contains("The plan"))
    }

    func testAHeadingTheNoteDoesNotHaveShowsTheMessageSayingSo() async throws {
        let missing = try await requiredContent("Other#Nowhere")
        guard case .missingSection = try XCTUnwrap(missing.blocks.first) else { return XCTFail("The missing section's message: \(missing.blocks)") }
    }

    func testALinkToAHeadingOfItsOwnNoteShowsThatSection() async throws {
        let own = try await requiredContent("#Here")
        XCTAssertEqual(own.path, try VaultPath("Note.md"))
        XCTAssertTrue(LinkPreviewTestVault.text(of: own.blocks).contains("Local section"))
    }

    func testAMarkdownLinkAndAPictureShowAsTheirEmbedsDo() async throws {
        let markdownLink = try await requiredContent("Other.md", isWiki: false)
        XCTAssertEqual(markdownLink.path, try VaultPath("Other.md"))
        let picture = try await requiredContent("Photo.png")
        XCTAssertEqual(picture.path, try VaultPath("Pictures/Photo.png"))
        guard case .image = try XCTUnwrap(picture.blocks.first) else { return XCTFail("The picture: \(picture.blocks)") }
    }

    func testALinkNothingAnswersAnotherKindOfFileAndANoteTooLargeToEmbedShowNoCard() async throws {
        let nothing = try await content("Nobody")
        XCTAssertNil(nothing)
        let lecture = try await content("Lecture.pdf")
        XCTAssertNil(lecture, "A PDF has no card.")
        let big = try await content("Big")
        XCTAssertNil(big, "A note over \(NotePreviewDocument.maximumEmbeddedNoteBytes) bytes shows as a link when embedded, so it has no card.")
    }
}
