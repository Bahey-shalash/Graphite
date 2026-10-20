import Foundation
import XCTest
@testable import GraphiteCore

/// The Swift reader against the reference reader on the owner's real Goodnotes notebooks. The notebooks are personal
/// and never in the repository, so this test is skipped unless `GRAPHITE_IMPORT_SAMPLES` and
/// `GRAPHITE_IMPORT_REFERENCE_COUNTS` point at them and at `scripts/import-reference-counts.py`'s output (see
/// `NotebookImportSamples`).
final class GoodnotesNotebookReaderSampleTests: XCTestCase {
    func testEverySampleNotebookHasTheReferenceReadersCounts() throws {
        let configuration = try NotebookImportSamples.configuration()
        let samplePaths = NotebookImportSamples.samplePaths(withExtension: "goodnotes", in: configuration)
        XCTAssertFalse(samplePaths.isEmpty)
        for samplePath in samplePaths {
            let archiveBytes = try Data(contentsOf: configuration.samplesFolder.appendingPathComponent(samplePath), options: .alwaysMapped)
            let counts = try Self.counts(of: GoodnotesNotebookReader(archiveBytes: archiveBytes, limits: .standard))
            print("GOODNOTES-COUNTS \(samplePath) \(Self.json(counts))")
            let reference = try XCTUnwrap(configuration.referenceCounts[samplePath])
            XCTAssertEqual(Set(counts.keys), Set(reference.keys), samplePath)
            for (name, value) in counts {
                XCTAssertEqual(value, reference[name], "\(name) of \(samplePath)")
            }
        }
    }

    private typealias Counts = [String: NotebookImportSamples.JSONValue]

    private static func counts(of reader: GoodnotesNotebookReader) throws -> Counts {
        var numbers = ["pages": 0, "strokes": 0, "points": 0, "pictures": 0, "text_boxes": 0, "fills": 0, "sticky_notes": 0,
                       "rtf_text_elements": 0, "outline_segments": 0, "bookmarked_pages": 0]
        var unknownCategories = Set(reader.notebook.issues.compactMap(referenceCategory))
        for pageIndex in 0..<reader.pageCount {
            let page = try reader.page(at: pageIndex)
            numbers["pages", default: 0] += 1
            numbers["bookmarked_pages", default: 0] += page.descriptor.isBookmarked ? 1 : 0
            unknownCategories.formUnion(page.issues.compactMap(referenceCategory))
            for element in page.elements { count(element.content, into: &numbers) }
        }
        var counts = numbers.mapValues { number in NotebookImportSamples.JSONValue.number(Double(number)) }
        counts["outline_entries"] = .number(Double(reader.notebook.outlineEntries.count))
        counts["recordings"] = .number(Double(reader.notebook.recordings.count))
        counts["schema_version"] = reader.notebook.schemaVersion.map { version in .number(Double(version)) } ?? .null
        counts["unknown"] = .list(unknownCategories.sorted().map(NotebookImportSamples.JSONValue.text))
        return counts
    }

    private static func count(_ content: GoodnotesElementContent, into numbers: inout [String: Int]) {
        switch content {
        case .stroke(let stroke):
            if case .unknownLayout = stroke.path { return }
            numbers["strokes", default: 0] += 1
            numbers["points", default: 0] += pointCount(stroke.path)
            numbers["outline_segments", default: 0] += outlineSegmentCount(stroke.path)
        case .picture: numbers["pictures", default: 0] += 1
        case .textBox, .rtfTextBox: numbers["text_boxes", default: 0] += 1
        case .shapeFill: numbers["fills", default: 0] += 1
        case .stickyNote: numbers["sticky_notes", default: 0] += 1
        case .rtfTextElement: numbers["rtf_text_elements", default: 0] += 1
        // The reference reader drops what it does not know, so its counts leave these out.
        case .unknown: break
        }
    }

    /// Per subpath its start and two points per curve, as `scripts/import-reference-counts.py` counts them.
    private static func pointCount(_ path: GoodnotesStrokePath) -> Int {
        switch path {
        case .constantWidth(let path): path.subpaths.reduce(0) { total, subpath in total + 1 + 2 * subpath.curves.count }
        case .varyingWidth(let path): path.centerLine.map { centerLine in 1 + 2 * centerLine.curves.count } ?? 0
        case .olderVaryingWidth: 0
        case .pencil(let path): path.subpaths.reduce(0) { total, subpath in total + 1 + 2 * subpath.curves.count }
        case .unknownLayout: 0
        }
    }

    private static func outlineSegmentCount(_ path: GoodnotesStrokePath) -> Int {
        switch path {
        case .varyingWidth(let path): path.outline.count
        case .olderVaryingWidth(let path): path.outline.count
        case .constantWidth, .pencil, .unknownLayout: 0
        }
    }

    /// The reference reader's name for the category of an issue. Facts the reference reader does not report (an
    /// attachment or paper missing from the log, an unsafe path) have none; a part the Swift reader skipped is its own
    /// category, so that it fails the comparison.
    private static func referenceCategory(_ issue: GoodnotesReadingIssue) -> String? {
        switch issue {
        case .schemaVersionNotKnown: "schema version"
        case .eventKindNotKnown: "event kinds"
        case .elementHeaderFieldNotKnown: "element header fields"
        case .elementKindNotKnown: "element kinds"
        case .elementFieldNotKnown(let elementKind, _): "element kind \(elementKind) fields"
        case .strokePathFormatNotKnown: "stroke path formats"
        case .strokePathHeaderNotKnown: "stroke path header"
        case .pencilPathTrailingArrayNotEmpty: "pencil path"
        case .shapeFieldNotKnown: "shape fields"
        case .bodyWithoutHeader, .elementMissingFromMemberList: "elements"
        case .attachmentPathNotValid, .attachmentNotInLog, .paperNotInLog: nil
        case .layerIdentifierNotDerivable, .pagePositionNotReadable, .eventSkipped, .recordsTruncated, .recordSkipped, .elementSkipped,
             .layerUnreadable:
            "skipped by the Swift reader: \(issue)"
        }
    }

    private static func json(_ counts: Counts) -> String {
        counts.keys.sorted().map { name in "\"\(name)\": \(text(counts[name] ?? .null))" }.joined(separator: ", ")
    }

    private static func text(_ value: NotebookImportSamples.JSONValue) -> String {
        switch value {
        case .number(let number): String(Int(number))
        case .text(let text): "\"\(text)\""
        case .list(let values): "[" + values.map(text).joined(separator: ", ") + "]"
        case .null: "null"
        }
    }
}
