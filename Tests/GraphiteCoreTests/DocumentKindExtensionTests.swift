import XCTest
@testable import GraphiteCore

/// Which kind of document a file is, decided by its lowercase extension alone.
final class DocumentKindExtensionTests: XCTestCase {
    private let extensionsByKind: [(kind: DocumentKind, fileExtensions: [String])] = [
        (.markdown, ["md", "markdown"]),
        (.base, ["base"]),
        (.canvas, ["canvas"]),
        (.pdf, ["pdf"]),
        (.image, ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp", "svg"]),
        (.media, ["m4a", "mp3", "wav", "aac", "ogg", "flac", "3gp", "mp4", "mov", "m4v", "webm"]),
    ]

    func testEveryKnownExtensionIsClassifiedAsItsKind() {
        for (kind, fileExtensions) in extensionsByKind {
            for fileExtension in fileExtensions {
                XCTAssertEqual(DocumentKind(fileExtension: fileExtension), kind, fileExtension)
            }
        }
    }

    func testExtensionsInAnyCaseAreClassifiedAsTheirLowercaseForm() {
        for (kind, fileExtensions) in extensionsByKind {
            for fileExtension in fileExtensions {
                XCTAssertEqual(DocumentKind(fileExtension: fileExtension.uppercased()), kind, fileExtension.uppercased())
                XCTAssertEqual(DocumentKind(fileExtension: fileExtension.capitalized), kind, fileExtension.capitalized)
            }
        }
    }

    func testEveryPlayableExtensionIsMediaAndNoExtensionIsBothAudioAndVideo() {
        for fileExtension in DocumentKind.audioFileExtensions.union(DocumentKind.videoFileExtensions) {
            XCTAssertEqual(DocumentKind(fileExtension: fileExtension), .media, fileExtension)
        }
        XCTAssertTrue(DocumentKind.audioFileExtensions.isDisjoint(with: DocumentKind.videoFileExtensions))
    }

    func testAnyOtherExtensionIsOtherEvenWhenItIsAnImageOrNoteTypeNeighbour() {
        for fileExtension in ["", "txt", "json", "bmp", "heif", "tif", "mkv", "opus", "docx", "md ", ".md", "mdx", "pdfx", "excalidraw", "canvas.bak"] {
            XCTAssertEqual(DocumentKind(fileExtension: fileExtension), .other, "'\(fileExtension)'")
        }
    }

    func testAPathIsClassifiedByItsLastExtensionInLowercase() throws {
        let expectedKindsByPath: [(path: String, kind: DocumentKind)] = [
            ("Notes/Lecture.MD", .markdown),
            ("Notes/Lecture.Markdown", .markdown),
            ("Scans/page 1.JPEG", .image),
            ("Scans/archive.tar.pdf", .pdf),
            ("Scans/archive.pdf.txt", .other),
            ("Audio/take 3.M4A", .media),
            ("Board.Canvas", .canvas),
            ("Table.BASE", .base),
            ("README", .other),
            (".hidden", .other),
        ]
        for (path, kind) in expectedKindsByPath {
            XCTAssertEqual(DocumentKind(path: try VaultPath(path)), kind, path)
        }
    }

    func testKindsKeepTheirStoredNames() {
        XCTAssertEqual(DocumentKind.markdown.rawValue, "markdown")
        XCTAssertEqual(DocumentKind.pdf.rawValue, "pdf")
        XCTAssertEqual(DocumentKind.image.rawValue, "image")
        XCTAssertEqual(DocumentKind.media.rawValue, "media")
        XCTAssertEqual(DocumentKind.base.rawValue, "base")
        XCTAssertEqual(DocumentKind.canvas.rawValue, "canvas")
        XCTAssertEqual(DocumentKind.other.rawValue, "other")
    }
}
