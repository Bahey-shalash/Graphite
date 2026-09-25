import Foundation
import CoreGraphics
import ImageIO
import GraphiteCore

/// Encodes a tall raster as an 8-bit sRGB PNG one horizontal band at a time.
///
/// ImageIO pulls rows in order from a sequential data provider, so only the band being
/// encoded is in memory. Every band starts on a whole pixel row: a band edge inside a
/// pixel row left that row lighter where two antialiased bands overlapped.
enum BandedPNGEncoder {
    struct Raster: Equatable {
        /// A power of two, so a scale rounded down to a multiple of `1 / bandPointHeight`
        /// is exact in binary and every band edge lands on a whole pixel row.
        static let bandPointHeight = 1_024.0

        let size: CGSize
        let scale: Double
        let pixelWidth: Int
        let pixelHeight: Int
        let bandPixelHeight: Int
        /// White background with no alpha channel; otherwise transparent.
        let isOpaque: Bool

        /// Nil when the size or scale cannot make a bitmap.
        init?(size: CGSize, preferredScale: Double, isOpaque: Bool) {
            guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
                  preferredScale.isFinite, preferredScale * Self.bandPointHeight >= 1 else { return nil }
            let bandPixelHeight = (preferredScale * Self.bandPointHeight).rounded(.down)
            let scale = bandPixelHeight / Self.bandPointHeight
            let pixelWidth = (size.width * scale).rounded(.up), pixelHeight = (size.height * scale).rounded(.up)
            guard pixelWidth <= Double(Int32.max), pixelHeight <= Double(Int32.max) else { return nil }
            self.size = size
            self.scale = scale
            self.pixelWidth = Int(pixelWidth)
            self.pixelHeight = Int(pixelHeight)
            self.bandPixelHeight = Int(bandPixelHeight)
            self.isOpaque = isOpaque
        }

        var bandCount: Int { (pixelHeight + bandPixelHeight - 1) / bandPixelHeight }

        /// The band's region of the drawing, in points, top-left origin.
        func bandRectangle(at bandIndex: Int) -> CGRect {
            let bandTop = Double(bandIndex) * Self.bandPointHeight
            return CGRect(x: 0, y: bandTop, width: size.width, height: min(Self.bandPointHeight, size.height - bandTop))
        }
    }

    struct EncodedImage {
        let pngData: Data
        /// A small rendering of the same pixels, for checking what a decoder sees.
        let reference: CGImage
    }

    /// Longest side of the reference image and of the decoded thumbnail it is compared with.
    static let referenceMaximumDimension = 256
    /// Largest difference, out of 255, allowed between the mean colors of matching strips
    /// of the reference and the decoded file. Resampling moves the means by a few levels;
    /// a failed encode (solid black, empty, shifted) moves them by far more.
    private static let maximumStripMeanDifference = 24.0
    private static let comparisonStripCount = 8

