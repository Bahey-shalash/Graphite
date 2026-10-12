import SwiftUI
import GraphiteCore

/// Plugins' views (`registerView`, `ItemView`) where Graphite keeps its own: a view a plugin
/// puts in one of Obsidian's sidebars is a panel of Graphite's sidebar, any other is a tab.
/// The view lives in the plugins' page, laid out at the size of its tab or panel; Graphite
/// shows a copy of it, as it shows plugins' code blocks, and sends taps, typing and keys back.
extension CommunityPluginHost {
    /// The plugin views that belong in the sidebar.
    var sidebarViews: [CommunityPluginView] { pluginViews.filter { view in view.placement == .sidebar } }

    func pluginView(withIdentifier identifier: String) -> CommunityPluginView? {
        pluginViews.first { view in view.id == identifier }
    }

    /// Shows a view where it belongs, as `revealLeaf` asks.
    func revealView(_ identifier: String) {
        guard let view = pluginView(withIdentifier: identifier) else { return }
        switch view.placement {
        case .sidebar: sidebarViewRequest = CommunityPluginSidebarRequest(viewIdentifier: identifier)
        case .tab: workspace?.openPluginViewInTab(identifier)
        }
    }

    /// Closes a view, as closing its tab or panel does in Obsidian.
    func closeView(_ identifier: String) {
        guard isRuntimeRunning else { return }
        Task { _ = try? await send(["operation": "view.close", "leafIdentifier": identifier], timeout: .seconds(5)) }
    }
}

extension WorkspaceModel {
    /// Shows a plugin view in a tab: the tab already showing it, else the empty tab in use,
    /// else a new tab.
    func openPluginViewInTab(_ identifier: String) {
        if let tabID = tabDocuments.first(where: { entry in entry.value.pluginViewIdentifier == identifier })?.key, layout.tab(withID: tabID) != nil {
            activateTab(tabID)
            return
        }
        let activeTab = layout.activeTab
        if activeTab.path != nil || document(for: activeTab.id).pluginViewIdentifier != nil { openNewTab() }
        document(for: layout.activeTab.id).pluginViewIdentifier = identifier
    }

    /// Tabs whose plugin view a plugin closed (or that unloaded) become empty tabs.
    func forgetClosedPluginViews(keeping identifiers: Set<String>) {
        for document in tabDocuments.values {
            if let identifier = document.pluginViewIdentifier, !identifiers.contains(identifier) { document.pluginViewIdentifier = nil }
        }
    }
}

/// Graphite's symbol for a plugin view's Lucide icon, for the sidebar's picker and tabs.
enum CommunityPluginViewSymbol {
    private static let symbolsByIconName: [String: String] = [
        "calendar": "calendar", "calendar-days": "calendar", "calendar-with-checkmark": "calendar.badge.checkmark", "calendar-check": "calendar.badge.checkmark",
        "clock": "clock", "history": "clock.arrow.circlepath", "file": "doc", "document": "doc", "files": "doc.on.doc", "folder": "folder",
        "list": "list.bullet", "list-checks": "checklist", "check-square": "checkmark.square", "star": "star", "bookmark": "bookmark",
        "tag": "tag", "tags": "tag", "hashtag": "number", "search": "magnifyingglass", "settings": "gearshape", "gear": "gearshape",
        "paintbrush": "paintbrush", "palette": "paintpalette", "brush": "paintbrush", "table": "tablecells", "kanban": "rectangle.split.3x1",
        "network": "point.3.connected.trianglepath.dotted", "git-fork": "arrow.triangle.branch", "pencil": "pencil", "book": "book",
        "image": "photo", "map": "map", "graph": "chart.xyaxis.line", "bar-chart": "chart.bar", "lines-of-text": "text.alignleft",
    ]

    static func systemImage(forIcon iconName: String) -> String {
        let name = iconName.hasPrefix("lucide-") ? String(iconName.dropFirst("lucide-".count)) : iconName
        return symbolsByIconName[name] ?? "puzzlepiece.extension"
    }
}

/// A plugin's view, filling its tab or sidebar panel: the copy of what the plugin drew,
/// scrolling inside like the plugin's own view.
struct CommunityPluginViewContent: View {
    let host: CommunityPluginHost
    let viewIdentifier: String
    @State private var shownView: CommunityPluginShownCodeBlock?
    @State private var size: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accent) private var accent
    /// Obsidian's interface text size, 15 points, grown and shrunk with the system's text size.
    @ScaledMetric(relativeTo: .body) private var scaledTextSize: Double = 15

    var body: some View {
        Group {
            switch shownView?.appearance ?? .drawing {
            case .drawn(let html):
                if let shownView {
                    CommunityPluginCodeBlockDisplay(block: shownView, html: html, styleSheets: host.pluginStyleSheets, isDark: colorScheme == .dark,
                                                    textSize: scaledTextSize, accentHex: accent.sRGBHex, fillsSpace: true,
                                                    bodyClasses: host.pluginBodyClasses, bodyStyle: host.pluginBodyStyle, hasTheme: !host.activeThemeName.isEmpty)
                }
            case .failed(let message):
                ContentUnavailableView(message, systemImage: "puzzlepiece.extension")
            case .drawing, .unchanged:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { geometry in geometry.size } action: { newSize in size = newSize }
        .task(id: AttachmentKey(viewIdentifier: viewIdentifier, hasSize: size.width > 0 && size.height > 0)) {
            guard size.width > 0, size.height > 0 else { return }
            let view = shownView ?? CommunityPluginShownCodeBlock(host: host)
            shownView = view
            await view.attachView(viewIdentifier, size: size)
        }
        .onChange(of: size) { _, newSize in shownView?.resizeView(to: newSize) }
        .onDisappear {
            shownView?.release()
            shownView = nil
        }
    }

    private struct AttachmentKey: Equatable {
        let viewIdentifier: String
        let hasSize: Bool
    }
}
