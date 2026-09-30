import SwiftUI
import GraphiteCore
import GraphiteApple

struct DrawingEditorRequest: Identifiable {
    enum Target {
        case newDrawing(notePath: VaultPath, insertionRange: NSRange)
        case existingDrawing(path: VaultPath, location: URL, revision: FileRevision)
    }
    var id = UUID()
    let target: Target
    let title: String
    let initialStrokeData: Data
    /// Nil for a new drawing: the canvas then takes `newDrawingCanvasWidth`.
    let canvasWidth: Double?
    let background: DrawingBackground
    let format: DrawingFormat
    /// Strokes kept from an editor the system closed with the app; they are not saved yet.
    var isRecoveredDraft = false

    /// The width limit of a Markdown note in reading view, so a new drawing is embedded at
    /// the size it was drawn at, whatever the screen or window it was drawn in.
    static let newDrawingCanvasWidth: Double = 760

    var isNewDrawing: Bool {
        if case .newDrawing = target { return true }
        return false
    }

    var resolvedCanvasWidth: Double { canvasWidth ?? Self.newDrawingCanvasWidth }
}

#if canImport(UIKit)
import UIKit
import PencilKit

struct DrawingEditor: View {
    let request: DrawingEditorRequest
    let save: (DrawingContent, DrawingFormat) async throws -> Void
    let exportCopy: (DrawingContent, DrawingFormat) async throws -> URL
    /// Keeps a recovery copy of unsaved strokes while the app is in the background.
    let preserveDraft: (DrawingContent) -> Void
    /// Called when the user closes the editor, saved or not; its recovery copy is no longer needed.
    let removeDraft: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var canvasController: DrawingCanvasController
    private let format: DrawingFormat
    private let background: DrawingBackground
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Set when a PNG is too large to save sharply, so the alert can offer the vector formats.
    @State private var failedPNGSave = false
    @State private var showsDiscardConfirmation = false
    @State private var sharedFile: SharedFile?
    @AppStorage("GraphiteDrawingDrawsWithFinger") private var drawsWithFinger = false
    @State private var showsToolPicker = true

    init(request: DrawingEditorRequest,
         save: @escaping (DrawingContent, DrawingFormat) async throws -> Void,
         exportCopy: @escaping (DrawingContent, DrawingFormat) async throws -> URL,
         preserveDraft: @escaping (DrawingContent) -> Void,
         removeDraft: @escaping () -> Void) {
        self.request = request
        self.save = save
        self.exportCopy = exportCopy
        self.preserveDraft = preserveDraft
        self.removeDraft = removeDraft
        format = request.format
        background = request.background
        _canvasController = State(initialValue: DrawingCanvasController(hasChanges: request.isRecoveredDraft))
    }

