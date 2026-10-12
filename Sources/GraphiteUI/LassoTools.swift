import Foundation
import CoreGraphics
import SwiftUI
import GraphiteCore

/// How Graphite's lasso is drawn: a loop drawn freehand around what to take, or a box
/// dragged from one corner to the opposite one. Chosen from the lasso's button and kept
/// between launches, for every canvas.
enum LassoShape: String, CaseIterable, Identifiable {
    case freehand, rectangle

    static let preferenceKey = "GraphiteLassoShape"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .freehand: "Freehand"
        case .rectangle: "Rectangle"
        }
    }
    var symbolName: String {
        switch self {
        case .freehand: "lasso"
        case .rectangle: "rectangle.dashed"
        }
    }

    static var stored: LassoShape {
        get { UserDefaults.standard.string(forKey: preferenceKey).flatMap(LassoShape.init(rawValue:)) ?? .freehand }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey) }
    }
}

/// What the laser pointer shows: a glowing dot under the Pencil or finger that is gone
/// when it lifts, or a line that fades a moment after it is drawn. Kept between launches.
enum LaserPointerStyle: String, CaseIterable, Identifiable {
    case dot, line

    static let preferenceKey = "GraphiteLaserPointerStyle"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dot: "Dot"
        case .line: "Line"
        }
    }
    var symbolName: String {
        switch self {
        case .dot: "circle.fill"
        case .line: "scribble"
        }
    }

    static var stored: LaserPointerStyle {
        get { UserDefaults.standard.string(forKey: preferenceKey).flatMap(LaserPointerStyle.init(rawValue:)) ?? .dot }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey) }
    }
}

/// Where a picture of the page, taken with the lasso, can be inserted as an attachment:
/// the note a PDF is embedded in, the note open beside a PDF, or the note a drawing
/// belongs to.
struct LassoNoteDestination {
    /// The note's name, for "Add to “Name”".
    let noteName: String
    /// Saves PNG data as an attachment of the note, under a name made from the second
    /// argument (such as "Lecture 3, page 4"), and embeds it there.
    let addImage: (_ pngData: Data, _ name: String) -> Void
}

extension WorkspaceModel {
    /// Saves a picture taken with the lasso as an attachment of the note, where the note's
    /// attachments go, and embeds it at the note's cursor, as a pasted image is.
    func addLassoPicture(_ pngData: Data, named name: String, to note: MarkdownSession) async {
        await saveAttachment(pngData, stem: LassoNoteDestination.fileStem(for: name), fileExtension: "png", into: note)
    }
}

#if canImport(UIKit)
extension WorkspaceModel {
    /// The note a drawing goes into, or was opened over an image from, while that note is
    /// open: where the lasso's pictures of the drawing can be added.
    func lassoNoteDestination(for request: DrawingEditorRequest) -> LassoNoteDestination? {
        let notePath: VaultPath?
        switch request.target {
        case .newDrawing(let path, _): notePath = path
        case .drawingOnImage(_, let path): notePath = path
        case .existingDrawing: notePath = nil
        }
        guard let notePath, let note = openMarkdownSession(at: notePath) else { return nil }
        return .note(note, in: self)
    }
}
#endif

extension LassoNoteDestination {
    /// The note a view shows, as the destination of the lasso's pictures in it.
    @MainActor static func note(_ note: MarkdownSession, in workspace: WorkspaceModel) -> LassoNoteDestination {
        LassoNoteDestination(noteName: workspace.preferences.displayName(for: note.path)) { pngData, name in
            Task { await workspace.addLassoPicture(pngData, named: name, to: note) }
        }
    }

    /// A file name from a picture's name: characters that a file name or a link cannot hold
    /// become hyphens, and an empty name becomes "Screenshot".
    static func fileStem(for name: String) -> String {
        let reservedCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")
        let stem = name.unicodeScalars.map { scalar in reservedCharacters.contains(scalar) ? "-" : String(scalar) }.joined()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return stem.isEmpty ? "Screenshot" : stem
    }
}

extension EnvironmentValues {
    /// The note a view's embedded PDFs belong to, for the lasso's Add to Note.
    @Entry var lassoNoteDestination: LassoNoteDestination? = nil
}

#if canImport(UIKit)
import UIKit
import PencilKit
import LinkPresentation
import GraphiteCore

