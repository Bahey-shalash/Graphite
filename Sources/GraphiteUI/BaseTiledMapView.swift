import SwiftUI
import MapKit
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Raster tiles from one template of a map view's `mapTiles`. A tile is fetched only from
/// the address the template names, with a session that keeps no cookies, credentials or
/// disk cache, and a response larger than `maximumTileBytes` is refused.
final class BaseMapTileOverlay: MKTileOverlay {
    /// A 256-point tile at twice the scale is well under a megabyte; anything far larger
    /// is not a map tile.
    static let maximumTileBytes = 4 * 1_048_576
    /// The Maps plugin gives MapLibre 256-point tiles.
    private static let tileSide: CGFloat = 256

    let tileTemplate: BaseMapTileTemplate
    private let session: URLSession

    init(tileTemplate: BaseMapTileTemplate, session: URLSession = BaseMapTileOverlay.tileSession) {
        self.tileTemplate = tileTemplate
        self.session = session
        super.init(urlTemplate: nil)
        tileSize = CGSize(width: Self.tileSide, height: Self.tileSide)
    }

    /// Shared by every tiled map, so tiles seen once stay in memory while the app runs.
    static let tileSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = URLCache(memoryCapacity: 32 * 1_048_576, diskCapacity: 0)
        return URLSession(configuration: configuration)
    }()

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, (any Error)?) -> Void) {
        let deliver = TileResultHandler(result)
        guard let tileURL = tileTemplate.url(column: path.x, row: path.y, zoom: path.z, scale: Double(path.contentScaleFactor)) else {
            deliver(nil, GraphiteError.invalidFile("This map tile has no web address."))
            return
        }
        let session = session
        Task.detached(priority: .utility) {
            do { deliver(try await Self.tileData(at: tileURL, session: session), nil) } catch { deliver(nil, error) }
        }
    }

    static func tileData(at tileURL: URL, session: URLSession) async throws -> Data {
        let tooLargeError = GraphiteError.oversized("This map tile is larger than \(maximumTileBytes / 1_048_576) MB.")
        let (bytes, response) = try await session.bytes(from: tileURL)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw GraphiteError.unavailable("The map tile could not be downloaded (HTTP \(httpResponse.statusCode)).")
        }
        guard response.expectedContentLength <= Int64(maximumTileBytes) else { throw tooLargeError }
        var tileData = Data()
        for try await byte in bytes {
            tileData.append(byte)
            guard tileData.count <= maximumTileBytes else { throw tooLargeError }
        }
        return tileData
    }
}

/// MapKit's handler for one tile. MapKit accepts it from any thread, and each handler is
/// called exactly once, so it can cross to the task that downloads the tile.
private struct TileResultHandler: @unchecked Sendable {
    private let handler: (Data?, (any Error)?) -> Void
    init(_ handler: @escaping (Data?, (any Error)?) -> Void) { self.handler = handler }
    func callAsFunction(_ tileData: Data?, _ error: (any Error)?) { handler(tileData, error) }
}

/// One marker of a map with custom tiles.
final class BaseMapMarkerAnnotation: NSObject, MKAnnotation {
    let path: VaultPath
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(path: VaultPath, coordinate: CLLocationCoordinate2D, title: String) {
        self.path = path
        self.coordinate = coordinate
        self.title = title
    }
}

/// MapKit's map view, telling its coordinator when it is laid out: SwiftUI can update the
/// map before it has a size, and the camera is placed once it has one.
final class BaseLaidOutMapView: MKMapView {
    var didLayOut: (() -> Void)?

    #if canImport(UIKit)
    override func layoutSubviews() {
        super.layoutSubviews()
        didLayOut?()
    }
    #else
    override func layout() {
        super.layout()
        didLayOut?()
    }
    #endif
}

/// Where a tiled map's camera goes: a region, or around every marker.
enum BaseMapCameraTarget: Equatable {
    case region(MKCoordinateRegion)
    case fittingMarkers

