import CoreGraphics
@testable import MermaidDiagrams

/// A white bitmap a layout is drawn into at one pixel per point, its y running down as the layout's does, with
/// the color of any pixel read back.
struct DiagramBitmap {
    let width: Int
    let height: Int
    private let context: CGContext

    init?(size: CGSize) {
        width = Int(size.width.rounded(.up))
        height = Int(size.height.rounded(.up))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        self.context = context
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
    }

    func draw(_ layout: FlowchartLayout, palette: DiagramPalette) {
        FlowchartRenderer.draw(layout, in: context, palette: palette)
    }

    func draw(_ layout: StateDiagramLayout, palette: DiagramPalette) {
        StateDiagramRenderer.draw(layout, in: context, palette: palette)
    }

    func draw(_ layout: ClassDiagramLayout, palette: ClassDiagramPalette) {
        ClassDiagramRenderer.draw(layout, in: context, palette: palette)
    }

    func draw(_ layout: SequenceLayout, palette: DiagramPalette) {
        SequenceRenderer.draw(layout, in: context, palette: palette)
    }

    /// The red, green and blue of the pixel at a point, 0 to 255.
    func color(at point: CGPoint) -> [Int] {
        guard let data = context.data else { return [] }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let offset = (Int(point.y) * width + Int(point.x)) * 4
        return (0..<3).map { channel in Int(bytes[offset + channel]) }
    }

    /// Whether any pixel of `rectangle` is darker than `level` in every channel.
    func hasPixel(in rectangle: CGRect, darkerThan level: Int) -> Bool {
        for y in Int(rectangle.minY)..<Int(rectangle.maxY) {
            for x in Int(rectangle.minX)..<Int(rectangle.maxX) where color(at: CGPoint(x: x, y: y)).allSatisfy({ channel in channel < level }) {
                return true
            }
        }
        return false
    }
}
