import XCTest
@testable import GraphiteUI

/// The device settings of PDF annotation, kept under these names.
@MainActor
final class PDFAnnotationPreferenceKeyTests: XCTestCase {
    func testThePDFSettingsAreKeptUnderTheseNames() {
        XCTAssertEqual(PDFAnnotationPreferenceKey.drawsWithFinger, "GraphitePDFDrawsWithFinger")
        XCTAssertEqual(PDFAnnotationPreferenceKey.showsToolPicker, "GraphitePDFShowsToolPicker")
        XCTAssertEqual(PDFAnnotationPreferenceKey.drawsShapes, "GraphiteDrawsShapes")
        XCTAssertEqual(PDFAnnotationPreferenceKey.writingGuidePattern, "GraphitePDFWritingGuidePattern")
        XCTAssertEqual(PDFAnnotationPreferenceKey.writingGuideSpacing, "GraphitePDFWritingGuideSpacing")
    }

    #if canImport(UIKit)
    func testTheShapeToolIsOneSettingSharedByThePencilPaletteAndThePDFPanes() {
        XCTAssertEqual(PencilToolPalette.drawsShapesPreferenceKey, PDFAnnotationPreferenceKey.drawsShapes)
    }
    #endif
}
