import SwiftUI
import GraphiteCore

/// Obsidian's local graph: the open note and the notes around it, in the right sidebar.
struct LocalGraphPanel: View {
    let session: MarkdownSession
    @Bindable var workspace: WorkspaceModel
    @AppStorage(GraphSettingKey.localDepth) private var depth = GraphSettingDefault.localDepth
    @AppStorage(GraphSettingKey.localFollowsIncomingLinks) private var followsIncomingLinks = GraphSettingDefault.localFollowsIncomingLinks
    @AppStorage(GraphSettingKey.localFollowsOutgoingLinks) private var followsOutgoingLinks = GraphSettingDefault.localFollowsOutgoingLinks
    @AppStorage(GraphSettingKey.localShowsNeighborLinks) private var showsNeighborLinks = GraphSettingDefault.localShowsNeighborLinks
    @AppStorage(GraphSettingKey.localShowsTags) private var showsTags = GraphSettingDefault.localShowsTags
    @AppStorage(GraphSettingKey.localShowsAttachments) private var showsAttachments = GraphSettingDefault.localShowsAttachments
    @AppStorage(GraphSettingKey.localShowsExistingFilesOnly) private var showsExistingFilesOnly = GraphSettingDefault.localShowsExistingFilesOnly
    @State private var vaultGraph: LinkGraph?
    @State private var fitRequest = 0
    @State private var chosenTag: String?
    @State private var groupColoring = GraphGroupColoring()

    private var colorGroupStore: GraphColorGroupStore { workspace.processServices.graphColorGroups }

    /// The open vault's groups, which color the local graph as they color the whole graph.
    private var colorGroups: [GraphColorGroup] {
        workspace.currentVaultIdentifier.map(colorGroupStore.groups(ofVault:)) ?? []
    }

