import Foundation
import CoreGraphics
import GraphiteCore

/// What a one-finger drag on the board is doing.
enum CanvasDrag {
    /// Moving the board; `lastTranslation` is how far the drag had gone at its last report.
    case panning(lastTranslation: CGSize)
    /// Moving the selected cards, with the cards inside selected groups.
    case moving(originalFrames: [String: CGRect], grabbedNodeIdentifier: String)
    case resizing(nodeIdentifier: String, handle: CanvasResizeHandle, originalFrame: CGRect)
    /// Drawing a connection; its state is `CanvasSession.pendingConnection`.
    case connecting
    /// Drawing a selection rectangle from `startPoint`, on the board, adding to `baseSelection`.
    case selecting(startPoint: CGPoint, baseSelection: Set<String>)
}

/// Touches and commands on the board. Gestures arrive in view coordinates from the
/// platform's recognizers; everything they do is decided here, away from any view, so it
/// is the same for a finger, a Pencil and a pointer, and can be tested without a screen.
extension CanvasSession {
    /// Sizes of touch targets, in view points, so they stay the same at every magnification.
    enum TouchMetrics {
        static let handleReach: CGFloat = 22
        /// How far outside a card's side its connection dot sits.
        static let connectionDotDistance: CGFloat = 24
        static let edgeReach: CGFloat = 14
        static let groupBorderReach: CGFloat = 12
        static let snapReach: CGFloat = 8
    }

    /// Sizes new cards get, in board pixels. Text and note cards match Obsidian's.
    enum NewCardSize {
        static let text = CGSize(width: 250, height: 60)
        static let note = CGSize(width: 400, height: 400)
        static let media = CGSize(width: 400, height: 240)
        static let link = CGSize(width: 360, height: 140)
        static let group = CGSize(width: 420, height: 300)
        /// The space a new group leaves around the cards it is drawn around.
        static let groupPadding: CGFloat = 20
        /// How far a copy lands from its original.
        static let duplicateOffset: CGFloat = 40
    }

    // MARK: What is where

    /// The card that shows resize handles and connection dots: the only thing selected.
    var nodeWithHandles: CanvasNode? {
        guard isWriting, textEdit == nil, selectedEdgeIdentifiers.isEmpty, selectedNodeIdentifiers.count == 1,
              let identifier = selectedNodeIdentifiers.first, let node = file.node(withIdentifier: identifier) else { return nil }
        return node
    }

    /// Where a side's connection dot is drawn, in the view.
    func connectionDotPosition(for side: CanvasSide, ofViewFrame viewFrame: CGRect) -> CGPoint {
        let anchor = CanvasGeometry.anchor(of: viewFrame, side: side)
        switch side {
        case .top: return CGPoint(x: anchor.x, y: anchor.y - TouchMetrics.connectionDotDistance)
        case .right: return CGPoint(x: anchor.x + TouchMetrics.connectionDotDistance, y: anchor.y)
        case .bottom: return CGPoint(x: anchor.x, y: anchor.y + TouchMetrics.connectionDotDistance)
        case .left: return CGPoint(x: anchor.x - TouchMetrics.connectionDotDistance, y: anchor.y)
        }
    }

    /// The card or connection at a point of the view.
    func target(atViewPoint viewPoint: CGPoint, includesEdges: Bool = true) -> CanvasHitTarget? {
        let edgeRoutes: [(identifier: String, route: CanvasEdgeRoute)] = includesEdges
            ? file.edges.compactMap { edge in route(of: edge).map { route in (edge.id, route) } } : []
        return CanvasGeometry.target(at: viewport.boardPoint(forViewPoint: viewPoint), nodes: shownNodes, edgeRoutes: edgeRoutes,
                                     edgeTolerance: TouchMetrics.edgeReach / viewport.scale, groupLabelFrames: groupLabelFrames,
                                     borderTolerance: TouchMetrics.groupBorderReach / viewport.scale)
    }