/// The colors of what the lasso draws over a page. The pages and a drawing's paper keep
/// their own colors in dark appearance, so these do not follow the appearance: the accent
/// as it reads on white, over a white halo that keeps it visible on dark ink and pictures.
@MainActor
enum LassoColors {
    static func line(for traitCollection: UITraitCollection) -> UIColor {
        let pageTraits = UITraitCollection(traitsFrom: [traitCollection, UITraitCollection(userInterfaceStyle: .light)])
        let accent = PlatformColor.graphiteAccent(hex: GraphitePreferences.storedAccentHex()) ?? .systemBlue
        return accent.resolvedColor(with: pageTraits)
    }

    static let halo = UIColor.white.withAlphaComponent(0.9)
    /// The enclosed area is tinted this faintly, so it reads as an area and not as ink.
    static let areaFillOpacity: CGFloat = 0.08
}

/// A picture placed on a page or a drawing, as Graphite's lasso sees it: in the drawing's
/// coordinates, whose top-left corner is the page's or the drawing's.
struct LassoPicture: Equatable {
    /// Unique among the canvas's pictures.
    let identifier: String
    /// The picture's frame before it is turned.
    var frame: CGRect
    /// How far the picture is turned about its middle, in radians, clockwise on screen.
    var rotationRadians: Double

    /// The upright rectangle the picture covers once turned.
    var boundingFrame: CGRect { PictureRotation.boundingRectangle(of: frame, turnedBy: rotationRadians) }

    /// The picture's four corners as turned, which a loop must mostly enclose to take it.
    var corners: [CGPoint] {
        let middle = CGPoint(x: frame.midX, y: frame.midY)
        return [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY),
                CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.minX, y: frame.maxY)].map { corner in
            PictureRotation.point(corner, turnedBy: rotationRadians, about: middle)
        }
    }
}

/// What a canvas offers Graphite's lasso besides its ink: the pictures placed under the
/// ink, which a selection moves, resizes and deletes with the ink; and what lies under
/// the ink, for a picture of an area. PDF pages and the drawing editor's canvas provide it.
@MainActor
protocol LassoCanvasContent: AnyObject {
    /// The pictures under the ink, the lowest first.
    func lassoPictures() -> [LassoPicture]
    /// The picture's image as it is drawn, upright.
    func lassoPictureImage(_ identifier: String) -> UIImage?
    /// Moves or resizes pictures to new frames, each kept turned as it was. Called in the
    /// same turn of the run loop as the ink's change, so both are one step of the history.
    func moveLassoPictures(to frames: [String: CGRect])
    /// Removes pictures, in the same step of the history as the ink removed with them.
    func deleteLassoPictures(_ identifiers: [String])
    /// Hides pictures while the selection's frame carries their picture.
    func setLassoPicturesHidden(_ identifiers: Set<String>)
    /// Draws what lies under the ink in a region of the drawing's coordinates: the PDF
    /// page with its pictures, or a drawing's paper and pictures. The context's coordinates
    /// are the drawing's.
    func drawContentUnderInk(in context: CGContext, region: CGRect)
    /// How many quarter turns clockwise the drawing is shown at, as a turned PDF page is.
    var lassoDisplayQuarterTurns: Int { get }
    /// The part of the drawing's coordinates there is anything in, which a picture of an
    /// area is kept to: the page, or the width of a drawing.
    var lassoDrawingBounds: CGRect { get }
    /// A name for a picture taken of an area, such as "Lecture 3, page 4".
    var lassoCaptureName: String { get }
    /// Where such a picture can be added as an attachment; nil when there is no note.
    var lassoNoteDestination: LassoNoteDestination? { get }
}

/// Pictures of an area of a page or a drawing, taken with the lasso: the page's own
/// content, its pictures and the ink, drawn afresh at print resolution rather than taken
/// from the screen, so an area of a zoomed-out page is as sharp as the page itself.
@MainActor
enum LassoAreaCapture {
    /// Pixels per point of the drawing: 288 per inch on a PDF page, enough for print.
    static let preferredPixelsPerPoint: CGFloat = 4
    /// The longest side of a picture, in pixels; a larger area is drawn at a lower scale.
    static let maximumSidePixels: CGFloat = 6_000
    /// The most pixels in a picture: 24 megapixels, under 100 MB while it is drawn.
    static let maximumPixelCount: CGFloat = 24_000_000

    /// The scale an area is drawn at: the preferred one, or what the screen shows when that
    /// is finer, kept under the limits.
    static func pixelsPerPoint(for region: CGRect, screenPixelsPerPoint: CGFloat) -> CGFloat {
        guard region.width > 0, region.height > 0 else { return 1 }
        let wanted = max(preferredPixelsPerPoint, screenPixelsPerPoint)
        let sideLimit = maximumSidePixels / max(region.width, region.height)
        let countLimit = (maximumPixelCount / (region.width * region.height)).squareRoot()
        return max(min(wanted, sideLimit, countLimit), 0.25)
    }

