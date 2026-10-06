import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit

/// The board with its touch handling. The board is SwiftUI; the gestures are UIKit's,
/// on a view around it, because only they offer what an endless board needs: a
/// two-finger pan that also takes trackpad scrolling, a pinch that also takes the
/// trackpad's, and touches on the cards themselves, which SwiftUI would give to the
/// cards alone. A finger, a Pencil and a pointer all arrive through the same recognizers.
struct CanvasBoardHost: UIViewControllerRepresentable {
    let session: CanvasSession
    let environment: CanvasCardEnvironment

    func makeUIViewController(context: Context) -> CanvasBoardViewController {
        CanvasBoardViewController(session: session, board: board(in: context))
    }

    func updateUIViewController(_ controller: CanvasBoardViewController, context: Context) {
        controller.show(board(in: context), for: session)
    }

    /// The board with this view's whole environment, which a hosting controller of its
    /// own would not inherit: the accent, the text size, and the app's own values.
    private func board(in context: Context) -> AnyView {
        AnyView(CanvasBoardView(session: session, environment: environment).environment(\.self, context.environment))
    }
}

final class CanvasBoardViewController: UIViewController, UIGestureRecognizerDelegate {
    private(set) var session: CanvasSession
    private let hostingController: UIHostingController<AnyView>
    private let twoFingerPan = UIPanGestureRecognizer()
    private let pinch = UIPinchGestureRecognizer()
    private let drag = UIPanGestureRecognizer()
    private let tap = UITapGestureRecognizer()
    private let doubleTap = UITapGestureRecognizer()
    private let longPress = UILongPressGestureRecognizer()
    private var keyboardObserver: NSObjectProtocol?

    /// How far a scroll with Command held must travel to double the magnification.
    private static let scrollDistancePerDoubling: CGFloat = 240

