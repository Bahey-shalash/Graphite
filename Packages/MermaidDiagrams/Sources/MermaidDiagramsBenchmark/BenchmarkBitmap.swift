import CoreGraphics

/// The bitmap the mindmap's and the timeline's benchmarks paint into.
enum BenchmarkBitmap {
    /// A bitmap at two pixels per point, its y running down as a layout's does.
    static func context(size: CGSize) -> CGContext? {
        let scale: CGFloat = 2
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        return context
    }
}