    /// The card a connection dropped at `boardPoint` would end at: the topmost card
    /// there, else the smallest group around the point.
    private func connectionTarget(at boardPoint: CGPoint, from sourceIdentifier: String) -> CanvasNode? {
        let candidates = shownNodes.filter { node in node.id != sourceIdentifier && node.id == node.identifierInFile && node.frame.contains(boardPoint) }
        if let card = candidates.last(where: { node in !node.isGroup }) { return card }
        return candidates.min { firstGroup, secondGroup in firstGroup.frame.width * firstGroup.frame.height < secondGroup.frame.width * secondGroup.frame.height }
    }

    // MARK: Drags

    func beginDrag(atViewPoint viewPoint: CGPoint) {
        stopViewportAnimation()
        guard isWriting else {
            activeDrag = .panning(lastTranslation: .zero)
            return
        }
        if let node = nodeWithHandles {
            let viewFrame = viewport.viewFrame(forBoardFrame: frame(of: node))
            var nearest: (drag: CanvasDrag, distance: CGFloat, connectionSide: CanvasSide?)?
            func consider(_ drag: CanvasDrag, at position: CGPoint, connectionSide: CanvasSide? = nil) {
                let distance = hypot(viewPoint.x - position.x, viewPoint.y - position.y)
                guard distance <= TouchMetrics.handleReach, nearest.map({ nearest in distance < nearest.distance }) ?? true else { return }
                nearest = (drag, distance, connectionSide)
            }
            for handle in CanvasResizeHandle.allCases {
                consider(.resizing(nodeIdentifier: node.id, handle: handle, originalFrame: frame(of: node)), at: handle.position(on: viewFrame))
            }
            // A card that shares its `id` with another cannot be named by a connection.
            if node.id == node.identifierInFile {
                for side in CanvasSide.allCases { consider(.connecting, at: connectionDotPosition(for: side, ofViewFrame: viewFrame), connectionSide: side) }
            }
            if let nearest {
                activeDrag = nearest.drag
                if let connectionSide = nearest.connectionSide {
                    pendingConnection = CanvasPendingConnection(fromNodeIdentifier: node.id, fromSide: connectionSide, endPoint: viewport.boardPoint(forViewPoint: viewPoint))
                }
                return
            }
        }
        if case .node(let identifier)? = target(atViewPoint: viewPoint, includesEdges: false) {
            if !selectedNodeIdentifiers.contains(identifier) {
                selectedNodeIdentifiers = [identifier]
                selectedEdgeIdentifiers = []
            }
            endEditing()
            var movingNodes = selectedNodes
            for group in selectedNodes where group.isGroup { movingNodes += CanvasGeometry.nodes(inside: group, among: file.nodes) }
            activeDrag = .moving(originalFrames: Dictionary(movingNodes.map { node in (node.id, node.frame) }, uniquingKeysWith: { firstFrame, _ in firstFrame }),
                                 grabbedNodeIdentifier: identifier)
            return
        }
        endEditing()
        activeDrag = .selecting(startPoint: viewport.boardPoint(forViewPoint: viewPoint), baseSelection: [])
    }

