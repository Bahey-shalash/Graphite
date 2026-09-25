import Foundation
import CoreGraphics
import PDFKit
import GraphiteCore

public enum PaperTemplate: String, CaseIterable, Sendable, Identifiable, Codable {
    case blank, dotted, grid, ruled, cornell, engineering
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct PaperSpecification: Sendable, Codable {
    public var template: PaperTemplate
    public var width: Double
    public var height: Double
    public var spacing: Double
    public init(template: PaperTemplate = .dotted, width: Double = 595.28, height: Double = 841.89, spacing: Double = 18) {
        self.template = template; self.width = width; self.height = height; self.spacing = spacing
    }
}

public enum PDFTemplateGenerator {
    /// The page sizes PDF itself allows (ISO 32000 Annex C), in points.
    private static let portablePageSizeRange = 3.0...14_400.0
    private static let margin = 30.0

    public static func documentData(paper: PaperSpecification, pageCount: Int = 1) throws -> Data {
        guard paper.width.isFinite, paper.height.isFinite, paper.spacing.isFinite,
              (72...2880).contains(paper.width), (72...2880).contains(paper.height),
              (4...144).contains(paper.spacing), (1...1000).contains(pageCount) else {
            throw GraphiteError.invalidFile("Choose a paper size from 1 to 40 inches, spacing from 4 to 144 points, and 1 to 1,000 pages.")
        }
        return try render(paper, pageCount: pageCount)
    }

    /// One template page the size of an existing page, for inserting into that PDF. Scans
    /// and posters are often larger than the sizes offered for new notebooks, so any size
    /// PDF allows is accepted; a size outside that is brought into it.
    public static func pageData(template: PaperTemplate, matching pageSize: CGSize) throws -> Data {
        guard pageSize.width.isFinite, pageSize.height.isFinite, pageSize.width > 0, pageSize.height > 0 else {
            throw GraphiteError.invalidFile("This page has no size, so a matching page cannot be made.")
        }
        func portableLength(_ length: Double) -> Double {
            min(max(length, portablePageSizeRange.lowerBound), portablePageSizeRange.upperBound)
        }
        return try render(PaperSpecification(template: template, width: portableLength(pageSize.width), height: portableLength(pageSize.height)), pageCount: 1)
    }

    private static func render(_ paper: PaperSpecification, pageCount: Int) throws -> Data {
        let output = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: paper.width, height: paper.height)
        guard let consumer = CGDataConsumer(data: output), let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else {
            throw GraphiteError.unavailable("Could not create PDF paper.")
        }
        let layout = TemplateLayout(paper: paper, margin: margin)
        let dotPattern = paper.template == .dotted ? try makeDotPattern(spacing: paper.spacing, firstDot: CGPoint(x: layout.firstColumnPosition, y: layout.firstRowPosition)) : nil
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(bounds)
            context.setStrokeColor(CGColor(gray: 0.77, alpha: 1)); context.setFillColor(CGColor(gray: 0.67, alpha: 1))
            context.setLineWidth(0.4)
            func line(from start: CGPoint, to end: CGPoint) {
                context.move(to: start); context.addLine(to: end); context.strokePath()
            }
            switch paper.template {
            case .blank: break
            case .dotted:
                if let dotPattern { fillDots(dotPattern, layout: layout, spacing: paper.spacing, in: context) }
            case .grid, .engineering:
                // Lines end at the last crossing line, not at the margin, so no stubs stick
                // out past the grid at the top and right.
                for horizontalPosition in layout.columnPositions {
                    line(from: CGPoint(x: horizontalPosition, y: layout.firstRowPosition), to: CGPoint(x: horizontalPosition, y: layout.lastRowPosition))
                }
                for verticalPosition in layout.rowPositions {
                    line(from: CGPoint(x: layout.firstColumnPosition, y: verticalPosition), to: CGPoint(x: layout.lastColumnPosition, y: verticalPosition))
                }
                if paper.template == .engineering {
                    context.setLineWidth(0.9)
                    for horizontalPosition in stride(from: margin, through: layout.lastColumnPosition, by: paper.spacing * 5) {
                        line(from: CGPoint(x: horizontalPosition, y: layout.firstRowPosition), to: CGPoint(x: horizontalPosition, y: layout.lastRowPosition))
                    }
                    for verticalPosition in stride(from: margin, through: layout.lastRowPosition, by: paper.spacing * 5) {
                        line(from: CGPoint(x: layout.firstColumnPosition, y: verticalPosition), to: CGPoint(x: layout.lastColumnPosition, y: verticalPosition))
                    }
                }
            case .ruled, .cornell:
                let bottomMargin = paper.template == .cornell ? paper.height * 0.2 : margin
                for verticalPosition in stride(from: bottomMargin, through: paper.height - margin, by: paper.spacing) {
                    line(from: CGPoint(x: margin, y: verticalPosition), to: CGPoint(x: paper.width - margin, y: verticalPosition))
                }
                if paper.template == .cornell {
                    context.setLineWidth(1)
                    line(from: CGPoint(x: paper.width * 0.3, y: bottomMargin), to: CGPoint(x: paper.width * 0.3, y: paper.height - margin))
                    line(from: CGPoint(x: margin, y: bottomMargin), to: CGPoint(x: paper.width - margin, y: bottomMargin))
                }
            }
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    /// Grid positions: lines every `spacing` points from the bottom-left margin, as far as
    /// the opposite margin allows.
    private struct TemplateLayout {
        let columnPositions: [Double]
        let rowPositions: [Double]

