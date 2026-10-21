/**
 * File: NotePDFRendererTests.swift
 * --------------------------------
 * Layer: Tests
 * Description: A note exported to PDF, read back with PDFKit: its text on pages that never cut or repeat a line,
 *              headings kept with their text, the outline, title and links, light colours, and the note untouched.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import XCTest
import SwiftUI
import PDFKit
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class NotePDFRendererTests: XCTestCase {
    private var vault: TemporaryVault!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "NotePDFVault", for: self)
        index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault.cacheDirectory) // Best-effort removal of a temporary folder.
    }

    /// A lecture note with what lecture notes hold: math, a folded callout, a table, code, a
    /// picture, a footnote and a web link.
    static let sampleNote = """
        # Signals and Systems

        A signal is sampled at the rate $f_s$, as the [lecture notes](https://example.com/notes) explain.[^1]

        $$
        x[n] = x(nT)
        $$

        > [!note]- Folded remark
        > Folded callouts print open.

        | Rate | Period |
        | --- | --- |
        | 8 kHz | 125 µs |
        | 44.1 kHz | 22.7 µs |

        ```swift
        let rate = 44_100
        ```

        ![](Figure.png)

        ## Aliasing

        Frequencies above half the rate fold back.

        [^1]: Nyquist, 1928.
        """

    private func source(_ text: String, name: String = "Signals") throws -> NotePDFSource {
        NotePDFSource(text: text, path: try VaultPath("\(name).md"), vault: try XCTUnwrap(ReadingVault(vault.root, index)),
                      readingConfiguration: ReadingConfiguration(), title: name,
                      appearance: NotePDFAppearance(typography: .standard, codeColorTheme: .obsidian, accent: .blue))
    }

    private func render(_ text: String, options: NotePDFOptions = NotePDFOptions()) async throws -> PDFDocument {
        let pdf = try await NotePDFRenderer(source: try source(text), options: options).render { _ in }
        let document = try XCTUnwrap(PDFDocument(data: pdf.data))
        XCTAssertEqual(document.pageCount, pdf.pageCount)
        return document
    }

    private func pageTexts(_ document: PDFDocument) -> [String] {
        (0..<document.pageCount).map { pageIndex in document.page(at: pageIndex)?.string ?? "" }
    }

    private func writeFigure() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        try vault.writeFile("Figure.png", data: try ImageEncoding.pngData(from: try XCTUnwrap(context.makeImage())))
    }

    func testASampleNotePrintsItsTextTitleOutlineAndLinks() async throws {
        try writeFigure()
        let document = try await render(Self.sampleNote)
        let text = pageTexts(document).joined(separator: "\n")
        for expected in ["Signals", "Signals and Systems", "A signal is sampled", "lecture notes", "Folded callouts print open.", "44.1 kHz", "22.7 µs",
                         "let rate = 44_100", "Aliasing", "Frequencies above half the rate fold back.", "Nyquist, 1928."] {
            XCTAssertTrue(text.contains(expected), "The PDF's text has “\(expected)”: \(text)")
        }
        XCTAssertEqual(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, "Signals")
        XCTAssertNil(document.documentAttributes?[PDFDocumentAttribute.authorAttribute], "The author is left empty.")
        let outline = try XCTUnwrap(document.outlineRoot)
        XCTAssertEqual(outline.numberOfChildren, 1)
        XCTAssertEqual(outline.child(at: 0)?.label, "Signals and Systems")
        XCTAssertEqual(outline.child(at: 0)?.child(at: 0)?.label, "Aliasing", "Lower headings sit under the heading above them.")
        let links = (0..<document.pageCount).flatMap { pageIndex in document.page(at: pageIndex)?.annotations ?? [] }.compactMap(\.url)
        XCTAssertEqual(links, [URL(string: "https://example.com/notes")])
        attachPages(of: document, named: "Sample note")
    }

    func testPagesEndBetweenLinesAndEveryLineIsPrintedOnce() async throws {
        let paragraphs = (1...30).map { number in "Paragraph \(number) of the lecture, long enough to fill most of a printed line." }
        let items = (1...60).map { number in "- Item \(number) of the list" }
        let rows = (1...40).map { number in "| Row \(number) | \(number * 3) |" }
        let note = paragraphs.joined(separator: "\n\n") + "\n\n## A heading near a break\n\n" + items.joined(separator: "\n")
            + "\n\n| Name | Value |\n| --- | --- |\n" + rows.joined(separator: "\n") + "\n"
        let document = try await render(note)
        XCTAssertGreaterThan(document.pageCount, 3)
        let pages = pageTexts(document)
        let allText = pages.joined(separator: "\n")
        let itemTexts = items.map { item in String(item.dropFirst(2)) }
        let rowNames = (1...40).map { number in "Row \(number) " }
        for line in paragraphs + itemTexts + rowNames {
            XCTAssertEqual(allText.components(separatedBy: line).count - 1, 1, "Printed once: \(line)")
        }
        // The table's header is printed above its rows on every page it spans.
        let pagesWithRows = pages.filter { page in page.contains("Row ") }
        XCTAssertGreaterThan(pagesWithRows.count, 1)
        XCTAssertTrue(pagesWithRows.allSatisfy { page in page.contains("Name") && page.contains("Value") })
        // The list goes on in order from page to page.
        let itemOrder = (1...60).compactMap { number in allText.range(of: "Item \(number) of the list")?.lowerBound }
        XCTAssertEqual(itemOrder, itemOrder.sorted())
        // The heading is on the page of the list's first item.
        let headingPage = pages.firstIndex { page in page.contains("A heading near a break") }
        XCTAssertNotNil(headingPage)
        XCTAssertEqual(headingPage, pages.firstIndex { page in page.contains("Item 1 of the list") })
    }

    func testATextTallerThanAPageIsCutBetweenItsLines() async throws {
        let longParagraph = (1...120).map { number in "Sentence \(number) of one very long paragraph." }.joined(separator: " ")
        var options = NotePDFOptions()
        options.pageSize = .a5
        options.includesFileNameAsTitle = false
        let document = try await render(longParagraph, options: options)
        XCTAssertGreaterThan(document.pageCount, 1)
        // Each page's band shows whole lines: every line read back is a full line of words,
        // and the lines of consecutive pages follow on.
        for pageIndex in 0..<document.pageCount {
            let page = try XCTUnwrap(document.page(at: pageIndex))
            let contentBounds = page.bounds(for: .cropBox).insetBy(dx: options.margins.points, dy: options.margins.points)
            let visibleText = page.selection(for: contentBounds)?.string ?? ""
            XCTAssertFalse(visibleText.isEmpty)
            let lineHeights = (page.selection(for: contentBounds)?.selectionsByLine() ?? []).map { line in line.bounds(for: page).height }
            let tallest = lineHeights.max() ?? 0
            XCTAssertTrue(lineHeights.allSatisfy { height in height > tallest * 0.6 }, "No line is cut short at the page's edge on page \(pageIndex + 1).")
        }
    }

    func testThePDFIsLightInDarkModeAndTheNoteIsNotChanged() async throws {
        let notePath = "Signals.md"
        try vault.writeFile(notePath, text: Self.sampleNote)
        let attributesBefore = try FileManager.default.attributesOfItem(atPath: vault.location(of: notePath).path)
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: vault.root.path)
        let document = try await withDarkAppearance { try await self.render(Self.sampleNote) }
        let page = try XCTUnwrap(document.page(at: 0))
        let picture = page.thumbnail(of: page.bounds(for: .cropBox).size, for: .cropBox)
        let brightness = try XCTUnwrap(PictureBrightness(picture))
        XCTAssertGreaterThan(brightness.averageLuminance, 0.85, "A white page.")
        XCTAssertLessThan(brightness.darkestLuminance, 0.25, "Dark text.")
        XCTAssertEqual(try vault.readText(at: notePath), Self.sampleNote)
        let attributesAfter = try FileManager.default.attributesOfItem(atPath: vault.location(of: notePath).path)
        XCTAssertEqual(attributesAfter[.modificationDate] as? Date, attributesBefore[.modificationDate] as? Date)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vault.root.path), filesBefore, "Nothing is written into the vault.")
    }

    func testPropertiesArePrintedOnlyWhenAskedFor() async throws {
        let note = "---\ncourse: EE-330 Digital IC Design\n---\n# Lecture\n\nBody text.\n"
        let withoutProperties = pageTexts(try await render(note)).joined()
        XCTAssertFalse(withoutProperties.contains("EE-330 Digital IC Design"), "Left out by default, as in Obsidian.")
        XCTAssertTrue(withoutProperties.contains("Body text."))
        var options = NotePDFOptions()
        options.includesProperties = true
        let withPropertiesDocument = try await render(note, options: options)
        let withProperties = pageTexts(withPropertiesDocument).joined()
        XCTAssertTrue(withProperties.contains("EE-330 Digital IC Design"), withProperties)
        XCTAssertTrue(withProperties.contains("Body text."), "The text after the properties is printed too.")
    }

    func testCancellingStopsTheExportWithoutAResult() async throws {
        let note = (1...400).map { number in "Paragraph \(number)." }.joined(separator: "\n\n")
        let renderer = NotePDFRenderer(source: try source(note), options: NotePDFOptions())
        let task = Task { try await renderer.render { _ in } }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled export gives no PDF.")
        } catch is CancellationError {
        }
    }

    func testAPreviewDrawsOnlyTheFirstPages() async throws {
        let note = (1...200).map { number in "Paragraph \(number) of a long note." }.joined(separator: "\n\n")
        let preview = try await NotePDFRenderer(source: try source(note), options: NotePDFOptions()).render(pageLimit: 2) { _ in }
        XCTAssertEqual(preview.pageCount, 2)
    }

    // MARK: Helpers

    private func withDarkAppearance<Result>(_ work: () async throws -> Result) async rethrows -> Result {
        #if os(macOS)
        let previous = NSApplication.shared.appearance
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        defer { NSApplication.shared.appearance = previous }
        #endif
        return try await work()
    }

    private func attachPages(of document: PDFDocument, named name: String) {
        let attachment = XCTAttachment(data: document.dataRepresentation() ?? Data(), uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// How light a picture is, from its pixels.
private struct PictureBrightness {
    let averageLuminance: Double
    let darkestLuminance: Double

    #if os(macOS)
    init?(_ picture: NSImage) {
        guard let image = picture.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        self.init(image)
    }
    #else
    init?(_ picture: UIImage) {
        guard let image = picture.cgImage else { return nil }
        self.init(image)
    }
    #endif

    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw, width > 0, height > 0 else { return nil }
        var total = 0.0
        var darkest = 1.0
        for pixelIndex in 0..<(width * height) {
            let offset = pixelIndex * 4
            let luminance = (0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1]) + 0.0722 * Double(pixels[offset + 2])) / 255
            total += luminance
            darkest = min(darkest, luminance)
        }
        averageLuminance = total / Double(width * height)
        darkestLuminance = darkest
    }
}
