import XCTest
import SwiftUI
import MapKit
import GraphiteCore
@testable import GraphiteUI

/// Map tiles from a map view's `mapTiles`: which addresses are fetched, how a tile's
/// download is bounded, and the MapKit map that draws them.
@MainActor
final class UiBasesMapTilesTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func setUp() async throws {
        TileRequestStub.recorder.reset()
    }

    override func tearDown() async throws {
        for window in windows { window.contentView = nil }
        windows = []
    }

    private func stubbedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TileRequestStub.self]
        return URLSession(configuration: configuration)
    }

    private func overlay(_ template: String) throws -> BaseMapTileOverlay {
        BaseMapTileOverlay(tileTemplate: try XCTUnwrap(BaseMapTileTemplate(template)), session: stubbedSession())
    }

    // MARK: Fetching tiles

    func testATileIsFetchedFromTheTemplatesAddressOnly() async throws {
        let tileOverlay = try overlay("https://tiles.example/{z}/{x}/{y}{ratio}.png")
        let tileData = try await tileOverlay.loadTile(at: MKTileOverlayPath(x: 1, y: 2, z: 3, contentScaleFactor: 2))
        XCTAssertEqual(String(decoding: tileData, as: UTF8.self), "tile /3/1/2@2x.png")
        XCTAssertEqual(TileRequestStub.recorder.requestedURLs.map(\.absoluteString), ["https://tiles.example/3/1/2@2x.png"])
        XCTAssertEqual(tileOverlay.tileSize, CGSize(width: 256, height: 256), "The plugin's tiles are 256 points square.")
    }

    func testATileTheServerDoesNotHaveIsAnError() async throws {
        let tileOverlay = try overlay("https://tiles.example/missing/{z}/{x}/{y}.png")
        do {
            _ = try await tileOverlay.loadTile(at: MKTileOverlayPath(x: 0, y: 0, z: 0, contentScaleFactor: 1))
            XCTFail("A 404 is no tile.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("404"), error.localizedDescription)
        }
    }

    func testAnOversizedTileIsRefused() async throws {
        let tileOverlay = try overlay("https://tiles.example/huge/{z}/{x}/{y}.png")
        do {
            _ = try await tileOverlay.loadTile(at: MKTileOverlayPath(x: 0, y: 0, z: 0, contentScaleFactor: 1))
            XCTFail("A response beyond the limit is no tile.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("larger than"), error.localizedDescription)
        }
    }

    func testTheSharedTileSessionKeepsNoCookiesCredentialsOrDiskCache() {
        let configuration = BaseMapTileOverlay.tileSession.configuration
        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertEqual(configuration.urlCache?.diskCapacity, 0)
    }

    // MARK: The map that draws them

    func testTheTiledMapReplacesApplesMapAndShowsEveryMarker() async throws {
        let templates = try ["https://base.example/{z}/{x}/{y}.png", "https://labels.example/{z}/{x}/{y}.png"].map { template in try XCTUnwrap(BaseMapTileTemplate(template)) }
        let annotations = try [("Places/Louvre.md", 48.8606, 2.3376), ("Places/Orsay.md", 48.86, 2.3266)].map { path, latitude, longitude in
            BaseMapMarkerAnnotation(path: try VaultPath(path), coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), title: path)
        }
        let mapView = try await hostedMapView(BaseTiledMapView(
            tileTemplates: templates, annotations: annotations,
            cameraTarget: .region(MKCoordinateRegion(center: annotations[0].coordinate, latitudinalMeters: 5_000, longitudinalMeters: 5_000)),
            cameraConfiguration: 1, cameraLayout: 1, cameraDistances: 100...1_000_000,
            selectedPath: .constant(nil), pinImage: { _, _ in nil }))

        let tileOverlays = mapView.overlays.compactMap { overlay in overlay as? BaseMapTileOverlay }
        XCTAssertEqual(tileOverlays.map(\.tileTemplate), templates, "Each template is a layer, bottom to top.")
        XCTAssertEqual(tileOverlays.map(\.canReplaceMapContent), [true, false], "The first layer replaces Apple's map, so none of it is loaded.")
        XCTAssertEqual(Set(mapView.annotations.compactMap { annotation in (annotation as? BaseMapMarkerAnnotation)?.path.rawValue }), ["Places/Louvre.md", "Places/Orsay.md"])
        XCTAssertEqual(mapView.region.center.latitude, 48.8606, accuracy: 0.01)
        XCTAssertEqual(mapView.cameraZoomRange.minCenterCoordinateDistance, 100, accuracy: 1)
    }

    private func hostedMapView(_ view: BaseTiledMapView) async throws -> MKMapView {
        let hostingView = NSHostingView(rootView: view.frame(width: 600, height: 400))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hostingView
        windows.append(window)
        for _ in 0..<40 {
            hostingView.layoutSubtreeIfNeeded()
            if let mapView = Self.descendant(of: hostingView), mapView.bounds.width > 0, !mapView.overlays.isEmpty { return mapView }
            try await Task.sleep(for: .milliseconds(25))
        }
        return try XCTUnwrap(Self.descendant(of: hostingView))
    }

    private static func descendant(of view: NSView) -> MKMapView? {
        if let mapView = view as? MKMapView { return mapView }
        return view.subviews.lazy.compactMap(descendant(of:)).first
    }
}

/// Answers tile requests without the network and records what was asked for.
private final class TileRequestStub: URLProtocol {
    final class Recorder: @unchecked Sendable {
        // Requests arrive on URL loading threads; the lock orders them.
        private let lock = NSLock()
        private var urls: [URL] = []
        var requestedURLs: [URL] { lock.withLock { urls } }
        func record(_ url: URL) { lock.withLock { urls.append(url) } }
        func reset() { lock.withLock { urls = [] } }
    }

    static let recorder = Recorder()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.recorder.record(url)
        let isMissing = url.path.contains("missing")
        let body = url.path.contains("huge") ? Data(count: BaseMapTileOverlay.maximumTileBytes + 1) : Data("tile \(url.path)".utf8)
        guard let response = HTTPURLResponse(url: url, statusCode: isMissing ? 404 : 200, httpVersion: "HTTP/1.1", headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