    /// - Parameters:
    ///   - translation: How far the finger has moved since the drag began, in the view.
    ///   - viewPoint: Where the finger is now.
    func continueDrag(translation: CGSize, atViewPoint viewPoint: CGPoint) {
        guard let activeDrag else { return }
        let boardTranslation = CGSize(width: translation.width / viewport.scale, height: translation.height / viewport.scale)
        let snapTolerance = TouchMetrics.snapReach / viewport.scale
        switch activeDrag {
        case .panning(let lastTranslation):
            viewport.pan(byViewTranslation: CGSize(width: translation.width - lastTranslation.width, height: translation.height - lastTranslation.height))
            self.activeDrag = .panning(lastTranslation: translation)
        case .moving(let originalFrames, let grabbedNodeIdentifier):
            guard let grabbedFrame = originalFrames[grabbedNodeIdentifier] else { return }
            let proposedFrame = grabbedFrame.offsetBy(dx: boardTranslation.width, dy: boardTranslation.height)
            let snap = CanvasGeometry.snappedMove(of: proposedFrame, otherFrames: snapsToObjects ? framesToSnapTo(excluding: Set(originalFrames.keys)) : [],
                                                 gridSpacing: snapsToGrid ? CanvasGeometry.gridSpacing : nil, tolerance: snapTolerance)
            let offset = CGSize(width: snap.frame.minX - grabbedFrame.minX, height: snap.frame.minY - grabbedFrame.minY)
            previewFrames = originalFrames.mapValues { originalFrame in originalFrame.offsetBy(dx: offset.width, dy: offset.height) }
            snapGuides = CanvasSnapGuides(vertical: snap.verticalGuide, horizontal: snap.horizontalGuide)
        case .resizing(let nodeIdentifier, let handle, let originalFrame):
            let snap = CanvasGeometry.snappedResize(of: originalFrame, handle: handle, translation: boardTranslation,
                                                   otherFrames: snapsToObjects ? framesToSnapTo(excluding: [nodeIdentifier]) : [],
                                                   gridSpacing: snapsToGrid ? CanvasGeometry.gridSpacing : nil, tolerance: snapTolerance)
            previewFrames = [nodeIdentifier: snap.frame]
            snapGuides = CanvasSnapGuides(vertical: snap.verticalGuide, horizontal: snap.horizontalGuide)
        case .connecting:
            guard var connection = pendingConnection else { return }
            connection.endPoint = viewport.boardPoint(forViewPoint: viewPoint)
            connection.targetNodeIdentifier = connectionTarget(at: connection.endPoint, from: connection.fromNodeIdentifier)?.id
            pendingConnection = connection
        case .selecting(let startPoint, let baseSelection):
            let currentPoint = viewport.boardPoint(forViewPoint: viewPoint)
            let rectangle = CGRect(x: min(startPoint.x, currentPoint.x), y: min(startPoint.y, currentPoint.y),
                                   width: abs(currentPoint.x - startPoint.x), height: abs(currentPoint.y - startPoint.y))
            selectionRectangle = rectangle
            selectedNodeIdentifiers = baseSelection.union(CanvasGeometry.nodes(selectedBy: rectangle, among: file.nodes).map(\.id))
            selectedEdgeIdentifiers = []
        }
    }

    /// - Parameter isCancelled: True when the system took the touch away; nothing is changed then.
    func endDrag(isCancelled: Bool = false) {
        defer {
            activeDrag = nil
            previewFrames = [:]
            snapGuides = CanvasSnapGuides()
            selectionRectangle = nil
            pendingConnection = nil
        }
        guard let activeDrag, !isCancelled else { return }
        switch activeDrag {
        case .panning, .selecting:
            break
        case .moving:
            guard !previewFrames.isEmpty else { return }
            perform([.setFrames(previewFrames)], named: previewFrames.count == 1 ? "Move Card" : "Move Cards")
        case .resizing:
            guard !previewFrames.isEmpty else { return }
            perform([.setFrames(previewFrames)], named: "Resize Card")
        case .connecting:
            guard let connection = pendingConnection, let targetIdentifier = connection.targetNodeIdentifier,
                  let sourceNode = file.node(withIdentifier: connection.fromNodeIdentifier), let targetNode = file.node(withIdentifier: targetIdentifier) else { return }
            let edge = CanvasEdge(id: file.newIdentifier(), fromNode: sourceNode.identifierInFile, toNode: targetNode.identifierInFile, fromSide: connection.fromSide,
                                  toSide: CanvasGeometry.nearestSide(of: targetNode.frame, to: connection.endPoint))
            if perform([.add(nodes: [], edges: [edge])], named: "Connect Cards") {
                selectedNodeIdentifiers = []
                selectedEdgeIdentifiers = [edge.id]
            }
        }
    }

    /// The cards a dragged card can line up with: those on screen, which are the ones a
    /// guide line could be seen for.
    private func framesToSnapTo(excluding excludedIdentifiers: Set<String>) -> [CGRect] {
        let visibleFrame = visibleBoardFrame
        return file.nodes.lazy.filter { node in !excludedIdentifiers.contains(node.id) && node.frame.intersects(visibleFrame) }
            .prefix(Self.maximumSnapCandidateCount).map(\.frame)
    }

    private static var maximumSnapCandidateCount: Int { 400 }

