import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit
#endif

/// Plugins' items in Graphite's own menus, as Obsidian gives plugins its file and editor
/// menus (`file-menu`, `files-menu`, `editor-menu`). Graphite asks the plugins for the items
/// of one menu at a time, shows them, and has the chosen one run; a menu is closed in the
/// runtime when it goes away without a choice.
extension CommunityPluginHost {
    /// How long Graphite waits for plugins to fill a menu before showing it without them.
    static let menuTimeout: Duration = .seconds(2)

    /// A menu's items, kept in the runtime until one is chosen or the menu is dismissed.
    struct PluginMenu {
        let identifier: String
        let items: [CommunityPluginMenuRequest.Item]
    }

    /// The items plugins add to the menu of files or folders.
    func fileMenu(for paths: [VaultPath], source: String = "file-explorer-context-menu") async -> PluginMenu? {
        guard isRuntimeRunning, hasFileMenuItems, !paths.isEmpty else { return nil }
        let identifier = UUID().uuidString
        let message: [String: Any] = ["operation": "menu.file", "menuIdentifier": identifier, "paths": paths.map(\.rawValue), "source": source]
        return await pluginMenu(identifier, message)
    }

    /// The items plugins add to the note editor's menu at the cursor.
    func editorMenu() async -> PluginMenu? {
        guard isRuntimeRunning, hasEditorMenuItems else { return nil }
        let identifier = UUID().uuidString
        let message: [String: Any] = ["operation": "menu.editor", "menuIdentifier": identifier, "activeDocument": activeDocumentDescription(includingEditor: true)]
        return await pluginMenu(identifier, message)
    }

    private func pluginMenu(_ identifier: String, _ message: [String: Any]) async -> PluginMenu? {
        guard let answer = try? await send(message, timeout: Self.menuTimeout) else {
            dismiss(identifier)
            return nil
        }
        let items = Self.menuItems(answer["items"] as? [[String: Any]] ?? [])
        return items.isEmpty ? nil : PluginMenu(identifier: identifier, items: items)
    }

    /// Runs the chosen item of a menu the runtime is keeping.
    func choose(_ item: CommunityPluginMenuRequest.Item, in menu: PluginMenu) {
        Task {
            guard let answer = try? await send(["operation": "menu.choose", "menuIdentifier": menu.identifier, "position": item.id], timeout: .seconds(5)) else { return }
            if answer["outcome"] as? String == "failed" { showNotice("“\(item.title)” failed: \(answer["message"] as? String ?? "")", pluginIdentifier: nil) }
        }
    }

    func dismiss(_ menu: PluginMenu) { dismiss(menu.identifier) }

    private func dismiss(_ identifier: String) {
        Task { _ = try? await send(["operation": "menu.dismiss", "menuIdentifier": identifier], timeout: .seconds(5)) }
    }

    /// The plugins' actions for a file or folder, from its menu in the file list: Graphite's
    /// list menus cannot wait for plugins, so their items open in a dialog of their own.
    func showFileActions(for path: VaultPath, source: String = "file-explorer-context-menu") async {
        guard let menu = await fileMenu(for: [path], source: source) else {
            showNotice("No plugin has an action for “\(path.name)”.", pluginIdentifier: nil)
            return
        }
        let itemDescriptions: [[String: Any]] = menu.items.map { item in
            ["position": item.id, "title": item.title, "isDisabled": item.isDisabled, "isWarning": item.isWarning, "isChecked": item.isChecked]
        }
        guard let position = await showMenu(itemDescriptions, title: path.name), let item = menu.items.first(where: { candidate in candidate.id == position }) else {
            dismiss(menu)
            return
        }
        choose(item, in: menu)
    }

    #if canImport(UIKit)
    /// The plugins' items for the note editor's menu, filled in when the menu opens; UIKit
    /// shows the menu at once and adds them when the plugins answer.
    func editorMenuElement() -> UIMenuElement {
        UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else { return completion([]) }
            Task { @MainActor in
                guard let menu = await self.editorMenu() else { return completion([]) }
                let actions: [UIMenuElement] = menu.items.map { item in
                    var attributes: UIMenuElement.Attributes = []
                    if item.isDisabled { attributes.insert(.disabled) }
                    if item.isWarning { attributes.insert(.destructive) }
                    return UIAction(title: item.title, attributes: attributes, state: item.isChecked ? .on : .off) { [weak self] _ in
                        self?.choose(item, in: menu)
                    }
                }
                completion([UIMenu(title: "", options: .displayInline, children: actions)])
            }
        }
    }
    #endif
}

/// "Plugin Actions…" in a file's or folder's menu, while plugins offer some.
struct CommunityPluginFileActionsButton: View {
    let host: CommunityPluginHost
    let path: VaultPath
    /// Where the menu is, in Obsidian's words: the file list's menu, a note's More menu
    /// (`more-options`) or a tab's (`tab-header`). Plugins may offer different items.
    var source = "file-explorer-context-menu"

    var body: some View {
        if host.isRuntimeRunning && host.hasFileMenuItems {
            Button("Plugin Actions…", systemImage: "puzzlepiece.extension") {
                Task { await host.showFileActions(for: path, source: source) }
            }
        }
    }
}
