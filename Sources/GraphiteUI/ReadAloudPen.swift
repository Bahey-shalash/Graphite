import SwiftUI

/// The Read Aloud pen's glyph on the bar: the laser's slim pointer (`PencilPointerOutline`),
/// leaning as a pen tip does, with two small sound waves at its tip in place of the laser's
/// red dot. The waves are its only color, the reading highlight's blue, so the bar stays
/// monochrome but for what each tool casts.
struct ReadAloudPenGlyph: View {
    let isInUse: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        ZStack {
            PencilPointerOutline()
                .stroke(style: StrokeStyle(lineWidth: isInUse ? LaserPointerGlyph.semiboldStrokeWidth : LaserPointerGlyph.regularStrokeWidth, lineJoin: .round))
                .foregroundStyle(isInUse ? .primary : .secondary)
            SoundWaves()
                .stroke(style: StrokeStyle(lineWidth: isInUse ? 1.8 : 1.5, lineCap: .round))
                .foregroundStyle(Self.waveColor(isDark: colorScheme == .dark, increasedContrast: colorSchemeContrast == .increased))
        }
        .frame(width: LaserPointerGlyph.side, height: LaserPointerGlyph.side)
        .rotationEffect(.degrees(45))
        .accessibilityHidden(true)
    }

    /// The waves' blue against the bar, white or black: at least 3:1 as a non-text element
    /// (5.6:1 on white, 8.0:1 on black), more with Increase Contrast (7.7:1 and 10.1:1).
    static func waveColor(isDark: Bool, increasedContrast: Bool) -> Color {
        switch (isDark, increasedContrast) {
        case (false, false): Color(red: 0x00 / 255, green: 0x64 / 255, blue: 0xD2 / 255)
        case (false, true): Color(red: 0x00 / 255, green: 0x50 / 255, blue: 0xAA / 255)
        case (true, false): Color(red: 0x4D / 255, green: 0xA3 / 255, blue: 0xFF / 255)
        case (true, true): Color(red: 0x7A / 255, green: 0xB8 / 255, blue: 0xFF / 255)
        }
    }

    /// Two arcs spreading from the pointer's tip, as a speaker's waves do.
    private struct SoundWaves: Shape {
        func path(in rect: CGRect) -> Path {
            let scale = rect.width / LaserPointerGlyph.side
            let tip = PencilPointerOutline.tip
            var arcs = Path()
            // Each arc is its own subpath, so no line joins one to the next.
            for radius: CGFloat in [3, 5.8] {
                let startAngle = -140 * CGFloat.pi / 180
                arcs.move(to: CGPoint(x: tip.x + radius * cos(startAngle), y: tip.y + radius * sin(startAngle)))
                arcs.addArc(center: tip, radius: radius, startAngle: .degrees(-140), endAngle: .degrees(-40), clockwise: false)
            }
            return arcs.applying(CGAffineTransform(scaleX: scale, y: scale)).offsetBy(dx: rect.minX, dy: rect.minY)
        }
    }
}

#if canImport(UIKit)
import UIKit
import PencilKit

extension ReadAloudPenGlyph {
    /// The glyph as a template image, for the floating palette's menu and button.
    @MainActor static func templateImage() -> UIImage? {
        if let cachedTemplateImage { return cachedTemplateImage }
        let renderer = ImageRenderer(content: ReadAloudPenGlyph(isInUse: false).foregroundStyle(.black).environment(\.colorScheme, .light))
        renderer.scale = 3
        let image = renderer.uiImage?.withRenderingMode(.alwaysTemplate)
        cachedTemplateImage = image
        return image
    }

    @MainActor private static var cachedTemplateImage: UIImage?
}

/// The Read Aloud pen on one canvas: a tap of Apple Pencil, or of a finger when fingers draw,
/// tells the canvas's owner where it landed, which reads from the word there or marks where
/// reading stops (`ReadAloudNavigator.penTapped`). Like the laser it never draws, never
/// changes the document, and takes no hand resting on the page (`CanvasToolTouches`).
@MainActor
final class ReadAloudPenController: NSObject, UIGestureRecognizerDelegate {
    private unowned let canvas: HistoryCanvasView
    private lazy var tapRecognizer: ReadAloudPenTapRecognizer = {
        let recognizer = ReadAloudPenTapRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.delegate = self
        return recognizer
    }()