    /// - Parameter bandImage: The pixels of band `bandIndex`, at `raster.scale`, drawn with
    ///   its first row at the band's first row. Called in order, possibly more than once
    ///   per band if the encoder restarts.
    static func encode(_ raster: Raster, bandImage: (Int) throws -> CGImage) throws -> EncodedImage {
        try withoutActuallyEscaping(bandImage) { escapableBandImage in
            let source = try BandPixelSource(raster: raster, bandImage: escapableBandImage)
            var callbacks = CGDataProviderSequentialCallbacks(version: 0, getBytes: { information, buffer, requestedCount in
                guard let information else { return 0 }
                return Unmanaged<BandPixelSource>.fromOpaque(information).takeUnretainedValue().copyBytes(into: buffer, count: requestedCount)
            }, skipForward: { information, requestedCount in
                guard let information else { return 0 }
                return Unmanaged<BandPixelSource>.fromOpaque(information).takeUnretainedValue().skipBytes(count: requestedCount)
            }, rewind: { information in
                guard let information else { return }
                Unmanaged<BandPixelSource>.fromOpaque(information).takeUnretainedValue().rewind()
            }, releaseInfo: nil)
            // The source outlives the provider's use: the image is encoded and released
            // before this closure returns.
            let information = Unmanaged.passUnretained(source).toOpaque()
            guard let provider = CGDataProvider(sequentialInfo: information, callbacks: &callbacks),
                  let image = CGImage(width: raster.pixelWidth, height: raster.pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                                      bytesPerRow: raster.pixelWidth * 4, space: source.colorSpace, bitmapInfo: CGBitmapInfo(rawValue: source.bitmapInfo),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
                throw GraphiteError.unavailable("Cannot allocate the drawing image.")
            }
            let encoding = withExtendedLifetime(source) { Result { try ImageEncoding.pngData(from: image) } }
            // A band that failed to render ends the stream early; report why, not the
            // encoder's resulting complaint about missing rows.
            if let renderingError = source.renderingError { throw renderingError }
            let pngData = try encoding.get()
            guard source.hasProducedEveryRow, let reference = source.referenceContext.makeImage() else {
                throw GraphiteError.invalidFile("Cannot encode the drawing image.")
            }
            return EncodedImage(pngData: pngData, reference: reference)
        }
    }

    /// Whether an ordinary decoder sees the reference's picture in `fileData`. Decodes a
    /// small thumbnail, which ImageIO streams without holding the full bitmap.
    static func decodedContentMatches(_ fileData: Data, reference: CGImage) -> Bool {
        guard let imageSource = CGImageSourceCreateWithData(fileData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: referenceMaximumDimension,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let decodedMeans = stripMeans(of: thumbnail), let referenceMeans = stripMeans(of: reference),
              decodedMeans.count == referenceMeans.count else { return false }
        for (decodedStrip, referenceStrip) in zip(decodedMeans, referenceMeans) {
            for (decodedComponent, referenceComponent) in zip(decodedStrip, referenceStrip)
            where abs(decodedComponent - referenceComponent) > maximumStripMeanDifference {
                return false
            }
        }
        return true
    }

    /// Mean premultiplied RGBA of horizontal strips, top to bottom.
    private static func stripMeans(of image: CGImage) -> [[Double]]? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let pixelBytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let stripCount = min(comparisonStripCount, height)
        return (0..<stripCount).map { stripIndex in
            // Memory row 0 is the top row of the image.
            let firstRow = stripIndex * height / stripCount, endRow = (stripIndex + 1) * height / stripCount
            var componentTotals = [Double](repeating: 0, count: 4)
            for row in firstRow..<endRow {
                for column in 0..<width {
                    let pixelOffset = row * width * 4 + column * 4
                    for component in 0..<4 { componentTotals[component] += Double(pixelBytes[pixelOffset + component]) }
                }
            }
            let pixelCount = Double(max(1, (endRow - firstRow) * width))
            return componentTotals.map { total in total / pixelCount }
        }
    }
}

/// Produces the raster's bytes band by band for ImageIO's sequential reads, and draws each
/// band once into a small reference image.
private final class BandPixelSource {
    let raster: BandedPNGEncoder.Raster
    let colorSpace: CGColorSpace
    let bitmapInfo: UInt32
    let referenceContext: CGContext
    private(set) var renderingError: (any Error)?
    private let bandImage: (Int) throws -> CGImage
    private var bandPixels: [UInt8] = []
    private var nextBandIndex = 0
    private var offsetInBand = 0
    private var referenceBandCount = 0

    var bytesPerRow: Int { raster.pixelWidth * 4 }
    /// Every band was rendered at least once, so the reference shows the whole raster.
    var hasProducedEveryRow: Bool { referenceBandCount == raster.bandCount }

