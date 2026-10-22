import XCTest
import CoreText
@testable import MermaidDiagrams

final class CoreTextDiagramTextMeasurerTests: XCTestCase {
    private let font = DiagramFont(postScriptName: nil, size: 16)

    private func coreTextLineWidth(_ text: String) -> CGFloat {
        let attributes = [kCTFontAttributeName as NSAttributedString.Key: font.makeCoreTextFont()]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    func testPrintableASCIIIsMeasuredFromTheAdvancesAsCoreTextDrawsIt() {
        let measurer = CoreTextDiagramTextMeasurer(font: font)
        for text in ["Start", "Is it ready? (yes/no)", "fa:fa-car Car"] {
            // The table leaves kerning out; it stays within a point of the drawn line.
            XCTAssertEqual(measurer.width(of: text), coreTextLineWidth(text), accuracy: 1, text)
        }
    }

    func testOtherTextIsMeasuredAsALine() {
        let measurer = CoreTextDiagramTextMeasurer(font: font)
        for text in ["Étape", "Начало", "数据库", "Done ✓"] {
            XCTAssertEqual(measurer.width(of: text), coreTextLineWidth(text), accuracy: 0.01, text)
            XCTAssertGreaterThan(measurer.width(of: text), 0, text)
        }
    }

    func testTheLineHeightIsOneAndAHalfTimesTheSizeRounded() {
        XCTAssertEqual(CoreTextDiagramTextMeasurer(font: font).lineHeight, 24)
        XCTAssertEqual(CoreTextDiagramTextMeasurer(font: DiagramFont(postScriptName: nil, size: 17)).lineHeight, 26)
    }

    func testTheEdgeTextIsSevenEighthsOfTheNodeText() {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        XCTAssertEqual(typography.edgeText.fontSize, 14)
        XCTAssertEqual(typography.nodeText.fontSize, 16)
    }
}
