import XCTest
import CoreGraphics
import GraphiteCore
@testable import GraphiteUI

/// An open canvas driven the way its gestures drive it, in view coordinates: what each
/// touch changes on the board, what is saved to the file, and what Undo gives back.
@MainActor
final class CanvasSessionTests: XCTestCase {
    private var vault: URL!
    private var store: VaultStore!
    private var canvasPath: VaultPath!
    private let viewSize = CGSize(width: 1000, height: 800)

    /// Two text cards side by side, a file card below them, a group around the first two,
    /// and a connection, in Obsidian's layout, with a key Graphite does not know.
    private let board = "{\n\t\"nodes\":[\n"
        + "\t\t{\"id\":\"9000000000000001\",\"type\":\"group\",\"x\":-40,\"y\":-60,\"width\":760,\"height\":320,\"label\":\"Topic\"},\n"
        + "\t\t{\"id\":\"1000000000000001\",\"type\":\"text\",\"text\":\"First\",\"x\":0,\"y\":0,\"width\":250,\"height\":200},\n"
        + "\t\t{\"id\":\"1000000000000002\",\"type\":\"text\",\"text\":\"Second\",\"x\":400,\"y\":0,\"width\":250,\"height\":200,\"color\":\"2\",\"plugin\":{\"keep\":1}},\n"
        + "\t\t{\"id\":\"1000000000000003\",\"type\":\"file\",\"file\":\"Notes/Note.md\",\"x\":0,\"y\":400,\"width\":400,\"height\":300}\n"
        + "\t],\n\t\"edges\":[\n"
        + "\t\t{\"id\":\"2000000000000001\",\"fromNode\":\"1000000000000001\",\"fromSide\":\"right\",\"toNode\":\"1000000000000002\",\"toSide\":\"left\"}\n"
        + "\t]\n}"

