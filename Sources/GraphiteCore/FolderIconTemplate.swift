import CoreGraphics

/// The shapes the icon maker puts a picture in, each built as three layers: a back (Apple's
/// folder art, or nothing), the picture clipped to a shape over the background color, and a
/// top (a page's turned corner). The geometry is in fractions of the icon's side, measured
/// on the system's folder icon of macOS 27 (front face from 4% to 96% across and 26% to 87%
/// down, as `NSWorkspace.icon(for: .folder)` draws it at 256 pixels).
public enum FolderIconTemplate: String, CaseIterable, Identifiable, Sendable {
    /// The picture fills the folder's front face.
    case folderFull
    /// The picture, small and rounded, in the middle of the folder, as Finder draws app folders.
    case folderCenter
    case round
    /// The rounded square of an app icon.
    case squircle
    /// A page with its top corner turned.
    case document

    public var id: Self { self }

    /// A shape the picture is clipped to.
    public enum Clip: Equatable, Sendable {
        /// Corner radius as a fraction of the frame's width.
        case roundedRectangle(cornerFraction: CGFloat)
        case ellipse
        /// A page whose top-right corner is turned, the fold a fraction of the frame's width.
        case page(foldFraction: CGFloat)
    }

    /// The frame the picture is placed in, in fractions of the icon's side, from the top left.
    public var pictureFrame: CGRect {
        switch self {
        case .folderFull: CGRect(x: 0.04, y: 0.262, width: 0.92, height: 0.605)
        case .folderCenter: CGRect(x: 0.29, y: 0.36, width: 0.42, height: 0.42)
        case .round, .squircle: CGRect(x: 0.098, y: 0.098, width: 0.804, height: 0.804)
        case .document: CGRect(x: 0.17, y: 0.07, width: 0.66, height: 0.86)
        }
    }

    public var clip: Clip {
        switch self {
        case .folderFull: .roundedRectangle(cornerFraction: 0.06)
        case .folderCenter: .roundedRectangle(cornerFraction: 0.18)
        case .round: .ellipse
        case .squircle: .roundedRectangle(cornerFraction: 0.2237)
        case .document: .page(foldFraction: 0.26)
        }
    }

    /// Whether Apple's folder art is drawn behind the picture.
    public var isOnFolder: Bool {
        switch self {
        case .folderFull, .folderCenter: true
        case .round, .squircle, .document: false
        }
    }

    /// How the made picture is kept: the centered picture alone, so the folder keeps its
    /// color, or the whole icon.
    public var layout: FolderPictureLayout {
        switch self {
        case .folderCenter: .onFolder
        case .folderFull, .round, .squircle, .document: .wholeIcon
        }
    }

    /// A blank page needs a color behind a transparent picture; the others show the art or nothing.
    public var defaultBackground: CGColorComponents? {
        switch self {
        case .document: CGColorComponents(red: 1, green: 1, blue: 1)
        case .folderFull, .folderCenter, .round, .squircle: nil
        }
    }
}

/// An opaque sRGB color, as plain numbers for drawing outside SwiftUI.
public struct CGColorComponents: Equatable, Hashable, Sendable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// Everything the icon maker sets: the template, where the picture sits, and the color behind it.
public struct FolderIconDesign: Equatable, Hashable, Sendable {
    public var template: FolderIconTemplate
    public var framing: FolderPictureFraming
    /// Nil is transparent, or the template's own background.
    public var background: CGColorComponents?

    public init(template: FolderIconTemplate = .folderCenter, framing: FolderPictureFraming = .filling, background: CGColorComponents? = nil) {
        self.template = template
        self.framing = framing
        self.background = background
    }

    /// The color drawn behind the picture: the one chosen, else the template's own.
    public var effectiveBackground: CGColorComponents? { background ?? template.defaultBackground }
}
