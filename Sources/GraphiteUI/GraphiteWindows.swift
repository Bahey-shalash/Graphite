import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore

/// What a Graphite window was opened to show. The system keeps it with the window, so the
/// window opens on the same vault after a relaunch (`WindowGroup(for:)`).
public struct GraphiteWindowContent: Codable, Hashable, Sendable {
    /// The vault the window shows; nil for a window with no vault open yet.
    var vaultIdentifier: UUID?
    /// Opened by New Window or Open in New Window: the window starts with one empty tab, or
    /// the file below, rather than the vault's remembered tabs. Cleared once the window has
    /// opened, so a relaunch shows what the window then showed.
    var opensFreshTabs = false
    /// The file a new window shows, as a vault path.
    var filePath: String?

    /// The user activity a dragged file or tab carries on the iPad, which iPadOS opens as a new
    /// window when the drag ends at the edge of the screen. Declared in `NSUserActivityTypes`.
    static let activityType = "com.graphite.study.open-window"

    var userActivity: NSUserActivity {
        let activity = NSUserActivity(activityType: Self.activityType)
        // Encoding three plain fields cannot fail; nothing to carry if it did.
        activity.userInfo = (try? JSONEncoder().encode(self)).map { encoded in ["content": encoded] } ?? [:] // see above
        return activity
    }

    init(vaultIdentifier: UUID?, opensFreshTabs: Bool = false, filePath: String? = nil) {
        self.vaultIdentifier = vaultIdentifier
        self.opensFreshTabs = opensFreshTabs
        self.filePath = filePath
    }

    /// A new window on the vault `vaultIdentifier` showing `path`, as "Open in New Window" and a
    /// dragged file or tab ask for.
    static func showing(_ path: VaultPath, inVault vaultIdentifier: UUID?) -> GraphiteWindowContent {
        GraphiteWindowContent(vaultIdentifier: vaultIdentifier, opensFreshTabs: true, filePath: path.rawValue)
    }

    /// The file the window was opened to show, if its path still reads as one.
    var file: VaultPath? {
        filePath.flatMap { path in try? VaultPath(path) } // a path that no longer reads as one shows no file
    }

    /// The content a dragged file or tab asked a new window for; nil for another activity.
    init?(activity: NSUserActivity) {
        guard activity.activityType == Self.activityType, let encoded = activity.userInfo?["content"] as? Data,
              let content = try? JSONDecoder().decode(Self.self, from: encoded) else { return nil } // an activity of another build opens nothing
        self = content
    }
}

extension View {
    /// A file or folder of the sidebar, dragged within Graphite (`VaultItemTransfer`); a file
    /// dragged to the edge of the iPad's screen opens in a new window on the vault.
    func draggableVaultEntry<Preview: View>(_ entry: VaultEntry, inVault vaultIdentifier: UUID?, @ViewBuilder preview: @escaping () -> Preview) -> some View {
        draggable(VaultItemTransfer(path: entry.path.rawValue), contentType: .graphiteVaultItem,
                  opening: entry.isDirectory ? nil : .showing(entry.path, inVault: vaultIdentifier), preview: preview)
    }

    /// `draggable(item)`; on the iPad the drag also carries the user activity of
    /// `windowContent`, so iPadOS opens it in a new window when the drag ends at the edge of
    /// the screen. Drops inside Graphite read `item` as before.
    func draggable<Item: Transferable & Encodable, Preview: View>(_ item: Item, contentType: UTType, opening windowContent: GraphiteWindowContent?,
                                                                  @ViewBuilder preview: @escaping () -> Preview) -> some View {
        #if canImport(UIKit)
        onDrag {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: contentType.identifier, visibility: .ownProcess) { completion in
                do { completion(try JSONEncoder().encode(item), nil) } catch { completion(nil, error) }
                return nil
            }
            if let windowContent { provider.registerObject(windowContent.userActivity, visibility: .all) }
            return provider
        } preview: {
            preview()
        }
        #else
        draggable(item, preview: preview)
        #endif
    }
}

/// The identifier of the windows that show a workspace, on the Mac and the iPad.
public enum GraphiteWindow {
    public static let identifier = "main"
}

