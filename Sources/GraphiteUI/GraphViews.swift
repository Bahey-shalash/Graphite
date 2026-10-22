import SwiftUI
import GraphiteCore

/// Obsidian's local graph: the open note and the notes around it, in the right sidebar.
struct LocalGraphPanel: View {
    let session: MarkdownSession
    @Bindable var workspace: WorkspaceModel
    @AppStorage(GraphSettingKey.localDepth) private var depth = 1
    @AppStorage(GraphSettingKey.localFollowsIncomingLinks) private var followsIncomingLinks = true
    @AppStorage(GraphSettingKey.localFollowsOutgoingLinks) private var followsOutgoingLinks = true
    @AppStorage(GraphSettingKey.localShowsNeighborLinks) private var showsNeighborLinks = true
    @AppStorage(GraphSettingKey.localShowsTags) private var showsTags = false
    @AppStorage(GraphSettingKey.localShowsAttachments) private var showsAttachments = false
    @AppStorage(GraphSettingKey.localShowsExistingFilesOnly) private var showsExistingFilesOnly = true
    @State private var vaultGraph: LinkGraph?
    @State private var fitRequest = 0

    private var localGraph: LinkGraph? {
        guard let vaultGraph else { return nil }
        let filters = GraphFilterOptions(showsTags: showsTags, showsAttachments: showsAttachments, showsExistingFilesOnly: showsExistingFilesOnly)
        let options = LocalGraphOptions(depth: depth, followsIncomingLinks: followsIncomingLinks, followsOutgoingLinks: followsOutgoingLinks, showsNeighborLinks: showsNeighborLinks)
        return vaultGraph.filtered(by: filters).neighborhood(of: session.path.rawValue, options: options)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Stepper("Depth \(depth)", value: $depth, in: 1...5).fixedSize()
                Spacer()
                Button("Show All", systemImage: "arrow.up.left.and.arrow.down.right") { fitRequest += 1 }
                    .labelStyle(.iconOnly)
                Menu("Filters", systemImage: "line.3.horizontal.decrease.circle") {
                    Toggle("Incoming Links", isOn: $followsIncomingLinks)
                    Toggle("Outgoing Links", isOn: $followsOutgoingLinks)
                    Toggle("Neighbor Links", isOn: $showsNeighborLinks)
                    Divider()
                    Toggle("Tags", isOn: $showsTags)
                    Toggle("Attachments", isOn: $showsAttachments)
                    Toggle("Existing Files Only", isOn: $showsExistingFilesOnly)
                }
                .labelStyle(.iconOnly)
            }
            .font(.callout)
            .padding(.horizontal, 12).padding(.bottom, 6)
            Divider()
            if let localGraph {
                if localGraph.nodes.count <= 1 {
                    ContentUnavailableView("No Links", systemImage: "point.3.connected.trianglepath.dotted",
                                           description: Text(workspace.hasCompletedIndexScan ? "This note has no links yet, in either direction." : "Still reading the vault."))
                } else {
                    GraphCanvas(graph: localGraph, highlightedIdentifier: session.path.rawValue, alwaysShowsLabels: localGraph.nodes.count <= 60,
                                open: { node in Task { await workspace.open(node, from: session.path) } }, fitRequest: fitRequest)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: workspace.indexVersion) { vaultGraph = await workspace.vaultGraph() }
    }
}

/// Obsidian's graph view of the whole vault, in a tab of its own: it stays open, beside a
/// note in a split if the person likes, while notes are opened from it.
struct VaultGraphView: View {
    @Bindable var workspace: WorkspaceModel
    @AppStorage(GraphSettingKey.showsTags) private var showsTags = false
    @AppStorage(GraphSettingKey.showsAttachments) private var showsAttachments = false
    @AppStorage(GraphSettingKey.showsExistingFilesOnly) private var showsExistingFilesOnly = true
    @AppStorage(GraphSettingKey.showsOrphans) private var showsOrphans = true
    @AppStorage(GraphSettingKey.showsArrows) private var showsArrows = false
    @AppStorage(GraphSettingKey.linkDistance) private var linkDistance = GraphLayout.Forces().linkDistance
    @AppStorage(GraphSettingKey.repelStrength) private var repelStrength = GraphLayout.Forces().repelStrength
    @AppStorage(GraphSettingKey.centerStrength) private var centerStrength = GraphLayout.Forces().centerStrength
    @State private var searchText = ""
    @State private var vaultGraph: LinkGraph?
    @State private var shownGraph: LinkGraph?
    @State private var showsSettings = false
    @State private var fitRequest = 0

