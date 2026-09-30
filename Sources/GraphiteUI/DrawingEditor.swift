import SwiftUI
import GraphiteCore
import GraphiteApple

struct DrawingEditorRequest: Identifiable {
    enum Target {
        case newDrawing(notePath: VaultPath, insertionRange: NSRange)
        case existingDrawing(path: VaultPath, location: URL, revision: FileRevision)
        /// Ink over an image, saved as a new PNG; the image stays as it is. From a note, the
        /// note's embeds of the image then show the new file.
        case drawingOnImage(imagePath: VaultPath, notePath: VaultPath?)
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
    /// The picture the ink is drawn over, for a drawing made on an image.
    var backgroundImage: DrawingBackgroundImage?
    /// Pictures placed on the drawing, the lowest first.
    var pictures: [DrawingBackgroundImage] = []
    var paper: DrawingPaper = .plain

    /// The width limit of a Markdown note in reading view, so a new drawing is embedded at
    /// the size it was drawn at, whatever the screen or window it was drawn in.
    static let newDrawingCanvasWidth: Double = 760

    var isNewDrawing: Bool {
        if case .newDrawing = target { return true }
        return false
    }

    /// A new file is made only when there is ink or a picture to save.
    var requiresContent: Bool {
        if case .existingDrawing = target { return false }
        return true
    }

    /// Pictures make a drawing a PNG. A new drawing takes that format when it is saved; an
    /// existing SVG or PDF drawing keeps its name in the notes that embed it, so it takes no
    /// pictures.
    var acceptsPictures: Bool {
        if case .existingDrawing = target { return format == .png }
        return true
    }

    /// Insert for a drawing that goes into a note; Done where the file already has its place.
    var confirmationTitle: String { isNewDrawing ? "Insert" : "Done" }

