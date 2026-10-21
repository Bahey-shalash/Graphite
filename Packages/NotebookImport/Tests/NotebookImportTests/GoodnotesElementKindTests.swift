import Foundation
import XCTest
@testable import NotebookImport

/// The fields each Goodnotes element kind accepts without a report come from the kind's field enum, the same cases
/// the decoder reads by.
final class GoodnotesElementKindTests: XCTestCase {
    private static let allKinds: [GoodnotesElementKind] = [.picture, .stroke, .rtfTextBox, .shapeFill, .rtfTextElement, .stickyNote, .textBox]

    func testEveryCaseOfAKindsFieldEnumIsKnownToThatKind() {
        XCTAssertEqual(GoodnotesElementKind.stroke.knownFieldNumbers, GoodnotesStrokeField.knownFieldNumbers)
        XCTAssertEqual(GoodnotesElementKind.picture.knownFieldNumbers, GoodnotesPictureField.knownFieldNumbers)
        XCTAssertEqual(GoodnotesElementKind.shapeFill.knownFieldNumbers, GoodnotesShapeFillField.knownFieldNumbers)
        XCTAssertEqual(GoodnotesElementKind.rtfTextBox.knownFieldNumbers, GoodnotesRTFTextBoxField.knownFieldNumbers)
        XCTAssertEqual(GoodnotesElementKind.rtfTextElement.knownFieldNumbers, GoodnotesRTFTextElementField.knownFieldNumbers)
        XCTAssertEqual(GoodnotesElementKind.stickyNote.knownFieldNumbers, GoodnotesStickyNoteField.knownFieldNumbers)
        XCTAssertEqual(GoodnotesElementKind.textBox.knownFieldNumbers, GoodnotesTextBoxField.knownFieldNumbers)
    }

    func testTheKnownFieldsAreTheOnesTheFormatNotesAccountFor() {
        XCTAssertEqual(GoodnotesElementKind.stroke.knownFieldNumbers, [1, 2, 3, 4, 5, 6, 7, 9, 10, 14, 15, 20, 21])
        XCTAssertEqual(GoodnotesElementKind.picture.knownFieldNumbers, [1, 2, 3, 4, 5, 6, 7, 14, 15, 18])
        XCTAssertEqual(GoodnotesElementKind.stickyNote.knownFieldNumbers, [1, 2, 3, 7, 20, 21, 30, 31, 32, 33, 40, 41])
        XCTAssertEqual(GoodnotesShapeField.knownFieldNumbers, [1, 2, 3, 4, 5, 15])
        XCTAssertEqual(GoodnotesElementHeaderField.knownFieldNumbers, [1, 2, 3, 4, 6, 7, 8, 9, 10, 14, 16])
    }

    func testEveryKindsDrawingPositionFieldIsOneOfItsKnownFields() {
        for kind in Self.allKinds {
            XCTAssertTrue(kind.knownFieldNumbers.contains(kind.positionFieldNumber), "Kind \(kind.rawValue) must know its position field.")
        }
    }

    func testAFieldTheDecoderReadsIsNotReportedAndAnotherFieldIs() throws {
        // Kind 12: field 3 is the RTF the decoder reads, field 25 is known and not read, field 99 is in no layout.
        let record: [UInt8] = [0x1A, 0x00, 0xC8, 0x01, 0x01, 0x98, 0x06, 0x01]
        let decoder = GoodnotesElementDecoder(limits: .standard, attachments: [:])
        var issues = GoodnotesIssueList()
        let content = try decoder.content(of: .rtfTextElement, fields: GoodnotesRecordFields(parsing: record[...]), issues: &issues)
        guard case .rtfTextElement(let rtf) = content else { return XCTFail("The record is a text element.") }
        XCTAssertEqual(rtf, "")
        XCTAssertEqual(issues.issues, [.elementFieldNotKnown(elementKind: 12, fieldNumber: 99)])
    }
}