    private var localGraph: LinkGraph? {
        guard let vaultGraph else { return nil }
        let filters = GraphFilterOptions(showsTags: showsTags, showsAttachments: showsAttachments, showsExistingFilesOnly: showsExistingFilesOnly)
        let options = LocalGraphOptions(depth: depth, followsIncomingLinks: followsIncomingLinks, followsOutgoingLinks: followsOutgoingLinks, showsNeighborLinks: showsNeighborLinks)
        return vaultGraph.filtered(by: filters).neighborhood(of: session.path.rawValue, options: options)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let localGraph {
                if localGraph.nodes.count <= 1 {
                    ContentUnavailableView("No Links", systemImage: "point.3.connected.trianglepath.dotted",
                                           description: Text(workspace.hasCompletedIndexScan ? "This note has no links yet, in either direction." : "Still reading the vault."))
                } else {
                    GraphCanvas(graph: localGraph, highlightedIdentifier: session.path.rawValue, alwaysShowsLabels: localGraph.nodes.count <= 60,
                                open: { node in Task { await workspace.open(node, from: session.path) } }, fitRequest: fitRequest, chosenTag: $chosenTag,
                                groupColoring: groupColoring)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: workspace.currentVaultIdentifier) {
            if let vaultIdentifier = workspace.currentVaultIdentifier { colorGroupStore.loadGroups(ofVault: vaultIdentifier) }
        }
        .task(id: workspace.indexVersion) {
            vaultGraph = await workspace.vaultGraph()
            recolor()
        }
        .onChange(of: colorGroups) { recolor() }
    }

    /// The depth, Show All, the way to the whole graph and the filters, over the graph.
    private var header: some View {
        HStack {
            Stepper("Depth \(depth)", value: $depth, in: 1...5).fixedSize()
            Spacer()
            Button("Show All", systemImage: "arrow.up.left.and.arrow.down.right") { fitRequest += 1 }
                .labelStyle(.iconOnly)
            Button("Show in Graph View", systemImage: "point.3.connected.trianglepath.dotted") { workspace.showGraph(centeredOn: session.path) }
                .labelStyle(.iconOnly)
                .help("Show in Graph View")
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
    }

    /// Colors the files as the vault's groups match them, over the whole vault's graph.
    private func recolor() {
        groupColoring = vaultGraph.map { graph in GraphGroupColoring(groups: colorGroups, vaultGraph: graph) } ?? GraphGroupColoring()
    }
}

/// Obsidian's graph view of the whole vault, in a tab of its own: it stays open, beside a
/// note in a split if the person likes, while notes are opened from it.
struct VaultGraphView: View {
    @Bindable var workspace: WorkspaceModel
    /// The graph's tab, which notes opened from the graph leave in place.
    let tabID: UUID
    /// The tab's document, which keeps the filter while other tabs are in front, and
    /// carries a request to center on a note.
    @Bindable var document: TabDocument
    @AppStorage(GraphSettingKey.showsTags) private var showsTags = GraphSettingDefault.showsTags
    @AppStorage(GraphSettingKey.showsAttachments) private var showsAttachments = GraphSettingDefault.showsAttachments
    @AppStorage(GraphSettingKey.showsExistingFilesOnly) private var showsExistingFilesOnly = GraphSettingDefault.showsExistingFilesOnly
    @AppStorage(GraphSettingKey.showsOrphans) private var showsOrphans = GraphSettingDefault.showsOrphans
    @AppStorage(GraphSettingKey.showsArrows) private var showsArrows = GraphSettingDefault.showsArrows
    @AppStorage(GraphSettingKey.nodeSize) private var nodeSizeMultiplier = GraphDisplayOptions().nodeSizeMultiplier
    @AppStorage(GraphSettingKey.linkThickness) private var linkThicknessMultiplier = GraphDisplayOptions().linkThicknessMultiplier
    @AppStorage(GraphSettingKey.nameScale) private var nameScale = GraphDisplayOptions().nameScale
    @AppStorage(GraphSettingKey.linkDistance) private var linkDistance = GraphLayout.Forces().linkDistance
    @AppStorage(GraphSettingKey.repelStrength) private var repelStrength = GraphLayout.Forces().repelStrength
    @AppStorage(GraphSettingKey.centerStrength) private var centerStrength = GraphLayout.Forces().centerStrength
    @State private var vaultGraph: LinkGraph?
    @State private var shownGraph: LinkGraph?
    @State private var showsSettings = false
    @State private var fitRequest = 0
    @State private var groupColoring = GraphGroupColoring()

    private var filters: GraphFilterOptions {
        GraphFilterOptions(searchText: document.graphFilterText, showsTags: showsTags, showsAttachments: showsAttachments,
                           showsExistingFilesOnly: showsExistingFilesOnly, showsOrphans: showsOrphans)
    }

    private var colorGroupStore: GraphColorGroupStore { workspace.processServices.graphColorGroups }

    /// The open vault's groups, in the order they win in.
    private var colorGroups: [GraphColorGroup] {
        workspace.currentVaultIdentifier.map(colorGroupStore.groups(ofVault:)) ?? []
    }

    private var forces: GraphLayout.Forces {
        GraphLayout.Forces(linkDistance: linkDistance, repelStrength: repelStrength, centerStrength: centerStrength)
    }

    private var display: GraphDisplayOptions {
        GraphDisplayOptions(nodeSizeMultiplier: nodeSizeMultiplier, linkThicknessMultiplier: linkThicknessMultiplier, nameScale: nameScale)
    }

    var body: some View {
        Group {
            if let shownGraph {
                if shownGraph.nodes.isEmpty {
                    let filterText = document.graphFilterText
                    ContentUnavailableView(filterText.isEmpty ? "No Notes" : "No Matches", systemImage: "point.3.connected.trianglepath.dotted",
                                           description: Text(filterText.isEmpty ? "The graph shows notes once the vault is read." : "No file matches “\(filterText)”."))
                } else {
                    // The file opened last keeps its highlight, so the graph shows where the person is.
                    GraphCanvas(graph: shownGraph, highlightedIdentifier: workspace.recentFiles.paths.first?.rawValue, forces: forces, showsArrows: showsArrows,
                                alwaysShowsLabels: shownGraph.nodes.count <= 40, previousPositions: workspace.graphPositions,
                                open: { node in Task { await workspace.open(node, fromGraphTab: tabID) } },
                                keepPositions: { positions in workspace.graphPositions.merge(positions) { _, newPosition in newPosition } },
                                fitRequest: fitRequest, centerRequest: document.graphCenterRequest, chosenTag: $document.graphChosenTag,
                                groupColoring: groupColoring, display: display, keptPlace: $document.graphPlace)
                    .overlay(alignment: .bottomLeading) {
                        Text(shownGraph.counts.summary)
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
        .task(id: workspace.currentVaultIdentifier) {
            if let vaultIdentifier = workspace.currentVaultIdentifier { colorGroupStore.loadGroups(ofVault: vaultIdentifier) }
        }
        .task(id: workspace.indexVersion) {
            vaultGraph = await workspace.vaultGraph()
            shownGraph = vaultGraph?.filtered(by: filters)
            recolor()
        }
        .onChange(of: filters) { shownGraph = vaultGraph?.filtered(by: filters) }
        .onChange(of: colorGroups) { recolor() }
    }

    /// Colors the files as the vault's groups match them, over the whole vault's graph.
    private func recolor() {
        groupColoring = vaultGraph.map { graph in GraphGroupColoring(groups: colorGroups, vaultGraph: graph) } ?? GraphGroupColoring()
    }

    /// The filter by path, Show All and the settings, over the top of the graph: in a tab the
    /// graph has no bar of its own.
    private var controls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter by path or tag:", text: $document.graphFilterText)
                    .textFieldStyle(.plain)
                    #if canImport(UIKit)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                if !document.graphFilterText.isEmpty {
                    Button("Clear Filter", systemImage: "xmark.circle.fill") { document.graphFilterText = "" }
                        .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: 280)
            .background(.regularMaterial, in: Capsule())
            Spacer(minLength: 0)
            // Tags on and off without opening the settings; the same setting as theirs.
            Toggle("Tags", systemImage: "number", isOn: $showsTags)
                .toggleStyle(.button)
                .help(showsTags ? "Hide Tags" : "Show Tags")
            Button("Show All", systemImage: "arrow.up.left.and.arrow.down.right") { fitRequest += 1 }
            Button("Graph Settings", systemImage: "slider.horizontal.3") { showsSettings = true }
                .popover(isPresented: $showsSettings) { settings }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(12)
    }

    /// Obsidian's Filters, Groups, Display and Forces panels.
    private var settings: some View {
        Form {
            Section("Filters") {
                Toggle("Tags", isOn: $showsTags)
                Toggle("Attachments", isOn: $showsAttachments)
                Toggle("Existing Files Only", isOn: $showsExistingFilesOnly)
                Toggle("Orphans", isOn: $showsOrphans)
            }
            if let vaultIdentifier = workspace.currentVaultIdentifier {
                GraphColorGroupsSection(groups: colorGroups, addGroup: { colorGroupStore.addGroup(toVault: vaultIdentifier) },
                                        update: { group in colorGroupStore.update(group, inVault: vaultIdentifier) },
                                        removeGroup: { identifier in colorGroupStore.removeGroup(identifiedBy: identifier, fromVault: vaultIdentifier) })
            }
            displaySettings
            forceSettings
        }
        .frame(minWidth: 360, idealWidth: 380, minHeight: 640, idealHeight: 760)
    }

    private var displaySettings: some View {
        Section {
            Toggle("Arrows", isOn: $showsArrows)
            LabeledContent("Names From Zoom") { Slider(value: $nameScale, in: GraphDisplayOptions.nameScales) }
            LabeledContent("Node Size") { Slider(value: $nodeSizeMultiplier, in: GraphDisplayOptions.nodeSizeMultipliers) }
            LabeledContent("Link Thickness") { Slider(value: $linkThicknessMultiplier, in: GraphDisplayOptions.linkThicknessMultipliers) }
            Button("Restore Defaults") {
                let defaults = GraphDisplayOptions()
                nameScale = defaults.nameScale
                nodeSizeMultiplier = defaults.nodeSizeMultiplier
                linkThicknessMultiplier = defaults.linkThicknessMultiplier
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Names show from this zoom, tags' from half of it: further right, closer in. Obsidian calls it the text fade threshold.")
        }
    }

    private var forceSettings: some View {
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
}

extension LinkGraph.Counts {
    /// What the graph's corner says it shows, "4,700 notes · 699 tags · 1,690 links";
    /// attachments, tags and link targets without a file only when there are some.
    var summary: String {
        var parts = [Self.counted(notes, one: "note", many: "notes")]
        if attachments > 0 { parts.append(Self.counted(attachments, one: "attachment", many: "attachments")) }
        if tags > 0 { parts.append(Self.counted(tags, one: "tag", many: "tags")) }
        if unresolved > 0 { parts.append(Self.counted(unresolved, one: "unresolved", many: "unresolved")) }
        parts.append(Self.counted(links, one: "link", many: "links"))
        return parts.joined(separator: " · ")
    }

    private static func counted(_ count: Int, one: String, many: String) -> String {
        count == 1 ? "1 " + one : count.formatted() + " " + many
    }
}
