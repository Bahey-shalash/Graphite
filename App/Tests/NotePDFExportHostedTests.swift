/**
 * File: NotePDFExportHostedTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: A note exported to PDF inside the iPad app: pages that end between lines with headings kept with
 *              their text, a sample lecture note's text, outline, links and picture read back, light colours
 *              while the app is dark, and the sheet's preview, options and export.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 21/10/2026
 */

#if os(iOS)
import XCTest
import SwiftUI
import PDFKit
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

@MainActor
final class NotePDFExportHostedTests: XCTestCase {
    private var vaultDirectory: URL?
    private var index: VaultIndex?

    override func tearDown() async throws {
        index = nil
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) } // Best-effort removal of a temporary folder.
        vaultDirectory = nil
    }

    private static let sampleNote = """
        # Signals and Systems

        A signal is sampled at the rate $f_s$, as the [lecture notes](https://example.com/notes) explain.

        $$
        x[n] = x(nT)
        $$

        > [!tip]- Folded remark
        > Folded callouts print open.

        | Rate | Period |
        | --- | --- |
        | 8 kHz | 125 µs |
        | 44.1 kHz | 22.7 µs |

        ```c
        int rate = 44100;
        ```

        ![](Figure.png)

        ## Aliasing

        Frequencies above half the rate fold back.
        """

    private func makeVault() throws -> (root: URL, index: VaultIndex) {
        let root = hostedTemporaryLocation(named: "NotePDFHosted")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        vaultDirectory = root
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100))
        let figure = renderer.pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }
        try figure.write(to: root.appendingPathComponent("Figure.png"))
        let index = try VaultIndex(databaseURL: root.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        self.index = index
        return (root, index)
    }

    private func render(_ text: String, options: NotePDFOptions = NotePDFOptions()) async throws -> PDFDocument {
        let (root, index) = try makeVault()
        let source = NotePDFSource(text: text, path: try VaultPath("Signals.md"), vault: try XCTUnwrap(ReadingVault(root, index)),
                                   readingConfiguration: ReadingConfiguration(), title: "Signals",
                                   appearance: NotePDFAppearance(typography: .standard, codeColorTheme: .obsidian, accent: .blue))
        let pdf = try await NotePDFRenderer(source: source, options: options).render { _ in }
        let document = try XCTUnwrap(PDFDocument(data: pdf.data))
        let attachment = XCTAttachment(data: pdf.data, uniformTypeIdentifier: "com.adobe.pdf")
        attachment.name = "Exported note"
        attachment.lifetime = .keepAlways
        add(attachment)
        return document
    }

    func testASampleLectureNotePrintsItsTextOutlineAndLinks() async throws {
        let document = try await render(Self.sampleNote)
        let text = (0..<document.pageCount).compactMap { pageIndex in document.page(at: pageIndex)?.string }.joined(separator: "\n")
        for expected in ["Signals and Systems", "A signal is sampled", "Folded callouts print open.", "44.1 kHz", "int rate = 44100;", "Aliasing",
                         "Frequencies above half the rate fold back."] {
            XCTAssertTrue(text.contains(expected), "The PDF's text has “\(expected)”: \(text)")
        }
        XCTAssertEqual(document.outlineRoot?.child(at: 0)?.label, "Signals and Systems")
        XCTAssertEqual(document.outlineRoot?.child(at: 0)?.child(at: 0)?.label, "Aliasing")
        let links = (0..<document.pageCount).flatMap { pageIndex in document.page(at: pageIndex)?.annotations ?? [] }.compactMap(\.url)
        XCTAssertEqual(links, [URL(string: "https://example.com/notes")])
        // The picture and the formula are drawn: the first page has colour where they are.
        let page = try XCTUnwrap(document.page(at: 0))
        let picture = page.thumbnail(of: page.bounds(for: .cropBox).size, for: .cropBox)
        XCTAssertTrue(try hasTealPixels(picture), "The embedded picture is printed.")
    }

    func testPagesEndBetweenBlocksAndHeadingsStayWithTheirText() async throws {
        let paragraphs = (1...24).map { number in "Paragraph \(number) of the lecture, long enough to fill most of a printed line." }
        let items = (1...50).map { number in "- Item \(number) of the list" }
        let note = paragraphs.joined(separator: "\n\n") + "\n\n## A heading near a break\n\n" + items.joined(separator: "\n") + "\n"
        let document = try await render(note)
        XCTAssertGreaterThan(document.pageCount, 2)
        let pages = (0..<document.pageCount).map { pageIndex in document.page(at: pageIndex)?.string ?? "" }
        let allText = pages.joined(separator: "\n")
        for line in paragraphs + (1...50).map({ number in "Item \(number) of the list" }) {
            XCTAssertEqual(allText.components(separatedBy: line).count - 1, 1, "Printed once and whole: \(line)")
        }
        XCTAssertEqual(pages.firstIndex { page in page.contains("A heading near a break") }, pages.firstIndex { page in page.contains("Item 1 of the list") },
                       "The heading is printed on the page its list starts on.")
    }

    func testThePDFIsLightWhenTheAppIsDark() async throws {
        // The app's windows and the current traits are dark while the note is drawn.
        let appWindows = UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.flatMap(\.windows)
        let previousStyles = appWindows.map(\.overrideUserInterfaceStyle)
        let previousTraits = UITraitCollection.current
        appWindows.forEach { appWindow in appWindow.overrideUserInterfaceStyle = .dark }
        UITraitCollection.current = UITraitCollection(userInterfaceStyle: .dark)
        defer {
            zip(appWindows, previousStyles).forEach { appWindow, style in appWindow.overrideUserInterfaceStyle = style }
            UITraitCollection.current = previousTraits
        }
        let document = try await render(Self.sampleNote)
        let page = try XCTUnwrap(document.page(at: 0))
        let picture = page.thumbnail(of: page.bounds(for: .cropBox).size, for: .cropBox)
        let (average, darkest) = try luminance(of: picture)
        XCTAssertGreaterThan(average, 0.85, "A white page.")
        XCTAssertLessThan(darkest, 0.25, "Dark text.")
    }

    func testTheSheetPreviewsTheFirstPagesFollowsItsOptionsAndMakesThePDF() async throws {
        let (root, index) = try makeVault()
        let suiteName = "NotePDFExportHostedTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let note = (1...60).map { number in "Paragraph \(number) of the lecture, long enough to fill most of a printed line." }.joined(separator: "\n\n")
        let source = NotePDFSource(text: "# Lecture\n\n" + note, path: try VaultPath("Lecture.md"), vault: try XCTUnwrap(ReadingVault(root, index)),
                                   readingConfiguration: ReadingConfiguration(), title: "Lecture",
                                   appearance: NotePDFAppearance(typography: .standard, codeColorTheme: .obsidian, accent: .blue))
        let export = NotePDFExport(source: source, defaults: NotePDFExportDefaults(defaults: defaults), purpose: .save)
        let controller = UIHostingController(rootView: NotePDFExportSheet(export: export))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let sheetWindow = UIWindow(windowScene: scene)
        sheetWindow.frame = scene.coordinateSpace.bounds
        sheetWindow.rootViewController = controller
        sheetWindow.makeKeyAndVisible()
        defer { sheetWindow.isHidden = true }

        try await waitUntil(timeoutSeconds: 20) { export.previewPages.count == NotePDFExport.previewPageCount && !export.isPreparingPreview }
        let portraitPage = try XCTUnwrap(export.previewPages.first?.image)
        XCTAssertLessThan(portraitPage.width, portraitPage.height, "A4 portrait.")
        attachScreenshot(of: sheetWindow, named: "Export to PDF sheet")

        export.options.orientation = .landscape
        try await waitUntil(timeoutSeconds: 20) {
            !export.isPreparingPreview && (export.previewPages.first.map { page in page.image.width > page.image.height } ?? false)
        }

        export.export()
        try await waitUntil(timeoutSeconds: 30) { if case .saving = export.phase { true } else { false } }
        guard case .saving(let document) = export.phase else { return XCTFail("The PDF is made and waits to be saved.") }
        let pdf = try XCTUnwrap(PDFDocument(data: document.data))
        XCTAssertGreaterThan(pdf.pageCount, NotePDFExport.previewPageCount)
        let firstPageSize = try XCTUnwrap(pdf.page(at: 0)?.bounds(for: .cropBox).size)
        XCTAssertGreaterThan(firstPageSize.width, firstPageSize.height, "Exported in the orientation chosen.")
        XCTAssertEqual(NotePDFExportDefaults(defaults: defaults).options.orientation, .landscape, "The options are remembered for the next export.")
    }

    private func attachScreenshot(of window: UIWindow, named name: String) {
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: Pixels

    private func pixels(of picture: UIImage) throws -> (bytes: [UInt8], count: Int) {
        let image = try XCTUnwrap(picture.cgImage)
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return (bytes, width * height)
    }

    private func luminance(of picture: UIImage) throws -> (average: Double, darkest: Double) {
        let (bytes, count) = try pixels(of: picture)
        var total = 0.0, darkest = 1.0
        for pixelIndex in 0..<count {
            let offset = pixelIndex * 4
            let value = (0.2126 * Double(bytes[offset]) + 0.7152 * Double(bytes[offset + 1]) + 0.0722 * Double(bytes[offset + 2])) / 255
            total += value
            darkest = min(darkest, value)
        }
        return (total / Double(max(count, 1)), darkest)
    }

    private func hasTealPixels(_ picture: UIImage) throws -> Bool {
        let (bytes, count) = try pixels(of: picture)
        return (0..<count).contains { pixelIndex in
            let offset = pixelIndex * 4
            return bytes[offset] < 120 && bytes[offset + 1] > 140 && bytes[offset + 2] > 160
        }
    }
}
#endif
