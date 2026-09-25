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
            graphCache = (version, graph)
            return graph
        } catch {
            errorMessage = error.localizedDescription
            return nil
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

/// The graph view's filters and forces, kept on the device as Obsidian keeps them in its
/// workspace.
enum GraphSettingKey {
    static let showsTags = "graphShowsTags"
    static let showsAttachments = "graphShowsAttachments"
    static let showsExistingFilesOnly = "graphShowsExistingFilesOnly"
    static let showsOrphans = "graphShowsOrphans"
    static let showsArrows = "graphShowsArrows"
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
}
