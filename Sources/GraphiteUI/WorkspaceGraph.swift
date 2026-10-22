import Foundation
import GraphiteCore

/// Obsidian's Graph view core plugin.
extension WorkspaceModel {
    /// The vault's notes and links, built again only after the index takes in changes.
    func vaultGraph() async -> LinkGraph? {
        guard let index else { return nil }
        let version = indexVersion
        if let graphCache, graphCache.indexVersion == version { return graphCache.graph }
        do {
            let graph = try await index.linkGraph()
            // A graph of a vault left during the query is neither kept nor shown.
            guard self.index === index else { return nil }
            graphCache = (version, graph)
            return graph
        } catch {
            if self.index === index { errorMessage = error.localizedDescription }
            return nil
        }
    }

    /// Opens a node chosen in the graph's tab beside the graph, which stays where it is: on
    /// the other side of the split, or in the tab next to it.
    func open(_ node: GraphNode, fromGraphTab graphTabID: UUID) async {
        switch node.kind {
        case .note, .attachment:
            guard let path = node.path else { return }
            await open(path, placement: .besideTab(graphTabID))
        case .tag, .unresolved:
            await open(node, from: recentFiles.paths.first ?? .root)
        }
    }

    /// Opens a node's file; tags search for their notes, and links without a file offer
    /// to create it, as following the link would.
    func open(_ node: GraphNode, from source: VaultPath?) async {
        switch node.kind {
        case .note, .attachment:
            guard let path = node.path else { return }
            await open(path)
        case .tag:
            searchQuery = "tag:" + node.id
            searchFocusRequest += 1
        case .unresolved:
            if let source { await follow(node.id, from: source) }
        }
    }
}

/// A node the graph's tab is asked to center on, as when a note's local graph opens the
/// whole graph; each request is new, so asking again for the same note centers on it again.
struct GraphCenterRequest: Equatable {
    let identifier: String
    let token = UUID()
}

/// The graph view's filters, forces and groups, kept on the device as Obsidian keeps them in
/// its workspace; the groups for each vault.
enum GraphSettingKey {
    static let showsTags = "graphShowsTags"
    static let showsAttachments = "graphShowsAttachments"
    static let showsExistingFilesOnly = "graphShowsExistingFilesOnly"
    static let showsOrphans = "graphShowsOrphans"
    static let showsArrows = "graphShowsArrows"
    static let nodeSize = "graphNodeSize"
    static let linkThickness = "graphLinkThickness"
    static let nameScale = "graphNameScale"
    static let linkDistance = "graphLinkDistance"
    static let repelStrength = "graphRepelStrength"
    static let centerStrength = "graphCenterStrength"
    static let localDepth = "localGraphDepth"
    static let localFollowsIncomingLinks = "localGraphFollowsIncomingLinks"
    static let localFollowsOutgoingLinks = "localGraphFollowsOutgoingLinks"
    static let localShowsNeighborLinks = "localGraphShowsNeighborLinks"
    static let localShowsTags = "localGraphShowsTags"
    static let localShowsAttachments = "localGraphShowsAttachments"
    static let localShowsExistingFilesOnly = "localGraphShowsExistingFilesOnly"

    /// A vault's color groups, as the JSON list `GraphColorGroupList` reads.
    static func colorGroups(ofVault vaultIdentifier: UUID) -> String {
        "graphColorGroups." + vaultIdentifier.uuidString
    }

    /// What was kept as a vault's color groups and is not a list of them, kept aside rather
    /// than written over.
    static func unreadableColorGroups(ofVault vaultIdentifier: UUID) -> String {
        colorGroups(ofVault: vaultIdentifier) + ".unreadable"
    }
}

/// The graph's filters before the person changes them: Obsidian's, except that tags are
/// shown, so a vault's tags are in its graph without hunting for the setting.
enum GraphSettingDefault {
    static let showsTags = true
    static let showsAttachments = false
    static let showsExistingFilesOnly = true
    static let showsOrphans = true
    static let showsArrows = false
    static let localDepth = 1
    static let localFollowsIncomingLinks = true
    static let localFollowsOutgoingLinks = true
    static let localShowsNeighborLinks = true
    static let localShowsTags = true
    static let localShowsAttachments = false
    static let localShowsExistingFilesOnly = true
}
