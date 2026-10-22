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
}
