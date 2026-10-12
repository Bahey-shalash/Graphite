import SwiftUI

/// The laser pointer's glyph on the fixed bar: a slim pointer drawn at the stroke weight of
/// the SF Symbols beside it (the inks' tips, the eraser, the lasso), leaning toward the top
/// right as a pen tip does, with a small red dot glowing at its tip. The dot is its only
/// color, the laser's red, so the bar's tools stay monochrome but for what each one draws.
/// `laser.burst`, the system's starburst, read as a flash rather than as pointing, and was
/// far denser than its neighbors.
struct LaserPointerGlyph: View {
    /// Drawn at the weight of the tool in use, as the other tools' symbols are.
    let isInUse: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// The side of the square the glyph is drawn in, matching a 17-point symbol.
    static let side: CGFloat = 22
    /// SF Symbols' stroke at 17 points, regular and semibold.
    static let regularStrokeWidth: CGFloat = 1.5
    static let semiboldStrokeWidth: CGFloat = 2

    var body: some View {
        ZStack {
            PointerOutline()
                .stroke(style: StrokeStyle(lineWidth: isInUse ? Self.semiboldStrokeWidth : Self.regularStrokeWidth, lineJoin: .round))
                .foregroundStyle(isInUse ? .primary : .secondary)
            Circle()
                .fill(Self.dotColor(isDark: colorScheme == .dark, increasedContrast: colorSchemeContrast == .increased))
                .frame(width: 5, height: 5)
                .shadow(color: Self.dotColor(isDark: colorScheme == .dark, increasedContrast: false).opacity(0.7), radius: 1.5)
                // A beam's width from the tip, so the dot reads as what the pointer casts.
                .position(x: Self.side / 2, y: 3)
        }
        .frame(width: Self.side, height: Self.side)
        // A pen tip leans toward the top right, as the inks' symbols do.
        .rotationEffect(.degrees(45))
        .accessibilityHidden(true)
    }

    /// The dot's red against the bar's background, white or black: at least 3:1 as a
    /// non-text element (4.7:1 on white, 6.2:1 on black), and further with Increase
    /// Contrast (6.0:1 and 7.5:1).
    static func dotColor(isDark: Bool, increasedContrast: Bool) -> Color {
        switch (isDark, increasedContrast) {
        case (false, false): Color(red: 0xE0 / 255, green: 0x26 / 255, blue: 0x1A / 255)
        case (false, true): Color(red: 0xC8 / 255, green: 0x00 / 255, blue: 0x1E / 255)
        case (true, false): Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255)
        case (true, true): Color(red: 0xFF / 255, green: 0x69 / 255, blue: 0x61 / 255)
        }
    }

    /// The pointer, upright: a slim body with a rounded end and a pointed tip, in the
    /// glyph's 22-point square.
    private struct PointerOutline: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = rect.width / LaserPointerGlyph.side
            let middle = LaserPointerGlyph.side / 2
            let halfWidth: CGFloat = 2.6
            let tipBaseY: CGFloat = 11.5, tipY: CGFloat = 7.5, endY: CGFloat = 21.5
            var path = Path()
            path.move(to: CGPoint(x: middle, y: tipY))
            path.addLine(to: CGPoint(x: middle + halfWidth, y: tipBaseY))
            path.addLine(to: CGPoint(x: middle + halfWidth, y: endY - halfWidth))
            path.addArc(center: CGPoint(x: middle, y: endY - halfWidth), radius: halfWidth, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: middle - halfWidth, y: tipBaseY))
            path.closeSubpath()
            // The line where the tip meets the body, as a pen's tip is set apart.
            path.move(to: CGPoint(x: middle - halfWidth, y: tipBaseY))
            path.addLine(to: CGPoint(x: middle + halfWidth, y: tipBaseY))
            return path.applying(CGAffineTransform(scaleX: scale, y: scale)).offsetBy(dx: rect.minX, dy: rect.minY)
        }
    }
}

#if canImport(UIKit)
import UIKit

extension LaserPointerGlyph {
    /// The glyph as a template image, for the floating palette's menu and button, which draw
    /// their images in one color of their own.
    @MainActor static func templateImage() -> UIImage? {
        if let cachedTemplateImage { return cachedTemplateImage }
        let renderer = ImageRenderer(content: LaserPointerGlyph(isInUse: false).foregroundStyle(.black).environment(\.colorScheme, .light))
        renderer.scale = 3
        let image = renderer.uiImage?.withRenderingMode(.alwaysTemplate)
        cachedTemplateImage = image
        return image
    }

    @MainActor private static var cachedTemplateImage: UIImage?
}
#endif
