import SwiftUI
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
}

/// The identifier of the windows that show a workspace, on the Mac and the iPad.
public enum GraphiteWindow {
    public static let identifier = "main"
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

    public init(processServices: ProcessServices, launchMode: LaunchMode, windowContent: Binding<GraphiteWindowContent?>) {
        self.processServices = processServices
        self.launchMode = launchMode
        _windowContent = windowContent
    }

    public var body: some View {
        if let workspace {
            GraphiteRootView(workspace: workspace, launchMode: launchMode, windowContent: $windowContent)
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
        if !copied.isEmpty { sentences.append("A closed window's edits could not be saved in place, so they were saved as " + copied.joined(separator: ", ") + ".") }
        if !notCopied.isEmpty { sentences.append("The edits to " + notCopied.joined(separator: ", ") + " in a closed window could not be saved.") }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }
}
