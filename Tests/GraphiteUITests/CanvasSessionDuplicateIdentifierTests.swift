import XCTest
import CoreGraphics
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// A canvas file can hold several cards with one `id`. All are shown; a connection names
/// the first card with that `id`; the later cards with the same `id` can neither start a
/// connection nor be the end of one.
@MainActor
final class CanvasSessionDuplicateIdentifierTests: XCTestCase {
    private var vault: URL!
    private var store: VaultStore!
    private var canvasPath: VaultPath!
    private var deviceDefaults: UserDefaults!

    /// Two text cards both with the `id` "dup" (the first at the top left, the second to its right),
    /// a card "solo" below them, and one connection from "dup" to "solo".
    private let board = "{\n\t\"nodes\":[\n"
        + "\t\t{\"id\":\"dup\",\"type\":\"text\",\"text\":\"First\",\"x\":0,\"y\":0,\"width\":250,\"height\":200},\n"
        + "\t\t{\"id\":\"dup\",\"type\":\"text\",\"text\":\"Second\",\"x\":400,\"y\":0,\"width\":250,\"height\":200},\n"
        + "\t\t{\"id\":\"solo\",\"type\":\"text\",\"text\":\"Solo\",\"x\":0,\"y\":400,\"width\":250,\"height\":200}\n"
        + "\t],\n\t\"edges\":[\n"
        + "\t\t{\"id\":\"edge1\",\"fromNode\":\"dup\",\"fromSide\":\"bottom\",\"toNode\":\"solo\",\"toSide\":\"top\"}\n"
        + "\t]\n}"

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "CanvasSessionDuplicate", for: self).root
        canvasPath = try VaultPath("Board.canvas")
        try Data(board.utf8).write(to: vault.appendingPathComponent(canvasPath.rawValue))
        store = VaultStore(root: vault)
        deviceDefaults = try IsolatedDeviceState.make(prefix: "CanvasSessionDuplicateIdentifierTests", for: self).preferences
    }

    private func openSession() async throws -> CanvasSession {
        let session = try CanvasSession(path: canvasPath, snapshot: try await store.read(canvasPath), store: store, clock: ManualClock(),
                                        deviceDefaults: deviceDefaults) { _ in }
        session.viewSize = CGSize(width: 1000, height: 800)
        session.isWriting = true
        session.snapsToGrid = false
        session.snapsToObjects = false
        session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: -100, y: -100))
        return session
    }

    private func viewFrame(of node: CanvasNode, in session: CanvasSession) -> CGRect {
        session.viewport.viewFrame(forBoardFrame: node.frame)
    }

    private func drag(_ session: CanvasSession, from start: CGPoint, to end: CGPoint) {
        session.beginDrag(atViewPoint: start)
        for step in 1...4 {
            let fraction = CGFloat(step) / 4
            session.continueDrag(translation: CGSize(width: (end.x - start.x) * fraction, height: (end.y - start.y) * fraction),
                                 atViewPoint: CGPoint(x: start.x + (end.x - start.x) * fraction, y: start.y + (end.y - start.y) * fraction))
        }
        session.endDrag()
    }

    // MARK: Showing and naming

    func testEveryCardWithASharedIdentifierIsShownAndConnectionsNameTheFirst() async throws {
        let session = try await openSession()
        XCTAssertEqual(session.file.nodes.count, 3)
        let first = session.file.nodes[0], second = session.file.nodes[1]
        XCTAssertEqual(first.identifierInFile, "dup")
        XCTAssertEqual(second.identifierInFile, "dup")
        XCTAssertEqual(first.id, "dup")
        XCTAssertNotEqual(second.id, "dup", "The later card gets an identifier of its own inside Graphite.")
        XCTAssertEqual(first.content, .text("First"))
        XCTAssertEqual(second.content, .text("Second"))
        XCTAssertEqual(session.file.node(named: "dup")?.content, .text("First"), "A connection naming `dup` means the first card.")
        XCTAssertEqual(session.file.edges.first?.fromNode, "dup")
        XCTAssertEqual(session.shownNodes.count, 3)
    }

    // MARK: Starting a connection

    func testTheFirstCardOfASharedIdentifierCanStartAConnectionAndItIsWrittenWithTheSharedIdentifier() async throws {
        let session = try await openSession()
        let first = session.file.nodes[0], solo = session.file.nodes[2]
        session.tap(atViewPoint: CGPoint(x: viewFrame(of: first, in: session).midX, y: viewFrame(of: first, in: session).midY))
        let startDot = session.connectionDotPosition(for: .bottom, ofViewFrame: viewFrame(of: first, in: session))
        let soloFrame = viewFrame(of: solo, in: session)

        drag(session, from: startDot, to: CGPoint(x: soloFrame.midX + 20, y: soloFrame.minY + 30))

        XCTAssertEqual(session.file.edges.count, 2)
        let newEdge = try XCTUnwrap(session.file.edges.last)
        XCTAssertEqual(newEdge.fromNode, "dup")
        XCTAssertEqual(newEdge.toNode, "solo")
    }

    func testALaterCardOfASharedIdentifierCannotStartAConnection() async throws {
        let session = try await openSession()
        let second = session.file.nodes[1]
        let secondFrame = viewFrame(of: second, in: session)
        session.tap(atViewPoint: CGPoint(x: secondFrame.midX, y: secondFrame.midY))
        XCTAssertEqual(session.selectedNodeIdentifiers, [second.id])
        let soloFrame = viewFrame(of: session.file.nodes[2], in: session)

        for side in CanvasSide.allCases {
            session.beginDrag(atViewPoint: session.connectionDotPosition(for: side, ofViewFrame: secondFrame))
            XCTAssertNil(session.pendingConnection, "No connection starts at the \(side) dot of a card whose id is shared.")
            session.continueDrag(translation: CGSize(width: -300, height: 300), atViewPoint: CGPoint(x: soloFrame.midX, y: soloFrame.midY))
            session.endDrag()
        }
        XCTAssertEqual(session.file.edges.count, 1)
        XCTAssertEqual(session.file.data, Data(board.utf8))
    }

    // MARK: Ending a connection

    func testALaterCardOfASharedIdentifierCannotBeTheEndOfAConnectionButTheFirstCan() async throws {
        let session = try await openSession()
        let first = session.file.nodes[0], second = session.file.nodes[1], solo = session.file.nodes[2]
        session.tap(atViewPoint: CGPoint(x: viewFrame(of: solo, in: session).midX, y: viewFrame(of: solo, in: session).midY))
        let startDot = session.connectionDotPosition(for: .right, ofViewFrame: viewFrame(of: solo, in: session))
        let secondFrame = viewFrame(of: second, in: session)

        drag(session, from: startDot, to: CGPoint(x: secondFrame.midX, y: secondFrame.midY))
        XCTAssertEqual(session.file.edges.count, 1, "Dropped on the later card, no connection is made.")

        session.tap(atViewPoint: CGPoint(x: viewFrame(of: solo, in: session).midX, y: viewFrame(of: solo, in: session).midY))
        let firstFrame = viewFrame(of: first, in: session)
        drag(session, from: startDot, to: CGPoint(x: firstFrame.midX, y: firstFrame.midY))
        XCTAssertEqual(session.file.edges.count, 2, "Dropped on the first card, a connection is made.")
        XCTAssertEqual(session.file.edges.last?.toNode, "dup")
        XCTAssertEqual(session.file.edges.last?.fromNode, "solo")
    }
}
