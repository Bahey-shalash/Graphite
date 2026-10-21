import Foundation
import XCTest
@testable import NotebookImport

/// The keys a Notability reader accepts without a report come from the key enums the reads use.
final class NotabilityKnownKeysTests: XCTestCase {
    func testEachKnownSetHoldsEveryCaseOfItsKeyEnumAndNothingElse() {
        XCTAssertEqual(NotabilityKnownKeys.session, Set(NotabilitySessionKey.allCases.map(\.rawValue)))
        XCTAssertEqual(NotabilityKnownKeys.richText, Set(NotabilityRichTextKey.allCases.map(\.rawValue)))
        XCTAssertEqual(NotabilityKnownKeys.picture, Set(NotabilityPictureKey.allCases.map(\.rawValue)))
        XCTAssertEqual(NotabilityKnownKeys.textAttributes, Set(NotabilityTextAttributeKey.allCases.map(\.rawValue)))
        XCTAssertEqual(NotabilityKnownKeys.shape, Set(NotabilityShapeKey.allCases.map(\.rawValue)))
        XCTAssertEqual(NotabilityKnownKeys.pageLayout, Set(NotabilityPageLayoutKey.allCases.map(\.rawValue)))
    }

    func testTheInkKeysAreItsOwnKeysAndTheTenPackedCurveArraysButNotTheEventArrays() {
        let curveArrays: [NotabilityPackedArray] = [.curvePointCounts, .curvePoints, .curveWidths, .curveColors, .curveStyles, .curveUUIDs,
                                                    .knotWidthFactors, .knotForces, .knotAltitudeAngles, .knotAzimuthUnitVectors]
        XCTAssertEqual(NotabilityPackedArray.allCases.filter(\.isStoredInInk), curveArrays)
        XCTAssertEqual(NotabilityKnownKeys.ink.count, NotabilityInkKey.allCases.count + curveArrays.count)
        for key in curveArrays.map(\.rawValue) + ["numcurves", "numpoints", "numfractionalwidths", "shapes"] {
            XCTAssertTrue(NotabilityKnownKeys.ink.contains(key), key)
        }
        XCTAssertFalse(NotabilityKnownKeys.ink.contains(NotabilityPackedArray.eventTimestamps.rawValue))
    }

    func testTheKnownSetsHoldTheKeysTheFormatNotesAccountFor() {
        XCTAssertEqual([NotabilityKnownKeys.session.count, NotabilityKnownKeys.richText.count, NotabilityKnownKeys.ink.count,
                        NotabilityKnownKeys.picture.count, NotabilityKnownKeys.textAttributes.count, NotabilityKnownKeys.shape.count,
                        NotabilityKnownKeys.pageLayout.count], [19, 11, 17, 24, 5, 7, 6])
        XCTAssertTrue(NotabilityKnownKeys.session.contains("NBNoteTakingSessionBundleVersionNumberKey"))
        XCTAssertTrue(NotabilityKnownKeys.richText.contains("Handwriting Overlay"))
        XCTAssertTrue(NotabilityKnownKeys.picture.contains("handwritingZIndecesKey"))
        XCTAssertTrue(NotabilityKnownKeys.shape.contains("controlPoint1"))
    }

    func testTheKeysTheReadsUseAreKnownToTheirPart() {
        XCTAssertTrue(NotabilitySessionKey.knownKeys.contains(NotabilitySessionKey.paperLayoutModel.rawValue))
        XCTAssertTrue(NotabilityRichTextKey.knownKeys.contains(NotabilityRichTextKey.pageLayoutArray.rawValue))
        XCTAssertTrue(NotabilityPictureKey.knownKeys.contains(NotabilityPictureKey.unscaledContentSize.rawValue))
        XCTAssertTrue(NotabilityPageLayoutKey.knownKeys.contains(NotabilityPageLayoutKey.pdfFileName.rawValue))
    }
}