    var resolvedCanvasWidth: Double { canvasWidth ?? Self.newDrawingCanvasWidth }
}

/// Which files the drawing editor can draw over: images ImageIO decodes. SVG and PDF files
/// are not pictures it can read.
enum DrawableImages {
    static func canDrawOn(_ path: VaultPath) -> Bool {
        DocumentKind(path: path) == .image && path.fileExtension.lowercased() != "svg"
    }
}

extension DrawingPaperPattern {
    var title: String {
        switch self {
        case .plain: "Plain"
        case .squared: "Squared"
        case .ruled: "Ruled"
        case .dotted: "Dotted"
        }
    }
    var symbolName: String {
        switch self {
        case .plain: "rectangle"
        case .squared: "square.grid.3x3"
        case .ruled: "line.3.horizontal"
        case .dotted: "circle.grid.3x3"
        }
    }
}

#if canImport(UIKit)
import UIKit
import PencilKit
import PhotosUI
import UniformTypeIdentifiers

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
    @State private var toolbox = PencilToolbox.shared
    private let format: DrawingFormat
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Set when a PNG is too large to save sharply, so the alert can offer the vector formats.
    @State private var failedPNGSave = false
    @State private var showsDiscardConfirmation = false
    @State private var sharedFile: SharedFile?
    @State private var showsPhotoPicker = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var showsImageFilePicker = false
    @AppStorage("GraphiteDrawingDrawsWithFinger") private var drawsWithFinger = false
    @AppStorage(PDFAnnotationPreferenceKey.drawsShapes) private var drawsShapes = false
    @AppStorage(PencilToolbarStyle.preferenceKey) private var toolbarStyle = PencilToolbarStyle.floating
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
        _canvasController = State(initialValue: DrawingCanvasController(hasChanges: request.isRecoveredDraft, pictures: request.pictures, paper: request.paper,
                                                                       background: request.background))
    }

    /// The fixed bar takes the place of the floating palette; the compact layouts keep the palette.
    private var usesFixedToolbar: Bool { toolbarStyle == .fixed && horizontalSizeClass != .compact }

    var body: some View {
        NavigationStack {
            DrawingCanvas(controller: canvasController, initialStrokeData: request.initialStrokeData, canvasWidth: request.resolvedCanvasWidth,
                          backgroundImage: request.backgroundImage,
                          drawsWithFinger: drawsWithFinger, drawsShapes: drawsShapes,
                          showsToolPicker: showsToolPicker && !usesFixedToolbar && !canvasController.isArrangingPictures,
                          fixedTool: usesFixedToolbar ? toolbox.selection : nil)
                .ignoresSafeArea(edges: .bottom)
                .background(Color.white)
                .safeAreaInset(edge: .top, spacing: 0) {
                    // The bar stays while pictures are arranged: removing it would move the
                    // drawing under the finger.
                    if usesFixedToolbar, showsToolPicker {
                        PencilToolbar(toolbox: toolbox, favoriteColors: GraphitePreferences.storedColorPalette(), drawsShapes: $drawsShapes,
                                      addImage: request.acceptsPictures ? { showsPhotoPicker = true } : nil)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if canvasController.isArrangingPictures { pictureArrangementBar }
                }
                .navigationTitle(request.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .overlay {
                    if isSaving {
                        ProgressView("Saving drawing…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .alert("Drawing", isPresented: Binding(get: { errorMessage != nil }, set: { isPresented in if !isPresented { errorMessage = nil; failedPNGSave = false } })) {
                    if failedPNGSave && currentContent?.requiresPNG != true {
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
                .sheet(item: $sharedFile) { file in ShareSheet(items: [file.location]) }
                .photosPicker(isPresented: $showsPhotoPicker, selection: $pickedPhoto, matching: .images)
                .fileImporter(isPresented: $showsImageFilePicker, allowedContentTypes: [.image]) { pickedFile in
                    if case .success(let location) = pickedFile { Task { await addPicture(fromFileAt: location) } }
                }
                .onChange(of: pickedPhoto) { _, photo in
                    guard let photo else { return }
                    pickedPhoto = nil
                    Task { await addPicture(from: photo) }
                }
                // Taking up a tool ends arranging pictures.
                .onChange(of: toolbox.selection) { _, _ in canvasController.finishArrangingPictures() }
                .onAppear { if let loadingError = canvasController.loadingError { errorMessage = loadingError } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, canvasController.hasChanges, let content = currentContent { preserveDraft(content) }
        }
        .interactiveDismissDisabled(isSaving || canvasController.hasChanges)
        // The page is white paper in every appearance, so its controls use light styling.
        .preferredColorScheme(.light)
    }

    /// Shown while images are being arranged, where the palette otherwise is.
    private var pictureArrangementBar: some View {
        HStack(spacing: 16) {
            Text(canvasController.selectedPictureIdentifier == nil ? "Tap an image to select it." : "Drag the image to move it, or a corner to resize it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Delete Image", systemImage: "trash", role: .destructive) { canvasController.deleteSelectedPicture() }
                .labelStyle(.iconOnly)
                .disabled(canvasController.selectedPictureIdentifier == nil)
            Button("Done") { canvasController.finishArrangingPictures() }
                .fontWeight(.semibold)
                .tint(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { if canvasController.hasChanges { showsDiscardConfirmation = true } else { close() } }
                .disabled(isSaving)
                // On the button, so the question points at what was pressed.
                .confirmationDialog("Discard the changes to this drawing?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
                    Button("Discard Changes", role: .destructive) { close() }
                    Button("Keep Drawing", role: .cancel) {}
                }
        }
        // The same order as the note and PDF toolbars: tools, then Undo and Redo, then the
        // options menu; Insert or Done takes the place of Read/Write.
        ToolbarItemGroup(placement: .primaryAction) {
            if horizontalSizeClass != .compact {
                Button(showsToolPicker ? "Hide Tools" : "Show Tools", systemImage: showsToolPicker ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle") {
                    showsToolPicker.toggle()
                }
            }
            UndoRedoButtons(availability: canvasController.undoAvailability)
            Menu("Drawing Options", systemImage: "ellipsis.circle") {
                if horizontalSizeClass == .compact {
                    Toggle("Show Tools", systemImage: "pencil.tip.crop.circle", isOn: $showsToolPicker)
                }
                Toggle("Draw with Finger", systemImage: "hand.draw", isOn: $drawsWithFinger)
                Toggle("Draw Shapes", systemImage: "square.on.circle", isOn: $drawsShapes)
                Button("Fit to Width", systemImage: "arrow.left.and.right") { canvasController.fitToWidth() }
                Divider()
                Menu("Paper", systemImage: "square.grid.3x3") {
                    Picker("Paper", selection: $canvasController.paper.pattern) {
                        ForEach(DrawingPaperPattern.allCases) { pattern in Label(pattern.title, systemImage: pattern.symbolName).tag(pattern) }
                    }
                    Toggle("Show Paper in the Note", isOn: $canvasController.paper.appearsInSavedDrawing)
                        .disabled(canvasController.paper.pattern == .plain)
                    // A picture drawn on has no background of its own to choose.
                    if request.backgroundImage == nil {
                        Picker("Background", selection: $canvasController.background) {
                            ForEach(DrawingBackground.allCases) { background in Text("\(background.title) Background").tag(background) }
                        }
                    }
                }
                Menu("Add Image", systemImage: "photo.badge.plus") {
                    Button("Photo Library…", systemImage: "photo.on.rectangle") { showsPhotoPicker = true }
                    Button("Choose File…", systemImage: "folder") { showsImageFilePicker = true }
                    if UIPasteboard.general.hasImages {
                        Button("Paste Image", systemImage: "doc.on.clipboard") { Task { await addPictureFromPasteboard() } }
                    }
                }
                .disabled(!request.acceptsPictures)
                if !canvasController.pictures.isEmpty {
                    Button("Move or Resize Images", systemImage: "arrow.up.and.down.and.arrow.left.and.right") { canvasController.beginArrangingPictures() }
                }
                Divider()
                // The original format stays fixed; exporting makes a separate file.
                Menu("Export a Copy", systemImage: "square.and.arrow.up") {
                    ForEach(availableFormats) { drawingFormat in
                        Button(drawingFormat.title) { Task { await shareCopy(as: drawingFormat) } }
                    }
                }
                .disabled(!canvasController.hasContent)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(request.confirmationTitle) { Task { await saveAndClose(as: format) } }
                .fontWeight(.semibold)
                .disabled(isSaving || !canvasController.isReady || (request.requiresContent && !canvasController.hasContent))
        }
    }

    /// Drawings with pictures are raster pictures, saved and exported as PNG only.
    private var availableFormats: [DrawingFormat] {
        request.backgroundImage != nil || !canvasController.pictures.isEmpty ? [.png] : DrawingFormat.allCases
    }

    private var currentContent: DrawingContent? {
        guard canvasController.canvasWidth > 0 else { return nil }
        return DrawingContent(strokeData: canvasController.strokeData(), canvasWidth: canvasController.canvasWidth, background: canvasController.background,
                              backgroundImage: request.backgroundImage, pictures: canvasController.pictures.map(\.picture), paper: canvasController.paper)
    }

    private func saveAndClose(as chosenFormat: DrawingFormat) async {
        // Closing an unchanged drawing must not rewrite its file.
        guard request.requiresContent || canvasController.hasChanges else { close(); return }
        canvasController.finishArrangingPictures()
        guard let content = currentContent else { return }
        // A new drawing with pictures becomes a PNG whatever format new drawings take.
        let saveFormat = content.requiresPNG ? DrawingFormat.png : chosenFormat
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

    // MARK: Pictures

    private func addPicture(from photo: PhotosPickerItem) async {
        do {
            guard let imageData = try await photo.loadTransferable(type: Data.self) else {
                throw GraphiteError.invalidFile("This photo could not be read.")
            }
            await addPicture(imageData: imageData)
        } catch { errorMessage = error.localizedDescription }
    }

    private func addPicture(fromFileAt location: URL) async {
        do {
            let imageData = try await Task.detached(priority: .userInitiated) {
                try PickedImageFiles.imageData(at: location)
            }.value
            await addPicture(imageData: imageData)
        } catch { errorMessage = error.localizedDescription }
    }

    private func addPictureFromPasteboard() async {
        guard let imageData = UIPasteboard.general.image?.pngData() else { return }
        await addPicture(imageData: imageData)
    }

    private func addPicture(imageData: Data) async {
        let canvasWidth = canvasController.canvasWidth
        do {
            // Prepared for the full width, so enlarging it later does not blur it.
            let picture = try await Task.detached(priority: .userInitiated) {
                try DrawingPictures.picture(from: imageData, canvasWidth: canvasWidth)
            }.value
            try canvasController.addPicture(picture)
        } catch { errorMessage = error.localizedDescription }
    }
}

/// Reads an image file chosen in the file picker.
enum PickedImageFiles {
    /// Bound on a picked image; the picture kept is far smaller.
    static let maximumImageBytes = 64 * 1_048_576

    static func imageData(at location: URL) throws -> Data {
        let hasAccess = location.startAccessingSecurityScopedResource()
        defer { if hasAccess { location.stopAccessingSecurityScopedResource() } }
        if let fileSize = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize, fileSize > maximumImageBytes {
            throw GraphiteError.oversized("This image is too large to add.")
        }
        return try Data(contentsOf: location)
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

/// A picture placed on a drawing, as the editor moves and resizes it.
struct PlacedPicture: Identifiable, Equatable {
    let id: UUID
    var picture: DrawingBackgroundImage

    init(id: UUID = UUID(), picture: DrawingBackgroundImage) {
        self.id = id
        self.picture = picture
    }
}

/// State the SwiftUI toolbar needs from the PencilKit canvas, and the drawing's undo
/// history. The history is Graphite's rather than PencilKit's, as for PDF pages
/// (`HistoryCanvasView`): a stroke the shape tool replaced is one step, a picture added,
/// moved, resized or deleted is one step, and the palette's Undo, the toolbar's, and ⌘Z act
/// on the same steps.
@MainActor @Observable
final class DrawingCanvasController {
    fileprivate weak var canvasView: InfiniteCanvasView? {
        didSet { showPicturesAndPaper() }
    }
    var hasChanges: Bool
    var hasInk = false
    var canvasWidth: Double = 0
    var loadingError: String?
    private(set) var pictures: [PlacedPicture]
    /// The paper under the ink. Changing it is a change to the drawing, not a step to undo.
    var paper: DrawingPaper {
        didSet {
            guard paper != oldValue else { return }
            canvasView?.paperPattern = paper.pattern
            hasChanges = true
        }
    }
    /// White paper, or none: the note shows through a saved drawing without a background.
    var background: DrawingBackground {
        didSet { if background != oldValue { hasChanges = true } }
    }
    /// While arranging, touches move and resize pictures instead of drawing.
    private(set) var isArrangingPictures = false
    private(set) var selectedPictureIdentifier: UUID?
    var isReady: Bool { canvasView != nil && canvasWidth > 0 && loadingError == nil }
    /// A drawing worth saving has ink or a picture.
    var hasContent: Bool { hasInk || !pictures.isEmpty }
    @ObservationIgnored let history = UndoManager()
    @ObservationIgnored let undoAvailability = UndoAvailability()

    init(hasChanges: Bool = false, pictures: [DrawingBackgroundImage] = [], paper: DrawingPaper = .plain, background: DrawingBackground = .white) {
        self.hasChanges = hasChanges
        self.pictures = pictures.map { picture in PlacedPicture(picture: picture) }
        self.paper = paper
        self.background = background
        undoAvailability.follow(history)
    }

    func fitToWidth() {
        canvasView?.fitToWidth()
    }
    func strokeData() -> Data { canvasView?.drawing.dataRepresentation() ?? Data() }

    fileprivate func refreshState() {
        guard let canvasView else { return }
        hasInk = !canvasView.drawing.strokes.isEmpty
        undoAvailability.refresh()
    }

    /// Records a change the canvas made. Undo and redo register each other, so a step can
    /// be undone and redone repeatedly.
    fileprivate func registerChange(_ change: PencilDrawingChange, reverting: Bool = true) {
        history.registerUndo(withTarget: self) { controller in controller.applyFromHistory(change, reverting: reverting) }
        history.setActionName("Drawing")
    }

    private func applyFromHistory(_ change: PencilDrawingChange, reverting: Bool) {
        guard let canvasView else { return }
        guard let drawing = reverting ? change.reverting(canvasView.drawing) : change.reapplying(to: canvasView.drawing) else { return }
        registerChange(change, reverting: !reverting)
        canvasView.showDrawingFromHistory(drawing)
        refreshState()
    }

    // MARK: Pictures

    /// Places a picture in the middle of what is on screen, at most 60% of the canvas wide,
    /// and selects it so it can be moved into place.
    func addPicture(_ picture: DrawingBackgroundImage) throws {
        guard pictures.count < DrawingLimits.maximumPictureCount else {
            throw GraphiteError.oversized("A drawing can hold \(DrawingLimits.maximumPictureCount) images.")
        }
        let existingBytes = pictures.reduce(0) { total, placed in total + placed.picture.imageData.count }
        guard existingBytes + picture.imageData.count <= DrawingLimits.maximumBackgroundImageBytes else {
            throw GraphiteError.oversized("The images on this drawing are as large together as a drawing can hold.")
        }
        let width = min(picture.frame.width, canvasWidth * Self.newPictureWidthFraction)
        let height = picture.frame.height * width / picture.frame.width
        let visibleRegion = canvasView?.visibleDrawingRegion ?? CGRect(x: 0, y: 0, width: canvasWidth, height: height)
        let origin = CGPoint(x: (canvasWidth - width) / 2, y: max(visibleRegion.midY - height / 2, visibleRegion.minY + Self.newPictureTopMargin, 0))
        let placed = PlacedPicture(picture: DrawingBackgroundImage(imageData: picture.imageData, frame: CGRect(origin: origin, size: CGSize(width: width, height: height)).integral))
        replacePictures(with: pictures + [placed], actionName: "Add Image")
        isArrangingPictures = true
        selectedPictureIdentifier = placed.id
        showPicturesAndPaper()
    }

    private static let newPictureWidthFraction = 0.6
    private static let newPictureTopMargin = 24.0

    func beginArrangingPictures(selecting identifier: UUID? = nil) {
        guard !pictures.isEmpty else { return }
        isArrangingPictures = true
        selectedPictureIdentifier = identifier ?? (pictures.count == 1 ? pictures.first?.id : nil)
        showPicturesAndPaper()
    }

    func finishArrangingPictures() {
        guard isArrangingPictures else { return }
        isArrangingPictures = false
        selectedPictureIdentifier = nil
        showPicturesAndPaper()
    }

    func deleteSelectedPicture() {
        guard let selectedPictureIdentifier else { return }
        self.selectedPictureIdentifier = nil
        replacePictures(with: pictures.filter { placed in placed.id != selectedPictureIdentifier }, actionName: "Delete Image")
        if pictures.isEmpty { isArrangingPictures = false }
        showPicturesAndPaper()
    }

    /// The canvas reports a picture tapped while arranging (nil for a tap beside them all),
    /// or tapped with a finger that does not draw.
    func pictureWasTapped(_ identifier: UUID?) {
        if let identifier {
            isArrangingPictures = true
            selectedPictureIdentifier = identifier
        } else if selectedPictureIdentifier != nil {
            selectedPictureIdentifier = nil
        } else {
            isArrangingPictures = false
        }
        showPicturesAndPaper()
    }

    func pictureFrameChangeDidEnd(_ identifier: UUID, frame: CGRect) {
        guard let pictureIndex = pictures.firstIndex(where: { placed in placed.id == identifier }), pictures[pictureIndex].picture.frame != frame else { return }
        var movedPictures = pictures
        movedPictures[pictureIndex].picture = DrawingBackgroundImage(imageData: movedPictures[pictureIndex].picture.imageData, frame: frame)
        replacePictures(with: movedPictures, actionName: "Move Image")
        showPicturesAndPaper()
    }

    /// One undo step: undo puts the earlier pictures back, and registers the step again for redo.
    private func replacePictures(with newPictures: [PlacedPicture], actionName: String) {
        let earlierPictures = pictures
        history.registerUndo(withTarget: self) { controller in
            controller.replacePictures(with: earlierPictures, actionName: actionName)
            if let selected = controller.selectedPictureIdentifier, !controller.pictures.contains(where: { placed in placed.id == selected }) {
                controller.selectedPictureIdentifier = nil
            }
            controller.showPicturesAndPaper()
        }
        history.setActionName(actionName)
        pictures = newPictures
        hasChanges = true
        undoAvailability.refresh()
    }

    private func showPicturesAndPaper() {
        guard let canvasView else { return }
        canvasView.paperPattern = paper.pattern
        canvasView.showPictures(pictures, selected: selectedPictureIdentifier, isArranging: isArrangingPictures)
    }
}

/// The paper pattern under a drawing's ink. It covers only what is on screen and is drawn
/// again as the canvas scrolls and zooms, so a tall drawing needs no tall bitmap.
final class DrawingPaperView: UIView {
    var pattern: DrawingPaperPattern = .plain {
        didSet {
            guard pattern != oldValue else { return }
            isHidden = pattern == .plain
            setNeedsDisplay()
        }
    }
    /// The part of the drawing the view covers, in drawing points.
    var drawingRegion: CGRect = .zero {
        didSet { if drawingRegion != oldValue { setNeedsDisplay() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isHidden = true
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("DrawingPaperView is created in code.") }

    override func draw(_ rect: CGRect) {
        guard pattern != .plain, drawingRegion.width > 0, let context = UIGraphicsGetCurrentContext() else { return }
        let pointsPerDrawingPoint = bounds.width / drawingRegion.width
        context.scaleBy(x: pointsPerDrawingPoint, y: pointsPerDrawingPoint)
        context.translateBy(x: -drawingRegion.minX, y: -drawingRegion.minY)
        DrawingPaperRenderer.draw(pattern, in: drawingRegion, context: context)
    }
}

/// A PencilKit canvas with a fixed logical width and unlimited height. The width is
/// zoomed to fit the screen, so a drawing made on one iPad opens intact on another.
///
/// The canvas is clear: PencilKit paints an opaque canvas's paper over everything under its
/// ink, and the paper pattern and the pictures are under the ink. The editor's white
/// background is the paper.
final class InfiniteCanvasView: HistoryCanvasView {
    var canvasWidth: CGFloat = 0
    var onCanvasWidthResolved: ((CGFloat) -> Void)?
    /// A picture was tapped (nil: a tap beside every picture while arranging).
    var pictureWasTapped: ((UUID?) -> Void)?
    var pictureFrameChangeDidEnd: ((UUID, CGRect) -> Void)?
    private var fittedBoundsWidth: CGFloat = 0
    private let paperView = DrawingPaperView()
    /// The picture under the ink of a drawing made on an image, in canvas coordinates.
    private var basePictureView: UIImageView?
    private var basePictureFrame: CGRect = .null
    private var pictures: [PlacedPicture] = []
    private var pictureViews: [UUID: UIImageView] = [:]
    private var selectedPictureIdentifier: UUID?
    private var selectionView: PictureSelectionView?
    private(set) var isArrangingPictures = false
    private lazy var pictureTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handlePictureTap(_:)))
    private let pictureTapGate = PictureTapGate()

    var paperPattern: DrawingPaperPattern {
        get { paperView.pattern }
        set { paperView.pattern = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        insertSubview(paperView, at: 0)
        pictureTapGate.canvas = self
        pictureTapRecognizer.delegate = pictureTapGate
        addGestureRecognizer(pictureTapRecognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("InfiniteCanvasView is created in code.") }

    /// The part of the drawing on screen, in drawing points.
    var visibleDrawingRegion: CGRect {
        guard zoomScale > 0 else { return .zero }
        return CGRect(x: bounds.minX / zoomScale, y: bounds.minY / zoomScale, width: bounds.width / zoomScale, height: bounds.height / zoomScale)
    }

    /// Places the picture under everything PencilKit draws; it scrolls and zooms with the ink.
    func showBasePicture(_ picture: UIImage, in frame: CGRect) {
        let imageView = basePictureView ?? UIImageView()
        imageView.image = picture
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        imageView.accessibilityLabel = "Image being drawn on"
        if imageView.superview == nil { insertSubview(imageView, aboveSubview: paperView) }
        basePictureView = imageView
        basePictureFrame = frame
        positionPictures()
    }

    /// Shows the pictures placed on the drawing, the lowest first, under the ink, and the
    /// selection frame around the selected one while they are being arranged.
    func showPictures(_ placedPictures: [PlacedPicture], selected: UUID?, isArranging: Bool) {
        pictures = placedPictures
        let identifiers = Set(placedPictures.map(\.id))
        for (identifier, imageView) in pictureViews where !identifiers.contains(identifier) {
            imageView.removeFromSuperview()
            pictureViews[identifier] = nil
        }
        var viewBelow: UIView = basePictureView ?? paperView
        for placed in placedPictures {
            let imageView = pictureViews[placed.id] ?? {
                let newView = UIImageView(image: UIImage(data: placed.picture.imageData))
                newView.contentMode = .scaleToFill
                newView.isUserInteractionEnabled = false
                newView.isAccessibilityElement = true
                newView.accessibilityLabel = "Image"
                pictureViews[placed.id] = newView
                return newView
            }()
            insertSubview(imageView, aboveSubview: viewBelow)
            viewBelow = imageView
        }
        isArrangingPictures = isArranging
        // A pen must not draw while a picture is dragged under it.
        isDrawingEnabled = !isArranging
        selectedPictureIdentifier = isArranging ? selected : nil
        updateSelectionView()
        updateContentSize()
    }

    private func updateSelectionView() {
        guard let selectedPictureIdentifier, pictures.contains(where: { placed in placed.id == selectedPictureIdentifier }) else {
            selectionView?.removeFromSuperview()
            selectionView = nil
            return
        }
        let selection = selectionView ?? {
            let newSelection = PictureSelectionView(frame: .zero)
            newSelection.frameDidChange = { [weak self] frame in self?.selectionFrameDidChange(frame) }
            newSelection.frameChangeDidEnd = { [weak self] frame in self?.selectionFrameChangeDidEnd(frame) }
            // Dragging a picture must not scroll the page with it.
            for recognizer in newSelection.dragRecognizers { panGestureRecognizer.require(toFail: recognizer) }
            selectionView = newSelection
            return newSelection
        }()
        addSubview(selection)
        positionPictures()
    }

    private func selectionFrameDidChange(_ frame: CGRect) {
        guard let selectedPictureIdentifier, zoomScale > 0 else { return }
        pictureViews[selectedPictureIdentifier]?.frame = frame
    }

    private func selectionFrameChangeDidEnd(_ frame: CGRect) {
        guard let selectedPictureIdentifier, zoomScale > 0 else { return }
        let drawingFrame = CGRect(x: frame.minX / zoomScale, y: frame.minY / zoomScale, width: frame.width / zoomScale, height: frame.height / zoomScale)
        pictureFrameChangeDidEnd?(selectedPictureIdentifier, drawingFrame)
    }

    /// The topmost picture at a point of the canvas's content.
    func picture(atContentPoint contentPoint: CGPoint) -> UUID? {
        guard zoomScale > 0 else { return nil }
        let drawingPoint = CGPoint(x: contentPoint.x / zoomScale, y: contentPoint.y / zoomScale)
        return pictures.last { placed in placed.picture.frame.contains(drawingPoint) }?.id
    }

    @objc private func handlePictureTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        pictureWasTapped?(picture(atContentPoint: recognizer.location(in: self)))
    }

    private func zoomed(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX * zoomScale, y: frame.minY * zoomScale, width: frame.width * zoomScale, height: frame.height * zoomScale)
    }

    private func positionPictures() {
        if let basePictureView, !basePictureFrame.isNull { basePictureView.frame = zoomed(basePictureFrame) }
        for placed in pictures { pictureViews[placed.id]?.frame = zoomed(placed.picture.frame) }
        if let selectionView, let selected = pictures.first(where: { placed in placed.id == selectedPictureIdentifier }) {
            selectionView.frame = zoomed(selected.picture.frame)
            // A picture stays where it can be reached: its middle on the canvas, not above its top.
            selectionView.centerLimits = CGRect(x: 0, y: 0, width: canvasWidth * zoomScale, height: .greatestFiniteMagnitude)
        }
    }

    func fitToWidth() {
        setZoomScale(minimumZoomScale, animated: true)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The paper follows what is on screen; this runs at every scroll step.
        if paperView.frame != bounds { paperView.frame = bounds }
        paperView.drawingRegion = visibleDrawingRegion
        guard bounds.width > 0, bounds.width != fittedBoundsWidth else { return }
        let isFirstFit = fittedBoundsWidth == 0
        let wasFitted = isFirstFit || abs(zoomScale - minimumZoomScale) < 0.001
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
        // Zooming keeps the middle of the view in place, which would open the drawing
        // scrolled down, its top under the navigation bar.
        if isFirstFit { scrollToTop() }
    }

    override func adjustedContentInsetDidChange() {
        super.adjustedContentInsetDidChange()
        // The bars' insets can arrive after the first layout; a drawing still at its top stays there.
        if contentOffset.y <= 0 { scrollToTop() }
    }

    private func scrollToTop() {
        contentOffset = CGPoint(x: -adjustedContentInset.left, y: -adjustedContentInset.top)
    }

    /// Always leaves most of a screen of blank paper below the lowest ink or picture; a
    /// picture being drawn on is always shown whole, with room for notes below it.
    func updateContentSize() {
        guard canvasWidth > 0, zoomScale > 0 else { return }
        positionPictures()
        let visibleHeight = bounds.height / zoomScale
        let pictureBottom = max(basePictureFrame.isNull ? 0 : basePictureFrame.maxY, pictures.map(\.picture.frame.maxY).max() ?? 0)
        let contentBottom = max(drawing.strokes.isEmpty ? 0 : drawing.bounds.maxY, pictureBottom)
        let canvasHeight = max(visibleHeight, contentBottom + visibleHeight * 0.75)
        let newContentSize = CGSize(width: canvasWidth * zoomScale, height: canvasHeight * zoomScale)
        if contentSize != newContentSize { contentSize = newContentSize }
    }
}

/// Decides which taps select a picture: every finger tap while pictures are being arranged,
/// and otherwise a finger tap on a picture when fingers do not draw. The canvas cannot be
/// the recognizer's delegate itself: a scroll view answers those questions for its own
/// recognizers.
private final class PictureTapGate: NSObject, UIGestureRecognizerDelegate {
    weak var canvas: InfiniteCanvasView?

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let canvas, touch.type != .pencil else { return false }
        if canvas.isArrangingPictures { return !(touch.view is PictureSelectionView) && !(touch.view?.superview is PictureSelectionView) }
        return canvas.drawingPolicy == .pencilOnly && canvas.picture(atContentPoint: touch.location(in: canvas)) != nil
    }
}

private struct DrawingCanvas: UIViewRepresentable {
    let controller: DrawingCanvasController
    let initialStrokeData: Data
    let canvasWidth: Double
    let backgroundImage: DrawingBackgroundImage?
    let drawsWithFinger: Bool
    let drawsShapes: Bool
    let showsToolPicker: Bool
    /// The tool of the fixed tool bar; nil while the floating palette chooses the tool.
    let fixedTool: PencilToolSelection?

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> InfiniteCanvasView {
        let canvasView = InfiniteCanvasView()
        let coordinator = context.coordinator
        // Drawings are saved as they look on white paper, so ink never adapts to dark mode.
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.drawingPolicy = drawsWithFinger ? .anyInput : .pencilOnly
        canvasView.alwaysBounceVertical = true
        canvasView.showsHorizontalScrollIndicator = false
        canvasView.canvasWidth = CGFloat(canvasWidth)
        canvasView.onCanvasWidthResolved = { [controller] resolvedWidth in controller.canvasWidth = Double(resolvedWidth) }
        canvasView.pictureWasTapped = { [controller] identifier in controller.pictureWasTapped(identifier) }
        canvasView.pictureFrameChangeDidEnd = { [controller] identifier, frame in controller.pictureFrameChangeDidEnd(identifier, frame: frame) }
        controller.canvasWidth = canvasWidth
        if !initialStrokeData.isEmpty {
            do { canvasView.drawing = try PKDrawing(data: initialStrokeData) }
            catch { controller.loadingError = "The editable strokes could not be read. The original file is unchanged." }
        }
        if let backgroundImage {
            if let picture = UIImage(data: backgroundImage.imageData) {
                canvasView.showBasePicture(picture, in: backgroundImage.frame)
            } else {
                controller.loadingError = "The image under this drawing could not be read. The original file is unchanged."
            }
        }
        canvasView.recordedDrawing = canvasView.drawing
        canvasView.delegate = coordinator
        controller.canvasView = canvasView
        coordinator.drawsShapes = drawsShapes
        coordinator.toolPickerHost.documentUndoManager = controller.history
        coordinator.toolPickerHost.canvases = { [weak canvasView] in canvasView.map { canvas in [canvas] } ?? [] }
        canvasView.addSubview(coordinator.toolPickerHost)
        coordinator.toolPicker.overrideUserInterfaceStyle = .light
        coordinator.toolPicker.accessoryItem = coordinator.paletteAccessoryItem
        coordinator.toolPicker.setVisible(showsToolPicker, forFirstResponder: coordinator.toolPickerHost)
        coordinator.apply(fixedTool, to: canvasView)
        DispatchQueue.main.async {
            coordinator.toolPickerHost.becomeFirstResponder()
            controller.refreshState()
        }
        return canvasView
    }

    func updateUIView(_ canvasView: InfiniteCanvasView, context: Context) {
        canvasView.drawingPolicy = drawsWithFinger ? .anyInput : .pencilOnly
        context.coordinator.drawsShapes = drawsShapes
        PencilToolPalette.updateShapesButton(context.coordinator.paletteAccessoryItem, isOn: drawsShapes)
        context.coordinator.toolPicker.setVisible(showsToolPicker, forFirstResponder: context.coordinator.toolPickerHost)
        context.coordinator.apply(fixedTool, to: canvasView)
    }

    static func dismantleUIView(_ canvasView: InfiniteCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker.setVisible(false, forFirstResponder: coordinator.toolPickerHost)
        coordinator.toolPickerHost.takesFirstResponderBackFromSelections = false
        canvasView.stopFollowing(coordinator.toolPicker)
        coordinator.stopObservingToolbox()
        coordinator.toolPickerHost.resignFirstResponder()
        coordinator.controller.history.removeAllActions()
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let controller: DrawingCanvasController
        let toolPicker = PencilToolPalette.makeToolPicker()
        lazy var paletteAccessoryItem = PencilToolPalette.makeAccessoryItem(for: toolPicker)
        let toolPickerHost = PencilToolPickerHostView()
        var drawsShapes = false
        private var usesFixedTool = false
        private var toolboxObserver: NSObjectProtocol?
        private lazy var shapeFeedback = UICanvasFeedbackGenerator(view: toolPickerHost)
        init(controller: DrawingCanvasController) { self.controller = controller }

        /// The canvas takes its tool from the fixed bar, or follows the floating palette.
        func apply(_ fixedTool: PencilToolSelection?, to canvasView: InfiniteCanvasView) {
            usesFixedTool = fixedTool != nil
            canvasView.takeTool(from: toolPicker, fixedTool: fixedTool)
            guard toolboxObserver == nil else { return }
            // The bar's tool applies from the moment it is chosen, before the next touch;
            // SwiftUI's update of this view would come a moment later.
            toolboxObserver = NotificationCenter.default.addObserver(forName: PencilToolbox.selectionDidChange, object: PencilToolbox.shared, queue: nil) { [weak self, weak canvasView] _ in
                MainActor.assumeIsolated {
                    guard let self, let canvasView, self.usesFixedTool else { return }
                    canvasView.takeTool(from: self.toolPicker, fixedTool: PencilToolbox.shared.selection)
                }
            }
        }

        func stopObservingToolbox() {
            if let toolboxObserver { NotificationCenter.default.removeObserver(toolboxObserver) }
            toolboxObserver = nil
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard let canvas = canvasView as? InfiniteCanvasView, !canvas.isShowingRecognizedShape else { return }
            var drawing = canvas.drawing
            if drawsShapes, let shapedDrawing = PencilShapes.replacingNewStroke(in: drawing, previousDrawing: canvas.recordedDrawing) {
                drawing = shapedDrawing
                canvas.showRecognizedShape(shapedDrawing)
                // Apple Pencil Pro taps when a stroke snaps to a shape.
                if let shapeBounds = shapedDrawing.strokes.last?.renderBounds {
                    shapeFeedback.pathCompleted(at: canvas.convert(CGPoint(x: shapeBounds.midX * canvas.zoomScale, y: shapeBounds.midY * canvas.zoomScale), to: toolPickerHost))
                }
            }
            // A drawing the history itself showed was recorded before it was shown.
            if let change = PencilDrawingChange(from: canvas.recordedDrawing, to: drawing) { controller.registerChange(change) }
            canvas.recordedDrawing = drawing
            canvas.updateContentSize()
            controller.hasChanges = true
            controller.refreshState()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? InfiniteCanvasView)?.updateContentSize()
        }
    }
}
#endif