    init(raster: BandedPNGEncoder.Raster, bandImage: @escaping (Int) throws -> CGImage) throws {
        self.raster = raster
        self.bandImage = bandImage
        bitmapInfo = raster.isOpaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
        let referenceScale = Double(BandedPNGEncoder.referenceMaximumDimension) / Double(max(raster.pixelWidth, raster.pixelHeight))
        let referenceWidth = max(1, Int((Double(raster.pixelWidth) * min(1, referenceScale)).rounded()))
        let referenceHeight = max(1, Int((Double(raster.pixelHeight) * min(1, referenceScale)).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let referenceContext = CGContext(data: nil, width: referenceWidth, height: referenceHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw GraphiteError.unavailable("Cannot allocate the drawing image.")
        }
        self.colorSpace = colorSpace
        self.referenceContext = referenceContext
        referenceContext.interpolationQuality = .high
        if raster.isOpaque {
            referenceContext.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            referenceContext.fill(CGRect(x: 0, y: 0, width: referenceWidth, height: referenceHeight))
        }
    }

    func copyBytes(into buffer: UnsafeMutableRawPointer, count requestedCount: Int) -> Int {
        var copiedCount = 0
        while copiedCount < requestedCount, prepareBandIfNeeded() {
            let availableCount = min(requestedCount - copiedCount, bandPixels.count - offsetInBand)
            bandPixels.withUnsafeBytes { pixels in
                if let pixelStart = pixels.baseAddress {
                    (buffer + copiedCount).copyMemory(from: pixelStart + offsetInBand, byteCount: availableCount)
                }
            }
            copiedCount += availableCount
            offsetInBand += availableCount
        }
        return copiedCount
    }

    func skipBytes(count requestedCount: off_t) -> off_t {
        var skippedCount: off_t = 0
        while skippedCount < requestedCount, prepareBandIfNeeded() {
            let availableCount = min(Int(requestedCount - skippedCount), bandPixels.count - offsetInBand)
            skippedCount += off_t(availableCount)
            offsetInBand += availableCount
        }
        return skippedCount
    }

    func rewind() {
        nextBandIndex = 0
        offsetInBand = 0
        bandPixels = []
    }

    /// Renders the next band when the current one is used up. False at the end, or after
    /// a rendering error, which ends the stream early.
    private func prepareBandIfNeeded() -> Bool {
        if offsetInBand < bandPixels.count { return true }
        guard renderingError == nil, nextBandIndex < raster.bandCount else { return false }
        do {
            try renderBand(nextBandIndex)
            nextBandIndex += 1
            return offsetInBand < bandPixels.count
        } catch {
            renderingError = error
            bandPixels = []
            return false
        }
    }

    private func renderBand(_ bandIndex: Int) throws {
        let firstRow = bandIndex * raster.bandPixelHeight
        let rowCount = min(raster.bandPixelHeight, raster.pixelHeight - firstRow)
        bandPixels = [UInt8](repeating: 0, count: rowCount * bytesPerRow)
        offsetInBand = 0
        let image = try bandImage(bandIndex)
        try bandPixels.withUnsafeMutableBytes { pixels in
            guard let context = CGContext(data: pixels.baseAddress, width: raster.pixelWidth, height: rowCount, bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo) else {
                throw GraphiteError.unavailable("Cannot allocate the drawing image.")
            }
            context.interpolationQuality = .none
            if raster.isOpaque {
                context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: raster.pixelWidth, height: rowCount))
            }
            // Core Graphics puts the origin at the bottom-left, so the image is placed
            // against the top edge of the band.
            context.draw(image, in: CGRect(x: 0, y: rowCount - image.height, width: image.width, height: image.height))
        }
        if bandIndex == referenceBandCount {
            drawIntoReference(image, firstRow: firstRow)
            referenceBandCount += 1
        }
    }

    private func drawIntoReference(_ image: CGImage, firstRow: Int) {
        let horizontalScale = Double(referenceContext.width) / Double(raster.pixelWidth)
        let verticalScale = Double(referenceContext.height) / Double(raster.pixelHeight)
        let imageBottomRow = Double(firstRow + image.height)
        referenceContext.draw(image, in: CGRect(x: 0, y: (Double(raster.pixelHeight) - imageBottomRow) * verticalScale,
                                                width: Double(image.width) * horizontalScale, height: Double(image.height) * verticalScale))
    }
}