        init(paper: PaperSpecification, margin: Double) {
            columnPositions = Array(stride(from: margin, through: paper.width - margin, by: paper.spacing))
            rowPositions = Array(stride(from: margin, through: paper.height - margin, by: paper.spacing))
        }

        var firstColumnPosition: Double { columnPositions.first ?? 0 }
        var lastColumnPosition: Double { columnPositions.last ?? 0 }
        var firstRowPosition: Double { rowPositions.first ?? 0 }
        var lastRowPosition: Double { rowPositions.last ?? 0 }
    }

    /// Dots as one tiling pattern cell instead of one path per dot per page: a 1,000-page
    /// dotted A4 notebook was 66 MB, and a single 40-inch page over 1 MB.
    private static func makeDotPattern(spacing: Double, firstDot: CGPoint) throws -> CGPattern {
        var callbacks = CGPatternCallbacks(version: 0, drawPattern: { _, context in
            // Pattern callbacks cannot capture values; the dot's color and size are the
            // constants the path-based dots used.
            context.setFillColor(CGColor(gray: 0.67, alpha: 1))
            context.fillEllipse(in: CGRect(x: -0.65, y: -0.65, width: 1.3, height: 1.3))
        }, releaseInfo: nil)
        // The cell is centered on a dot. Pattern space is the page's default space, so the
        // matrix moves the first cell onto the first dot position.
        guard let pattern = CGPattern(info: nil, bounds: CGRect(x: -spacing / 2, y: -spacing / 2, width: spacing, height: spacing),
                                      matrix: CGAffineTransform(translationX: firstDot.x, y: firstDot.y), xStep: spacing, yStep: spacing,
                                      tiling: .constantSpacing, isColored: true, callbacks: &callbacks) else {
            throw GraphiteError.unavailable("Could not create PDF paper.")
        }
        return pattern
    }

    private static func fillDots(_ pattern: CGPattern, layout: TemplateLayout, spacing: Double, in context: CGContext) {
        guard !layout.columnPositions.isEmpty, !layout.rowPositions.isEmpty,
              let patternColorSpace = CGColorSpace(patternBaseSpace: nil) else { return }
        context.saveGState()
        context.setFillColorSpace(patternColorSpace)
        var patternAlpha: CGFloat = 1
        context.setFillPattern(pattern, colorComponents: &patternAlpha)
        // Only whole cells around real dot positions are filled.
        context.fill(CGRect(x: layout.firstColumnPosition - spacing / 2, y: layout.firstRowPosition - spacing / 2,
                            width: Double(layout.columnPositions.count) * spacing, height: Double(layout.rowPositions.count) * spacing))
        context.restoreGState()
    }
}