    private var filters: GraphFilterOptions {
        GraphFilterOptions(searchText: searchText, showsTags: showsTags, showsAttachments: showsAttachments,
                           showsExistingFilesOnly: showsExistingFilesOnly, showsOrphans: showsOrphans)
    }

    private var forces: GraphLayout.Forces {
        GraphLayout.Forces(linkDistance: linkDistance, repelStrength: repelStrength, centerStrength: centerStrength)
    }

    var body: some View {
        Group {
            if let shownGraph {
                if shownGraph.nodes.isEmpty {
                    ContentUnavailableView(searchText.isEmpty ? "No Notes" : "No Matches", systemImage: "point.3.connected.trianglepath.dotted",
                                           description: Text(searchText.isEmpty ? "The graph shows notes once the vault is read." : "No file's path contains “\(searchText)”."))
                } else {
                    // The file opened last keeps its highlight, so the graph shows where the person is.
                    GraphCanvas(graph: shownGraph, highlightedIdentifier: workspace.recentFiles.paths.first?.rawValue, forces: forces, showsArrows: showsArrows,
                                alwaysShowsLabels: shownGraph.nodes.count <= 40, previousPositions: workspace.graphPositions,
                                open: { node in Task { await workspace.open(node, from: workspace.recentFiles.paths.first) } },
                                keepPositions: { positions in workspace.graphPositions.merge(positions) { _, newPosition in newPosition } },
                                fitRequest: fitRequest)
                    .overlay(alignment: .bottomLeading) {
                        Text("\(shownGraph.nodes.count == 1 ? "1 item" : "\(shownGraph.nodes.count.formatted()) items") · \(shownGraph.edges.count == 1 ? "1 link" : "\(shownGraph.edges.count.formatted()) links")")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(8).background(.thinMaterial, in: Capsule()).padding(12)
                    }
                }
            } else {
                ProgressView("Reading links…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) { controls }
        .task(id: workspace.indexVersion) {
            vaultGraph = await workspace.vaultGraph()
            shownGraph = vaultGraph?.filtered(by: filters)
        }
        .onChange(of: filters) { shownGraph = vaultGraph?.filtered(by: filters) }
    }

    /// The filter by path, Show All and the settings, over the top of the graph: in a tab the
    /// graph has no bar of its own.
    private var controls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter by path", text: $searchText)
                    .textFieldStyle(.plain)
                    #if canImport(UIKit)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button("Clear Filter", systemImage: "xmark.circle.fill") { searchText = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: 280)
            .background(.regularMaterial, in: Capsule())
            Spacer(minLength: 0)
            Button("Show All", systemImage: "arrow.up.left.and.arrow.down.right") { fitRequest += 1 }
            Button("Graph Settings", systemImage: "slider.horizontal.3") { showsSettings = true }
                .popover(isPresented: $showsSettings) { settings }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(12)
    }

    /// Obsidian's Filters and Forces panels.
    private var settings: some View {
        Form {
            Section("Filters") {
                Toggle("Tags", isOn: $showsTags)
                Toggle("Attachments", isOn: $showsAttachments)
                Toggle("Existing Files Only", isOn: $showsExistingFilesOnly)
                Toggle("Orphans", isOn: $showsOrphans)
            }
            Section("Display") {
                Toggle("Arrows", isOn: $showsArrows)
            }
            Section("Forces") {
                LabeledContent("Center Force") { Slider(value: $centerStrength, in: 0...0.2) }
                LabeledContent("Repel Force") { Slider(value: $repelStrength, in: 20...400) }
                LabeledContent("Link Distance") { Slider(value: $linkDistance, in: 20...200) }
                Button("Restore Defaults") {
                    let defaults = GraphLayout.Forces()
                    linkDistance = defaults.linkDistance; repelStrength = defaults.repelStrength; centerStrength = defaults.centerStrength
                }
            }
        }
        .frame(minWidth: 340, idealWidth: 360, minHeight: 640, idealHeight: 660)
    }
}