    override func setUp() async throws {
        vault = FileManager.default.temporaryDirectory.appendingPathComponent("CanvasSession-\(UUID().uuidString)")
        canvasPath = try VaultPath("Boards/Board.canvas")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Boards"), withIntermediateDirectories: true)
        try Data(board.utf8).write(to: vault.appendingPathComponent(canvasPath.rawValue))
        store = VaultStore(root: vault)
        UserDefaults.standard.removeObject(forKey: CanvasPreferenceKey.snapsToGrid)
        UserDefaults.standard.removeObject(forKey: CanvasPreferenceKey.snapsToObjects)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: vault)
        UserDefaults.standard.removeObject(forKey: CanvasPreferenceKey.snapsToGrid)
        UserDefaults.standard.removeObject(forKey: CanvasPreferenceKey.snapsToObjects)
    }

    private func openSession(isWriting: Bool = true) async throws -> CanvasSession {
        let session = try CanvasSession(path: canvasPath, snapshot: try await store.read(canvasPath), store: store) { _ in }
        session.viewSize = viewSize
        session.isWriting = isWriting
        return session
    }

    private func fileText() throws -> String {
        try String(contentsOf: vault.appendingPathComponent(canvasPath.rawValue), encoding: .utf8)
    }

    private func viewCenter(of identifier: String, in session: CanvasSession) throws -> CGPoint {
        let node = try XCTUnwrap(session.file.node(withIdentifier: identifier))
        let frame = session.viewport.viewFrame(forBoardFrame: node.frame)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    /// A one-finger drag from `start` by `translation`, in view points, in a few steps.
    private func drag(_ session: CanvasSession, from start: CGPoint, by translation: CGSize) {
        session.beginDrag(atViewPoint: start)
        for step in 1...4 {
            let fraction = CGFloat(step) / 4
            let partial = CGSize(width: translation.width * fraction, height: translation.height * fraction)
            session.continueDrag(translation: partial, atViewPoint: CGPoint(x: start.x + partial.width, y: start.y + partial.height))
        }
        session.endDrag()
    }

    // MARK: Viewing

    func testACanvasOpensShowingAllOfItAndLookingNeverWritesTheFile() async throws {
        let modificationDate = try FileManager.default.attributesOfItem(atPath: vault.appendingPathComponent(canvasPath.rawValue).path)[.modificationDate] as? Date
        let session = try await openSession(isWriting: false)
        let viewBounds = CGRect(origin: .zero, size: viewSize)
        for node in session.file.nodes {
            XCTAssertTrue(viewBounds.contains(session.viewport.viewFrame(forBoardFrame: node.frame)), "\(node.id) is in view after opening")
        }
        // Looking around: panning, zooming, tapping, double tapping, zooming to fit.
        var viewport = session.viewport
        viewport.pan(byViewTranslation: CGSize(width: 120, height: -40))
        viewport.zoom(by: 1.7, around: CGPoint(x: 300, y: 300))
        session.viewport = viewport
        session.tap(atViewPoint: try viewCenter(of: "1000000000000001", in: session))
        XCTAssertEqual(session.focusedNodeIdentifier, "1000000000000001", "A tap in Read lets that card's content scroll.")
        session.doubleTap(atViewPoint: try viewCenter(of: "1000000000000002", in: session))
        session.drag(from: CGPoint(x: 500, y: 500), by: CGSize(width: -200, height: 50))
        session.zoomToFit(animated: false)
        XCTAssertFalse(session.hasUnsavedChanges)
        try await session.save()
        XCTAssertEqual(try fileText(), board)
        let laterModificationDate = try FileManager.default.attributesOfItem(atPath: vault.appendingPathComponent(canvasPath.rawValue).path)[.modificationDate] as? Date
        XCTAssertEqual(laterModificationDate, modificationDate, "A canvas that is only looked at is never written.")
        XCTAssertTrue(session.file.nodes.allSatisfy { node in session.file.node(withIdentifier: node.id)?.frame == node.frame })
    }

    func testDraggingInReadPansTheBoardAndMovesNoCard() async throws {
        let session = try await openSession(isWriting: false)
        let before = session.viewport
        let cardCenter = try viewCenter(of: "1000000000000001", in: session)
        session.drag(from: cardCenter, by: CGSize(width: 80, height: 30))
        XCTAssertEqual(session.viewport.viewPoint(forBoardPoint: .zero).x, before.viewPoint(forBoardPoint: .zero).x + 80, accuracy: 0.001)
        XCTAssertEqual(session.viewport.viewPoint(forBoardPoint: .zero).y, before.viewPoint(forBoardPoint: .zero).y + 30, accuracy: 0.001)
        XCTAssertEqual(session.file.data, Data(board.utf8))
    }

    func testDoubleTappingACardInReadZoomsToIt() async throws {
        let session = try await openSession(isWriting: false)
        session.zoom(toNodeWithIdentifier: "1000000000000003", animated: false)
        let frame = session.viewport.viewFrame(forBoardFrame: try XCTUnwrap(session.file.node(withIdentifier: "1000000000000003")).frame)
        XCTAssertEqual(frame.midX, viewSize.width / 2, accuracy: 0.5)
        XCTAssertEqual(frame.midY, viewSize.height / 2, accuracy: 0.5)
        XCTAssertEqual(session.viewport.scale, 1, "A card smaller than the view is shown at its own size.")
    }

    func testCardsShowTheirContentOnlyWhenLegibleAndNeverTooMany() async throws {
        let session = try await openSession(isWriting: false)
        session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: -100, y: -100))
        XCTAssertEqual(Set(session.detailedNodes.map(\.id)), ["1000000000000001", "1000000000000002", "1000000000000003"], "Groups are drawn, not shown as cards.")
        session.viewport = CanvasViewport(scale: CanvasSession.minimumDetailScale / 2, origin: CGPoint(x: -100, y: -100))
        XCTAssertTrue(session.detailedNodes.isEmpty, "Far out, cards are drawn as plain shapes.")
        session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: 5_000, y: 5_000))
        XCTAssertTrue(session.detailedNodes.isEmpty, "Cards out of view are not shown.")

        let manyCards = (0..<500).map { cardIndex in
            "{\"id\":\"\(String(format: "%016x", cardIndex))\",\"type\":\"text\",\"text\":\"\(cardIndex)\",\"x\":\(cardIndex % 25 * 40),\"y\":\(cardIndex / 25 * 40),\"width\":30,\"height\":30}"
        }
        try Data(("{\"nodes\":[" + manyCards.joined(separator: ",") + "]}").utf8).write(to: vault.appendingPathComponent(canvasPath.rawValue))
        let crowded = try await openSession(isWriting: false)
        crowded.viewport = CanvasViewport(scale: 1, origin: .zero)
        XCTAssertEqual(crowded.detailedNodes.count, CanvasSession.maximumDetailedCardCount)
        XCTAssertTrue(crowded.detailedNodes.contains { node in node.frame.contains(CGPoint(x: 505, y: 405)) }, "The cards nearest the middle of the view show their content.")
    }

    // MARK: Moving and resizing

    func testDraggingACardMovesItOnTheGridSavesOnlyItsPositionAndUndoes() async throws {
        let session = try await openSession()
        session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: -100, y: -100))
        session.snapsToObjects = false
        drag(session, from: try viewCenter(of: "1000000000000001", in: session), by: CGSize(width: 33, height: 208))
        XCTAssertEqual(session.file.node(withIdentifier: "1000000000000001")?.frame, CGRect(x: 40, y: 200, width: 250, height: 200), "Snapped to the 20-pixel grid")
        XCTAssertEqual(session.selectedNodeIdentifiers, ["1000000000000001"])
        XCTAssertTrue(session.previewFrames.isEmpty)
        try await session.save()
        XCTAssertEqual(try fileText(), board.replacingOccurrences(of: "\"text\":\"First\",\"x\":0,\"y\":0,", with: "\"text\":\"First\",\"x\":40,\"y\":200,"))
        XCTAssertEqual(session.undoAvailability.undoActionName, "Move Card")
        session.undoAvailability.undo()
        try await session.save()
        XCTAssertEqual(try fileText(), board, "Undo gives the file back byte for byte.")
        session.undoAvailability.redo()
        XCTAssertEqual(session.file.node(withIdentifier: "1000000000000001")?.frame.origin, CGPoint(x: 40, y: 200))
    }

    func testDraggingAGroupMovesTheCardsInsideIt() async throws {
        let session = try await openSession()
        session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: -100, y: -100))
        session.snapsToGrid = false
        session.snapsToObjects = false
        // The group is taken by its border.
        let borderPoint = session.viewport.viewPoint(forBoardPoint: CGPoint(x: -40, y: 100))
        drag(session, from: borderPoint, by: CGSize(width: 10, height: 20))
        XCTAssertEqual(session.file.node(withIdentifier: "9000000000000001")?.frame.origin, CGPoint(x: -30, y: -40))
        XCTAssertEqual(session.file.node(withIdentifier: "1000000000000001")?.frame.origin, CGPoint(x: 10, y: 20))
        XCTAssertEqual(session.file.node(withIdentifier: "1000000000000002")?.frame.origin, CGPoint(x: 410, y: 20))
        XCTAssertEqual(session.file.node(withIdentifier: "1000000000000003")?.frame.origin, CGPoint(x: 0, y: 400), "A card outside the group stays.")
        session.undoAvailability.undo()
        XCTAssertEqual(session.file.data, Data(board.utf8), "One step moves the group and its cards back.")
    }

    func testDraggingNextToAnotherCardLinesItUpAndShowsTheGuide() async throws {
        let session = try await openSession()
        session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: -100, y: -100))
        let start = try viewCenter(of: "1000000000000003", in: session)
        session.beginDrag(atViewPoint: start)
        // The file card's left edge (0) to within 5 of the second card's left edge (400).
        session.continueDrag(translation: CGSize(width: 395, height: 0), atViewPoint: CGPoint(x: start.x + 395, y: start.y))
        XCTAssertEqual(session.previewFrames["1000000000000003"]?.minX, 400)
        XCTAssertEqual(session.snapGuides.vertical, 400)
        session.endDrag(isCancelled: true)
        XCTAssertEqual(session.file.data, Data(board.utf8), "A drag the system cancels changes nothing.")
        XCTAssertNil(session.snapGuides.vertical)
    }

    func testResizingByAHandleChangesOnlyTheSize() async throws {
        let session = try await openSession()
        session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: -100, y: -100))
        session.tap(atViewPoint: try viewCenter(of: "1000000000000002", in: session))
        let frame = session.viewport.viewFrame(forBoardFrame: try XCTUnwrap(session.file.node(withIdentifier: "1000000000000002")).frame)
        drag(session, from: CanvasResizeHandle.bottomRight.position(on: frame), by: CGSize(width: 52, height: -38))
        XCTAssertEqual(session.file.node(withIdentifier: "1000000000000002")?.frame, CGRect(x: 400, y: 0, width: 300, height: 160))
        try await session.save()
        XCTAssertEqual(try fileText(), board.replacingOccurrences(of: "\"x\":400,\"y\":0,\"width\":250,\"height\":200,", with: "\"x\":400,\"y\":0,\"width\":300,\"height\":160,"))
        XCTAssertEqual(session.undoAvailability.undoActionName, "Resize Card")
    }

    // MARK: Connecting and selecting

    func testDraggingFromACardsSideToAnotherCardConnectsThem() async throws {
        let session = try await openSession()
        session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: -100, y: -100))
        session.tap(atViewPoint: try viewCenter(of: "1000000000000001", in: session))
        let frame = session.viewport.viewFrame(forBoardFrame: try XCTUnwrap(session.file.node(withIdentifier: "1000000000000001")).frame)
        let dot = session.connectionDotPosition(for: .bottom, ofViewFrame: frame)
        // Down to the top part of the file card below.
        let target = session.viewport.viewPoint(forBoardPoint: CGPoint(x: 150, y: 420))
        drag(session, from: dot, by: CGSize(width: target.x - dot.x, height: target.y - dot.y))
        let newEdge = try XCTUnwrap(session.file.edges.last)
        XCTAssertEqual(session.file.edges.count, 2)
        XCTAssertEqual(newEdge.fromNode, "1000000000000001")
        XCTAssertEqual(newEdge.toNode, "1000000000000003")
        XCTAssertEqual(newEdge.fromSide, .bottom)
        XCTAssertEqual(newEdge.toSide, .top, "It ends at the side nearest where the finger lifted.")
        XCTAssertEqual(newEdge.id.count, 16)
        XCTAssertEqual(session.selectedEdgeIdentifiers, [newEdge.id])
        try await session.save()
        XCTAssertEqual(try fileText(), board.replacingOccurrences(of: "\"toSide\":\"left\"}\n\t]", with: "\"toSide\":\"left\"},\n\t\t{\"id\":\"\(newEdge.id)\",\"fromNode\":\"1000000000000001\",\"fromSide\":\"bottom\",\"toNode\":\"1000000000000003\",\"toSide\":\"top\"}\n\t]"))
        // Dropped on empty board, a connection is not made.
        session.tap(atViewPoint: try viewCenter(of: "1000000000000001", in: session))
        drag(session, from: session.connectionDotPosition(for: .left, ofViewFrame: frame), by: CGSize(width: -300, height: 0))
        XCTAssertEqual(session.file.edges.count, 2)
    }

    func testTapsAndSelectionRectanglesSelectCardsAndConnections() async throws {
        let session = try await openSession()
        session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: -100, y: -100))
        session.tap(atViewPoint: try viewCenter(of: "1000000000000001", in: session))
        XCTAssertEqual(session.selectedNodeIdentifiers, ["1000000000000001"])
        session.tap(atViewPoint: try viewCenter(of: "1000000000000002", in: session), extendsSelection: true)
        XCTAssertEqual(session.selectedNodeIdentifiers, ["1000000000000001", "1000000000000002"], "Shift adds to the selection")
        session.longPress(atViewPoint: try viewCenter(of: "1000000000000001", in: session))
        XCTAssertEqual(session.selectedNodeIdentifiers, ["1000000000000002"], "and a long press takes a card out of it again.")
        let edgeRoute = try XCTUnwrap(session.route(of: session.file.edges[0]))
        session.tap(atViewPoint: session.viewport.viewPoint(forBoardPoint: edgeRoute.midpoint))
        XCTAssertEqual(session.selectedEdgeIdentifiers, ["2000000000000001"])
        XCTAssertTrue(session.selectedNodeIdentifiers.isEmpty)
        session.tap(atViewPoint: session.viewport.viewPoint(forBoardPoint: CGPoint(x: 800, y: 800)))
        XCTAssertFalse(session.hasSelection, "A tap on empty board clears the selection.")
        // A rectangle from empty board, inside the group, over both text cards.
        drag(session, from: session.viewport.viewPoint(forBoardPoint: CGPoint(x: -20, y: -20)), by: CGSize(width: 500, height: 100))
        XCTAssertEqual(session.selectedNodeIdentifiers, ["1000000000000001", "1000000000000002"], "The group around them is not taken whole, so it is not selected.")
        XCTAssertNil(session.selectionRectangle)
        session.selectAll()
        XCTAssertEqual(session.selectedNodeIdentifiers.count, 4)
        XCTAssertEqual(session.selectedEdgeIdentifiers.count, 1)
        XCTAssertEqual(session.file.data, Data(board.utf8), "Selecting changes nothing in the file.")
    }

    // MARK: Adding and editing

    func testDoubleTappingEmptyBoardAddsATextCardToTypeIn() async throws {
        let session = try await openSession()
        session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: -100, y: -100))
        let point = session.viewport.viewPoint(forBoardPoint: CGPoint(x: 900, y: 600))
        // A double tap reaches the board as a tap, a second tap, and the double tap, in any order.
        session.tap(atViewPoint: point)
        session.doubleTap(atViewPoint: point)
        session.tap(atViewPoint: point)
        let edit = try XCTUnwrap(session.textEdit, "The second tap does not end the editing the double tap began.")
        let card = try XCTUnwrap(session.file.node(withIdentifier: edit.nodeIdentifier))
        XCTAssertEqual(card.content, .text(""))
        XCTAssertEqual(card.frame, CGRect(x: 780, y: 580, width: 250, height: 60), "Centered on the tap, on the grid, at Obsidian's size")
        session.updateTextEdit("# Heading\n\nSome **bold** text")
        XCTAssertTrue(session.hasUnsavedChanges)
        session.tap(atViewPoint: session.viewport.viewPoint(forBoardPoint: CGPoint(x: 1500, y: 1500)))
        XCTAssertNil(session.textEdit, "A tap elsewhere ends the editing")
        XCTAssertEqual(session.file.node(withIdentifier: card.id)?.content, .text("# Heading\n\nSome **bold** text"), "and keeps what was typed.")
        try await session.save()
        XCTAssertTrue(try fileText().contains("{\"id\":\"\(card.id)\",\"type\":\"text\",\"text\":\"# Heading\\n\\nSome **bold** text\",\"x\":780,\"y\":580,\"width\":250,\"height\":60}\n\t],"))
        XCTAssertEqual(session.undoAvailability.undoActionName, "Edit Text")
        session.undoAvailability.undo()
        XCTAssertEqual(session.file.node(withIdentifier: card.id)?.content, .text(""))
        session.undoAvailability.undo()
        XCTAssertNil(session.file.node(withIdentifier: card.id))
        XCTAssertEqual(session.file.data, Data(board.utf8))
    }

    func testDoubleTappingATextCardEditsItAndAGroupOrConnectionAsksForItsName() async throws {
        let session = try await openSession()
        session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: -100, y: -100))
        session.doubleTap(atViewPoint: try viewCenter(of: "1000000000000002", in: session))
        XCTAssertEqual(session.textEdit, CanvasTextEdit(nodeIdentifier: "1000000000000002", text: "Second"))
        session.endEditing()
        XCTAssertFalse(session.hasUnsavedChanges, "Editing without typing changes nothing.")
        session.doubleTap(atViewPoint: session.viewport.viewPoint(forBoardPoint: CGPoint(x: -40, y: 100)))
        XCTAssertEqual(session.nameRequest, .groupLabel(nodeIdentifier: "9000000000000001"))
        session.setGroupLabel("  Week 1 ", nodeIdentifier: "9000000000000001")
        XCTAssertEqual(session.file.node(withIdentifier: "9000000000000001")?.content, .group(label: "Week 1", background: nil, backgroundStyle: .cover))
        let edgeRoute = try XCTUnwrap(session.route(of: session.file.edges[0]))
        session.doubleTap(atViewPoint: session.viewport.viewPoint(forBoardPoint: edgeRoute.midpoint))
        XCTAssertEqual(session.nameRequest, .edgeLabel(edgeIdentifier: "2000000000000001"))
        session.setEdgeLabel("leads to", edgeIdentifier: "2000000000000001")
        XCTAssertEqual(session.file.edges[0].label, "leads to")
    }

    func testCommandsOnTheSelectionEachMakeOneStep() async throws {
        let session = try await openSession()
        session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: -100, y: -100))
        session.selectedNodeIdentifiers = ["1000000000000001", "1000000000000002"]
        session.setColorOfSelection(.preset(4))
        XCTAssertEqual(session.file.nodes.filter { node in session.selectedNodeIdentifiers.contains(node.id) }.map(\.color), [.preset(4), .preset(4)])
        session.duplicateSelection()
        XCTAssertEqual(session.file.nodes.count, 6)
        XCTAssertEqual(session.file.edges.count, 2, "The connection between the copied cards is copied too.")
        let copies = session.selectedNodes
        XCTAssertEqual(copies.map(\.frame.origin), [CGPoint(x: 40, y: 40), CGPoint(x: 440, y: 40)])
        XCTAssertEqual(copies.first?.content, .text("First"))
        session.sendSelectionToBack()
        XCTAssertEqual(Array(session.file.nodes.prefix(2)).map(\.id), copies.map(\.id))
        session.bringSelectionToFront()
        XCTAssertEqual(Array(session.file.nodes.suffix(2)).map(\.id), copies.map(\.id))
        session.deleteSelection()
        XCTAssertEqual(session.file.nodes.count, 4)
        XCTAssertEqual(session.file.edges.count, 1)
        session.selectedEdgeIdentifiers = ["2000000000000001"]
        session.selectedNodeIdentifiers = []
        session.setEndsOfSelectedEdges(fromEnd: .arrow, toEnd: .arrow)
        XCTAssertEqual(session.file.edges[0].fromEnd, .arrow)
        for _ in 0..<6 { session.undoAvailability.undo() }
        XCTAssertEqual(session.file.data, Data(board.utf8), "Six steps back is the file as it was.")
        XCTAssertFalse(session.undoAvailability.canUndo)
    }

    func testAddingCardsGroupsAndLinks() async throws {
        let session = try await openSession()
        session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: 2000, y: 2000))
        let noteIdentifier = try XCTUnwrap(session.addFileCard(try VaultPath("Notes/Other note.md"), size: CGSize(width: 400, height: 400)))
        XCTAssertEqual(session.file.node(withIdentifier: noteIdentifier)?.content, .file(path: "Notes/Other note.md", subpath: nil))
        XCTAssertEqual(session.file.node(withIdentifier: noteIdentifier)?.frame, CGRect(x: 2300, y: 2200, width: 400, height: 400), "In the middle of the view")
        let secondIdentifier = try XCTUnwrap(session.addFileCard(try VaultPath("Notes/Other note.md"), size: CGSize(width: 400, height: 400)))
        XCTAssertEqual(session.file.node(withIdentifier: secondIdentifier)?.frame.origin, CGPoint(x: 2320, y: 2220), "Never exactly on top of another card")
        XCTAssertNil(session.addLinkCard(address: "javascript:alert(1)"))
        XCTAssertNotNil(session.errorMessage)
        let linkIdentifier = try XCTUnwrap(session.addLinkCard(address: " obsidian.md/help "))
        XCTAssertEqual(session.file.node(withIdentifier: linkIdentifier)?.content, .link(address: "https://obsidian.md/help"))
        session.selectedNodeIdentifiers = [noteIdentifier, secondIdentifier]
        let groupIdentifier = try XCTUnwrap(session.addGroup())
        XCTAssertEqual(session.file.node(withIdentifier: groupIdentifier)?.frame, CGRect(x: 2280, y: 2180, width: 460, height: 460), "Around the selected cards, with room")
        XCTAssertEqual(session.nameRequest, .groupLabel(nodeIdentifier: groupIdentifier), "A new group is named at once.")
        session.isWriting = false
        XCTAssertNil(session.addTextCard(), "Nothing is added in Read.")
    }

    func testWebAddressesAreCheckedBeforeTheyAreKeptOrOpened() {
        XCTAssertEqual(CanvasSession.webAddress(from: "example.com/page?q=1"), "https://example.com/page?q=1")
        XCTAssertEqual(CanvasSession.webAddress(from: "http://example.com"), "http://example.com")
        for refused in ["", "   ", "javascript:alert(1)", "file:///etc/hosts", "obsidian://open?vault=x", "https://", "two words.com"] {
            XCTAssertNil(CanvasSession.webAddress(from: refused), refused)
        }
        XCTAssertNotNil(CanvasSession.browsableLocation(of: "https://en.wikipedia.org/wiki/Fourier_series"))
        XCTAssertNil(CanvasSession.browsableLocation(of: "file:///etc/hosts"), "A link card never opens a file")
        XCTAssertNil(CanvasSession.browsableLocation(of: "shortcuts://run-shortcut?name=x"), "or another app.")
    }

    // MARK: Saving safely

    func testAnEditOverAnotherAppsChangeIsKeptAsAConflictNotWrittenOverIt() async throws {
        let session = try await openSession()
        session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: -100, y: -100))
        session.selectedNodeIdentifiers = ["1000000000000003"]
        session.deleteSelection()
        let external = board.replacingOccurrences(of: "\"label\":\"Topic\"", with: "\"label\":\"Changed in Obsidian\"")
        try Data(external.utf8).write(to: vault.appendingPathComponent(canvasPath.rawValue))
        await session.checkExternalChange()
        XCTAssertTrue(session.hasExternalConflict)
        do {
            try await session.save()
            XCTFail("A save over another app's change must fail")
        } catch {
            XCTAssertEqual(error as? GraphiteError, .conflict)
        }
        XCTAssertEqual(try fileText(), external, "The other app's version is kept.")
        let copyPath = try await session.saveSeparateCopy()
        XCTAssertEqual(copyPath.rawValue, "Boards/Board Graphite edits.canvas")
        let copy = try CanvasFile(data: Data(contentsOf: vault.appendingPathComponent(copyPath.rawValue)))
        XCTAssertNil(copy.node(withIdentifier: "1000000000000003"), "The copy has the edits")
        XCTAssertFalse(session.hasExternalConflict)
        XCTAssertEqual(session.file.data, Data(external.utf8), "and the canvas shows the other app's version.")
        XCTAssertFalse(session.undoAvailability.canUndo, "Steps made for the replaced version are gone.")
    }

    func testAnotherAppsChangeIsShownWhenNothingIsUnsaved() async throws {
        let session = try await openSession(isWriting: false)
        let external = board.replacingOccurrences(of: "\"text\":\"First\"", with: "\"text\":\"Rewritten\"")
        try Data(external.utf8).write(to: vault.appendingPathComponent(canvasPath.rawValue))
        await session.checkExternalChange()
        XCTAssertFalse(session.hasExternalConflict)
        XCTAssertEqual(session.file.node(withIdentifier: "1000000000000001")?.content, .text("Rewritten"))
    }

    func testADamagedCanvasDoesNotOpenAndStaysAsItWas() async throws {
        let damaged = "{\"nodes\":[{\"id\":\"1\",\"type\":\"text\""
        try Data(damaged.utf8).write(to: vault.appendingPathComponent(canvasPath.rawValue))
        let snapshot = try await store.read(canvasPath)
        XCTAssertThrowsError(try CanvasSession(path: canvasPath, snapshot: snapshot, store: store) { _ in }) { error in
            XCTAssertTrue(error.localizedDescription.contains("damaged"), error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("left the file as it is"), error.localizedDescription)
        }
        XCTAssertEqual(try fileText(), damaged)
    }

    func testCardsAreDescribedForAssistiveTechnologiesInReadingOrder() async throws {
        let session = try await openSession(isWriting: false)
        let positions = session.readingPositions
        let ordered = positions.sorted { firstEntry, secondEntry in firstEntry.value < secondEntry.value }.map(\.key)
        XCTAssertEqual(ordered, ["9000000000000001", "1000000000000001", "1000000000000002", "1000000000000003"])
        let second = try XCTUnwrap(session.file.node(withIdentifier: "1000000000000002"))
        let description = CanvasCardDescription(node: second, file: session.file)
        XCTAssertEqual(description.label, "Orange Text card", "The color is named, not only shown.")
        XCTAssertEqual(description.content, "Second")
        XCTAssertEqual(description.connections, "Connected to First")
        let fileCard = try XCTUnwrap(session.file.node(withIdentifier: "1000000000000003"))
        XCTAssertEqual(CanvasCardDescription(node: fileCard, file: session.file).label, "Note card")
        XCTAssertEqual(CanvasCardDescription(node: fileCard, file: session.file).content, "Note")
    }
}

private extension CanvasSession {
    func drag(from start: CGPoint, by translation: CGSize) {
        beginDrag(atViewPoint: start)
        continueDrag(translation: translation, atViewPoint: CGPoint(x: start.x + translation.width, y: start.y + translation.height))
        endDrag()
    }
}
