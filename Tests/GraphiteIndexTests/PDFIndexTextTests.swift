import XCTest
@testable import GraphiteIndex
@testable import GraphiteCore
import GraphiteTestSupport

/// Search finds a PDF by the text of its text boxes: read by a scan and by a refresh of the
/// file, from the `/FreeText` annotations only, as plain text with no links or tags.
final class PDFIndexTextTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    /// A one-page PDF, written by hand, with the given `/FreeText` contents and one sticky note.
    private func pdfData(boxTexts: [String]) -> Data {
        let annotations = boxTexts.map { text in "<< /Type /Annot /Subtype /FreeText /Rect [10 10 200 60] /Contents (\(text)) >>" }
            + ["<< /Type /Annot /Subtype /Text /Rect [0 0 10 10] /Contents (sticky secret) >>"]
        let firstAnnotationNumber = 4
        let references = annotations.indices.map { annotationIndex in "\(firstAnnotationNumber + annotationIndex) 0 R" }.joined(separator: " ")
        let objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
                       "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Annots [\(references)] >>"] + annotations
        var file = "%PDF-1.7\n"
        var offsets: [Int] = []
        for (objectIndex, object) in objects.enumerated() {
            offsets.append(file.utf8.count)
            file += "\(objectIndex + 1) 0 obj\n\(object)\nendobj\n"
        }
        let crossReferenceOffset = file.utf8.count
        file += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { file += String(format: "%010d 00000 n \n", offset) }
        file += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(crossReferenceOffset)\n%%EOF\n"
        return Data(file.utf8)
    }

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "PDFIndexText", for: self).root
        try pdfData(boxTexts: ["Fourier transform of a #notatag [[not a link]]"]).write(to: vault.appendingPathComponent("Lecture 3.pdf"))
        try Data("A note about Laplace.".utf8).write(to: vault.appendingPathComponent("Note.md"))
        index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
    }

    func testAScanMakesThePDFsTextBoxesSearchable() async throws {
        let found = try await index.search("Fourier")
        XCTAssertEqual(found.results.map(\.path.rawValue), ["Lecture 3.pdf"])
        let notFound = try await index.search("content:\"sticky secret\"")
        XCTAssertTrue(notFound.results.isEmpty, "Only text boxes are read, not other annotations.")
    }

    func testTheTextOfABoxIsNotReadAsMarkdown() async throws {
        let tags = try await index.nestedTagCounts()
        XCTAssertFalse(tags.contains { tag in tag.tag.contains("notatag") })
        let backlinks = try await index.backlinks(to: VaultPath("not a link.md"))
        XCTAssertTrue(backlinks.isEmpty)
    }

    func testARefreshReadsTheNewTextOfAChangedPDF() async throws {
        try pdfData(boxTexts: ["Convolution theorem", "and a second box"]).write(to: vault.appendingPathComponent("Lecture 3.pdf"))
        try await index.refresh(paths: [VaultPath("Lecture 3.pdf")], root: vault)
        let found = try await index.search("Convolution")
        XCTAssertEqual(found.results.map(\.path.rawValue), ["Lecture 3.pdf"])
        let second = try await index.search("content:\"second box\"")
        XCTAssertEqual(second.results.map(\.path.rawValue), ["Lecture 3.pdf"])
        let old = try await index.search("content:Fourier")
        XCTAssertTrue(old.results.isEmpty)
    }

    func testAPDFThatDoesNotOpenStaysInTheInventoryWithoutText() async throws {
        try Data("not a pdf".utf8).write(to: vault.appendingPathComponent("Broken.pdf"))
        let report = try await index.reconcile(root: vault)
        XCTAssertTrue(report.failedPaths.contains { failure in failure.hasPrefix("Broken.pdf") })
        let named = try await index.search("Broken")
        XCTAssertEqual(named.results.map(\.path.rawValue), ["Broken.pdf"])
    }
}