    static func == (leftTarget: BaseMapCameraTarget, rightTarget: BaseMapCameraTarget) -> Bool {
        switch (leftTarget, rightTarget) {
        case (.fittingMarkers, .fittingMarkers): true
        case (.region(let leftRegion), .region(let rightRegion)):
            leftRegion.center.latitude == rightRegion.center.latitude && leftRegion.center.longitude == rightRegion.center.longitude
                && leftRegion.span.latitudeDelta == rightRegion.span.latitudeDelta && leftRegion.span.longitudeDelta == rightRegion.span.longitudeDelta
        default: false
        }
    }
}

/// A map whose background is raster tiles from the base's `mapTiles`. SwiftUI's `Map`
/// draws only Apple's maps, so this one wraps MapKit's map view, which takes tile
/// overlays. The first template replaces Apple's map, so none of it is loaded; later ones
/// are drawn over it, as the plugin layers them. Markers look and select as in
/// `BaseMapView`, which shows the selected marker's callout.
@MainActor
struct BaseTiledMapView {
    let tileTemplates: [BaseMapTileTemplate]
    let annotations: [BaseMapMarkerAnnotation]
    let cameraTarget: BaseMapCameraTarget
    /// Changes with the view, its center or its zoom, which always place the camera again.
    let cameraConfiguration: Int
    /// Changes when markers move or the map is resized, which place the camera again only
    /// until the person moves the map, as in `BaseMapView`.
    let cameraLayout: Int
    /// The closest and farthest the camera may be, in meters, from `minZoom` and `maxZoom`.
    let cameraDistances: ClosedRange<CLLocationDistance>
    @Binding var selectedPath: VaultPath?
    /// The pin drawn for a marker, selected or not.
    let pinImage: (VaultPath, Bool) -> CGImage?
    /// Fetches the tiles.
    var tileSession = BaseMapTileOverlay.tileSession

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: BaseTiledMapView
        var shownTemplates: [BaseMapTileTemplate] = []
        var shownAnnotationPaths: [VaultPath] = []
        var placedCameraConfiguration: Int?
        var placedCameraLayout: Int?
        var isPositionedByUser = false
        /// Set while the camera is placed from here, so only the person's moves count as theirs.
        var isPlacingCamera = false

        init(parent: BaseTiledMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let tileOverlay = overlay as? MKTileOverlay else { return MKOverlayRenderer(overlay: overlay) }
            return MKTileOverlayRenderer(tileOverlay: tileOverlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let marker = annotation as? BaseMapMarkerAnnotation else { return nil }
            let reuseIdentifier = "BaseMapMarker"
            let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) ?? MKAnnotationView(annotation: marker, reuseIdentifier: reuseIdentifier)
            annotationView.annotation = marker
            annotationView.canShowCallout = false
            setPin(of: annotationView, for: marker, isSelected: parent.selectedPath == marker.path)
            return annotationView
        }

        func mapView(_ mapView: MKMapView, didSelect annotationView: MKAnnotationView) {
            guard let marker = annotationView.annotation as? BaseMapMarkerAnnotation else { return }
            setPin(of: annotationView, for: marker, isSelected: true)
            if parent.selectedPath != marker.path { parent.selectedPath = marker.path }
        }

        func mapView(_ mapView: MKMapView, didDeselect annotationView: MKAnnotationView) {
            guard let marker = annotationView.annotation as? BaseMapMarkerAnnotation else { return }
            setPin(of: annotationView, for: marker, isSelected: false)
            if parent.selectedPath == marker.path { parent.selectedPath = nil }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !isPlacingCamera { isPositionedByUser = true }
        }