    init(canvas: HistoryCanvasView) {
        self.canvas = canvas
    }

    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if isActive, tapRecognizer.view == nil { canvas.addGestureRecognizer(tapRecognizer) }
            tapRecognizer.isEnabled = isActive
        }
    }

    /// The pen takes the touches the canvas would draw with: the Pencil, and a finger when
    /// fingers draw. Other fingers scroll the page as they do while drawing.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        canvas.drawingGestureRecognizer.allowedTouchTypes.contains(NSNumber(value: touch.type.rawValue))
            && !CanvasToolTouches.isHandResting(touch)
    }

    @objc private func handleTap(_ recognizer: ReadAloudPenTapRecognizer) {
        guard recognizer.state == .ended, let window = canvas.window else { return }
        canvas.readAloudPenTapped?(recognizer.location(in: window))
    }
}

/// Hears the floating palette show, hide or move, for the floating player to keep clear of it.
final class PaletteFrameObserver: NSObject, PKToolPickerObserver {
    private let changed: @MainActor () -> Void
    init(changed: @escaping @MainActor () -> Void) { self.changed = changed }
    func toolPickerVisibilityDidChange(_ toolPicker: PKToolPicker) { MainActor.assumeIsolated { changed() } }
    func toolPickerFramesObscuredDidChange(_ toolPicker: PKToolPicker) { MainActor.assumeIsolated { changed() } }
}

/// A touch that lifts within a moment and a few points of where it landed: a tap of the pen.
/// A drag is not a tap, so moving across the page with the pen reads nothing.
final class ReadAloudPenTapRecognizer: UIGestureRecognizer {
    static let maximumMovement: CGFloat = 14
    static let maximumDuration: TimeInterval = 0.8
    private weak var trackedTouch: UITouch?
    private var startLocation: CGPoint = .zero
    private var startTimestamp: TimeInterval = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first, touches.count == 1 else {
            state = .failed
            return
        }
        trackedTouch = touch
        startLocation = touch.location(in: nil)
        startTimestamp = touch.timestamp
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        let location = trackedTouch.location(in: nil)
        if hypot(location.x - startLocation.x, location.y - startLocation.y) > Self.maximumMovement { state = .failed }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = trackedTouch.timestamp - startTimestamp <= Self.maximumDuration ? .ended : .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
    }

    override func location(in view: UIView?) -> CGPoint {
        guard let view else { return startLocation }
        return view.convert(startLocation, from: nil)
    }
}

/// Where the Read Aloud pen marked the start or the end of what is read, on a PDF page: a
/// bar at the word's edge with a round end, as text selection marks its ends, over a faint
/// tint of the word. It is drawn over the page, never into it, and takes no touches.
final class ReadAloudPenMarkerView: UIView {
    static let color = UIColor.systemBlue
    let isStart: Bool
    private let tint = UIView()
    private let bar = UIView()
    private let knob = UIView()

    init(isStart: Bool) {
        self.isStart = isStart
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = isStart ? "Reading starts here" : "Reading stops here"
        tint.backgroundColor = Self.color.withAlphaComponent(0.14)
        bar.backgroundColor = Self.color
        knob.backgroundColor = Self.color
        // A white rim sets the knob apart from blue ink and dark pictures.
        knob.layer.borderColor = UIColor.white.cgColor
        knob.layer.borderWidth = 1
        for part in [tint, bar, knob] { addSubview(part) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ReadAloudPenMarkerView is created in code.") }

    /// Places the marker over a word's rectangle, given in its superview's coordinates.
    func place(overWord wordFrame: CGRect) {
        let knobSide: CGFloat = 9, barWidth: CGFloat = 2
        let outset = wordFrame.insetBy(dx: -1, dy: -2)
        frame = outset.insetBy(dx: -knobSide, dy: -knobSide)
        let word = convert(outset, from: superview)
        tint.frame = word
        tint.layer.cornerRadius = 2
        let barX = isStart ? word.minX - barWidth / 2 : word.maxX - barWidth / 2
        bar.frame = CGRect(x: barX, y: word.minY, width: barWidth, height: word.height)
        let knobCenterY = isStart ? word.minY - knobSide / 2 + 1 : word.maxY + knobSide / 2 - 1
        knob.frame = CGRect(x: barX + barWidth / 2 - knobSide / 2, y: knobCenterY - knobSide / 2, width: knobSide, height: knobSide)
        knob.layer.cornerRadius = knobSide / 2
    }
}
#endif

/// Where the Read Aloud pen tapped a PDF: a word, or a page without text to tell words apart
/// (a scan), which is read whole.
enum PDFReadAloudPenTap: Equatable {
    case word(pageIndex: Int, range: NSRange, bounds: CGRect)
    case page(pageIndex: Int)
}

/// A start or end the Read Aloud pen marked, shown over its page.
struct PDFReadAloudMarker: Equatable {
    let pageIndex: Int
    /// The word's rectangle in page space.
    let bounds: CGRect
    let isStart: Bool
}
