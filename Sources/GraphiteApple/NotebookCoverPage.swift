import Foundation
import CoreGraphics
import CoreText
import PDFKit
import GraphiteCore

/// The colors a notebook's cover is offered in.
public enum NotebookCoverColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case blue, green, red, orange, yellow, purple, brown, graphite

    public var id: String { rawValue }

    public var title: String { rawValue.capitalized }

    /// The color as sRGB components from 0 to 1.
    var components: (red: Double, green: Double, blue: Double) {
        switch self {
        case .blue: (0.20, 0.38, 0.72)
        case .green: (0.23, 0.55, 0.38)
        case .red: (0.74, 0.25, 0.25)
        case .orange: (0.88, 0.50, 0.18)
        case .yellow: (0.95, 0.78, 0.25)
        case .purple: (0.46, 0.33, 0.66)
        case .brown: (0.47, 0.34, 0.25)
        case .graphite: (0.26, 0.28, 0.31)
        }
    }

    /// The color as `#rrggbb`, for the picture of its swatch.
    public var colorHex: String {
        let channels = [components.red, components.green, components.blue].map { channel in Int((channel * 255).rounded()) }
        return String(format: "#%02x%02x%02x", channels[0], channels[1], channels[2])
    }

    /// Whether the title is drawn in dark ink: on the light colors, so it stays readable.
    var usesDarkTitle: Bool {
        // Relative luminance of sRGB, by the usual weights.
        0.2126 * components.red + 0.7152 * components.green + 0.0722 * components.blue > 0.6
    }
}

/// A notebook's cover: a first page of one color with the notebook's title, made when the
/// notebook is. It is an ordinary page of the PDF, so every other app shows it as it is.
public enum NotebookCoverPage {
    /// The title takes this share of the page's width.
    static let titleWidthFraction = 0.74
    /// The title's size is this share of the page's width, reduced until it fits.
    static let titleSizeFraction = 0.09
    static let smallestTitlePoints = 14.0
    /// The most of the page's height the title may take.
    static let titleHeightFraction = 0.45

    /// A one-page PDF of the cover, `pageSize` in PDF points.
    public static func pageData(title: String, color: NotebookCoverColor, pageSize: CGSize) throws -> Data {
        var pageBox = CGRect(origin: .zero, size: pageSize)
        let output = NSMutableData()
        guard pageSize.width > 0, pageSize.height > 0, let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &pageBox, nil) else { throw MyPaperTemplateError.notDrawn }
        context.beginPDFPage(nil)
        draw(title: title, color: color, in: context, pageSize: pageSize)
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    /// `notebookData` with a cover as its first page, the size of the page it had first.
    public static func prepending(coverTitled title: String, color: NotebookCoverColor, to notebookData: Data) throws -> Data {
        guard let notebook = PDFDocument(data: notebookData), let firstPage = notebook.page(at: 0) else { throw MyPaperTemplateError.notAPDF }
        let pageSize = firstPage.bounds(for: .mediaBox).size
        guard let cover = PDFDocument(data: try pageData(title: title, color: color, pageSize: pageSize)), let coverPage = cover.page(at: 0) else {
            throw MyPaperTemplateError.notDrawn
        }
        notebook.insert(coverPage, at: 0)
        guard let coveredData = notebook.dataRepresentation() else { throw MyPaperTemplateError.notDrawn }
        return coveredData
    }

    /// The cover drawn small, for the sheet's first-page picture.
    public static func previewImage(title: String, color: NotebookCoverColor, pageSize: CGSize, longerSidePixels: Int) -> CGImage? {
        let scale = Double(longerSidePixels) / max(pageSize.width, pageSize.height)
        let width = max(Int((pageSize.width * scale).rounded()), 1), height = max(Int((pageSize.height * scale).rounded()), 1)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        draw(title: title, color: color, in: context, pageSize: pageSize)
        return context.makeImage()
    }

    // MARK: Drawing

    private static func draw(title: String, color: NotebookCoverColor, in context: CGContext, pageSize: CGSize) {
        let components = color.components
        context.setFillColor(CGColor(srgbRed: components.red, green: components.green, blue: components.blue, alpha: 1))
        context.fill(CGRect(origin: .zero, size: pageSize))
        let inkValue = color.usesDarkTitle ? 0.12 : 1.0
        let ink = CGColor(srgbRed: inkValue, green: inkValue, blue: inkValue, alpha: 1)
        let titleWidth = pageSize.width * titleWidthFraction
        let maximumHeight = pageSize.height * titleHeightFraction
        var pointSize = max(pageSize.width * titleSizeFraction, smallestTitlePoints)
        var layout = frame(of: title, pointSize: pointSize, width: titleWidth, ink: ink)
        // Smaller until the title fits the height and no word is broken across lines.
        while layout.size.height > maximumHeight || longestWordWidth(of: title, pointSize: pointSize) > titleWidth, pointSize > smallestTitlePoints {
            pointSize = max(pointSize * 0.85, smallestTitlePoints)
            layout = frame(of: title, pointSize: pointSize, width: titleWidth, ink: ink)
        }
        let titleOrigin = CGPoint(x: (pageSize.width - titleWidth) / 2, y: pageSize.height * 0.55 - layout.size.height / 2)
        let titleRect = CGRect(x: titleOrigin.x, y: titleOrigin.y, width: titleWidth, height: layout.size.height)
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: 0)
        let path = CGPath(rect: titleRect, transform: nil)
        let drawnFrame = CTFramesetterCreateFrame(layout.framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(drawnFrame, context)
        context.restoreGState()
        // A short rule under the title.
        context.setFillColor(ink.copy(alpha: 0.55) ?? ink)
        let ruleWidth = pageSize.width * 0.16
        context.fill(CGRect(x: (pageSize.width - ruleWidth) / 2, y: titleRect.minY - pointSize * 0.7, width: ruleWidth, height: max(pageSize.width * 0.004, 1)))
    }

    private static func longestWordWidth(of title: String, pointSize: Double) -> Double {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, pointSize, nil)
        return title.split(whereSeparator: \.isWhitespace).map { word in
            let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(word), attributes: attributes))
            return CTLineGetTypographicBounds(line, nil, nil, nil)
        }.max() ?? 0
    }

    private static func frame(of title: String, pointSize: Double, width: Double, ink: CGColor) -> (framesetter: CTFramesetter, size: CGSize) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, pointSize, nil)
        var alignment = CTTextAlignment.center
        let alignmentSetting = withUnsafeMutablePointer(to: &alignment) { pointer in
            CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
        }
        let paragraphStyle = CTParagraphStyleCreate([alignmentSetting], 1)
        let text = NSAttributedString(string: title, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let constraints = CGSize(width: width, height: .greatestFiniteMagnitude)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: 0), nil, constraints, nil)
        return (framesetter, size)
    }
}
