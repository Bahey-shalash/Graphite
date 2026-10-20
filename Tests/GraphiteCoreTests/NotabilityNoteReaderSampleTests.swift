import Foundation
import XCTest
@testable import GraphiteCore

/// Compares the reader with `scripts/notability-reader.py` on the owner's sample notes, which are never in the
/// repository (see `NotebookImportSamples`). Each sample's counts are printed as one `NOTABILITY-COUNTS` line.
final class NotabilityNoteReaderSampleTests: XCTestCase {
    private static let countKeys = ["curves", "points", "highlighter_curves", "shapes", "pictures", "text_runs", "text_utf16_units",
                                    "pdf_pages", "recordings", "timed_curves", "pages"]

    func testCountsEqualTheReferenceReadersOnEverySample() throws {
        let configuration = try NotebookImportSamples.configuration()
        let samplePaths = NotebookImportSamples.samplePaths(withExtension: "note", in: configuration)
        XCTAssertFalse(samplePaths.isEmpty, "the reference counts list no .note sample")
        for samplePath in samplePaths {
            let sampleURL = configuration.samplesFolder.appendingPathComponent(samplePath)
            let reader = try NotabilityNoteReader(archiveBytes: Data(contentsOf: sampleURL, options: .alwaysMapped), limits: .standard)
            let counts = try Self.counts(of: reader)
            let unknownCategories = Set(reader.issues.compactMap(Self.referenceCategory(of:)))
            let swiftOnlyIssues = reader.issues.filter { issue in Self.referenceCategory(of: issue) == nil }
            print("NOTABILITY-COUNTS \(samplePath) \(Self.json(counts: counts, unknownCategories: unknownCategories, swiftOnlyIssueCount: swiftOnlyIssues.count))")
            guard let reference = configuration.referenceCounts[samplePath] else { continue }
            for key in Self.countKeys {
                let expected = reference[key] ?? .null
                let count: Int? = counts[key] ?? nil
                let actual = count.map { count in NotebookImportSamples.JSONValue.number(Double(count)) } ?? .null
                XCTAssertEqual(actual, expected, "\(samplePath): \(key)")
            }
            let referenceUnknown: Set<String>
            if case .list(let categories)? = reference["unknown"] {
                referenceUnknown = Set(categories.compactMap { category in if case .text(let name) = category { name } else { nil } })
            } else {
                referenceUnknown = []
            }
            XCTAssertEqual(unknownCategories, referenceUnknown, "\(samplePath): unknown categories")
            XCTAssertEqual(swiftOnlyIssues, [], "\(samplePath): skipped elements")
        }
    }

    private static func counts(of reader: NotabilityNoteReader) throws -> [String: Int?] {
        var pointCount = 0
        var highlighterCount = 0
        for curveIndex in 0..<reader.curveCount {
            pointCount += try reader.curve(at: curveIndex).points.count
            if try reader.isHighlighter(curveIndex: curveIndex) { highlighterCount += 1 }
        }
        let note = reader.note
        return ["curves": reader.curveCount, "points": pointCount, "highlighter_curves": highlighterCount, "shapes": note.shapes.count,
                "pictures": note.pictures.count, "text_runs": note.typedText.runs.count, "text_utf16_units": note.typedText.text.utf16.count,
                "pdf_pages": note.importedPDFPages.count, "recordings": note.recordings.count, "timed_curves": note.playbackEvents.count,
                "pages": reader.pageCount]
    }

    /// The reference reader's name for the category of an issue; nil for what only this reader reports.
    private static func referenceCategory(of issue: NotabilityReadingIssue) -> String? {
        switch issue {
        case .unknownKey(let context, _):
            switch context {
            case .session: "session keys"
            case .richText: "rich text keys"
            case .ink: "ink keys"
            case .picture: "picture keys"
            case .textAttributes: "text attribute keys"
            case .shape: "shape keys"
            case .pageLayout: "page layout keys"
            }
        case .sessionFormatNotSupported: "session format"
        case .reflowStateUnknown: "reflow states"
        case .curveStyleUnknown: "curve styles"
        case .shapeKindUnknown: "shape kinds"
        case .mediaClassUnknown: "media classes"
        case .playbackEventWithoutCurve: "playback events"
        case .paperSizeUnknown: "paper sizes"
        case .pictureSkipped, .shapesSkipped, .shapeSkipped, .perKnotArrayIgnored, .textRunColorNotReadable, .pageWidthNotUsable, .textRunSkipped,
             .pageLayoutSkipped, .playbackEventsSkipped, .recordingsSkipped, .archivePathNotValid:
            nil
        }
    }

    private static func json(counts: [String: Int?], unknownCategories: Set<String>, swiftOnlyIssueCount: Int) -> String {
        let fields = countKeys.map { key in "\"\(key)\": \((counts[key] ?? nil).map(String.init) ?? "null")" }
        let unknown = unknownCategories.sorted().map { category in "\"\(category)\"" }.joined(separator: ", ")
        return "{" + (fields + ["\"unknown\": [\(unknown)]", "\"swift_only_issues\": \(swiftOnlyIssueCount)"]).joined(separator: ", ") + "}"
    }
}