        private func setPin(of annotationView: MKAnnotationView, for marker: BaseMapMarkerAnnotation, isSelected: Bool) {
            guard let pinImage = parent.pinImage(marker.path, isSelected) else { return }
            #if canImport(UIKit)
            annotationView.image = UIImage(cgImage: pinImage, scale: annotationView.traitCollection.displayScale, orientation: .up)
            annotationView.accessibilityLabel = marker.title
            #else
            let scale = annotationView.window?.backingScaleFactor ?? 2
            annotationView.image = NSImage(cgImage: pinImage, size: CGSize(width: CGFloat(pinImage.width) / scale, height: CGFloat(pinImage.height) / scale))
            annotationView.setAccessibilityLabel(marker.title)
            #endif
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private func makeMapView(context: Context) -> BaseLaidOutMapView {
        let mapView = BaseLaidOutMapView()
        mapView.delegate = context.coordinator
        let coordinator = context.coordinator
        mapView.didLayOut = { [weak mapView, weak coordinator] in
            guard let mapView, let coordinator else { return }
            coordinator.parent.placeCamera(on: mapView, coordinator: coordinator)
        }
        mapView.showsCompass = true
        #if canImport(UIKit)
        mapView.showsScale = true
        #endif
        return mapView
    }

    private func update(_ mapView: BaseLaidOutMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.shownTemplates != tileTemplates {
            mapView.removeOverlays(mapView.overlays)
            for (position, tileTemplate) in tileTemplates.enumerated() {
                let overlay = BaseMapTileOverlay(tileTemplate: tileTemplate, session: tileSession)
                overlay.canReplaceMapContent = position == 0
                mapView.addOverlay(overlay, level: .aboveLabels)
            }
            coordinator.shownTemplates = tileTemplates
        }
        if coordinator.shownAnnotationPaths != annotations.map(\.path) {
            mapView.removeAnnotations(mapView.annotations)
            mapView.addAnnotations(annotations)
            coordinator.shownAnnotationPaths = annotations.map(\.path)
        }
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: cameraDistances.lowerBound,
                                                            maxCenterCoordinateDistance: cameraDistances.upperBound)
        // The markers on the map were made by an earlier update, so they are found by file.
        let isSelectionShown = mapView.selectedAnnotations.contains { annotation in (annotation as? BaseMapMarkerAnnotation)?.path == selectedPath }
        if !isSelectionShown {
            for annotation in mapView.selectedAnnotations { mapView.deselectAnnotation(annotation, animated: true) }
            if let selectedMarker = mapView.annotations.first(where: { annotation in selectedPath != nil && (annotation as? BaseMapMarkerAnnotation)?.path == selectedPath }) {
                mapView.selectAnnotation(selectedMarker, animated: true)
            }
        }
        placeCamera(on: mapView, coordinator: coordinator)
    }

    /// Places the camera when the configuration changed, or when the layout changed and
    /// the person has not moved the map. A map without a size yet waits for its layout.
    fileprivate func placeCamera(on mapView: MKMapView, coordinator: Coordinator) {
        guard mapView.bounds.width > 0, mapView.bounds.height > 0 else { return }
        let isNewConfiguration = coordinator.placedCameraConfiguration != cameraConfiguration
        guard isNewConfiguration || (coordinator.placedCameraLayout != cameraLayout && !coordinator.isPositionedByUser) else { return }
        coordinator.isPlacingCamera = true
        defer { coordinator.isPlacingCamera = false }
        switch cameraTarget {
        case .region(let region): mapView.setRegion(region, animated: false)
        case .fittingMarkers: mapView.showAnnotations(mapView.annotations, animated: false)
        }
        coordinator.placedCameraConfiguration = cameraConfiguration
        coordinator.placedCameraLayout = cameraLayout
        if isNewConfiguration { coordinator.isPositionedByUser = false }
    }
}

#if canImport(UIKit)
extension BaseTiledMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> BaseLaidOutMapView { makeMapView(context: context) }
    func updateUIView(_ mapView: BaseLaidOutMapView, context: Context) { update(mapView, context: context) }
}
#else
extension BaseTiledMapView: NSViewRepresentable {
    func makeNSView(context: Context) -> BaseLaidOutMapView { makeMapView(context: context) }
    func updateNSView(_ mapView: BaseLaidOutMapView, context: Context) { update(mapView, context: context) }
}
#endif