/// "Open in New Window" for a file, shown where the app runs several windows.
struct OpenInNewWindowButton: View {
    /// Opens the file with the `.newWindow` placement.
    let openInNewWindow: () -> Void
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some View {
        if supportsMultipleWindows {
            Button("Open in New Window", systemImage: "macwindow.badge.plus", action: openInNewWindow)
        }
    }
}

/// File › New Window (⌥⌘N): another window on the vault of the window in front, with an empty
/// tab, as Mail keeps ⌘N for a new message and opens a new viewer window with ⌥⌘N (owner,
/// 2026-10-21). Shown only where the app runs several windows, so never on an iPhone.
public struct WindowCommands: Commands {
    @FocusedValue(\.workspaceMenuActions) private var actions
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .newItem) {
            if supportsMultipleWindows {
                Button("New Window") {
                    openWindow(id: GraphiteWindow.identifier,
                               value: GraphiteWindowContent(vaultIdentifier: actions?.workspace.currentVaultIdentifier, opensFreshTabs: true))
                }
                .keyboardShortcut("n", modifiers: [.option, .command])
            }
        }
    }
}

/// One window: it makes the window's workspace once, over the services every window shares,
/// and shows it. Making the workspace in the root view's initializer would build one each
/// time SwiftUI evaluates the window's scene again.
public struct GraphiteWindowScene: View {
    private let processServices: ProcessServices
    private let launchMode: LaunchMode
    @Binding private var windowContent: GraphiteWindowContent?
    @State private var workspace: WorkspaceModel?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    public init(processServices: ProcessServices, launchMode: LaunchMode, windowContent: Binding<GraphiteWindowContent?>) {
        self.processServices = processServices
        self.launchMode = launchMode
        _windowContent = windowContent
    }

    public var body: some View {
        if let workspace {
            GraphiteRootView(workspace: workspace, launchMode: launchMode, windowContent: $windowContent)
                // A file or tab dragged to the edge of the screen opened this window.
                .onContinueUserActivity(GraphiteWindowContent.activityType) { activity in
                    guard let content = GraphiteWindowContent(activity: activity), let vaultIdentifier = content.vaultIdentifier else { return }
                    windowContent = content
                    Task {
                        await workspace.openVaultOfWindow(vaultIdentifier, restoresTabs: false, showing: content.file)
                    }
                }
                .onChange(of: workspace.newWindowRequest) { _, request in
                    guard let request else { return }
                    workspace.newWindowRequest = nil
                    if supportsMultipleWindows {
                        openWindow(id: GraphiteWindow.identifier, value: request)
                    } else if let file = request.file {
                        Task { await workspace.open(file, placement: .newTab) }
                    }
                }
                .onChange(of: workspace.currentVaultIdentifier) { _, vaultIdentifier in
                    // A vault switched in the window: a relaunch opens the window there.
                    if windowContent?.vaultIdentifier != vaultIdentifier { windowContent = GraphiteWindowContent(vaultIdentifier: vaultIdentifier) }
                }
                .onDisappear {
                    // The window closed: what it has open is saved, then it lets go of the
                    // vault's index, which closes unless another window has the vault open.
                    // Edits that could not be saved are kept as copies, which a remaining
                    // window names.
                    Task {
                        let outcome = await workspace.saveBeforeWindowCloses()
                        workspace.windowDidClose()
                        guard let problem = Self.closingProblem(copied: outcome.copied, notCopied: outcome.notCopied) else { return }
                        processServices.openWindows.all.first?.presentProblem(problem)
                    }
                }
        } else {
            Color.clear.onAppear { workspace = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock()) }
        }
    }

    /// What a remaining window says about a closed window's edits that could not be saved.
    static func closingProblem(copied: [String], notCopied: [String]) -> String? {
        var sentences: [String] = []
        if !copied.isEmpty {
            sentences.append("A closed window's edits could not be saved in place, so they were saved as " + copied.joined(separator: ", ") + ".")
        }
        if !notCopied.isEmpty { sentences.append("The edits to " + notCopied.joined(separator: ", ") + " in a closed window could not be saved.") }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }
}
