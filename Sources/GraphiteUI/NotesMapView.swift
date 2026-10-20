import SwiftUI
import MapKit
import GraphiteCore

/// One note on the map.
final class PlacedNoteAnnotation: NSObject, MKAnnotation {
    let path: VaultPath
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(note: PlacedNote, title: String) {
        path = note.path
        coordinate = CLLocationCoordinate2D(latitude: note.coordinate.latitude, longitude: note.coordinate.longitude)
        self.title = title
    }
}

/// Notes on Apple's map, drawn by MapKit's own map view rather than SwiftUI's `Map`: nearby
/// notes gather into one numbered marker as the map zooms out, which keeps thousands of
/// places legible and the map smooth, and each marker shows its note's name when there is
/// room. Choosing a note opens it; choosing a group zooms in on its notes.
@MainActor
struct NotesMapView {
    let notes: [PlacedNote]
    let title: (VaultPath) -> String
    /// The note drawn in the accent color, such as the one a local map is beside.
    let highlightedPath: VaultPath?
    let accent: Color
    let open: (VaultPath) -> Void
    /// Changes to place the camera around every note again.
    let fitRequest: Int

    private static let noteReuseIdentifier = "PlacedNote"
    private static let groupReuseIdentifier = "PlacedNoteGroup"
    private static let clusteringIdentifier = "PlacedNotes"
    /// How much of the map a single note shows around it, in meters.
    private static let singleNoteSpan: CLLocationDistance = 5_000
    /// Room left between the notes and the map's edges, so markers and their names are not
    /// cut off: a marker is drawn above its point, with its name below.
    private static let framingInsets = PlatformEdgeInsets(top: 56, left: 40, bottom: 40, right: 40)

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: NotesMapView
        var shownNotes: [PlacedNote] = []
        var placedFitRequest: Int?
        /// The highlight and accent the markers were last styled for.
        var styledAppearance: (highlightedPath: VaultPath?, accent: Color)?

        init(parent: NotesMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if let group = annotation as? MKClusterAnnotation {
                let groupView = mapView.dequeueReusableAnnotationView(withIdentifier: NotesMapView.groupReuseIdentifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: group, reuseIdentifier: NotesMapView.groupReuseIdentifier)
                groupView.annotation = group
                groupView.markerTintColor = platformColor(parent.accent)
                groupView.glyphText = group.memberAnnotations.count.formatted()
                return groupView
            }
            guard let note = annotation as? PlacedNoteAnnotation else { return nil }
            let noteView = mapView.dequeueReusableAnnotationView(withIdentifier: NotesMapView.noteReuseIdentifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: note, reuseIdentifier: NotesMapView.noteReuseIdentifier)
            noteView.annotation = note
            noteView.clusteringIdentifier = NotesMapView.clusteringIdentifier
            noteView.titleVisibility = .adaptive
            style(noteView, for: note)
            return noteView
        }

        func mapView(_ mapView: MKMapView, didSelect annotationView: MKAnnotationView) {
            guard let annotation = annotationView.annotation else { return }
            mapView.deselectAnnotation(annotation, animated: false)
            if let group = annotation as? MKClusterAnnotation {
                mapView.showAnnotations(group.memberAnnotations, animated: true)
            } else if let note = annotation as? PlacedNoteAnnotation {
                parent.open(note.path)
            }
        }

        /// The open note stands out, and is never hidden in a group.
        func style(_ noteView: MKMarkerAnnotationView, for note: PlacedNoteAnnotation) {
            let isHighlighted = note.path == parent.highlightedPath
            noteView.markerTintColor = isHighlighted ? platformColor(parent.accent) : PlatformMapColor.systemGray
            noteView.displayPriority = isHighlighted ? .required : .defaultHigh
            noteView.clusteringIdentifier = isHighlighted ? nil : NotesMapView.clusteringIdentifier
            noteView.glyphImage = Self.noteGlyph
        }

        /// One image for every marker, rather than one made for each marker on each update.
        #if canImport(UIKit)
        private static let noteGlyph = UIImage(systemName: "doc.text")
        #else
        private static let noteGlyph = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        #endif

        private func platformColor(_ color: Color) -> PlatformMapColor { PlatformMapColor(color) }
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
        if coordinator.shownNotes != notes {
            mapView.removeAnnotations(mapView.annotations)
            mapView.addAnnotations(notes.map { note in PlacedNoteAnnotation(note: note, title: title(note.path)) })
            // Other notes, such as another note's neighbors or a new filter, are framed again.
            coordinator.placedFitRequest = nil
            coordinator.shownNotes = notes
        }
        // The markers shown are styled again only when what they show changes: each update
        // of the view around the map restyled thousands of them, and changing a marker's
        // grouping made MapKit group the notes again.
        if coordinator.styledAppearance?.highlightedPath != highlightedPath || coordinator.styledAppearance?.accent != accent {
            coordinator.styledAppearance = (highlightedPath, accent)
            for annotation in mapView.annotations {
                guard let note = annotation as? PlacedNoteAnnotation, let noteView = mapView.view(for: note) as? MKMarkerAnnotationView else { continue }
                coordinator.style(noteView, for: note)
            }
        }
        placeCamera(on: mapView, coordinator: coordinator)
    }

    /// Frames every note once the map has a size, again on each request, and leaves the
    /// camera where the person put it otherwise.
    fileprivate func placeCamera(on mapView: MKMapView, coordinator: Coordinator) {
        guard mapView.bounds.width > 0, mapView.bounds.height > 0, coordinator.placedFitRequest != fitRequest else { return }
        let noteAnnotations = mapView.annotations.filter { annotation in annotation is PlacedNoteAnnotation }
        guard !noteAnnotations.isEmpty else { return }
        if noteAnnotations.count == 1, let onlyNote = noteAnnotations.first {
            mapView.setRegion(MKCoordinateRegion(center: onlyNote.coordinate, latitudinalMeters: Self.singleNoteSpan, longitudinalMeters: Self.singleNoteSpan), animated: false)
        } else {
            let notesRectangle = noteAnnotations.reduce(MKMapRect.null) { rectangle, annotation in
                rectangle.union(MKMapRect(origin: MKMapPoint(annotation.coordinate), size: MKMapSize(width: 0, height: 0)))
            }
            mapView.setVisibleMapRect(notesRectangle, edgePadding: Self.framingInsets, animated: false)
        }
        coordinator.placedFitRequest = fitRequest
    }
}

#if canImport(UIKit)
typealias PlatformMapColor = UIColor
typealias PlatformEdgeInsets = UIEdgeInsets
extension NotesMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> BaseLaidOutMapView { makeMapView(context: context) }
    func updateUIView(_ mapView: BaseLaidOutMapView, context: Context) { update(mapView, context: context) }
}
#else
typealias PlatformMapColor = NSColor
typealias PlatformEdgeInsets = NSEdgeInsets
extension NotesMapView: NSViewRepresentable {
    func makeNSView(context: Context) -> BaseLaidOutMapView { makeMapView(context: context) }
    func updateNSView(_ mapView: BaseLaidOutMapView, context: Context) { update(mapView, context: context) }
}
#endif
