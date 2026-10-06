import Foundation
import Observation
import CoreGraphics
import GraphiteCore

/// A text card being edited in place, and its Markdown as typed so far.
struct CanvasTextEdit: Equatable {
    let nodeIdentifier: String
    var text: String
}

/// A connection being drawn from a card's side, before the finger lifts.
struct CanvasPendingConnection: Equatable {
    let fromNodeIdentifier: String
    let fromSide: CanvasSide
    /// Where the finger is, on the board.
    var endPoint: CGPoint
    /// The card under the finger, which the connection will end at.
    var targetNodeIdentifier: String?
}

/// The lines a moved or resized card lined up with, on the board, drawn while it is dragged.
struct CanvasSnapGuides: Equatable {
    /// The horizontal position of a vertical line.
    var vertical: CGFloat?
    var horizontal: CGFloat?
}

enum CanvasPreferenceKey {
    static let snapsToGrid = "GraphiteCanvasSnapsToGrid"
    static let snapsToObjects = "GraphiteCanvasSnapsToObjects"
}

/// Something of a canvas whose name is asked for in a small sheet.
enum CanvasNameRequest: Identifiable, Equatable {
    case groupLabel(nodeIdentifier: String)
    case edgeLabel(edgeIdentifier: String)
    /// A web address for a new link card.
    case webAddress

    var id: String {
        switch self {
        case .groupLabel(let nodeIdentifier): "group|" + nodeIdentifier
        case .edgeLabel(let edgeIdentifier): "edge|" + edgeIdentifier
        case .webAddress: "address"
        }
    }
}

/// An open `.canvas` file: its cards and connections, the part of the board on screen,
/// the selection, and its own undo history. The file's bytes are the document. Every
/// edit replaces only the bytes it changes (`CanvasFile.applying`), and a canvas that is
/// only looked at is never written.
@MainActor @Observable
final class CanvasSession {
    static let maximumUndoSteps = 200
    /// How long after an edit the canvas is saved, as for notes.
    static let autosaveDelay = Duration.milliseconds(900)
    /// Below this magnification cards are drawn as plain shapes, as Obsidian does: their
    /// text could not be read anyway, and thousands of cards can be in view at once.
    static let minimumDetailScale: CGFloat = 0.3
    /// At most this many cards show their content at once; the ones nearest the middle
    /// of the view win, and the rest are drawn as plain shapes.
    static let maximumDetailedCardCount = 60
    static let viewPadding: CGFloat = 48

    let path: VaultPath
    private let store: VaultStore
    private let didSave: @MainActor (VaultPath) -> Void

    // MARK: Document

    /// The canvas as it is now, with every edit made.
    private(set) var file: CanvasFile
    /// Increases with every change to `file`.
    private(set) var changeVersion = 0
    @ObservationIgnored private var savedVersion = 0
    @ObservationIgnored private var savedData: Data
    @ObservationIgnored private var revision: FileRevision
    @ObservationIgnored private var activeSave: Task<Void, Error>?
    @ObservationIgnored private var autosave: Task<Void, Never>?
    var errorMessage: String?
    var hasExternalConflict = false
    /// Read or Write, as for notes and PDFs. Read never changes the file.
    var isWriting = false {
        didSet {
            guard isWriting != oldValue else { return }
            // Text typed so far is kept; the selection belongs to writing.
            if !isWriting { endEditing(); clearSelection() }
            focusedNodeIdentifier = nil
        }
    }
    /// The canvas's own undo history. Each step keeps only the bytes it changed.
    @ObservationIgnored let undoManager: UndoManager = {
        let undoManager = UndoManager()
        undoManager.levelsOfUndo = CanvasSession.maximumUndoSteps
        // Each edit is one step, whatever else happens in the same turn of the run loop.
        undoManager.groupsByEvent = false
        return undoManager
    }()
    @ObservationIgnored let undoAvailability = UndoAvailability()

    var isSaving: Bool { activeSave != nil }
    var hasUnsavedChanges: Bool { changeVersion != savedVersion || hasUncommittedText }

    // MARK: View

