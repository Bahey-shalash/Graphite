import Foundation
import CoreGraphics
import PDFKit
import GraphiteCore

public enum PaperTemplate: String, CaseIterable, Sendable, Identifiable, Codable {
    case blank, dotted, grid, ruled, cornell, engineering, isometric, music
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// The paper of a notebook's pages: its pattern, size, spacing and colors. The pattern is
/// page content, part of the PDF like printed paper.
public struct PaperSpecification: Sendable, Codable, Equatable {
    public var template: PaperTemplate
    public var width: Double
    public var height: Double
    public var spacing: Double
    /// The paper's color as `#rrggbb`; nil for white.
    public var paperColorHex: String?
    public var lineColor: DrawingPaperLineColor
    public var lineStrength: DrawingPaperLineStrength

    public static let standardSpacing = 18.0

    public init(template: PaperTemplate = .dotted, width: Double = 595.28, height: Double = 841.89, spacing: Double = standardSpacing,
                paperColorHex: String? = nil, lineColor: DrawingPaperLineColor = .gray, lineStrength: DrawingPaperLineStrength = .standard) {
        self.template = template; self.width = width; self.height = height; self.spacing = spacing
        self.paperColorHex = paperColorHex; self.lineColor = lineColor; self.lineStrength = lineStrength
    }

    private enum CodingKeys: String, CodingKey {
        case template, width, height, spacing, paperColorHex, lineColor, lineStrength
    }

