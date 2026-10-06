#if os(iOS)
import XCTest
import SwiftUI
import MapKit
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Bases views hosted in the app: resized table columns, `html()` values, Kanban boards
/// and map tiles. SwiftUI builds no accessibility elements in a test process, so each
/// test acts through the base's model and attaches screenshots of what the views show.
@MainActor
final class BasesViewsTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var vault: URL?

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        if let vault {
            try? FileManager.default.removeItem(at: vault)
            try? FileManager.default.removeItem(at: vault.appendingPathExtension("cache"))
        }
        vault = nil
        HostedTileStub.recorder.reset()
    }

    // MARK: Table columns

    func testTableColumnsTakeTheirSavedWidthsAndAResizeIsShown() async throws {
        let (model, controller) = try await hostedBase("Books.base", files: [
            "Books/Dune.md": "---\nauthor: Frank Herbert\nyear: 1965\n---\n",
            "Books/Emma.md": "---\nauthor: Jane Austen\nyear: 1815\n---\n",
            "Books.base": "filters: file.inFolder(\"Books\")\nviews:\n  - type: table\n    name: Books\n    order: [file.name, note.author, note.year]\n    columnSize:\n      note.author: 120\n",
        ])
        XCTAssertEqual(BaseTableView.columnWidths(for: try XCTUnwrap(model.result)), [240, 120, 170])
        XCTAssertTrue(model.canEditDefinition, "A table of a base file shows resize handles.")
        attachScreenshot(of: controller, named: "Table with a 120-point author column")

        let isSaved = await model.setColumnWidth(260, of: .note("author"))
        XCTAssertTrue(isSaved)
        XCTAssertEqual(try text(at: "Books.base"),
                       "filters: file.inFolder(\"Books\")\nviews:\n  - type: table\n    name: Books\n    order: [file.name, note.author, note.year]\n    columnSize:\n      note.author: 260\n")
        XCTAssertEqual(BaseTableView.columnWidths(for: try XCTUnwrap(model.result)), [240, 260, 170])
        try await Task.sleep(for: .milliseconds(300))
        attachScreenshot(of: controller, named: "Table after the author column was widened to 260 points")
    }

    // MARK: html()

    func testHTMLValuesAreShownAsFormattedText() async throws {
        let (model, controller) = try await hostedBase("Books.base", files: [
            "Books/Dune.md": "---\nstatus: reading\n---\n",
            "Books.base": """
                filters: file.inFolder("Books")
                formulas:
                  badge: 'html("<b style=\\"color: red\\">" + status + "</b> <i>now</i> <script>alert(1)</script><img src=\\"https://tracker.example/p.gif\\" alt=\\"(cover)\\"> <a href=\\"https://obsidian.md\\">site</a>")'
                views:
                  - type: table
                    name: Books
                    order: [file.name, formula.badge]
                    columnSize:
                      formula.badge: 320

                """,
        ])
        let badge = try XCTUnwrap(model.result?.rows.first?.cells.last?.value)
        guard case .html(let source) = badge else { return XCTFail("The formula's value is markup: \(badge)") }
        XCTAssertEqual(BaseHTMLText(source: source).plainText, "reading now (cover) site")
        try await Task.sleep(for: .milliseconds(300))
        attachScreenshot(of: controller, named: "html() value in a table cell: red bold status, italic word, link")
    }

    // MARK: Kanban

    func testABoardShowsAColumnPerValueAndAMovedCardChangesColumn() async throws {
        let (model, controller) = try await hostedBase("Tasks.base", files: [
            "Tasks/Fix testbench.md": "---\nstatus: todo\npriority: 1\n---\n",
            "Tasks/Review lecture.md": "---\nstatus: doing\npriority: 2\n---\n",
            "Tasks/Email the TA.md": "---\nstatus: done\npriority: 2\n---\n",
            "Tasks/Plan study group.md": "---\npriority: 3\n---\n",
            "Tasks.base": "filters: file.inFolder(\"Tasks\")\nviews:\n  - type: kanban\n    name: Board\n    order: [file.name, priority]\n    groupBy:\n      property: status\n      direction: ASC\n",
        ])
        XCTAssertEqual(model.result?.groups.map(BaseKanbanView.title(of:)), ["doing", "done", "todo", "None"])
        try await Task.sleep(for: .milliseconds(300))
        attachScreenshot(of: controller, named: "Board grouped by status")

        let doingKey = try XCTUnwrap(model.result?.groups.first?.key)
        let isMoved = await model.moveToGroup(try VaultPath("Tasks/Fix testbench.md"), groupKey: doingKey)
        XCTAssertTrue(isMoved)
        XCTAssertEqual(try text(at: "Tasks/Fix testbench.md"), "---\nstatus: doing\npriority: 1\n---\n")
        XCTAssertEqual(model.result?.groups.map { group in group.rows.count }, [2, 1, 1])
        try await Task.sleep(for: .milliseconds(300))
        attachScreenshot(of: controller, named: "Board after moving Fix testbench to doing")
    }

    // MARK: Map tiles

    func testTheMapFetchesTilesFromTheBasesTileAddressAndDrawsThem() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HostedTileStub.self]
        let template = try XCTUnwrap(BaseMapTileTemplate("https://tiles.graphite.test/{z}/{x}/{y}.png"))
        let paris = CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522)
        let mapView = BaseTiledMapView(
            tileTemplates: [template],
            annotations: [BaseMapMarkerAnnotation(path: try VaultPath("Places/Paris.md"), coordinate: paris, title: "Paris")],
            cameraTarget: .region(MKCoordinateRegion(center: paris, latitudinalMeters: 40_000, longitudinalMeters: 40_000)),
            cameraConfiguration: 1, cameraLayout: 1, cameraDistances: 100...10_000_000,
            selectedPath: .constant(nil), pinImage: { _, _ in Self.bluePin }, tileSession: URLSession(configuration: configuration))
        let controller = try host(mapView)
        try await waitUntil(timeout: 20) { HostedTileStub.recorder.requestedURLs.count >= 4 }
        let requestedURLs = HostedTileStub.recorder.requestedURLs
        XCTAssertEqual(Set(requestedURLs.compactMap(\.host)), ["tiles.graphite.test"], "Every tile comes from the address the base names.")
        for tileURL in requestedURLs {
            let parts = tileURL.path.split(separator: "/")
            XCTAssertEqual(parts.count, 3, tileURL.absoluteString)
            XCTAssertTrue(tileURL.path.hasSuffix(".png"), tileURL.absoluteString)
        }
        let zoomLevels = Set(requestedURLs.compactMap { tileURL in Int(tileURL.path.split(separator: "/").first ?? "") })
        XCTAssertTrue(zoomLevels.contains { zoom in (9...13).contains(zoom) }, "Tiles around Paris at a city's zoom were asked for: \(zoomLevels)")
        // MapKit draws tiles as they arrive, over its own grid of empty squares; once they
        // are all drawn the stubbed tiles, and nothing of Apple's map, fill the view.
        let windowBounds = try XCTUnwrap(controller.view.window?.bounds)
        var samplePoints: [CGPoint] = []
        for row in 1...5 {
            for column in 1...5 {
                let sampleX = windowBounds.width * CGFloat(column) / 6 + 23
                let sampleY = windowBounds.height * CGFloat(row) / 6 + 17
                samplePoints.append(CGPoint(x: sampleX, y: sampleY))
            }
        }
        func showsOnlyStubbedTiles() -> Bool {
            guard let mapImage = screenshot(of: controller) else { return false }
            return samplePoints.allSatisfy { point in
                guard let sampleColor = color(in: mapImage, at: point) else { return false }
                return sampleColor.red > 0.8 && sampleColor.green < 0.45
            }
        }
        try await waitUntil(timeout: 20) { showsOnlyStubbedTiles() }
        attachScreenshot(of: controller, named: "Map drawn from stubbed red tiles, with its marker")
        let finishedMapImage = try XCTUnwrap(screenshot(of: controller))
        let marker = try XCTUnwrap(color(in: finishedMapImage, at: CGPoint(x: windowBounds.midX, y: windowBounds.midY)))
        XCTAssertGreaterThan(marker.blue, 0.7, "The marker is drawn over the tiles, at the region's center: \(marker)")
    }

    /// A blue dot standing for a marker's pin.
    private static let bluePin: CGImage? = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 28)).image { context in
        UIColor.systemBlue.setFill()
        context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 28, height: 28))
    }.cgImage

    // MARK: Hosting

    /// A base file opened on its own, hosted in a window, with the model behind it.
    private func hostedBase(_ basePath: String, files: [String: String]) async throws -> (BaseDocumentModel, UIViewController) {
        let (store, index) = try await makeVault(files: files)
        let path = try VaultPath(basePath)
        let modelCache = EmbeddedBaseModelCache()
        let controller = try host(BaseContainerView(source: .file(path), contextPath: path, preferredViewName: nil, store: store, index: index, contentVersion: 1,
                                                    isIndexComplete: true, presentation: .document, open: { _ in }, openBase: { _, _ in }, filesChanged: { _ in },
                                                    modelCache: modelCache))
        let identity = EmbeddedBaseView.EmbedIdentity(source: .file(path), embeddingNote: path, viewName: nil)
        let model = modelCache.model(for: identity) {
            XCTFail("The hosted base made its model.")
            return BaseDocumentModel(source: .file(path), contextPath: path, store: store, index: index)
        }
        try await waitUntil { model.result != nil && !model.isLoading }
        XCTAssertNil(model.loadErrorMessage)
        return (model, controller)
    }

    private func makeVault(files: [String: String]) async throws -> (VaultStore, VaultIndex) {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent("BasesViewsVault-\(UUID().uuidString)")
        self.vault = vault
        for (relativePath, text) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: location)
        }
        let index = try VaultIndex(databaseURL: vault.appendingPathExtension("cache").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        return (VaultStore(root: vault), index)
    }

    private func text(at relativePath: String) throws -> String {
        try String(contentsOf: try XCTUnwrap(vault).appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func host(_ rootView: some View) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(rootView))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { scene in scene as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        windows.append(window)
        return controller
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(condition(), "The hosted base did not reach the expected state.")
    }

    private func screenshot(of controller: UIViewController) -> UIImage? {
        guard let window = controller.view.window else { return nil }
        return UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    private func attachScreenshot(of controller: UIViewController, named name: String) {
        guard let screenshot = screenshot(of: controller) else { return }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// The color at a point of an image, in points.
    private func color(in image: UIImage, at point: CGPoint) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        guard let cgImage = image.cgImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let pixelX = point.x * image.scale, pixelY = point.y * image.scale
        context.draw(cgImage, in: CGRect(x: -pixelX, y: pixelY - CGFloat(cgImage.height) + 1, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
    }
}

/// Answers tile requests with a red tile, without the network, and records them.
private final class HostedTileStub: URLProtocol {
    final class Recorder: @unchecked Sendable {
        // Requests arrive on URL loading threads; the lock orders them.
        private let lock = NSLock()
        private var urls: [URL] = []
        var requestedURLs: [URL] { lock.withLock { urls } }
        func record(_ url: URL) { lock.withLock { urls.append(url) } }
        func reset() { lock.withLock { urls = [] } }
    }

    static let recorder = Recorder()

    private static let redTile: Data = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).pngData { context in
        UIColor.systemRed.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"]) else { return }
        Self.recorder.record(url)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.redTile)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
#endif
