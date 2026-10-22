import SwiftUI
import WebKit
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
    func revealView(_ identifier: String, replacesCurrentTab: Bool = false) {
        guard let view = pluginView(withIdentifier: identifier) else { return }
        switch view.placement {
        case .sidebar: sidebarViewRequest = CommunityPluginSidebarRequest(viewIdentifier: identifier)
        case .tab:
            if replacesCurrentTab { Task { await workspace?.openPluginViewInCurrentTab(identifier) } } else { workspace?.openPluginViewInTab(identifier) }
        case .split: workspace?.openPluginViewBeside(identifier)
        }
    }

    // MARK: Files in plugins' views

    /// Whether a plugin may show this file in a view of its own: its extension is registered,
    /// or it is a note and a plugin shows some notes in its own view.
    func mayShowInPluginView(_ path: VaultPath) -> Bool {
        guard isRuntimeRunning else { return false }
        let fileExtension = (path.name as NSString).pathExtension.lowercased()
        if fileExtension == "md" { return pluginsTakeOverNotes }
        return pluginFileExtensions[fileExtension] != nil
    }

    /// Asks the plugins to open the file in their view; the leaf's identifier when one did.
    /// A plugin that takes too long leaves the file to Graphite.
    func openFileInPluginView(_ path: VaultPath) async -> String? {
        guard mayShowInPluginView(path),
              let answer = try? await send(["operation": "file.openInView", "path": path.rawValue], timeout: .seconds(3)),
              answer["isOpened"] as? Bool == true, let identifier = answer["leafIdentifier"] as? String else { return nil }
        // The view list arrives right after; until then the tab knows the view by its identifier.
        if pluginView(withIdentifier: identifier) == nil {
            pluginViews.append(CommunityPluginView(id: identifier, title: (path.name as NSString).deletingPathExtension, viewType: "",
                                                   icon: "file", placement: .tab, isLive: true, filePath: path.rawValue))
        }
        return identifier
    }

    /// Asks plugins' views of files to save what they hold now (Graphite is leaving the screen,
    /// and iOS may end it before their own autosave). Waits a few seconds at most.
    func saveOpenFileViews() async {
        guard isRuntimeRunning, pluginViews.contains(where: \.isLive) else { return }
        _ = try? await send(["operation": "views.saveFiles"], timeout: .seconds(4))
    }

    // MARK: Live views

    /// Shows the view live: its tab shows the runtime's own web view, where the leaf fills
    /// the page. Another view shown live before goes back to being a copy.
    func showLive(_ identifier: String) async -> Bool {
        guard isRuntimeRunning else { return false }
        // The view giving up the web view leaves a picture of itself in its tab, which may
        // still be on screen beside this one.
        if let previous = liveViewIdentifier, previous != identifier, let webView, webView.window != nil,
           ContinuousClock.now - liveViewChangeTime > .seconds(1.5),
           let picture = await CommunityPluginViewPicture.taken(of: webView) {
            liveViewPictures[previous] = picture
        }
        liveViewPictures[identifier] = nil
        if liveViewIdentifier != identifier { liveViewChangeTime = .now }
        liveViewIdentifier = identifier
        let answer = try? await send(["operation": "view.live", "leafIdentifier": identifier], timeout: .seconds(5))
        return answer?["isShown"] as? Bool == true
    }

    /// Where a frame the plugins' page measured is in the window showing the page, as a live
    /// view; nil while the page is in no window.
    func windowFrame(ofPageFrame pageFrame: CGRect) -> CGRect? {
        guard let webView, webView.window != nil else { return nil }
        return webView.convert(pageFrame, to: nil)
    }

    /// The live view's tab went away: the page shows the plugins' panel content again.
    func hideLive(_ identifier: String) {
        guard liveViewIdentifier == identifier else { return }
        liveViewIdentifier = nil
        guard isRuntimeRunning else { return }
        Task { _ = try? await send(["operation": "view.unlive", "leafIdentifier": identifier], timeout: .seconds(5)) }
    }

    // MARK: Paste and drop

    /// Offers a paste into the focused note to plugins that listen (`editor-paste`); true when
    /// one took it over. A plugin that does not answer in time leaves the paste to Graphite.
    func offerPaste(into session: MarkdownSession, text: String?, html: String?) async -> Bool {
        guard isRuntimeRunning, hasPasteListeners, workspace?.markdownSession === session else { return false }
        var message: [String: Any] = ["operation": "editor.paste", "activeDocument": activeDocumentDescription(includingEditor: true)]
        if let text { message["text"] = text }
        if let html { message["html"] = html }
        let answer = try? await send(message, timeout: .milliseconds(1500))
        return answer?["isHandled"] as? Bool == true
    }

    /// Offers a drop on the focused note to plugins that listen (`editor-drop`), with the
    /// dropped files' names and types; true when one took it over.
    func offerDrop(into session: MarkdownSession, files: [(name: String, type: String)], text: String?) async -> Bool {
        guard isRuntimeRunning, hasDropListeners, workspace?.markdownSession === session else { return false }
        var message: [String: Any] = ["operation": "editor.drop", "activeDocument": activeDocumentDescription(includingEditor: true),
                                      "files": files.map { file in ["name": file.name, "type": file.type] }]
        if let text { message["text"] = text }
        let answer = try? await send(message, timeout: .milliseconds(1500))
        return answer?["isHandled"] as? Bool == true
    }

    // MARK: Bases views from plugins

    /// Makes a plugin's view of a base's results; the leaf to show live.
    func openBasesView(type viewType: String, viewName: String, viewIndex: Int, source: BaseSource, result: BaseQueryResult) async -> String? {
        guard isRuntimeRunning, pluginBasesViews[viewType] != nil else { return nil }
        var message = Self.basesMessage(result)
        message.merge(["operation": "basesView.open", "viewType": viewType, "viewName": viewName, "viewIndex": viewIndex]) { _, new in new }
        switch source {
        case .file(let path): message["baseFilePath"] = path.rawValue
        case .inline(let yaml): message["baseYaml"] = yaml
        }
        guard let answer = try? await send(message, timeout: .seconds(10)), answer["isOpened"] as? Bool == true else { return nil }
        return answer["leafIdentifier"] as? String
    }

    func updateBasesView(_ identifier: String, result: BaseQueryResult) {
        guard isRuntimeRunning else { return }
        var message = Self.basesMessage(result)
        message["operation"] = "basesView.update"
        message["leafIdentifier"] = identifier
        Task { _ = try? await send(message, timeout: .seconds(10)) }
    }

    /// The base's matching files by group, and its columns: the plugin reads each file's
    /// values from the vault's metadata itself.
    static func basesMessage(_ result: BaseQueryResult) -> [String: Any] {
        let groups: [[String: Any]] = result.groups.map { group in
            ["key": group.key?.value.map { value in value.displayText as Any } ?? NSNull(), "paths": group.rows.map(\.path.rawValue)]
        }
        // Formulas are evaluated by Graphite, as its own views show them; a plugin's view reads
        // each file's values of the view's formula columns.
        var formulaValues: [String: [String: Any]] = [:]
        let formulaColumns = result.columns.enumerated().filter { _, column in
            if case .formula = column.property { return true }
            return false
        }
        if !formulaColumns.isEmpty {
            for row in result.rows {
                var values: [String: Any] = [:]
                for (columnIndex, column) in formulaColumns where row.cells.indices.contains(columnIndex) {
                    values[column.property.rawValue] = row.cells[columnIndex].value.map(pluginValue) ?? ["type": "null"]
                }
                formulaValues[row.path.rawValue] = values
            }
        }
        return ["groups": groups, "properties": result.columns.map { column in column.property.rawValue }, "formulaValues": formulaValues]
    }

    /// A base value as the runtime makes Obsidian's Bases values of it (`community-plugin-runtime-bases.js`).
    static func pluginValue(_ value: BaseValue) -> [String: Any] {
        switch value {
        case .null: return ["type": "null"]
        case .boolean(let boolean): return ["type": "boolean", "value": boolean]
        case .number(let number): return number.isFinite ? ["type": "number", "value": number] : ["type": "null"]
        case .string(let text): return ["type": "string", "value": text]
        case .date(let date): return ["type": "date", "value": date.date.timeIntervalSince1970 * 1000, "hasTime": date.hasTime]
        case .list(let values): return ["type": "list", "value": values.map(pluginValue)]
        case .link(let link): return ["type": "link", "value": "[[" + link.target + (link.display.map { display in "|" + display } ?? "") + "]]"]
        case .file(let path): return ["type": "file", "value": path.rawValue]
        case .object(let object): return ["type": "object", "value": object.entries.map { entry in [entry.key, pluginValue(entry.value)] as [Any] }]
        case .duration, .regularExpression, .image, .icon, .html: return ["type": "string", "value": value.displayText]
        }
    }

    /// Opens a view saved when Graphite last closed; the new leaf's identifier, or nil when no
    /// plugin shows that type of view now.
    func restoreView(_ savedView: SavedTabLayout.PluginView, inSidebar: Bool) async -> String? {
        guard isRuntimeRunning,
              let answer = try? await send(["operation": "view.restore", "viewType": savedView.viewType, "state": savedView.state,
                                            "placement": inSidebar ? "right" : "tab"], timeout: .seconds(10)),
              answer["isOpened"] as? Bool == true, let identifier = answer["leafIdentifier"] as? String else { return nil }
        return identifier
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
        if activeTab.path != nil || activeTab.coreView != nil || document(for: activeTab.id).pluginViewIdentifier != nil { openNewTab() }
        show(pluginView: identifier, inTab: layout.activeTab.id)
    }

    /// Shows a plugin view in the focused tab in place of what the tab shows, as a view opened
    /// "in the current tab" replaces it in Obsidian. The tab's work is saved first; when it
    /// cannot be saved the tab stays as it is. A pinned tab keeps its file, and the view opens
    /// in a tab beside it.
    func openPluginViewInCurrentTab(_ identifier: String) async {
        let replacedTab = layout.activeTab
        guard replacedTab.path != nil, !replacedTab.isPinned else {
            openPluginViewInTab(identifier)
            return
        }
        guard await saveBeforeClosing([replacedTab.id]) else { return }
        // The replaced tab closes only if the person has not moved on to another meanwhile.
        guard layout.tab(withID: replacedTab.id)?.path == replacedTab.path else { return }
        let viewTabID = layout.addTab()
        show(pluginView: identifier, inTab: viewTabID)
        layout.closeTab(replacedTab.id)
        removeTabDocuments([replacedTab.id])
    }

    private func show(pluginView identifier: String, inTab tabID: UUID) {
        let document = document(for: tabID)
        document.pluginViewIdentifier = identifier
        document.restorablePluginView = communityPlugins.pluginView(withIdentifier: identifier).flatMap(Self.restorable)
        saveTabLayout()
    }

    /// Shows a plugin view on the other side of the split, leaving the note where it is and
    /// still the focused document, as a split beside it in Obsidian (Mind Map follows the note).
    func openPluginViewBeside(_ identifier: String) {
        if let tabID = tabDocuments.first(where: { entry in entry.value.pluginViewIdentifier == identifier })?.key, layout.tab(withID: tabID) != nil {
            revealTab(tabID)
            return
        }
        let previousTabID = layout.activeTab.id
        let tabID = layout.tabForOpeningInOtherGroup()
        show(pluginView: identifier, inTab: tabID)
        if layout.tab(withID: previousTabID) != nil { activateTab(previousTabID) }
    }

    /// The plugins' views changed: tabs whose view a plugin closed (or that unloaded) become
    /// empty tabs, and what opens the others again after a restart is brought up to date.
    /// A view closed because the runtime stops is not forgotten.
    func pluginViewsDidChange() {
        let host = communityPlugins
        for document in tabDocuments.values {
            guard let identifier = document.pluginViewIdentifier else { continue }
            if let view = host.pluginView(withIdentifier: identifier) {
                if let restorable = Self.restorable(view) { document.restorablePluginView = restorable }
            } else {
                host.liveViewPictures[identifier] = nil
                document.pluginViewIdentifier = nil
                // Plugins that unload close their views too; those views open again with them.
                if !host.runtimePhase.isStopping { document.restorablePluginView = nil }
            }
        }
        if host.hasRestoredViews {
            restorableSidebarPluginViews = (host.sidebarViews.compactMap(Self.restorable),
                                            host.shownSidebarViewIdentifier.flatMap(host.pluginView(withIdentifier:))?.viewType)
        }
        saveTabLayout()
    }

    /// What opens a view again: its type and state, once the plugin has given them.
    private static func restorable(_ view: CommunityPluginView) -> SavedTabLayout.PluginView? {
        guard !view.viewType.isEmpty, let state = view.state else { return nil }
        return SavedTabLayout.PluginView(viewType: view.viewType, state: state)
    }

    // MARK: Restoring views after a restart

    /// The layout to save: empty tabs keep the plugin views they show, and the sidebar its
    /// plugins' views, as Obsidian's workspace does.
    func savedLayoutWithPluginViews() -> SavedTabLayout {
        var saved = layout.saved
        for (groupIndex, group) in layout.groups.enumerated() where saved.groups.indices.contains(groupIndex) {
            for (tabIndex, tab) in group.tabs.enumerated() where tab.path == nil && saved.groups[groupIndex].tabs.indices.contains(tabIndex) {
                saved.groups[groupIndex].tabs[tabIndex].pluginView = tabDocuments[tab.id]?.restorablePluginView
            }
        }
        if !restorableSidebarPluginViews.views.isEmpty {
            saved.sidebarPluginViews = restorableSidebarPluginViews.views
            saved.shownSidebarPluginViewType = restorableSidebarPluginViews.shownViewType
        }
        return saved
    }

    /// Keeps the restored layout's plugin views until their plugins load.
    func takePluginViewsToRestore(from saved: SavedTabLayout) {
        for (tabID, pluginView) in layout.pluginViewsToRestore { document(for: tabID).restorablePluginView = pluginView }
        restorableSidebarPluginViews = (saved.sidebarPluginViews ?? [], saved.shownSidebarPluginViewType)
    }

    /// Opens the plugin views Graphite showed when it last closed, once the plugins have
    /// loaded: each empty tab's view in its tab, and sidebar views their plugins did not open
    /// again themselves. A view no plugin shows now leaves its tab empty.
    func restorePluginViews() async {
        let host = communityPlugins
        defer {
            host.hasRestoredViews = true
            pluginViewsDidChange()
        }
        for group in layout.groups {
            for tab in group.tabs where tab.path == nil {
                guard let document = tabDocuments[tab.id], document.pluginViewIdentifier == nil, let savedView = document.restorablePluginView else { continue }
                let identifier = await host.restoreView(savedView, inSidebar: false)
                // The tab may have closed, or a file opened in it, meanwhile.
                guard layout.tab(withID: tab.id)?.path == nil, tabDocuments[tab.id] === document else {
                    if let identifier { host.closeView(identifier) }
                    continue
                }
                if let identifier {
                    document.pluginViewIdentifier = identifier
                } else {
                    document.restorablePluginView = nil
                }
            }
        }
        let savedSidebar = restorableSidebarPluginViews
        for savedView in savedSidebar.views where !host.sidebarViews.contains(where: { view in view.viewType == savedView.viewType }) {
            if let identifier = await host.restoreView(savedView, inSidebar: true), host.pluginView(withIdentifier: identifier) == nil {
                // The view list arrives right after; until then the sidebar knows the view by its identifier.
                host.pluginViews.append(CommunityPluginView(id: identifier, title: "", viewType: savedView.viewType, icon: "", placement: .sidebar, state: savedView.state))
            }
        }
        if host.shownSidebarViewIdentifier == nil, let shownViewType = savedSidebar.shownViewType {
            host.shownSidebarViewIdentifier = host.sidebarViews.first { view in view.viewType == shownViewType }?.id
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
    /// Whether the view's tab is on the focused side of the split (a sidebar panel is not).
    var isInFocusedGroup = true
    @State private var shownView: CommunityPluginShownCodeBlock?
    @State private var size: CGSize = .zero
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accent) private var accent
    /// Obsidian's interface text size, 15 points, grown and shrunk with the system's text size.
    @ScaledMetric(relativeTo: .body) private var scaledTextSize: Double = 15

    var body: some View {
        if host.pluginView(withIdentifier: viewIdentifier)?.isLive == true {
            CommunityPluginLiveViewContent(host: host, viewIdentifier: viewIdentifier, isInFocusedGroup: isInFocusedGroup)
        } else {
            copyContent
        }
    }

    private var copyContent: some View {
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


/// A plugin view shown live: the tab shows the runtime's own web view, where the view's leaf
/// fills the page, so touches, Pencil, drags, gestures and typing reach the plugin directly
/// (Excalidraw draws, Fountain edits its script). There is one web view per vault, so one
/// view is live at a time; the plugin panel and a plugin's settings page take the web view
/// while they show, and the tab takes it back after.
struct CommunityPluginLiveViewContent: View {
    let host: CommunityPluginHost
    let viewIdentifier: String
    /// A live view on the side not focused does not take the web view from one already
    /// shown as it appears (both sides restored at launch); a tap there takes it.
    var isInFocusedGroup = true
    @Environment(\.linkPreviews) private var linkPreviews

    var body: some View {
        Group {
            if host.liveViewIdentifier == viewIdentifier {
                CommunityPluginLiveWebView(host: host, isPanelPresented: host.isPanelPresented, releaseCount: host.webViewReleaseCount)
            } else if let picture = host.liveViewPictures[viewIdentifier] {
                // Two live views on screen at once (a split): the one not holding the web view
                // shows how it looked, and a tap swaps them, each keeping its state in the page.
                Button { Task { _ = await host.showLive(viewIdentifier) } } label: {
                    // At the size it was taken, in points: the tab rarely changes size meanwhile.
                    picture.image
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
                        .overlay(alignment: .bottom) {
                            Label("Tap to Use This View", systemImage: "hand.tap")
                                .font(.callout).padding(.horizontal, 14).padding(.vertical, 8)
                                .background(.regularMaterial, in: Capsule()).padding(.bottom, 24)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(host.pluginView(withIdentifier: viewIdentifier)?.title ?? "Plugin view"), shown as a picture")
                .accessibilityHint("Makes this view usable; the other plugin view becomes a picture.")
            } else {
                ContentUnavailableView {
                    Label(host.pluginView(withIdentifier: viewIdentifier)?.title ?? "Plugin View", systemImage: "rectangle.on.rectangle")
                } description: {
                    Text("This view is in use in another tab or beside this one.")
                } actions: {
                    Button("Show Here") { Task { _ = await host.showLive(viewIdentifier) } }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: viewIdentifier) {
            if !isInFocusedGroup, let shownView = host.liveViewIdentifier, shownView != viewIdentifier { return }
            _ = await host.showLive(viewIdentifier)
        }
        // Links the plugin asks to preview here show this window's cards.
        .onChange(of: linkPreviews.map(ObjectIdentifier.init), initial: true) { host.useLinkPreviews(linkPreviews, forLiveView: viewIdentifier) }
        .onDisappear {
            host.useLinkPreviews(nil, forLiveView: viewIdentifier)
            host.hideLive(viewIdentifier)
        }
    }
}

/// The runtime's web view in a live view's tab, unless the plugin panel has it.
@MainActor
struct CommunityPluginLiveWebView {
    let host: CommunityPluginHost
    let isPanelPresented: Bool
    let releaseCount: Int

    final class Coordinator {
        let host: CommunityPluginHost
        init(host: CommunityPluginHost) { self.host = host }
    }

    func makeCoordinator() -> Coordinator { Coordinator(host: host) }

    fileprivate func place(in container: CommunityPluginPlatformView) {
        guard !isPanelPresented, let webView = host.webView else { return }
        CommunityPluginWebViewPlacement.show(webView, in: container)
    }
}

#if canImport(UIKit)
extension CommunityPluginLiveWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        place(in: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) { place(in: container) }

    static func dismantleUIView(_ container: UIView, coordinator: Coordinator) {
        for subview in container.subviews { subview.removeFromSuperview() }
        coordinator.host.parkWebViewIfDetached()
    }
}
#elseif canImport(AppKit)
extension CommunityPluginLiveWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        place(in: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) { place(in: container) }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        for subview in container.subviews { subview.removeFromSuperview() }
        coordinator.host.parkWebViewIfDetached()
    }
}
#endif

/// A base's view of a type a plugin registered (`registerBasesView`): the plugin draws the
/// base's results in its own view, shown live in place of Graphite's table or cards.
struct CommunityPluginBasesViewContent: View {
    let host: CommunityPluginHost
    let viewType: String
    let view: BaseView
    let source: BaseSource
    let result: BaseQueryResult?
    @State private var leafIdentifier: String?
    @State private var didFail = false

    /// Everything the plugin's view is sent for `result` (`basesMessage`), as comparable
    /// data: the view is sent the results again when this changes, so formula values and
    /// columns reach it as well as the rows.
    static func updateKey(for result: BaseQueryResult?) -> Data {
        guard let result else { return Data() }
        // `basesMessage` holds only JSON values (`pluginValue` turns non-finite numbers into null), so the encoding cannot fail.
        return (try? JSONSerialization.data(withJSONObject: CommunityPluginHost.basesMessage(result), options: [.sortedKeys])) ?? Data()
    }

    var body: some View {
        Group {
            if let leafIdentifier {
                CommunityPluginLiveViewContent(host: host, viewIdentifier: leafIdentifier)
            } else if didFail {
                ContentUnavailableView("\u{201C}\(host.pluginBasesViews[viewType] ?? viewType)\u{201D} Could Not Be Shown", systemImage: "puzzlepiece.extension",
                                       description: Text("Its plugin did not draw the view. Settings › Community Plugins lists what went wrong."))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: OpeningKey(viewType: viewType, viewIndex: view.id, hasResult: result != nil)) {
            guard let result, leafIdentifier == nil else { return }
            leafIdentifier = await host.openBasesView(type: viewType, viewName: view.name, viewIndex: view.id, source: source, result: result)
            didFail = leafIdentifier == nil
        }
        .onChange(of: Self.updateKey(for: result)) {
            if let leafIdentifier, let result { host.updateBasesView(leafIdentifier, result: result) }
        }
        .onDisappear {
            if let leafIdentifier { host.closeView(leafIdentifier) }
            leafIdentifier = nil
        }
    }

    private struct OpeningKey: Equatable {
        let viewType: String
        let viewIndex: Int
        let hasResult: Bool
    }
}

/// A picture of a live view taken as another view took the runtime's web view.
struct CommunityPluginViewPicture {
    let image: Image

    @MainActor static func taken(of webView: WKWebView) async -> CommunityPluginViewPicture? {
        #if canImport(UIKit)
        guard let picture = try? await webView.takeSnapshot(configuration: nil) else { return nil }
        return CommunityPluginViewPicture(image: Image(uiImage: picture))
        #elseif canImport(AppKit)
        guard let picture = try? await webView.takeSnapshot(configuration: nil) else { return nil }
        return CommunityPluginViewPicture(image: Image(nsImage: picture))
        #endif
    }
}