    /// Specifications written before paper colors keep their meaning: white paper, gray lines.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(template: try container.decode(PaperTemplate.self, forKey: .template), width: try container.decode(Double.self, forKey: .width),
                  height: try container.decode(Double.self, forKey: .height), spacing: try container.decode(Double.self, forKey: .spacing),
                  paperColorHex: try container.decodeIfPresent(String.self, forKey: .paperColorHex),
                  lineColor: try container.decodeIfPresent(DrawingPaperLineColor.self, forKey: .lineColor) ?? .gray,
                  lineStrength: try container.decodeIfPresent(DrawingPaperLineStrength.self, forKey: .lineStrength) ?? .standard)
    }

    /// The same paper in another size, for a page inserted beside an existing one.
    public func sized(_ pageSize: CGSize) -> PaperSpecification {
        var paper = self
        paper.width = pageSize.width
        paper.height = pageSize.height
        return paper
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
        try pageData(paper: PaperSpecification(template: template), matching: pageSize)
    }

    /// One page of the paper, in the size of an existing page.
    public static func pageData(paper: PaperSpecification, matching pageSize: CGSize) throws -> Data {
        guard pageSize.width.isFinite, pageSize.height.isFinite, pageSize.width > 0, pageSize.height > 0 else {
            throw GraphiteError.invalidFile("This page has no size, so a matching page cannot be made.")
        }
        guard paper.spacing.isFinite, (4...144).contains(paper.spacing) else {
            throw GraphiteError.invalidFile("Choose a spacing from 4 to 144 points.")
        }
        func portableLength(_ length: Double) -> Double {
            min(max(length, portablePageSizeRange.lowerBound), portablePageSizeRange.upperBound)
        }
        return try render(paper.sized(CGSize(width: portableLength(pageSize.width), height: portableLength(pageSize.height))), pageCount: 1)
    }

    private static func render(_ paper: PaperSpecification, pageCount: Int) throws -> Data {
        let output = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: paper.width, height: paper.height)
        guard let consumer = CGDataConsumer(data: output), let context = CGContext(consumer: consumer, mediaBox: &bounds, nil) else {
            throw GraphiteError.unavailable("Could not create PDF paper.")
        }
        let layout = TemplateLayout(paper: paper, margin: margin)
        let colors = TemplateColors(paper: paper)
        let dotPattern = paper.template == .dotted
            ? try makeDotPattern(spacing: paper.spacing, firstDot: CGPoint(x: layout.firstColumnPosition, y: layout.firstRowPosition), color: colors.dot) : nil
        for _ in 0..<pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(colors.paper); context.fill(bounds)
            context.setStrokeColor(colors.line); context.setFillColor(colors.dot)
            context.setLineWidth(0.4)
            func line(from start: CGPoint, to end: CGPoint) {
                context.move(to: start); context.addLine(to: end); context.strokePath()
            }
            switch paper.template {
            case .blank: break
            case .dotted:
                if let dotPattern { fillDots(dotPattern, layout: layout, spacing: paper.spacing, in: context) }
            case .isometric:
                strokeIsometricLines(spacing: paper.spacing, in: CGRect(x: margin, y: margin, width: paper.width - 2 * margin, height: paper.height - 2 * margin), context: context)
            case .music:
                strokeStaves(spacing: paper.spacing, in: CGRect(x: margin, y: margin, width: paper.width - 2 * margin, height: paper.height - 2 * margin), context: context)
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

    /// The colors of a page: gray lines on white keep the exact grays notebooks always had.
    private struct TemplateColors {
        let paper: CGColor
        let line: CGColor
        let dot: CGColor

        init(paper specification: PaperSpecification) {
            paper = specification.paperColorHex.flatMap(Self.color(hex:)) ?? CGColor(gray: 1, alpha: 1)
            if specification.lineColor == .gray, specification.lineStrength == .standard {
                line = CGColor(gray: 0.77, alpha: 1)
                dot = CGColor(gray: 0.67, alpha: 1)
            } else {
                let style = DrawingPaper(pattern: .squared, appearsInSavedDrawing: true, lineColor: specification.lineColor, lineStrength: specification.lineStrength)
                let lineColor = DrawingPaperRenderer.color(of: style, forDots: false), dotColor = DrawingPaperRenderer.color(of: style, forDots: true)
                line = CGColor(srgbRed: lineColor.red, green: lineColor.green, blue: lineColor.blue, alpha: 1)
                dot = CGColor(srgbRed: dotColor.red, green: dotColor.green, blue: dotColor.blue, alpha: 1)
            }
        }

        private static func color(hex: String) -> CGColor? {
            guard hex.count == 7, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
            return CGColor(srgbRed: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255, alpha: 1)
        }
    }

    /// Three families of lines at 60 degrees to each other, making equilateral triangles
    /// whose rows are `spacing` apart, for isometric drawing.
    private static func strokeIsometricLines(spacing: Double, in region: CGRect, context: CGContext) {
        context.saveGState()
        context.clip(to: region)
        // Vertical lines are spaced so that the slanted ones cross them on the rows.
        let verticalSpacing = spacing * 2 / 3.0.squareRoot()
        for horizontalPosition in stride(from: region.minX, through: region.maxX, by: verticalSpacing) {
            context.move(to: CGPoint(x: horizontalPosition, y: region.minY)); context.addLine(to: CGPoint(x: horizontalPosition, y: region.maxY))
        }
        // Lines at 30 degrees up and down, crossing the left edge every `spacing * 2`.
        let rise = region.width * tan(Double.pi / 6)
        for startHeight in stride(from: region.minY - rise, through: region.maxY + rise, by: spacing * 2) {
            context.move(to: CGPoint(x: region.minX, y: startHeight)); context.addLine(to: CGPoint(x: region.maxX, y: startHeight + rise))
            context.move(to: CGPoint(x: region.minX, y: startHeight)); context.addLine(to: CGPoint(x: region.maxX, y: startHeight - rise))
        }
        context.strokePath()
        context.restoreGState()
    }

    /// Five-line staves, with the lines a third of `spacing` apart and two spacings between
    /// staves, from the top of the page down.
    private static func strokeStaves(spacing: Double, in region: CGRect, context: CGContext) {
        let lineGap = spacing / 3
        let staffHeight = lineGap * 4
        let staffPeriod = staffHeight + spacing * 2
        var staffTop = region.maxY
        while staffTop - staffHeight >= region.minY {
            for lineIndex in 0..<5 {
                let height = staffTop - Double(lineIndex) * lineGap
                context.move(to: CGPoint(x: region.minX, y: height)); context.addLine(to: CGPoint(x: region.maxX, y: height))
            }
            staffTop -= staffPeriod
        }
        context.strokePath()
    }

    /// The color a dot pattern draws with, handed to its callbacks, which cannot capture values.
    private final class DotColor {
        let color: CGColor
        init(_ color: CGColor) { self.color = color }
    }

    /// Dots as one tiling pattern cell instead of one path per dot per page: a 1,000-page
    /// dotted A4 notebook was 66 MB, and a single 40-inch page over 1 MB. The cell has its
    /// color in it: Core Graphics' own PDF renderer draws no dots from a cell without one.
    private static func makeDotPattern(spacing: Double, firstDot: CGPoint, color: CGColor) throws -> CGPattern {
        var callbacks = CGPatternCallbacks(version: 0, drawPattern: { info, context in
            guard let info else { return }
            context.setFillColor(Unmanaged<DotColor>.fromOpaque(info).takeUnretainedValue().color)
            // The dot's size is the constant the path-based dots used.
            context.fillEllipse(in: CGRect(x: -0.65, y: -0.65, width: 1.3, height: 1.3))
        }, releaseInfo: { info in
            guard let info else { return }
            Unmanaged<DotColor>.fromOpaque(info).release()
        })
        let colorInfo = Unmanaged.passRetained(DotColor(color)).toOpaque()
        // The cell is centered on a dot. Pattern space is the page's default space, so the
        // matrix moves the first cell onto the first dot position.
        guard let pattern = CGPattern(info: colorInfo, bounds: CGRect(x: -spacing / 2, y: -spacing / 2, width: spacing, height: spacing),
                                      matrix: CGAffineTransform(translationX: firstDot.x, y: firstDot.y), xStep: spacing, yStep: spacing,
                                      tiling: .constantSpacing, isColored: true, callbacks: &callbacks) else {
            Unmanaged<DotColor>.fromOpaque(colorInfo).release()
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