    /// The part of the board on screen.
    var viewport = CanvasViewport() {
        didSet { if viewport != oldValue { updateDetailedNodes() } }
    }
    /// The board view's size, which zooming and "Zoom to fit" need.
    var viewSize = CGSize.zero {
        didSet {
            guard viewSize != oldValue, viewSize.width > 0, viewSize.height > 0 else { return }
            if !hasShownWholeBoard { hasShownWholeBoard = true; zoomToFit(animated: false) } else { updateDetailedNodes() }
        }
    }
    /// A canvas opens showing all of it; afterwards it stays where the person left it.
    @ObservationIgnored private var hasShownWholeBoard = false
    /// The cards that show their content now, bottom first. Kept apart from `viewport`
    /// so the card views are rebuilt only when this list changes, not at every pan.
    private(set) var detailedNodes: [CanvasNode] = []
    @ObservationIgnored private var viewportAnimation: Task<Void, Never>?
    /// Where each group's label is drawn, on the board, for touches on it. Set by the
    /// view that draws the labels.
    @ObservationIgnored var groupLabelFrames: [String: CGRect] = [:]
    @ObservationIgnored private var cachedReadingPositions: (changeVersion: Int, positions: [String: Int])?

    // MARK: Selection and gestures

    var selectedNodeIdentifiers: Set<String> = []
    var selectedEdgeIdentifiers: Set<String> = []
    /// In Read, the card whose content scrolls and takes touches, as a selected card does
    /// in Obsidian.
    var focusedNodeIdentifier: String?
    /// Where cards being moved or resized are shown before the finger lifts.
    var previewFrames: [String: CGRect] = [:] {
        didSet { if previewFrames != oldValue { updateDetailedNodes() } }
    }
    /// The lines a moved card snapped to.
    var snapGuides = CanvasSnapGuides()
    /// The selection rectangle being drawn, on the board.
    var selectionRectangle: CGRect?
    var pendingConnection: CanvasPendingConnection?
    var textEdit: CanvasTextEdit?
    var nameRequest: CanvasNameRequest?
    @ObservationIgnored var activeDrag: CanvasDrag?
    /// "Snap to grid" and "Snap to objects", as in Obsidian's canvas menu. Kept on the
    /// device for every canvas.
    var snapsToGrid = UserDefaults.standard.object(forKey: CanvasPreferenceKey.snapsToGrid) as? Bool ?? true {
        didSet { UserDefaults.standard.set(snapsToGrid, forKey: CanvasPreferenceKey.snapsToGrid) }
    }
    var snapsToObjects = UserDefaults.standard.object(forKey: CanvasPreferenceKey.snapsToObjects) as? Bool ?? true {
        didSet { UserDefaults.standard.set(snapsToObjects, forKey: CanvasPreferenceKey.snapsToObjects) }
    }

    init(path: VaultPath, snapshot: FileSnapshot, store: VaultStore, didSave: @escaping @MainActor (VaultPath) -> Void) throws {
        self.path = path; self.store = store; self.didSave = didSave
        file = try CanvasFile(data: snapshot.data)
        savedData = snapshot.data
        revision = snapshot.revision
        undoAvailability.follow(undoManager)
    }

    // MARK: Looking things up

    /// A card's frame as shown: where it is being dragged to, else where the file puts it.
    func frame(of node: CanvasNode) -> CGRect {
        previewFrames[node.id] ?? node.frame
    }

    /// The file's cards with the frames they are shown at.
    var shownNodes: [CanvasNode] {
        guard !previewFrames.isEmpty else { return file.nodes }
        return file.nodes.map { node in
            guard let previewFrame = previewFrames[node.id] else { return node }
            var shownNode = node
            shownNode.frame = previewFrame
            return shownNode
        }
    }

    /// The curve of a connection, or nil when a card it names is not on the board.
    func route(of edge: CanvasEdge) -> CanvasEdgeRoute? {
        guard let fromNode = file.node(named: edge.fromNode), let toNode = file.node(named: edge.toNode) else { return nil }
        return CanvasGeometry.route(from: frame(of: fromNode), to: frame(of: toNode), fromSide: edge.fromSide, toSide: edge.toSide)
    }

    var selectedNodes: [CanvasNode] { file.nodes.filter { node in selectedNodeIdentifiers.contains(node.id) } }
    var selectedEdges: [CanvasEdge] { file.edges.filter { edge in selectedEdgeIdentifiers.contains(edge.id) } }
    var hasSelection: Bool { !selectedNodeIdentifiers.isEmpty || !selectedEdgeIdentifiers.isEmpty }

