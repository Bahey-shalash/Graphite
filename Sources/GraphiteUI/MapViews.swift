import SwiftUI
import GraphiteCore

/// The open note and the notes it links to, or that link to it, on a map in the right
/// sidebar, as the local graph shows them as a graph.
struct LocalMapPanel: View {
    let session: MarkdownSession
    @Bindable var workspace: WorkspaceModel
    @Environment(\.accent) private var accent
    @State private var placedNotes: [PlacedNote]?
    @State private var vaultGraph: LinkGraph?
    @State private var fitRequest = 0

    /// The open note's place and its linked notes' places.
    private var localNotes: [PlacedNote]? {
        guard let placedNotes, let vaultGraph else { return nil }
        let options = LocalGraphOptions(depth: 1, followsIncomingLinks: true, followsOutgoingLinks: true, showsNeighborLinks: false)
        let nearbyIdentifiers = Set(vaultGraph.neighborhood(of: session.path.rawValue, options: options).nodes.map(\.id)).union([session.path.rawValue])
        return placedNotes.filter { note in nearbyIdentifiers.contains(note.path.rawValue) }
    }

    var body: some View {
        // Found once per update: the neighborhood was searched twice, for the count and the map.
        let localNotes = localNotes
        VStack(spacing: 0) {
            HStack {
                Text(localNotes.map { notes in notes.count == 1 ? "1 place" : "\(notes.count.formatted()) places" } ?? " ")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show All", systemImage: "arrow.up.left.and.arrow.down.right") { fitRequest += 1 }
                    .labelStyle(.iconOnly)
            }
            .font(.callout)
            .padding(.horizontal, 12).padding(.bottom, 6)
            Divider()
            if let localNotes {
                if localNotes.isEmpty {
                    ContentUnavailableView("No Places", systemImage: "map",
                                           description: Text(workspace.hasCompletedIndexScan ? "This note and the notes it links to have no coordinates or location property." : "Still reading the vault."))
                } else {
                    NotesMapView(notes: localNotes, title: { path in path.stem }, highlightedPath: session.path,
                                 accent: accent, open: { path in Task { await workspace.open(path) } }, fitRequest: fitRequest)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: workspace.indexVersion) {
            placedNotes = await workspace.placedNotes()
            vaultGraph = await workspace.vaultGraph()
        }
    }
}

/// Every note of the vault with a place, on one map.
struct VaultMapScreen: View {
    @Bindable var workspace: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var searchText = ""
    @State private var placedNotes: [PlacedNote]?
    @State private var fitRequest = 0

    private var shownNotes: [PlacedNote]? {
        guard let placedNotes else { return nil }
        guard !searchText.isEmpty else { return placedNotes }
        return placedNotes.filter { note in note.path.rawValue.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let shownNotes {
                    if shownNotes.isEmpty {
                        ContentUnavailableView(searchText.isEmpty ? "No Places" : "No Matches", systemImage: "map",
                                               description: Text(searchText.isEmpty
                                                                 ? "A note appears here once it has a coordinates or location property, such as coordinates: [48.8566, 2.3522]."
                                                                 : "No placed note's path contains “\(searchText)”."))
                    } else {
                        NotesMapView(notes: shownNotes, title: { path in path.stem }, highlightedPath: workspace.selection,
                                     accent: accent,
                                     open: { path in
                                         dismiss()
                                         Task { await workspace.open(path) }
                                     },
                                     fitRequest: fitRequest)
                        .overlay(alignment: .bottomLeading) {
                            Text(shownNotes.count == 1 ? "1 note" : "\(shownNotes.count.formatted()) notes")
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(8).background(.thinMaterial, in: Capsule()).padding(12)
                        }
                    }
                } else {
                    ProgressView("Reading places…")
                }
            }
            .navigationTitle("Map View")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $searchText, prompt: "Filter by path")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Show All", systemImage: "arrow.up.left.and.arrow.down.right") { fitRequest += 1 }
                }
            }
        }
        .task(id: workspace.indexVersion) { placedNotes = await workspace.placedNotes() }
    }
}
