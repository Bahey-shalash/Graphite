import XCTest
@testable import MermaidDiagrams

final class MindmapShapeDrawingTests: XCTestCase {
    func testTheCloudAndTheBangSurroundTheirCenter() throws {
        let frame = CGRect(x: 10, y: 20, width: 108, height: 72)
        for outline in [MindmapNodeOutline.cloud, .bang] {
            let path = try XCTUnwrap(MindmapShapeDrawing.outline(of: outline, in: frame))
            XCTAssertTrue(path.contains(CGPoint(x: frame.midX, y: frame.midY)), "\(outline)")
            XCTAssertFalse(path.contains(CGPoint(x: frame.minX + 1, y: frame.minY + 1)), "\(outline)")
            XCTAssertTrue(frame.insetBy(dx: -8, dy: -1).contains(path.boundingBoxOfPath), "\(outline): \(path.boundingBoxOfPath)")
        }
        XCTAssertNil(MindmapShapeDrawing.outline(of: .text, in: frame))
    }

    func testAPillNarrowerThanItsHeightKeepsCornersThatFit() throws {
        let frame = CGRect(x: 0, y: 0, width: 24, height: 30)
        let pill = try XCTUnwrap(MindmapShapeDrawing.outline(of: .pill, in: frame))
        XCTAssertEqual(pill.boundingBoxOfPath, frame)
    }
}