    /// The frame around the selected cards and connections, on the board; nil for none.
    var selectionBounds: CGRect? {
        var bounds = selectedNodes.reduce(CGRect.null) { bounds, node in bounds.union(frame(of: node)) }
        for edge in selectedEdges { if let route = route(of: edge) { bounds = bounds.union(route.bounds) } }
        return bounds.isNull ? nil : bounds
    }

    /// Each card's place in reading order (`CanvasGeometry.readingOrder`), by identifier,
    /// for assistive technologies. Worked out once per version of the file.
    var readingPositions: [String: Int] {
        if let cached = cachedReadingPositions, cached.changeVersion == changeVersion { return cached.positions }
        let positions = Dictionary(uniqueKeysWithValues: CanvasGeometry.readingOrder(of: file.nodes).enumerated().map { position, node in (node.id, position) })
        cachedReadingPositions = (changeVersion, positions)
        return positions
    }

    // MARK: Editing

    /// Makes `changes` as one step of the undo history, and saves soon after.
    /// - Returns: False when the change could not be made; the canvas is then as it was.
    @discardableResult
    func perform(_ changes: [CanvasChange], named actionName: String) -> Bool {
        do {
            let result = try file.applying(changes)
            guard !result.undoPatch.isEmpty else { return true }
            adopt(result.file)
            registerUndo(result.undoPatch, named: actionName)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func registerUndo(_ patch: CanvasPatch, named actionName: String) {
        // While undoing or redoing, the undo manager groups what is registered itself.
        let opensGroup = !undoManager.isUndoing && !undoManager.isRedoing
        if opensGroup { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { session in session.applyFromHistory(patch, named: actionName) }
        undoManager.setActionName(actionName)
        if opensGroup { undoManager.endUndoGrouping() }
        undoAvailability.refresh()
    }

    private func applyFromHistory(_ patch: CanvasPatch, named actionName: String) {
        do {
            // Text being typed is set aside: the step may remove the card it is typed in.
            textEdit = nil
            let result = try file.applying(patch)
            adopt(result.file)
            registerUndo(result.undoPatch, named: actionName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func adopt(_ newFile: CanvasFile) {
        file = newFile
        changeVersion += 1
        // Cards and connections that are gone cannot stay selected.
        selectedNodeIdentifiers = selectedNodeIdentifiers.filter { identifier in newFile.node(withIdentifier: identifier) != nil }
        selectedEdgeIdentifiers = selectedEdgeIdentifiers.filter { identifier in newFile.edge(withIdentifier: identifier) != nil }
        if let focusedNodeIdentifier, newFile.node(withIdentifier: focusedNodeIdentifier) == nil { self.focusedNodeIdentifier = nil }
        if let textEdit, newFile.node(withIdentifier: textEdit.nodeIdentifier) == nil { self.textEdit = nil }
        updateDetailedNodes()
        scheduleAutosave()
    }

    // MARK: Text cards

    private var hasUncommittedText: Bool {
        guard let textEdit, case .text(let savedText)? = file.node(withIdentifier: textEdit.nodeIdentifier)?.content else { return false }
        return textEdit.text != savedText
    }

    /// Starts editing a text card's Markdown in place.
    func beginEditingText(of nodeIdentifier: String) {
        guard isWriting, case .text(let text)? = file.node(withIdentifier: nodeIdentifier)?.content else { return }
        commitTextEdit()
        selectedNodeIdentifiers = [nodeIdentifier]; selectedEdgeIdentifiers = []
        textEdit = CanvasTextEdit(nodeIdentifier: nodeIdentifier, text: text)
        updateDetailedNodes()
    }

    /// Text typed into the card being edited. It is saved once typing pauses.
    func updateTextEdit(_ text: String) {
        guard textEdit != nil, textEdit?.text != text else { return }
        textEdit?.text = text
        scheduleAutosave()
    }

    /// Writes the text typed so far into the card, as one undo step; editing goes on.
    func commitTextEdit() {
        guard let textEdit, hasUncommittedText else { return }
        perform([.setText(textEdit.text, nodeIdentifier: textEdit.nodeIdentifier)], named: "Edit Text")
    }

    /// Ends editing in place, keeping what was typed.
    func endEditing() {
        commitTextEdit()
        textEdit = nil
    }

    // MARK: Saving

    private func scheduleAutosave() {
        autosave?.cancel()
        autosave = Task { [weak self] in
            do { try await Task.sleep(for: Self.autosaveDelay) } catch { return }
            // A failed save shows in the pane's banner; the edits stay open.
            try? await self?.save()
        }
    }

    /// Saves the canvas if it changed, through the vault's revision-checked writer: a file
    /// another app changed meanwhile is never overwritten. A save already running is
    /// awaited first, so autosave, navigation and "Save Now" never race.
    func save() async throws {
        commitTextEdit()
        while let previousSave = activeSave {
            _ = try? await previousSave.value
            // Whichever waiter resumes first clears the finished save (see `MarkdownSession.save`).
            if activeSave == previousSave { activeSave = nil }
        }
        guard changeVersion != savedVersion else { return }
        let versionToSave = changeVersion
        let dataToSave = file.data
        // Undoing back to what is on disk leaves nothing to write.
        guard dataToSave != savedData else {
            savedVersion = versionToSave
            return
        }
        guard !hasExternalConflict else { throw GraphiteError.conflict }
        let expectedRevision = revision
        let saveTask = Task { [store, path] in
            let newRevision = try await store.save(dataToSave, at: path, expecting: .revision(expectedRevision))
            self.revision = newRevision
            self.savedData = dataToSave
            self.savedVersion = versionToSave
        }
        activeSave = saveTask
        defer { if activeSave == saveTask { activeSave = nil } }
        do {
            try await saveTask.value
            errorMessage = nil
            didSave(path)
        } catch {
            if error as? GraphiteError == .conflict { hasExternalConflict = true }
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Reads the file again after another app may have changed it. Unsaved edits are
    /// kept, and the conflict is shown instead.
    func checkExternalChange() async {
        guard !isSaving else { return }
        do {
            let snapshot = try await store.read(path, maximumBytes: CanvasFile.maximumSourceBytes)
            guard snapshot.revision != revision else { return }
            if hasUnsavedChanges {
                hasExternalConflict = true
                errorMessage = GraphiteError.conflict.localizedDescription
            } else {
                try adopt(snapshot)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Replaces the open canvas with the file's version, discarding unsaved edits.
    func reload() async throws {
        guard try await store.fileExists(path) else {
            throw GraphiteError.unavailable("Another app deleted or moved this canvas, so there is no other version to use. Save a Copy keeps your edits.")
        }
        try adopt(await store.read(path, maximumBytes: CanvasFile.maximumSourceBytes))
    }

    private func adopt(_ snapshot: FileSnapshot) throws {
        let newFile = try CanvasFile(data: snapshot.data)
        autosave?.cancel()
        textEdit = nil
        file = newFile
        savedData = snapshot.data; revision = snapshot.revision
        changeVersion += 1; savedVersion = changeVersion
        // The history's steps are byte changes to the version that was open.
        undoManager.removeAllActions()
        undoAvailability.refresh()
        selectedNodeIdentifiers = selectedNodeIdentifiers.filter { identifier in newFile.node(withIdentifier: identifier) != nil }
        selectedEdgeIdentifiers = selectedEdgeIdentifiers.filter { identifier in newFile.edge(withIdentifier: identifier) != nil }
        previewFrames = [:]; activeDrag = nil; pendingConnection = nil; selectionRectangle = nil
        hasExternalConflict = false; errorMessage = nil
        updateDetailedNodes()
    }

    /// Writes the edits to a new canvas beside this one and ends the conflict: this canvas
    /// shows the other app's version again.
    func saveSeparateCopy() async throws -> VaultPath {
        commitTextEdit()
        let separatePath = try await store.uniquePath(directory: path.parent, stem: path.stem + " Graphite edits", extension: "canvas")
        _ = try await store.save(file.data, at: separatePath, expecting: .absent)
        do {
            try await reload()
        } catch {
            // The edits are in the copy; this canvas keeps showing them until it is closed.
            savedVersion = changeVersion
            hasExternalConflict = false
            errorMessage = error.localizedDescription
        }
        return separatePath
    }

    // MARK: Viewport

    /// Sets the part of the board on screen, at once or over a short animation. The
    /// animation moves the viewport itself, so cards, connections and the grid stay together.
    func setViewport(_ newViewport: CanvasViewport, animated: Bool) {
        viewportAnimation?.cancel()
        guard animated, viewSize.width > 0 else {
            viewport = newViewport
            return
        }
        let startViewport = viewport
        let startCenter = startViewport.boardPoint(forViewPoint: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
        let endCenter = newViewport.boardPoint(forViewPoint: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
        viewportAnimation = Task { [weak self] in
            let clock = ContinuousClock()
            let start = clock.now
            let duration = Duration.milliseconds(260)
            while !Task.isCancelled {
                let progress = min(max((clock.now - start) / duration, 0), 1)
                // Ease out: fast at first, settling at the end.
                let eased = 1 - pow(1 - progress, 3)
                guard let self else { return }
                // Magnification changes evenly to the eye when its logarithm does.
                let scale = exp(log(startViewport.scale) + (log(newViewport.scale) - log(startViewport.scale)) * eased)
                let center = CGPoint(x: startCenter.x + (endCenter.x - startCenter.x) * eased, y: startCenter.y + (endCenter.y - startCenter.y) * eased)
                self.viewport = CanvasViewport(scale: scale, origin: CGPoint(x: center.x - self.viewSize.width / scale / 2, y: center.y - self.viewSize.height / scale / 2))
                if progress >= 1 { break }
                do { try await Task.sleep(for: .milliseconds(8)) } catch { return }
            }
            if !Task.isCancelled { self?.viewport = newViewport }
        }
    }

    /// Stops an animated move, as when a finger takes hold of the board.
    func stopViewportAnimation() {
        viewportAnimation?.cancel()
        viewportAnimation = nil
    }

    func zoomToFit(animated: Bool = true) {
        setViewport(CanvasViewport.fitting(CanvasGeometry.bounds(of: file.nodes), in: viewSize, padding: Self.viewPadding), animated: animated)
    }

    func zoomToSelection(animated: Bool = true) {
        guard let selectionBounds else { return }
        setViewport(CanvasViewport.fitting(selectionBounds, in: viewSize, padding: Self.viewPadding), animated: animated)
    }

    func zoom(toNodeWithIdentifier nodeIdentifier: String, animated: Bool = true) {
        guard let node = file.node(withIdentifier: nodeIdentifier) else { return }
        setViewport(CanvasViewport.fitting(node.frame, in: viewSize, padding: Self.viewPadding), animated: animated)
    }

    /// Magnifies around the middle of the view, for the zoom buttons.
    func zoom(by factor: CGFloat, animated: Bool = true) {
        var zoomedViewport = viewport
        zoomedViewport.zoom(by: factor, around: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
        setViewport(zoomedViewport, animated: animated)
    }

    func resetZoom(animated: Bool = true) {
        zoom(by: 1 / viewport.scale, animated: animated)
    }

    /// Brings a card wholly into the part of the view nothing covers, as when the keyboard
    /// comes up over the card being edited.
    func reveal(nodeWithIdentifier nodeIdentifier: String, in unobscuredViewFrame: CGRect) {
        guard let node = file.node(withIdentifier: nodeIdentifier) else { return }
        var revealingViewport = viewport
        revealingViewport.reveal(frame(of: node), in: unobscuredViewFrame, margin: 16)
        setViewport(revealingViewport, animated: true)
    }

    /// The board frame that is on screen, a little enlarged so cards about to scroll in
    /// are ready.
    var visibleBoardFrame: CGRect {
        viewport.visibleBoardFrame(viewSize: viewSize)
    }

    func updateDetailedNodes() {
        var newDetailedNodes: [CanvasNode] = []
        if viewport.scale >= Self.minimumDetailScale, viewSize.width > 0 {
            let visibleFrame = visibleBoardFrame
            var candidates = shownNodes.filter { node in !node.isGroup && node.frame.intersects(visibleFrame) }
            // The card being edited always shows its content, wherever it is.
            if let editedIdentifier = textEdit?.nodeIdentifier, !candidates.contains(where: { node in node.id == editedIdentifier }),
               let editedNode = shownNodes.first(where: { node in node.id == editedIdentifier }) {
                candidates.append(editedNode)
            }
            if candidates.count > Self.maximumDetailedCardCount {
                let center = CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
                let nearestIdentifiers = Set(candidates.sorted { firstNode, secondNode in
                    hypot(firstNode.frame.midX - center.x, firstNode.frame.midY - center.y) < hypot(secondNode.frame.midX - center.x, secondNode.frame.midY - center.y)
                }.prefix(Self.maximumDetailedCardCount).map(\.id))
                candidates = candidates.filter { node in nearestIdentifiers.contains(node.id) || node.id == textEdit?.nodeIdentifier }
            }
            newDetailedNodes = candidates
        }
        // Assigned only when it changes: the card views read it.
        if newDetailedNodes != detailedNodes { detailedNodes = newDetailedNodes }
    }
}
