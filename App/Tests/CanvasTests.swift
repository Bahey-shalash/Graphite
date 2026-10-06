#if os(iOS)
import XCTest
import SwiftUI
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI

/// Canvases in the hosted workspace: a `.canvas` file opens in a tab with its cards drawn
/// where the file puts them, an edit is saved and undone, text is edited in place, a
/// rename reaches an open canvas, and a large board is measured.
@MainActor
final class CanvasTests: XCTestCase {
    private var window: UIWindow?
    private var vaultDirectory: URL?

    /// A group, a green card with no text, a red card with Markdown, a note card, a
    /// picture card, a link card, and a labeled connection, in Obsidian's layout.
    private let boardText = "{\n\t\"nodes\":[\n"
        + "\t\t{\"id\":\"9000000000000001\",\"type\":\"group\",\"x\":-40,\"y\":-80,\"width\":1100,\"height\":600,\"color\":\"5\",\"label\":\"Week 1\"},\n"
        + "\t\t{\"id\":\"1000000000000001\",\"type\":\"text\",\"text\":\"\",\"x\":0,\"y\":0,\"width\":300,\"height\":200,\"color\":\"#00c000\"},\n"
        + "\t\t{\"id\":\"1000000000000002\",\"type\":\"text\",\"text\":\"# Title\\n\\nSome **bold** text and a [[Note]] link.\",\"x\":400,\"y\":0,\"width\":300,\"height\":200,\"color\":\"1\"},\n"
        + "\t\t{\"id\":\"1000000000000003\",\"type\":\"file\",\"file\":\"Note.md\",\"x\":0,\"y\":260,\"width\":300,\"height\":200},\n"
        + "\t\t{\"id\":\"1000000000000004\",\"type\":\"file\",\"file\":\"Picture.png\",\"x\":400,\"y\":260,\"width\":300,\"height\":200},\n"
        + "\t\t{\"id\":\"1000000000000005\",\"type\":\"link\",\"url\":\"https://obsidian.md/canvas\",\"x\":760,\"y\":0,\"width\":260,\"height\":200}\n"
        + "\t],\n\t\"edges\":[\n"
        + "\t\t{\"id\":\"2000000000000001\",\"fromNode\":\"1000000000000002\",\"fromSide\":\"bottom\",\"toNode\":\"1000000000000004\",\"toSide\":\"top\",\"label\":\"see\"}\n"
        + "\t]\n}"

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        if let vaultDirectory { try? FileManager.default.removeItem(at: vaultDirectory) }
        vaultDirectory = nil
    }

    // MARK: Viewing

    func testACanvasOpensInATabWithItsCardsWhereTheFileSaysInLightAndDark() async throws {
        try skipWhereTheBoardIsFittedToAPhone()
        let workspace = try await makeWorkspace()
        let tabID = try await open("Board.canvas", in: workspace)
        let session = try XCTUnwrap(workspace.document(for: tabID).canvasSession)
        session.isWriting = false
        let controller = try host(workspace)
        let board = try await boardView(in: controller)
        try await waitUntil { session.viewSize.width > 0 && !session.detailedNodes.isEmpty }
        try await Task.sleep(for: .milliseconds(600))

        // Opened showing the whole board.
        for node in session.file.nodes {
            XCTAssertTrue(CGRect(origin: .zero, size: session.viewSize).contains(session.viewport.viewFrame(forBoardFrame: node.frame)), "\(node.id) is in view")
        }
        attachScreenshot(named: "Canvas in light appearance")
        let fittedViewport = session.viewport
        session.setViewport(CanvasViewport(scale: 2, origin: CGPoint(x: 380, y: -20)), animated: false)
        try await Task.sleep(for: .milliseconds(600))
        attachScreenshot(named: "Canvas magnified twice")
        session.setViewport(fittedViewport, animated: false)
        try await Task.sleep(for: .milliseconds(400))
        let green = try XCTUnwrap(session.file.node(withIdentifier: "1000000000000001"))
        let greenCenter = board.convert(center(of: green, in: session), to: nil)
        let outsideCards = board.convert(session.viewport.viewPoint(forBoardPoint: CGPoint(x: 350, y: 230)), to: nil)
        let snapshot = try windowSnapshot()
        let cardPixel = try pixel(at: greenCenter, in: snapshot)
        let boardPixel = try pixel(at: outsideCards, in: snapshot)
        XCTAssertGreaterThan(cardPixel.green - cardPixel.red, 0.05, "The green card is drawn where the file puts it: \(cardPixel)")
        XCTAssertLessThan(abs(boardPixel.green - boardPixel.red) + abs(boardPixel.green - boardPixel.blue), 0.12,
                          "Between the cards is the board, inside the cyan group's light tint: \(boardPixel)")

        window?.overrideUserInterfaceStyle = .dark
        try await Task.sleep(for: .milliseconds(600))
        attachScreenshot(named: "Canvas in dark appearance")
        let darkPixel = try pixel(at: outsideCards, in: try windowSnapshot())
        XCTAssertLessThan(darkPixel.red + darkPixel.green + darkPixel.blue, 0.9, "The board follows dark appearance: \(darkPixel)")
        XCTAssertEqual(try String(contentsOf: try XCTUnwrap(vaultDirectory).appendingPathComponent("Board.canvas"), encoding: .utf8), boardText,
                       "Looking at a canvas does not write it.")
    }

    func testZoomToFitBringsTheWholeBoardBackIntoView() async throws {
        try skipWhereTheBoardIsFittedToAPhone()
        let workspace = try await makeWorkspace()
        let tabID = try await open("Board.canvas", in: workspace)
        let session = try XCTUnwrap(workspace.document(for: tabID).canvasSession)
        let controller = try host(workspace)
        _ = try await boardView(in: controller)
        try await waitUntil { session.viewSize.width > 0 }
        session.setViewport(CanvasViewport(scale: 3, origin: CGPoint(x: 50_000, y: 50_000)), animated: false)
        try await waitUntil { session.detailedNodes.isEmpty }
        session.zoomToFit()
        try await waitUntil {
            session.file.nodes.allSatisfy { node in CGRect(origin: .zero, size: session.viewSize).contains(session.viewport.viewFrame(forBoardFrame: node.frame)) }
        }
        XCTAssertLessThanOrEqual(session.viewport.scale, 1)
        XCTAssertEqual(Set(session.detailedNodes.map(\.id)), ["1000000000000001", "1000000000000002", "1000000000000003", "1000000000000004", "1000000000000005"])
    }

    func testTheBoardTakesTwoFingerPansTrackpadScrollingPinchesTapsAndDrags() async throws {
        let workspace = try await makeWorkspace()
        _ = try await open("Board.canvas", in: workspace)
        let controller = try host(workspace)
        let board = try await boardView(in: controller)
        let recognizers = board.gestureRecognizers ?? []
        let pans = recognizers.compactMap { recognizer in recognizer as? UIPanGestureRecognizer }
        let twoFingerPan = try XCTUnwrap(pans.first { pan in pan.minimumNumberOfTouches == 2 })
        XCTAssertEqual(twoFingerPan.allowedScrollTypesMask, .all, "Trackpad and mouse scrolling move the board.")
        let drag = try XCTUnwrap(pans.first { pan in pan.maximumNumberOfTouches == 1 }, "One finger, a Pencil or a pointer drags.")
        for touchType in [UITouch.TouchType.direct, .pencil, .indirectPointer] {
            XCTAssertTrue(drag.allowedTouchTypes.contains(NSNumber(value: touchType.rawValue)), "The drag takes touches of type \(touchType.rawValue).")
        }
        XCTAssertTrue(recognizers.contains { recognizer in recognizer is UIPinchGestureRecognizer })
        XCTAssertTrue(recognizers.contains { recognizer in (recognizer as? UITapGestureRecognizer)?.numberOfTapsRequired == 2 })
        XCTAssertTrue(recognizers.contains { recognizer in recognizer is UILongPressGestureRecognizer })
        XCTAssertTrue(recognizers.allSatisfy { recognizer in !recognizer.cancelsTouchesInView }, "Links and buttons inside cards keep their touches.")
    }

    // MARK: Editing

    func testAMovedCardIsSavedOnItsOwnAndUndoingSavesTheFileBack() async throws {
        let workspace = try await makeWorkspace()
        let tabID = try await open("Board.canvas", in: workspace)
        let session = try XCTUnwrap(workspace.document(for: tabID).canvasSession)
        session.isWriting = true
        session.snapsToGrid = true
        session.snapsToObjects = false
        let controller = try host(workspace)
        _ = try await boardView(in: controller)
        try await waitUntil { session.viewSize.width > 0 }
        let link = try XCTUnwrap(session.file.node(withIdentifier: "1000000000000005"))
        let start = center(of: link, in: session)
        let translation = CGSize(width: 45 * session.viewport.scale, height: 118 * session.viewport.scale)
        session.beginDrag(atViewPoint: start)
        session.continueDrag(translation: translation, atViewPoint: CGPoint(x: start.x + translation.width, y: start.y + translation.height))
        try await Task.sleep(for: .milliseconds(100))
        attachScreenshot(named: "Canvas card being moved, with its snapped position")
        session.endDrag()
        let movedFrame = try XCTUnwrap(session.file.node(withIdentifier: "1000000000000005")?.frame)
        XCTAssertEqual(movedFrame.origin, CGPoint(x: 800, y: 120), "Moved by the drag and snapped to the grid")
        let fileLocation = try XCTUnwrap(vaultDirectory).appendingPathComponent("Board.canvas")
        let expected = boardText.replacingOccurrences(of: "\"url\":\"https://obsidian.md/canvas\",\"x\":760,\"y\":0,", with: "\"url\":\"https://obsidian.md/canvas\",\"x\":800,\"y\":120,")
        try await waitUntil(seconds: 5) { (try? String(contentsOf: fileLocation, encoding: .utf8)) == expected }
        XCTAssertEqual(try String(contentsOf: fileLocation, encoding: .utf8), expected, "Saved on its own, and only the card's position changed.")
        attachScreenshot(named: "Canvas card selected with its handles after a move")

        session.undoAvailability.undo()
        try await waitUntil(seconds: 5) { (try? String(contentsOf: fileLocation, encoding: .utf8)) == self.boardText }
        XCTAssertEqual(try String(contentsOf: fileLocation, encoding: .utf8), boardText, "Undo saves the file back byte for byte.")
    }

    func testATextCardIsEditedInPlaceAndSaved() async throws {
        try skipWhereTheBoardIsFittedToAPhone()
        let workspace = try await makeWorkspace()
        let tabID = try await open("Board.canvas", in: workspace)
        let session = try XCTUnwrap(workspace.document(for: tabID).canvasSession)
        session.isWriting = true
        let controller = try host(workspace)
        _ = try await boardView(in: controller)
        try await waitUntil { session.viewSize.width > 0 }
        let greenCard = try XCTUnwrap(session.file.node(withIdentifier: "1000000000000001"))
        session.doubleTap(atViewPoint: center(of: greenCard, in: session))
        XCTAssertEqual(session.textEdit?.nodeIdentifier, greenCard.id)
        try await waitUntil { self.textViews(in: controller).contains { textView in textView.window != nil } }
        let editor = try XCTUnwrap(textViews(in: controller).first { textView in textView.window != nil })
        try await waitUntil { editor.isFirstResponder }
        editor.insertText("Hello **canvas**")
        try await waitUntil { session.textEdit?.text == "Hello **canvas**" }
        attachScreenshot(named: "Canvas text card edited in place")
        session.endEditing()
        XCTAssertEqual(session.file.node(withIdentifier: greenCard.id)?.content, .text("Hello **canvas**"))
        let fileLocation = try XCTUnwrap(vaultDirectory).appendingPathComponent("Board.canvas")
        let expected = boardText.replacingOccurrences(of: "\"type\":\"text\",\"text\":\"\",\"x\":0", with: "\"type\":\"text\",\"text\":\"Hello **canvas**\",\"x\":0")
        try await waitUntil(seconds: 5) { (try? String(contentsOf: fileLocation, encoding: .utf8)) == expected }
        try await waitUntil { !self.textViews(in: controller).contains { textView in textView.window != nil } }
        try await Task.sleep(for: .milliseconds(400))
        attachScreenshot(named: "Canvas text card rendered after editing")
    }

    // MARK: The workspace

    func testRenamingANoteUpdatesItsCardInAnOpenCanvas() async throws {
        let workspace = try await makeWorkspace()
        let tabID = try await open("Board.canvas", in: workspace)
        let session = try XCTUnwrap(workspace.document(for: tabID).canvasSession)
        let backlinks = try await workspace.index?.backlinks(to: VaultPath("Note.md")) ?? []
        XCTAssertTrue(backlinks.contains(try VaultPath("Board.canvas")), "The note lists the canvas among its backlinks.")
        await workspace.rename(try VaultPath("Note.md"), to: "Lecture notes")
        // Obsidian's default asks before links are updated; the answer here is to update them.
        let pendingMove = try XCTUnwrap(workspace.pendingMove)
        XCTAssertEqual(pendingMove.plan.changedLinkCount, 2)
        await workspace.resolve(pendingMove, updatesLinks: true)
        XCTAssertNil(workspace.errorMessage)
        let fileLocation = try XCTUnwrap(vaultDirectory).appendingPathComponent("Board.canvas")
        let expected = boardText.replacingOccurrences(of: "\"file\":\"Note.md\"", with: "\"file\":\"Lecture notes.md\"")
            .replacingOccurrences(of: "a [[Note]] link", with: "a [[Lecture notes]] link")
        XCTAssertEqual(try String(contentsOf: fileLocation, encoding: .utf8), expected, "The file card and the text card's link follow the note, and nothing else changes.")
        try await waitUntil { workspace.document(for: tabID).canvasSession?.file.node(withIdentifier: "1000000000000003")?.content == .file(path: "Lecture notes.md", subpath: nil) }
        XCTAssertTrue(workspace.document(for: tabID).canvasSession === session, "The open canvas takes in the change without reopening.")
    }

    func testALinkToACanvasOpensIt() async throws {
        let workspace = try await makeWorkspace()
        _ = try await open("Note.md", in: workspace)
        await workspace.follow("Board.canvas", from: try VaultPath("Note.md"))
        let tabID = try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath("Board.canvas")))
        XCTAssertNotNil(workspace.document(for: tabID).canvasSession)
    }

    func testCreatingACanvasWritesWhatObsidianWritesAndOpensItForWriting() async throws {
        let workspace = try await makeWorkspace()
        await workspace.createCanvas(named: "Plan")
        let tabID = try XCTUnwrap(workspace.layout.tabID(showing: try VaultPath("Plan.canvas")))
        let session = try XCTUnwrap(workspace.document(for: tabID).canvasSession)
        XCTAssertTrue(session.isWriting)
        XCTAssertEqual(try String(contentsOf: try XCTUnwrap(vaultDirectory).appendingPathComponent("Plan.canvas"), encoding: .utf8), "{}")
        session.viewSize = CGSize(width: 800, height: 600)
        session.addTextCard()
        session.updateTextEdit("First idea")
        try await session.save()
        let saved = try String(contentsOf: try XCTUnwrap(vaultDirectory).appendingPathComponent("Plan.canvas"), encoding: .utf8)
        XCTAssertTrue(saved.hasPrefix("{\n\t\"nodes\":[\n\t\t{\"id\":\""), saved)
        XCTAssertTrue(saved.hasSuffix("\"type\":\"text\",\"text\":\"First idea\",\"x\":-120,\"y\":-40,\"width\":250,\"height\":60}\n\t]\n}"), saved)
    }

    func testTurningCanvasOffShowsTheFileAsBefore() async throws {
        let workspace = try await makeWorkspace()
        workspace.preferences.setEnabled(.canvas, false)
        defer { workspace.preferences.setEnabled(.canvas, true) }
        let tabID = try await open("Board.canvas", in: workspace)
        XCTAssertNil(workspace.document(for: tabID).canvasSession)
        XCTAssertEqual(workspace.document(for: tabID).loadedPath, try VaultPath("Board.canvas"))
    }

    // MARK: Large boards

    func testALargeBoardOpensAndDrawsQuickly() async throws {
        let cardCount = 5_000
        var lines: [String] = []
        for cardIndex in 0..<cardCount {
            lines.append("\t\t{\"id\":\"\(String(format: "%016x", cardIndex))\",\"type\":\"text\",\"text\":\"Card \(cardIndex) with **bold** text and a [[Link \(cardIndex)]]\",\"x\":\(cardIndex % 100 * 320),\"y\":\(cardIndex / 100 * 220),\"width\":280,\"height\":180,\"color\":\"\(cardIndex % 7 == 0 ? "" : String(cardIndex % 6 + 1))\"}")
        }
        var edgeLines: [String] = []
        for cardIndex in 0..<cardCount - 1 where cardIndex % 100 != 99 {
            edgeLines.append("\t\t{\"id\":\"e\(String(format: "%015x", cardIndex))\",\"fromNode\":\"\(String(format: "%016x", cardIndex))\",\"fromSide\":\"right\",\"toNode\":\"\(String(format: "%016x", cardIndex + 1))\",\"toSide\":\"left\"}")
        }
        let largeBoard = "{\n\t\"nodes\":[\n" + lines.joined(separator: ",\n") + "\n\t],\n\t\"edges\":[\n" + edgeLines.joined(separator: ",\n") + "\n\t]\n}"
        let workspace = try await makeWorkspace(extraFiles: ["Large.canvas": largeBoard, "Empty.canvas": "{}"])
        let openStart = ContinuousClock.now
        let tabID = try await open("Large.canvas", in: workspace)
        let openDuration = ContinuousClock.now - openStart
        let session = try XCTUnwrap(workspace.document(for: tabID).canvasSession)
        session.isWriting = false
        let controller = try host(workspace)
        _ = try await boardView(in: controller)
        try await waitUntil { session.viewSize.width > 0 }
        XCTAssertTrue(session.detailedNodes.isEmpty, "Zoomed out to show all 5,000 cards, they are drawn as shapes.")
        attachScreenshot(named: "5,000 cards zoomed out")

        func averageFrameMilliseconds(frameCount: Int, move: (Int) -> Void) throws -> Double {
            let snapshotWindow = try XCTUnwrap(window)
            let start = ContinuousClock.now
            for frameIndex in 0..<frameCount {
                move(frameIndex)
                // Drawing the window's hierarchy lays it out and renders it, as a frame would.
                _ = UIGraphicsImageRenderer(bounds: snapshotWindow.bounds).image { _ in snapshotWindow.drawHierarchy(in: snapshotWindow.bounds, afterScreenUpdates: true) }
            }
            let elapsed = ContinuousClock.now - start
            return (Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18) * 1000 / Double(frameCount)
        }
        // What drawing the window costs without a board, to tell the board's own cost.
        let emptyTabID = try await open("Empty.canvas", in: workspace, placement: .newTab)
        let emptySession = try XCTUnwrap(workspace.document(for: emptyTabID).canvasSession)
        try await waitUntil { emptySession.viewSize.width > 0 }
        let emptyViewport = emptySession.viewport
        let baseline = try averageFrameMilliseconds(frameCount: 20) { frameIndex in
            var viewport = emptyViewport
            viewport.pan(byViewTranslation: CGSize(width: CGFloat(frameIndex), height: 0))
            emptySession.viewport = viewport
        }
        workspace.activateTab(tabID)
        try await waitUntil { session.viewSize.width > 0 && workspace.layout.activeTab.id == tabID }
        try await Task.sleep(for: .milliseconds(300))
        let fittedViewport = session.viewport
        let zoomedOut = try averageFrameMilliseconds(frameCount: 20) { frameIndex in
            var viewport = fittedViewport
            viewport.pan(byViewTranslation: CGSize(width: CGFloat(frameIndex), height: 0))
            session.viewport = viewport
        }
        session.setViewport(CanvasViewport(scale: 1, origin: CGPoint(x: 9_000, y: 5_000)), animated: false)
        try await Task.sleep(for: .milliseconds(1_500))
        XCTAssertFalse(session.detailedNodes.isEmpty)
        XCTAssertLessThanOrEqual(session.detailedNodes.count, CanvasSession.maximumDetailedCardCount)
        attachScreenshot(named: "5,000 cards at full size")
        let zoomedIn = try averageFrameMilliseconds(frameCount: 20) { frameIndex in
            session.viewport = CanvasViewport(scale: 1, origin: CGPoint(x: 9_000 + CGFloat(frameIndex) * 3, y: 5_000))
        }
        let summary = "Opened \(cardCount) cards in \(openDuration). A window snapshot with an empty canvas takes \(String(format: "%.1f", baseline)) ms; "
            + "with all \(cardCount) cards and \(cardCount - 50) connections in view \(String(format: "%.1f", zoomedOut)) ms; at full size \(String(format: "%.1f", zoomedIn)) ms."
        print("Canvas measurement (simulator): " + summary)
        let measurement = XCTAttachment(string: summary)
        measurement.lifetime = .keepAlways
        add(measurement)
    }

    // MARK: Helpers

    private func makeWorkspace(extraFiles: [String: String] = [:]) async throws -> WorkspaceModel {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Canvas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        vaultDirectory = directory
        var files = ["Board.canvas": boardText, "Note.md": "# Note\n\nSome text of the note.\n"]
        files.merge(extraFiles) { _, extra in extra }
        for (name, text) in files { try Data(text.utf8).write(to: directory.appendingPathComponent(name)) }
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 40)).pngData { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 40))
        }
        try picture.write(to: directory.appendingPathComponent("Picture.png"))
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: directory)
        workspace.store = VaultStore(root: directory)
        let index = try VaultIndex(databaseURL: directory.appendingPathExtension("index").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: directory)
        workspace.index = index
        workspace.hasCompletedIndexScan = true
        return workspace
    }

    private func open(_ name: String, in workspace: WorkspaceModel, placement: GraphiteUI.TabPlacement = .currentTab) async throws -> UUID {
        let path = try VaultPath(name)
        await workspace.open(path, placement: placement)
        return try XCTUnwrap(workspace.layout.tabID(showing: path), workspace.errorMessage ?? "")
    }

    /// These tests show the whole 1,100-point board with its cards in detail. Fitted to a
    /// phone it is drawn at about a third of its size, where cards are drawn without their
    /// contents, as intended; what the tests check needs an iPad's width.
    private func skipWhereTheBoardIsFittedToAPhone() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        if scene.coordinateSpace.bounds.width < 700 {
            throw XCTSkip("The board fitted to a phone's width draws its cards without detail.")
        }
    }

    private func host(_ workspace: WorkspaceModel) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
        return controller
    }

    /// The view the board's gestures are attached to.
    private func boardView(in controller: UIViewController) async throws -> UIView {
        try await waitUntil { self.boardController(in: controller) != nil }
        return try XCTUnwrap(boardController(in: controller)?.view)
    }

    private func boardController(in controller: UIViewController) -> CanvasBoardViewController? {
        if let boardController = controller as? CanvasBoardViewController { return boardController }
        for child in controller.children { if let found = boardController(in: child) { return found } }
        return nil
    }

    private func center(of node: CanvasNode, in session: CanvasSession) -> CGPoint {
        let frame = session.viewport.viewFrame(forBoardFrame: node.frame)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private func textViews(in controller: UIViewController) -> [UITextView] {
        descendants(of: controller.view, matching: UITextView.self)
    }

    private func windowSnapshot() throws -> CGImage {
        let snapshotWindow = try XCTUnwrap(window)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: snapshotWindow.bounds, format: format).image { _ in
            snapshotWindow.drawHierarchy(in: snapshotWindow.bounds, afterScreenUpdates: true)
        }
        return try XCTUnwrap(image.cgImage)
    }

    /// The color at a point of the window, from 0 to 1 per channel.
    private func pixel(at point: CGPoint, in image: CGImage) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: -point.x.rounded(.down), y: -(CGFloat(image.height) - point.y.rounded(.down) - 1), width: CGFloat(image.width), height: CGFloat(image.height)))
        return (CGFloat(bytes[0]) / 255, CGFloat(bytes[1]) / 255, CGFloat(bytes[2]) / 255)
    }

    private func attachScreenshot(named name: String) {
        guard let window else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let data = screenshot.pngData() {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CanvasScreenshots", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: directory.appendingPathComponent(name + ".png"))
        }
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in
            ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type)
        }
    }

    private func waitUntil(seconds: Double = 5, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(condition(), "The hosted canvas did not reach the expected state.")
    }
}
#endif