    init(session: CanvasSession, board: AnyView) {
        self.session = session
        hostingController = UIHostingController(rootView: board)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    isolated deinit {
        if let keyboardObserver { NotificationCenter.default.removeObserver(keyboardObserver) }
    }

    func show(_ board: AnyView, for session: CanvasSession) {
        self.session = session
        hostingController.rootView = board
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(hostingController)
        hostingController.view.backgroundColor = .clear
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // The board is the same size whatever the keyboard or the bars do; a card being
        // edited is brought above the keyboard by moving the board instead.
        hostingController.safeAreaRegions = []
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        twoFingerPan.minimumNumberOfTouches = 2
        twoFingerPan.maximumNumberOfTouches = 2
        // Trackpad and mouse-wheel scrolling arrive as a pan without touches.
        twoFingerPan.allowedScrollTypesMask = .all
        twoFingerPan.addTarget(self, action: #selector(handleTwoFingerPan))
        pinch.addTarget(self, action: #selector(handlePinch))
        drag.maximumNumberOfTouches = 1
        drag.addTarget(self, action: #selector(handleDrag))
        tap.addTarget(self, action: #selector(handleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.addTarget(self, action: #selector(handleDoubleTap))
        longPress.addTarget(self, action: #selector(handleLongPress))
        for recognizer in [twoFingerPan, pinch, drag, tap, doubleTap, longPress] as [UIGestureRecognizer] {
            recognizer.delegate = self
            // Buttons, links and players inside cards still get their touches.
            recognizer.cancelsTouchesInView = false
            view.addGestureRecognizer(recognizer)
        }
        keyboardObserver = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] notification in
            let keyboardFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            MainActor.assumeIsolated { self?.revealEditedCard(aboveKeyboardWithScreenFrame: keyboardFrame) }
        }
    }

    // MARK: Gestures

    @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        if recognizer.state == .began { session.stopViewportAnimation() }
        let translation = recognizer.translation(in: view)
        recognizer.setTranslation(.zero, in: view)
        if recognizer.numberOfTouches == 0, recognizer.modifierFlags.contains(.command) {
            // Command and scroll zooms, as Obsidian's Ctrl or Cmd and scroll does.
            var viewport = session.viewport
            viewport.zoom(by: pow(2, translation.y / Self.scrollDistancePerDoubling), around: recognizer.location(in: view))
            session.viewport = viewport
            return
        }
        var viewport = session.viewport
        viewport.pan(byViewTranslation: CGSize(width: translation.x, height: translation.y))
        session.viewport = viewport
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard recognizer.state == .began || recognizer.state == .changed else { return }
        if recognizer.state == .began { session.stopViewportAnimation() }
        var viewport = session.viewport
        viewport.zoom(by: recognizer.scale, around: recognizer.location(in: view))
        session.viewport = viewport
        recognizer.scale = 1
    }

    @objc private func handleDrag(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: view)
        let location = recognizer.location(in: view)
        switch recognizer.state {
        case .began:
            // A pan is recognized only once the finger has moved; what it meant to grab is
            // where it first touched.
            session.beginDrag(atViewPoint: CGPoint(x: location.x - translation.x, y: location.y - translation.y))
            session.continueDrag(translation: CGSize(width: translation.x, height: translation.y), atViewPoint: location)
        case .changed:
            session.continueDrag(translation: CGSize(width: translation.x, height: translation.y), atViewPoint: location)
        case .ended:
            session.endDrag()
        case .cancelled, .failed:
            session.endDrag(isCancelled: true)
        default:
            break
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        session.tap(atViewPoint: recognizer.location(in: view), extendsSelection: recognizer.modifierFlags.contains(.shift))
    }

    @objc private func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        session.doubleTap(atViewPoint: recognizer.location(in: view))
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, session.isWriting else { return }
        session.longPress(atViewPoint: recognizer.location(in: view))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer !== twoFingerPan, gestureRecognizer !== pinch else { return true }
        let viewPoint = touch.location(in: view)
        // The card being edited keeps its touches: they place the cursor and select text.
        if let editedIdentifier = session.textEdit?.nodeIdentifier, isPoint(viewPoint, insideCardWithIdentifier: editedIdentifier) { return false }
        // In Read, a drag inside the tapped card scrolls its content instead of the board.
        if gestureRecognizer === drag, !session.isWriting, let focusedIdentifier = session.focusedNodeIdentifier,
           isPoint(viewPoint, insideCardWithIdentifier: focusedIdentifier) { return false }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        let boardRecognizers: [UIGestureRecognizer] = [twoFingerPan, pinch]
        if boardRecognizers.contains(gestureRecognizer) && boardRecognizers.contains(otherGestureRecognizer) { return true }
        // A double tap is a tap followed by another; both are told. A tap on a link or a
        // button inside a card is that control's too, so the board's taps never make
        // the card's own recognizers fail.
        let tapRecognizers: [UIGestureRecognizer] = [tap, doubleTap]
        guard tapRecognizers.contains(gestureRecognizer) else { return false }
        return tapRecognizers.contains(otherGestureRecognizer) || otherGestureRecognizer.view !== view
    }

    private func isPoint(_ viewPoint: CGPoint, insideCardWithIdentifier identifier: String) -> Bool {
        guard let node = session.file.node(withIdentifier: identifier) else { return false }
        return session.viewport.viewFrame(forBoardFrame: session.frame(of: node)).contains(viewPoint)
    }

    // MARK: Keyboard

    /// Moves the board so the card being edited is above the keyboard.
    private func revealEditedCard(aboveKeyboardWithScreenFrame keyboardScreenFrame: CGRect?) {
        guard let editedIdentifier = session.textEdit?.nodeIdentifier, let keyboardScreenFrame, let window = view.window else { return }
        let keyboardFrame = view.convert(keyboardScreenFrame, from: window.screen.coordinateSpace)
        let coveredHeight = max(view.bounds.maxY - max(keyboardFrame.minY, view.bounds.minY), 0)
        guard coveredHeight > 0, coveredHeight < view.bounds.height else { return }
        session.reveal(nodeWithIdentifier: editedIdentifier, in: CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height - coveredHeight))
    }
}
#else

/// On the Mac the board is looked at: a drag moves it and a pinch magnifies it.
struct CanvasBoardHost: View {
    let session: CanvasSession
    let environment: CanvasCardEnvironment
    @State private var lastDragTranslation = CGSize.zero
    @State private var lastMagnification: CGFloat = 1

    var body: some View {
        CanvasBoardView(session: session, environment: environment)
            .gesture(DragGesture(minimumDistance: 4)
                .onChanged { drag in
                    var viewport = session.viewport
                    viewport.pan(byViewTranslation: CGSize(width: drag.translation.width - lastDragTranslation.width, height: drag.translation.height - lastDragTranslation.height))
                    session.viewport = viewport
                    lastDragTranslation = drag.translation
                }
                .onEnded { _ in lastDragTranslation = .zero })
            .simultaneousGesture(MagnifyGesture()
                .onChanged { magnify in
                    var viewport = session.viewport
                    viewport.zoom(by: magnify.magnification / lastMagnification, around: magnify.startLocation)
                    session.viewport = viewport
                    lastMagnification = magnify.magnification
                }
                .onEnded { _ in lastMagnification = 1 })
            .onTapGesture(count: 2) { location in session.doubleTap(atViewPoint: location) }
    }
}
#endif