    var body: some View {
        NavigationStack {
            DrawingCanvas(controller: canvasController, initialStrokeData: request.initialStrokeData, canvasWidth: request.resolvedCanvasWidth,
                          drawsWithFinger: drawsWithFinger, showsToolPicker: showsToolPicker)
                .ignoresSafeArea(edges: .bottom)
                .background(Color.white)
                .navigationTitle(request.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .overlay {
                    if isSaving {
                        ProgressView("Saving drawing…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .alert("Drawing", isPresented: Binding(get: { errorMessage != nil }, set: { isPresented in if !isPresented { errorMessage = nil; failedPNGSave = false } })) {
                    if failedPNGSave {
                        ForEach([DrawingFormat.pdf, .svg]) { vectorFormat in
                            if request.isNewDrawing {
                                Button("Insert as \(vectorFormat.title)") { Task { await saveAndClose(as: vectorFormat) } }
                            } else {
                                // The notes embed this file by its name, so it keeps its format.
                                Button("Export a Copy as \(vectorFormat.title)") { Task { await shareCopy(as: vectorFormat) } }
                            }
                        }
                    }
                    Button("OK", role: .cancel) {}
                } message: { Text(errorMessage ?? "") }
                .confirmationDialog("Discard the changes to this drawing?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
                    Button("Discard Changes", role: .destructive) { close() }
                    Button("Keep Drawing", role: .cancel) {}
                }
                .sheet(item: $sharedFile) { file in ShareSheet(items: [file.location]) }
                .onAppear { if let loadingError = canvasController.loadingError { errorMessage = loadingError } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, canvasController.hasChanges, let content = currentContent { preserveDraft(content) }
        }
        .interactiveDismissDisabled(isSaving || canvasController.hasChanges)
        // The page is white paper in every appearance, so its controls use light styling.
        .preferredColorScheme(.light)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { if canvasController.hasChanges { showsDiscardConfirmation = true } else { close() } }
                .disabled(isSaving)
        }
        // The same order as the note and PDF toolbars: tools, then Undo and Redo, then the
        // options menu; Insert or Done takes the place of Read/Write.
        ToolbarItemGroup(placement: .primaryAction) {
            if horizontalSizeClass != .compact {
                Button(showsToolPicker ? "Hide Tools" : "Show Tools", systemImage: showsToolPicker ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle") {
                    showsToolPicker.toggle()
                }
            }
            Button("Undo", systemImage: "arrow.uturn.backward") { canvasController.undo() }
                .disabled(!canvasController.canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward") { canvasController.redo() }
                .disabled(!canvasController.canRedo)
            Menu("Drawing Options", systemImage: "ellipsis.circle") {
                if horizontalSizeClass == .compact {
                    Toggle("Show Tools", systemImage: "pencil.tip.crop.circle", isOn: $showsToolPicker)
                }
                Toggle("Draw with Finger", systemImage: "hand.draw", isOn: $drawsWithFinger)
                Button("Fit to Width", systemImage: "arrow.left.and.right") { canvasController.fitToWidth() }
                Divider()
                // The original format stays fixed; exporting makes a separate file.
                Menu("Export a Copy", systemImage: "square.and.arrow.up") {
                    ForEach(DrawingFormat.allCases) { drawingFormat in
                        Button(drawingFormat.title) { Task { await shareCopy(as: drawingFormat) } }
                    }
                }
                .disabled(!canvasController.hasInk)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(request.isNewDrawing ? "Insert" : "Done") { Task { await saveAndClose(as: format) } }
                .fontWeight(.semibold)
                .disabled(isSaving || !canvasController.isReady || (request.isNewDrawing && !canvasController.hasInk))
        }
    }

    private var currentContent: DrawingContent? {
        guard canvasController.canvasWidth > 0 else { return nil }
        return DrawingContent(strokeData: canvasController.strokeData(), canvasWidth: canvasController.canvasWidth, background: background)
    }

    private func saveAndClose(as saveFormat: DrawingFormat) async {
        // Closing an unchanged drawing must not rewrite its file.
        guard request.isNewDrawing || canvasController.hasChanges else { close(); return }
        guard let content = currentContent else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await save(content, saveFormat)
            close()
        } catch {
            if saveFormat == .png, case GraphiteError.oversized = error { failedPNGSave = true }
            errorMessage = error.localizedDescription
        }
    }

    /// Removes the recovery copy only when the user closes the editor. Disappearing is not
    /// enough: the system can tear down a background window's views, which is the case the
    /// copy is kept for.
    private func close() {
        removeDraft()
        dismiss()
    }

    private func shareCopy(as exportFormat: DrawingFormat) async {
        guard let content = currentContent else { return }
        do { sharedFile = SharedFile(location: try await exportCopy(content, exportFormat)) }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct SharedFile: Identifiable {
    let location: URL
    var id: URL { location }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// State the SwiftUI toolbar needs from the PencilKit canvas.
@MainActor @Observable
final class DrawingCanvasController {
    fileprivate weak var canvasView: InfiniteCanvasView?
    var hasChanges: Bool
    var hasInk = false
    var canUndo = false
    var canRedo = false
    var canvasWidth: Double = 0
    var loadingError: String?
    var isReady: Bool { canvasView != nil && canvasWidth > 0 && loadingError == nil }

    init(hasChanges: Bool = false) {
        self.hasChanges = hasChanges
    }

    func undo() { canvasView?.undoManager?.undo(); refreshState() }
    func redo() { canvasView?.undoManager?.redo(); refreshState() }
    func fitToWidth() {
        canvasView?.fitToWidth()
    }
    func strokeData() -> Data { canvasView?.drawing.dataRepresentation() ?? Data() }

    fileprivate func refreshState() {
        guard let canvasView else { return }
        hasInk = !canvasView.drawing.strokes.isEmpty
        canUndo = canvasView.undoManager?.canUndo ?? false
        canRedo = canvasView.undoManager?.canRedo ?? false
    }
}

/// A PencilKit canvas with a fixed logical width and unlimited height. The width is
/// zoomed to fit the screen, so a drawing made on one iPad opens intact on another.
final class InfiniteCanvasView: PKCanvasView {
    var canvasWidth: CGFloat = 0
    /// PencilKit registers its steps with the responder chain's manager, which is the
    /// window's and outlives this editor. A canvas of its own keeps the steps of a closed
    /// drawing out of the next one, and the window's other steps out of this one.
    private let canvasUndoManager = UndoManager()
    override var undoManager: UndoManager? { canvasUndoManager }
    var onCanvasWidthResolved: ((CGFloat) -> Void)?
    private var fittedBoundsWidth: CGFloat = 0

    func fitToWidth() {
        setZoomScale(minimumZoomScale, animated: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.width != fittedBoundsWidth else { return }
        let wasFitted = fittedBoundsWidth == 0 || abs(zoomScale - minimumZoomScale) < 0.001
        fittedBoundsWidth = bounds.width
        if canvasWidth == 0 {
            canvasWidth = bounds.width
            onCanvasWidthResolved?(canvasWidth)
        }
        let fittingScale = bounds.width / canvasWidth
        minimumZoomScale = fittingScale
        maximumZoomScale = fittingScale * 4
        if wasFitted || zoomScale < fittingScale { zoomScale = fittingScale }
        updateContentSize()
    }

    /// Always leaves most of a screen of blank paper below the lowest ink.
    func updateContentSize() {
        guard canvasWidth > 0, zoomScale > 0 else { return }
        let visibleHeight = bounds.height / zoomScale
        let inkBottom = drawing.strokes.isEmpty ? 0 : drawing.bounds.maxY
        let canvasHeight = max(visibleHeight, inkBottom + visibleHeight * 0.75)
        let newContentSize = CGSize(width: canvasWidth * zoomScale, height: canvasHeight * zoomScale)
        if contentSize != newContentSize { contentSize = newContentSize }
    }
}

private struct DrawingCanvas: UIViewRepresentable {
    let controller: DrawingCanvasController
    let initialStrokeData: Data
    let canvasWidth: Double
    let drawsWithFinger: Bool
    let showsToolPicker: Bool

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> InfiniteCanvasView {
        let canvasView = InfiniteCanvasView()
        canvasView.backgroundColor = .white
        canvasView.isOpaque = true
        // Drawings are saved as they look on white paper, so ink never adapts to dark mode.
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.drawingPolicy = drawsWithFinger ? .anyInput : .pencilOnly
        canvasView.alwaysBounceVertical = true
        canvasView.showsHorizontalScrollIndicator = false
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvasView.canvasWidth = CGFloat(canvasWidth)
        canvasView.onCanvasWidthResolved = { [controller] resolvedWidth in controller.canvasWidth = Double(resolvedWidth) }
        controller.canvasWidth = canvasWidth
        if !initialStrokeData.isEmpty {
            do { canvasView.drawing = try PKDrawing(data: initialStrokeData) }
            catch { controller.loadingError = "The editable strokes could not be read. The original file is unchanged." }
        }
        canvasView.delegate = context.coordinator
        controller.canvasView = canvasView
        context.coordinator.toolPicker.overrideUserInterfaceStyle = .light
        context.coordinator.toolPicker.colorUserInterfaceStyle = .light
        context.coordinator.toolPicker.showsDrawingPolicyControls = false
        context.coordinator.toolPicker.addObserver(canvasView)
        context.coordinator.toolPicker.setVisible(showsToolPicker, forFirstResponder: canvasView)
        DispatchQueue.main.async {
            canvasView.becomeFirstResponder()
            controller.refreshState()
        }
        return canvasView
    }

    func updateUIView(_ canvasView: InfiniteCanvasView, context: Context) {
        canvasView.drawingPolicy = drawsWithFinger ? .anyInput : .pencilOnly
        context.coordinator.toolPicker.setVisible(showsToolPicker, forFirstResponder: canvasView)
    }

    static func dismantleUIView(_ canvasView: InfiniteCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker.setVisible(false, forFirstResponder: canvasView)
        coordinator.toolPicker.removeObserver(canvasView)
        canvasView.undoManager?.removeAllActions()
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let controller: DrawingCanvasController
        let toolPicker = PKToolPicker()
        init(controller: DrawingCanvasController) { self.controller = controller }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            (canvasView as? InfiniteCanvasView)?.updateContentSize()
            controller.hasChanges = true
            controller.refreshState()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? InfiniteCanvasView)?.updateContentSize()
        }
    }
}
#endif