    // MARK: Taps

    /// - Parameter extendsSelection: True with Shift held, which adds to the selection or
    ///   takes from it.
    func tap(atViewPoint viewPoint: CGPoint, extendsSelection: Bool = false) {
        let target = target(atViewPoint: viewPoint)
        // The double tap that starts editing a card is also told as two taps; the second
        // must not end the editing it began.
        if let editedIdentifier = textEdit?.nodeIdentifier, target == .node(editedIdentifier) { return }
        endEditing()
        guard isWriting else {
            if case .node(let identifier)? = target { focusedNodeIdentifier = identifier } else { focusedNodeIdentifier = nil }
            return
        }
        switch target {
        case .node(let identifier)?:
            if extendsSelection { toggleSelection(ofNode: identifier) } else { selectedNodeIdentifiers = [identifier]; selectedEdgeIdentifiers = [] }
        case .edge(let identifier)?:
            if extendsSelection { toggleSelection(ofEdge: identifier) } else { selectedNodeIdentifiers = []; selectedEdgeIdentifiers = [identifier] }
        case nil:
            if !extendsSelection { clearSelection() }
        }
    }

    /// In Read, zooms to the card. In Write, as in Obsidian: edits a text card, renames
    /// a group, labels a connection, and on empty board adds a text card there.
    func doubleTap(atViewPoint viewPoint: CGPoint) {
        let target = target(atViewPoint: viewPoint)
        guard isWriting else {
            if case .node(let identifier)? = target { zoom(toNodeWithIdentifier: identifier) }
            return
        }
        switch target {
        case .node(let identifier)?:
            guard let node = file.node(withIdentifier: identifier) else { return }
            switch node.content {
            case .text: beginEditingText(of: identifier)
            case .group: nameRequest = .groupLabel(nodeIdentifier: identifier)
            case .file, .link, .unknown: zoom(toNodeWithIdentifier: identifier)
            }
        case .edge(let identifier)?:
            selectedNodeIdentifiers = []; selectedEdgeIdentifiers = [identifier]
            nameRequest = .edgeLabel(edgeIdentifier: identifier)
        case nil:
            addTextCard(centeredAt: viewport.boardPoint(forViewPoint: viewPoint))
        }
    }

    /// A long press adds a card or connection to the selection, or takes it out: the
    /// way to select several by touch, where there is no Shift key.
    func longPress(atViewPoint viewPoint: CGPoint) {
        guard isWriting else { return }
        endEditing()
        switch target(atViewPoint: viewPoint) {
        case .node(let identifier)?: toggleSelection(ofNode: identifier)
        case .edge(let identifier)?: toggleSelection(ofEdge: identifier)
        case nil: break
        }
    }

    private func toggleSelection(ofNode identifier: String) {
        if selectedNodeIdentifiers.contains(identifier) { selectedNodeIdentifiers.remove(identifier) } else { selectedNodeIdentifiers.insert(identifier) }
    }

    private func toggleSelection(ofEdge identifier: String) {
        if selectedEdgeIdentifiers.contains(identifier) { selectedEdgeIdentifiers.remove(identifier) } else { selectedEdgeIdentifiers.insert(identifier) }
    }

    func clearSelection() {
        selectedNodeIdentifiers = []
        selectedEdgeIdentifiers = []
    }

    func selectAll() {
        guard isWriting else { return }
        endEditing()
        selectedNodeIdentifiers = Set(file.nodes.map(\.id))
        selectedEdgeIdentifiers = Set(file.edges.map(\.id))
    }

    // MARK: Commands on the selection

    func deleteSelection() {
        guard isWriting, hasSelection else { return }
        textEdit = nil
        let cardCount = selectedNodeIdentifiers.count, connectionCount = selectedEdgeIdentifiers.count
        let actionName = cardCount == 0 ? (connectionCount == 1 ? "Delete Connection" : "Delete Connections") : (cardCount == 1 ? "Delete Card" : "Delete Cards")
        perform([.remove(nodeIdentifiers: selectedNodeIdentifiers, edgeIdentifiers: selectedEdgeIdentifiers)], named: actionName)
    }

