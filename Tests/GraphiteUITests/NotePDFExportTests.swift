/**
 * File: NotePDFExportTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: One note's export: made to print with the remembered options, which printing leaves unchanged,
 *              and the words a failure is reported with.
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
@testable import GraphiteUI
import GraphiteTestSupport

@MainActor
final class NotePDFExportTests: XCTestCase {
    private var vault: TemporaryVault!
    private var index: VaultIndex!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "NotePDFExportVault", for: self)
        index = try VaultIndex(databaseURL: vault.cacheDirectory.appendingPathComponent("index.sqlite"))
        defaults = try IsolatedDeviceState.make(prefix: "NotePDFExportTests", for: self).preferences
    }

    override func tearDown() async throws {
        index = nil
        defaults = nil
        try? FileManager.default.removeItem(at: vault.cacheDirectory) // Best-effort removal of a temporary folder.
    }

    private func makeExport(purpose: NotePDFPurpose) throws -> NotePDFExport {
        let source = NotePDFSource(text: "# Lecture\n\nThe body of the note.", path: try VaultPath("Lecture.md"),
                                   vault: try XCTUnwrap(ReadingVault(vault.root, index)), readingConfiguration: ReadingConfiguration(), title: "Lecture",
                                   appearance: NotePDFAppearance(typography: .standard, codeColorTheme: .obsidian, accent: .blue))
        return NotePDFExport(source: source, defaults: NotePDFExportDefaults(defaults: defaults), purpose: purpose)
    }

    func testAPDFMadeToPrintUsesTheRememberedOptionsAndLeavesThemAsTheyWere() async throws {
        var remembered = NotePDFOptions()
        remembered.orientation = .landscape
        NotePDFExportDefaults(defaults: defaults).remember(remembered)
        let export = try makeExport(purpose: .print)
        XCTAssertEqual(export.options.orientation, .landscape)
        export.options.pageSize = .a5
        export.export()
        try await waitUntil { if case .printing = export.phase { true } else { false } }
        guard case .printing(let pdf) = export.phase else { return XCTFail("The PDF waits for the print panel.") }
        let page = try XCTUnwrap(PDFDocument(data: pdf.data)?.page(at: 0))
        XCTAssertTrue(page.string?.contains("The body of the note.") ?? false)
        XCTAssertGreaterThan(page.bounds(for: .cropBox).width, page.bounds(for: .cropBox).height, "Printed in the orientation remembered.")
        XCTAssertTrue(export.isFinishedPrinting)
        XCTAssertEqual(NotePDFExportDefaults(defaults: defaults).options, remembered, "Printing does not change the options remembered for exports.")
    }

    func testStoppingAPrintEndsItsProgress() async throws {
        let export = try makeExport(purpose: .print)
        XCTAssertFalse(export.isFinishedPrinting, "Nothing started yet.")
        export.export()
        export.cancelExport()
        try await waitUntil { export.isFinishedPrinting }
        if case .printing = export.phase { XCTFail("A stopped print hands nothing to the print panel.") }
    }

    func testFailuresAreWordedForThePerson() {
        XCTAssertEqual(NotePDFExport.message(for: NotePDFExportError.noteNotText), "The note could not be read, so no PDF was made.")
        XCTAssertEqual(NotePDFExport.message(for: NotePDFExportError.drawingUnavailable), "The PDF could not be made. Try again, or export with other options.")
    }
}