    /// The picture of a region of a canvas's drawing: what lies under the ink, then the ink,
    /// turned as the page is shown. Nil for an empty region.
    static func image(of region: CGRect, drawing: PKDrawing, content: LassoCanvasContent?, screenPixelsPerPoint: CGFloat) -> UIImage? {
        let region = region.integral
        guard !region.isNull, !region.isInfinite, region.width >= 1, region.height >= 1 else { return nil }
        let scale = pixelsPerPoint(for: region, screenPixelsPerPoint: screenPixelsPerPoint)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        // Ink is drawn as it looks on white paper, as the canvases show it.
        format.preferredRange = .standard
        let strokesInRegion = drawing.strokes.filter { stroke in stroke.renderBounds.intersects(region) }
        var inkImage: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            if !strokesInRegion.isEmpty { inkImage = PKDrawing(strokes: strokesInRegion).image(from: region, scale: scale) }
        }
        let upright = UIGraphicsImageRenderer(size: region.size, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            context.saveGState()
            context.translateBy(x: -region.minX, y: -region.minY)
            content?.drawContentUnderInk(in: context, region: region)
            context.restoreGState()
            inkImage?.draw(in: CGRect(origin: .zero, size: region.size))
        }
        return turned(upright, quarterTurnsClockwise: content?.lassoDisplayQuarterTurns ?? 0)
    }

    /// The image turned clockwise by quarter turns, drawn afresh so PNG data keeps the turn.
    static func turned(_ image: UIImage, quarterTurnsClockwise: Int) -> UIImage {
        let turns = ((quarterTurnsClockwise % 4) + 4) % 4
        guard turns != 0 else { return image }
        let size = turns % 2 == 1 ? CGSize(width: image.size.height, height: image.size.width) : image.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let context = rendererContext.cgContext
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: CGFloat(turns) * .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }

    /// Draws a picture into its frame, turned about the frame's middle.
    static func draw(_ picture: UIImage, in frame: CGRect, turnedBy rotationRadians: Double, context: CGContext) {
        context.saveGState()
        context.translateBy(x: frame.midX, y: frame.midY)
        context.rotate(by: CGFloat(rotationRadians))
        picture.draw(in: CGRect(x: -frame.width / 2, y: -frame.height / 2, width: frame.width, height: frame.height))
        context.restoreGState()
    }

    /// Offers the picture of an area: the system's share sheet, whose Copy, Save Image and
    /// sharing need nothing of Graphite's, with Add to Note first when there is a note.
    static func presentShareSheet(for image: UIImage, name: String, destination: LassoNoteDestination?, from sourceView: UIView, sourceRect: CGRect) {
        guard let presenter = topmostViewController(from: sourceView) else { return }
        let item = LassoCaptureItem(image: image, name: name)
        let activities = destination.map { destination in [AddToNoteActivity(destination: destination, image: image, name: name)] } ?? []
        let shareSheet = UIActivityViewController(activityItems: [item], applicationActivities: activities)
        shareSheet.popoverPresentationController?.sourceView = sourceView
        shareSheet.popoverPresentationController?.sourceRect = sourceRect
        presenter.present(shareSheet, animated: !GraphiteMotion.isReduced)
    }

    private static func topmostViewController(from view: UIView) -> UIViewController? {
        var controller = view.window?.rootViewController
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed { controller = presented }
        return controller
    }
}

/// The picture in the share sheet, with its name as the sheet's title.
private final class LassoCaptureItem: NSObject, UIActivityItemSource {
    let image: UIImage
    let name: String

    init(image: UIImage, name: String) {
        self.image = image
        self.name = name
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { image }
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { image }
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String { name }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = name
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }
}

/// "Add to “Note”" in the share sheet: saves the picture as an attachment of the note and
/// embeds it, as pasting an image into the note does.
final class AddToNoteActivity: UIActivity {
    private let destination: LassoNoteDestination
    private let image: UIImage
    private let name: String

    init(destination: LassoNoteDestination, image: UIImage, name: String) {
        self.destination = destination
        self.image = image
        self.name = name
        super.init()
    }

    override class var activityCategory: UIActivity.Category { .action }
    override var activityType: UIActivity.ActivityType? { UIActivity.ActivityType("com.graphite.study.addToNote") }
    override var activityTitle: String? { "Add to “\(destination.noteName)”" }
    override var activityImage: UIImage? { UIImage(systemName: "note.text.badge.plus") }
    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }

    override func perform() {
        if let pngData = image.pngData() { destination.addImage(pngData, name) }
        activityDidFinish(true)
    }
}
#endif