    /// Copies the selected cards beside themselves, with the connections among them, and
    /// selects the copies.
    func duplicateSelection() {
        guard isWriting, !selectedNodeIdentifiers.isEmpty else { return }
        endEditing()
        var takenIdentifiers: Set<String> = []
        func newIdentifier() -> String {
            let identifier = file.newIdentifier(avoiding: takenIdentifiers)
            takenIdentifiers.insert(identifier)
            return identifier
        }
        var newNamesBySourceName: [String: String] = [:]
        var nodeCopies: [CanvasNodeCopy] = []
        for node in selectedNodes {
            let copyIdentifier = newIdentifier()
            if newNamesBySourceName[node.identifierInFile] == nil { newNamesBySourceName[node.identifierInFile] = copyIdentifier }
            nodeCopies.append(CanvasNodeCopy(sourceIdentifier: node.id, newIdentifier: copyIdentifier,
                                             origin: CGPoint(x: node.frame.minX + NewCardSize.duplicateOffset, y: node.frame.minY + NewCardSize.duplicateOffset)))
        }
        let edgeCopies = file.edges.compactMap { edge -> CanvasEdgeCopy? in
            guard let fromNode = newNamesBySourceName[edge.fromNode], let toNode = newNamesBySourceName[edge.toNode] else { return nil }
            return CanvasEdgeCopy(sourceIdentifier: edge.id, newIdentifier: newIdentifier(), fromNode: fromNode, toNode: toNode)
        }
        if perform([.duplicate(nodes: nodeCopies, edges: edgeCopies)], named: nodeCopies.count == 1 ? "Duplicate Card" : "Duplicate Cards") {
            selectedNodeIdentifiers = Set(nodeCopies.map(\.newIdentifier))
            selectedEdgeIdentifiers = []
        }
    }

    /// - Parameter color: Nil removes the color.
    func setColorOfSelection(_ color: CanvasColor?) {
        guard isWriting, hasSelection else { return }
        var changes: [CanvasChange] = []
        if !selectedNodeIdentifiers.isEmpty { changes.append(.setNodeColor(color, nodeIdentifiers: selectedNodeIdentifiers)) }
        if !selectedEdgeIdentifiers.isEmpty { changes.append(.setEdgeColor(color, edgeIdentifiers: selectedEdgeIdentifiers)) }
        perform(changes, named: "Change Color")
    }

    func bringSelectionToFront() {
        guard isWriting, !selectedNodeIdentifiers.isEmpty else { return }
        perform([.moveToFront(nodeIdentifiers: selectedNodeIdentifiers)], named: "Bring to Front")
    }

    func sendSelectionToBack() {
        guard isWriting, !selectedNodeIdentifiers.isEmpty else { return }
        perform([.moveToBack(nodeIdentifiers: selectedNodeIdentifiers)], named: "Send to Back")
    }

    func setEndsOfSelectedEdges(fromEnd: CanvasEdgeEnd, toEnd: CanvasEdgeEnd) {
        guard isWriting, !selectedEdgeIdentifiers.isEmpty else { return }
        perform([.setEdgeEnds(fromEnd: fromEnd, toEnd: toEnd, edgeIdentifiers: selectedEdgeIdentifiers)], named: "Change Line Ends")
    }

    func setGroupLabel(_ label: String, nodeIdentifier: String) {
        guard isWriting else { return }
        perform([.setGroupLabel(label.trimmingCharacters(in: .whitespacesAndNewlines), nodeIdentifier: nodeIdentifier)], named: "Rename Group")
    }

    func setEdgeLabel(_ label: String, edgeIdentifier: String) {
        guard isWriting else { return }
        perform([.setEdgeLabel(label.trimmingCharacters(in: .whitespacesAndNewlines), edgeIdentifier: edgeIdentifier)], named: "Edit Label")
    }

    // MARK: Adding

