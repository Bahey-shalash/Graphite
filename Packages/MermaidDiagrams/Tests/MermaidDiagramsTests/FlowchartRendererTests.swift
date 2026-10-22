import XCTest
@testable import MermaidDiagrams

final class FlowchartRendererTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func laidOut(_ source: String) throws -> FlowchartLayout {
        try FlowchartLayoutEngine.layout(FlowchartReading.flowchart(source), typography: typography, limits: .standard)
    }

    private func drawn(_ layout: FlowchartLayout, palette: DiagramPalette = .peleLight) throws -> DiagramBitmap {
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        bitmap.draw(layout, palette: palette)
        return bitmap
    }

    func testANodeIsFilledWithTheSurfaceAndOutlinedWithTheBorder() throws {
        let layout = try laidOut("flowchart TD\nA[Start] --> B[Finish]")
        let bitmap = try drawn(layout)
        let frame = layout.nodes[0].frame
        XCTAssertEqual(bitmap.color(at: CGPoint(x: frame.minX + 4, y: frame.midY)), [0xF3, 0xF3, 0xF3])
        XCTAssertTrue(bitmap.color(at: CGPoint(x: frame.minX + 0.5, y: frame.midY)).allSatisfy { channel in channel < 0xF3 })
        XCTAssertTrue(bitmap.hasPixel(in: layout.nodes[0].text.frame, darkerThan: 0x80), "The text is drawn")
        XCTAssertEqual(bitmap.color(at: CGPoint(x: 1, y: 1)), [0xFF, 0xFF, 0xFF], "Nothing is drawn outside the shapes")
    }

    func testAnEdgeIsDrawnBetweenItsNodesWithItsArrow() throws {
        let layout = try laidOut("flowchart TD\nA --> B")
        let bitmap = try drawn(layout)
        let x = layout.nodes[0].frame.midX
        let gap = CGRect(x: x - 2, y: layout.nodes[0].frame.maxY + 2, width: 4, height: layout.nodes[1].frame.minY - layout.nodes[0].frame.maxY - 4)
        XCTAssertTrue(bitmap.hasPixel(in: gap, darkerThan: 0x80))
        let tip = try XCTUnwrap(layout.edges[0].targetMark?.tip)
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: tip.x - 3, y: tip.y - 6, width: 6, height: 4), darkerThan: 0x80), "The arrow is filled")
    }

    func testAnInvisibleEdgeDrawsNothing() throws {
        let layout = try laidOut("flowchart TD\nA ~~~ B")
        let bitmap = try drawn(layout)
        let gap = CGRect(x: layout.nodes[0].frame.minX, y: layout.nodes[0].frame.maxY + 2, width: layout.nodes[0].frame.width,
                         height: layout.nodes[1].frame.minY - layout.nodes[0].frame.maxY - 4)
        XCTAssertFalse(bitmap.hasPixel(in: gap, darkerThan: 0xF0))
    }

    func testAnEdgesTextSitsOnAPatchOfTheBackgroundThatHidesTheLine() throws {
        let layout = try laidOut("flowchart TD\nA -->|Yes| B")
        let darkBackground = DiagramPalette(background: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), foreground: DiagramPalette.peleLight.foreground,
                                            line: DiagramPalette.peleLight.line, surface: DiagramPalette.peleLight.surface, border: DiagramPalette.peleLight.border)
        let bitmap = try drawn(layout, palette: darkBackground)
        let text = try XCTUnwrap(layout.edges[0].text)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: text.frame.minX - 2, y: text.frame.minY + 1)), [0, 0, 0xFF])
    }

    func testDrawingTheSameLayoutInOtherColorsChangesOnlyTheColors() throws {
        let layout = try laidOut("flowchart LR\nA[One] --> B{Two}")
        let dark = DiagramPalette(background: CGColor(gray: 0.1, alpha: 1), foreground: CGColor(gray: 0.9, alpha: 1), line: CGColor(gray: 0.9, alpha: 1),
                                  surface: CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1), border: CGColor(gray: 0.5, alpha: 1))
        let point = CGPoint(x: layout.nodes[0].frame.minX + 4, y: layout.nodes[0].frame.midY)
        XCTAssertEqual(try drawn(layout).color(at: point), [0xF3, 0xF3, 0xF3])
        XCTAssertEqual(try drawn(layout, palette: dark).color(at: point), [0x33, 0x33, 0x33])
    }

    func testEveryShapeIsDrawnInsideItsFrame() throws {
        let layout = try laidOut("""
        flowchart LR
          A[a] --> B(b) --> C([c]) --> D[[d]] --> E[(e)] --> F((f)) --> G(((g)))
          G --> H>h] --> I{i} --> J{{j}} --> K[/k/] --> L[\\l\\] --> M[/m\\] --> N[\\n/] --> O@{ shape: text, label: "o" }
        """)
        let bitmap = try drawn(layout)
        for node in layout.nodes {
            XCTAssertTrue(bitmap.hasPixel(in: node.frame.insetBy(dx: -1, dy: -1), darkerThan: 0xC0), "\(node.shape)")
        }
        let bareText = try XCTUnwrap(layout.nodes.last)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: bareText.frame.minX + 1, y: bareText.frame.minY + 1)), [0xFF, 0xFF, 0xFF], "Bare text has no outline")
    }

    func testAGroupsBoxIsHalfTheAlternateSurfaceOverThePageWithAnOutlineAndAMutedTitle() throws {
        let layout = try laidOut("flowchart TD\nsubgraph one [Group]\nA --> B\nend")
        let bitmap = try drawn(layout)
        let box = layout.clusters[0].frame
        // Half of #e6e6e6 over white, inside the padding beside the nodes.
        XCTAssertTrue(bitmap.color(at: CGPoint(x: box.minX + 6, y: box.maxY - 6)).allSatisfy { channel in abs(channel - 242) <= 1 })
        XCTAssertTrue(bitmap.color(at: CGPoint(x: box.minX + 0.5, y: box.midY)).allSatisfy { channel in channel < 0xE0 }, "The outline")
        let title = try XCTUnwrap(layout.clusters[0].title)
        XCTAssertTrue(bitmap.hasPixel(in: title.frame, darkerThan: 0x80), "The title is drawn")
        XCTAssertFalse(bitmap.hasPixel(in: title.frame, darkerThan: 0x60), "The title is muted, lighter than the text")
        XCTAssertTrue(bitmap.hasPixel(in: layout.nodes[0].text.frame, darkerThan: 0x60), "Node text is in the foreground")
    }

    func testABoxInsideAnotherIsDarker() throws {
        let layout = try laidOut("flowchart TD\nsubgraph outer\nsubgraph inner\nA\nend\nend")
        let bitmap = try drawn(layout)
        let inner = layout.clusters[1].frame
        // Half of #e6e6e6 over the outer box's 242.5.
        XCTAssertTrue(bitmap.color(at: CGPoint(x: inner.minX + 6, y: inner.maxY - 6)).allSatisfy { channel in abs(channel - 236) <= 1 })
    }

    func testATitleAnEdgeRunsThroughIsPaintedOverTheEdgeOnThePatchOfItsBox() throws {
        let layout = try laidOut("flowchart TD\nX --> A\nsubgraph S [A title as wide as the box]\nA\nend")
        XCTAssertTrue(layout.clusters[0].isTitleCrossed)
        let bitmap = try drawn(layout)
        let box = layout.clusters[0].frame
        let title = try XCTUnwrap(layout.clusters[0].title)
        let crossing = try XCTUnwrap(layout.edges[0].path.allPoints.first { point in abs(point.y - box.minY) < 0.01 })
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: crossing.x - 2, y: box.minY - 6, width: 4, height: 4), darkerThan: 0xC0), "The edge above the box")
        XCTAssertFalse(bitmap.hasPixel(in: CGRect(x: crossing.x - 2, y: title.frame.minY, width: 4, height: 2), darkerThan: 0xE0),
                       "The patch hides the edge above the letters")
    }
}
