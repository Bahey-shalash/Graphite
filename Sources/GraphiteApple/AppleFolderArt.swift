import Foundation
import CoreGraphics
import GraphiteCore

/// Draws a folder look with Apple's own folder art, as `AppleFolderArtPlan` says: the system
/// draws a stand-in folder in Graphite's temporary items (Finder's art on the Mac, the Files
/// app's on iOS), then a color no tag has is tinted in and a picture is placed on it.
public struct AppleFolderArt: Sendable {
    /// Where the stand-in folders are kept: one empty folder per look, in the temporary items.
    public let standInDirectory: URL

    public init(standInDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("Graphite Folder Looks", isDirectory: true)) {
        self.standInDirectory = standInDirectory
    }

    /// The look drawn `pixels` wide; nil when the system gives no folder art, and the caller
    /// draws the folder itself.
    public func art(for style: FolderStyle, picture: CGImage?, pixels: Int) async -> CGImage? {
        let plan = AppleFolderArtPlan.plan(for: style)
        if plan.picture?.layout == .wholeIcon { return picture }
        guard var art = await standInArt(plan, pixels: pixels) else { return nil }
        if let tintColor = plan.tintColor, let tinted = Self.tinted(art, to: tintColor) { art = tinted }
        if let picture, let pictureLayout = plan.picture?.layout {
            art = FolderIconRenderer.finderIcon(picture: picture, layout: pictureLayout, folderIcon: art) ?? art
        }
        return art
    }

    private func standInArt(_ plan: AppleFolderArtPlan, pixels: Int) async -> CGImage? {
        let name = plan.standInName
        let standIn = standInDirectory.appendingPathComponent(name, isDirectory: true)
        do {
            if !FileManager.default.fileExists(atPath: standIn.path) {
                try FileManager.default.createDirectory(at: standIn, withIntermediateDirectories: true)
                try FinderFolderAttributes(root: standInDirectory).write(plan.standIn, to: VaultPath(name))
            }
        } catch {
            // Without a stand-in there is no Apple art for this look; the caller draws it.
            return nil
        }
        return await FinderFolderAttributes.systemIcon(at: standIn, pixels: pixels)
    }

    /// Recolors gray folder art: each pixel keeps its lightness and takes the color's hue and
    /// saturation (the `color` blend mode), so the gradient and edges stay Apple's.
    static func tinted(_ art: CGImage, to color: FolderColor) -> CGImage? {
        guard let components = color.sRGBComponents,
              let context = CGContext(data: nil, width: art.width, height: art.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: art.width, height: art.height)
        context.draw(art, in: bounds)
        context.saveGState()
        context.clip(to: bounds, mask: art)
        context.setBlendMode(.color)
        context.setFillColor(CGColor(srgbRed: components.red, green: components.green, blue: components.blue, alpha: 1))
        context.fill(bounds)
        context.restoreGState()
        return context.makeImage()
    }
}

extension FolderColor {
    /// The color as sRGB components, for drawing outside SwiftUI: the system colors' light
    /// appearance, or a custom color as stored. Nil for a color this build does not know.
    public var sRGBComponents: (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        switch self {
        case .blue: (0, 0.533, 1)
        case .green: (0.204, 0.78, 0.349)
        case .yellow: (1, 0.8, 0)
        case .orange: (1, 0.584, 0)
        case .red: (1, 0.22, 0.235)
        case .pink: (1, 0.176, 0.333)
        case .purple: (0.796, 0.188, 0.878)
        case .indigo: (0.38, 0.333, 0.961)
        case .teal: (0, 0.765, 0.816)
        case .gray: (0.557, 0.557, 0.576)
        case .custom(let red, let green, let blue): (CGFloat(red) / 255, CGFloat(green) / 255, CGFloat(blue) / 255)
        case .unknown: nil
        }
    }
}