    /// Where a new card of `size` goes: around `center`, or the middle of the view, on the
    /// grid when snapping is on, and never exactly on top of a card already there.
    private func frameForNewCard(size: CGSize, centeredAt center: CGPoint?) -> CGRect {
        let visibleFrame = visibleBoardFrame
        let center = center ?? CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        var origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        let spacing = CanvasGeometry.gridSpacing
        if snapsToGrid { origin = CGPoint(x: (origin.x / spacing).rounded() * spacing, y: (origin.y / spacing).rounded() * spacing) }
        origin = CGPoint(x: origin.x.rounded(), y: origin.y.rounded())
        let takenOrigins = Set(file.nodes.map { node in [node.frame.minX, node.frame.minY] })
        var attemptCount = 0
        while takenOrigins.contains([origin.x, origin.y]), attemptCount < 100 {
            origin = CGPoint(x: origin.x + spacing, y: origin.y + spacing)
            attemptCount += 1
        }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    private func add(_ content: CanvasNode.Content, size: CGSize, centeredAt center: CGPoint? = nil, named actionName: String) -> String? {
        guard isWriting else { return nil }
        endEditing()
        let node = CanvasNode(id: file.newIdentifier(), content: content, frame: frameForNewCard(size: size, centeredAt: center))
        guard perform([.add(nodes: [node], edges: [])], named: actionName) else { return nil }
        selectedNodeIdentifiers = [node.id]
        selectedEdgeIdentifiers = []
        return node.id
    }

    /// Adds an empty text card and starts typing in it.
    @discardableResult
    func addTextCard(centeredAt center: CGPoint? = nil) -> String? {
        guard let identifier = add(.text(""), size: NewCardSize.text, centeredAt: center, named: "Add Card") else { return nil }
        beginEditingText(of: identifier)
        return identifier
    }

    /// Adds a card showing a file of the vault.
    /// - Parameter size: The card's size; a picture's follows its shape.
    @discardableResult
    func addFileCard(_ path: VaultPath, size: CGSize) -> String? {
        add(.file(path: path.rawValue, subpath: nil), size: size, named: DocumentKind(path: path) == .markdown ? "Add Note" : "Add Media")
    }

    /// A web address as a link card keeps it, or nil when the text is not one. An address
    /// typed without `https://` gets it.
    static func webAddress(from typedText: String) -> String? {
        let trimmedText = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !trimmedText.contains(where: \.isWhitespace) else { return nil }
        let address = trimmedText.contains("://") ? trimmedText : "https://" + trimmedText
        guard let components = URLComponents(string: address), let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        return address
    }

    /// The address a link card opens in the browser: web pages only, never another app's
    /// link or a file.
    static func browsableLocation(of address: String) -> URL? {
        guard let location = URL(string: address), let scheme = location.scheme?.lowercased(), scheme == "http" || scheme == "https",
              location.host()?.isEmpty == false else { return nil }
        return location
    }

    @discardableResult
    func addLinkCard(address: String) -> String? {
        guard let webAddress = Self.webAddress(from: address) else {
            errorMessage = "“\(address)” is not a web address."
            return nil
        }
        return add(.link(address: webAddress), size: NewCardSize.link, named: "Add Web Link")
    }

    /// Adds a group: around the selected cards when there are some, else an empty one.
    @discardableResult
    func addGroup() -> String? {
        guard isWriting else { return nil }
        endEditing()
        let selectedFrames = selectedNodes.map(\.frame)
        let frame: CGRect
        if let firstFrame = selectedFrames.first {
            frame = selectedFrames.reduce(firstFrame) { bounds, selectedFrame in bounds.union(selectedFrame) }.insetBy(dx: -NewCardSize.groupPadding, dy: -NewCardSize.groupPadding)
        } else {
            frame = frameForNewCard(size: NewCardSize.group, centeredAt: nil)
        }
        let group = CanvasNode(id: file.newIdentifier(), content: .group(label: nil, background: nil, backgroundStyle: .cover), frame: frame)
        // Groups are drawn beneath cards wherever they are in the file, so the new one
        // joins the end of the list like any new card.
        guard perform([.add(nodes: [group], edges: [])], named: "Add Group") else { return nil }
        selectedNodeIdentifiers = [group.id]
        selectedEdgeIdentifiers = []
        nameRequest = .groupLabel(nodeIdentifier: group.id)
        return group.id
    }
}
