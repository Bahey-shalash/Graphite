#if os(macOS)
import AppKit
import MapKit
import SwiftUI
import XCTest
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// The Map View core plugin in MapKit's map view: the vault's placed notes, a note's linked
/// places in the right sidebar, and a marker that opens its note.
@MainActor
final class UiMapViewMacTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows { window.close() }
        windows = []
        for directory in temporaryDirectories { try? FileManager.default.removeItem(at: directory) }
        temporaryDirectories = []
        try await super.tearDown()
    }

    func testTheVaultMapPlacesEveryNoteWithAPlaceAndAMarkerOpensItsNote() async throws {
        let workspace = try await makeWorkspace()
        let mapView = try await show(VaultMapScreen(workspace: workspace))
        try await waitUntil { Self.notePaths(on: mapView) == ["Lausanne.md", "Paris.md", "Tokyo.md"] }

        let paris = try XCTUnwrap(mapView.annotations.first { annotation in (annotation as? PlacedNoteAnnotation)?.path.rawValue == "Paris.md" })
        mapView.selectAnnotation(paris, animated: false)
        try await waitUntil { workspace.selection?.rawValue == "Paris.md" }
    }

    func testTheLocalMapShowsTheOpenNoteAndTheNotesItLinksTo() async throws {
        let workspace = try await makeWorkspace()
        let store = try XCTUnwrap(workspace.store)
        let parisPath = try VaultPath("Paris.md")
        let session = try MarkdownSession(path: parisPath, snapshot: try await store.read(parisPath), store: store, didSave: { _ in })
        let mapView = try await show(LocalMapPanel(session: session, workspace: workspace))
        // Paris links to Lausanne; Tokyo is placed but not linked, and Notes.md has no place.
        try await waitUntil { Self.notePaths(on: mapView) == ["Lausanne.md", "Paris.md"] }
    }

    // MARK: Helpers

    private static func notePaths(on mapView: MKMapView) -> [String] {
        mapView.annotations.compactMap { annotation in (annotation as? PlacedNoteAnnotation)?.path.rawValue }.sorted()
    }

    private func makeFolder(_ prefix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        temporaryDirectories.append(folder)
        return folder
    }

    private func makeWorkspace() async throws -> WorkspaceModel {
        let vault = try makeFolder("MapVault")
        let notes = [
            "Paris.md": "---\ncoordinates: [48.8566, 2.3522]\n---\n# Paris\nOn the way to [[Lausanne]].\n",
            "Lausanne.md": "---\nlocation: \"46.5197, 6.6323\"\n---\n# Lausanne\n",
            "Tokyo.md": "---\ncoordinates: [35.6762, 139.6503]\n---\n# Tokyo\n",
            "Notes.md": "# Notes\nSee [[Paris]].\n",
        ]
        for (name, text) in notes { try Data(text.utf8).write(to: vault.appendingPathComponent(name)) }
        let index = try VaultIndex(databaseURL: try makeFolder("MapIndex").appendingPathComponent("index.sqlite"))
        _ = try await index.reconcile(root: vault)
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = index
        await workspace.refreshDirectory()
        return workspace
    }

    private func show(_ view: some View) async throws -> MKMapView {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        // Swift owns the window; closing it in tearDown must not release it a second time.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        windows.append(window)
        var mapView: MKMapView?
        try await waitUntil {
            mapView = Self.firstMapView(in: window.contentView)
            return mapView != nil
        }
        return try XCTUnwrap(mapView)
    }

    private static func firstMapView(in view: NSView?) -> MKMapView? {
        guard let view else { return nil }
        if let mapView = view as? MKMapView { return mapView }
        for subview in view.subviews {
            if let mapView = firstMapView(in: subview) { return mapView }
        }
        return nil
    }

    private func waitUntil(timeoutSeconds: TimeInterval = 20, _ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(timeoutSeconds)
        while !condition() {
            guard Date.now < deadline else {
                XCTFail("Timed out after \(timeoutSeconds) s")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
#endif
