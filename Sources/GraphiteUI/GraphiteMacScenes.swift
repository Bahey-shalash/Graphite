#if os(macOS)
import SwiftUI
import AppKit
import GraphiteCore

/// The Mac's scenes: windows of workspaces, as many as the person opens (File › New Window,
/// ⌥⌘N, and the window tab bar), the Guide's window, and Settings in a window of its own,
/// opened with ⌘, from the app menu as on every Mac. Settings acts on the window in front, so
/// a setting changed there reaches its vault at once; device-wide settings reach every window.
public struct GraphiteMacScenes: Scene {
    private let processServices: ProcessServices
    private let launchMode: LaunchMode
    @State private var frontmostWindow: FrontmostWindow

    public init(processServices: ProcessServices, launchMode: LaunchMode) {
        self.processServices = processServices
        self.launchMode = launchMode
        _frontmostWindow = State(initialValue: FrontmostWindow(processServices: processServices))
        GraphiteApplicationDelegate.openWindows = processServices.openWindows
    }

    /// The workspace Settings shows: the front window's, or, with no window open, one of its own.
    private var settingsWorkspace: WorkspaceModel { frontmostWindow.workspace ?? frontmostWindow.workspaceWithoutWindow }

    public var body: some Scene {
        // A window per workspace, each with its own tabs, sidebar and alerts over what every
        // window shares (`ProcessServices`); windows on one vault share its index. The system
        // keeps each window's content, so it opens on the same vault after a relaunch.
        WindowGroup("Graphite", id: GraphiteWindow.identifier, for: GraphiteWindowContent.self) { $windowContent in
            GraphiteWindowScene(processServices: processServices, launchMode: launchMode, windowContent: $windowContent)
                .environment(frontmostWindow)
        }
            .defaultSize(width: 1200, height: 820)
            .commands {
                GraphiteCommands()
                GuideCommands()
                WindowCommands()
            }
        // The Guide in a window of its own, beside the notes it explains.
        Window("Graphite Guide", id: GraphiteMacScenes.guideWindowIdentifier) {
            GuideView(showsDoneButton: false)
                .environment(\.accent, processServices.preferences.accentColor)
                .preferredColorScheme(processServices.preferences.appearanceMode.colorScheme)
        }
        .defaultSize(width: 1000, height: 720)
        .defaultPosition(.center)
        Settings {
            SettingsView(workspace: settingsWorkspace) { settingsWorkspace.isVaultManagerPresented = true }
                .defaultAppStorage(processServices.defaults)
                .environment(processServices.addOns)
                .tint(processServices.preferences.accentColor)
                .environment(\.accent, processServices.preferences.accentColor)
                .preferredColorScheme(processServices.preferences.appearanceMode.colorScheme)
        }
    }

    static let guideWindowIdentifier = "guide"
}

/// The window in front, whose workspace the Settings window shows; each window's root view
/// sets it as its window becomes key.
@MainActor @Observable
final class FrontmostWindow {
    weak var workspace: WorkspaceModel?
    /// Settings while no window is open: a workspace with no vault, over the same preferences.
    @ObservationIgnored let workspaceWithoutWindow: WorkspaceModel

    init(processServices: ProcessServices) {
        workspaceWithoutWindow = WorkspaceModel(processServices: processServices, clock: LiveApplicationClock())
    }
}

/// Help › Graphite Guide opens the Guide's window.
private struct GuideCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Graphite Guide") { openWindow(id: GraphiteMacScenes.guideWindowIdentifier) }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}

/// Saves what every window has open before Graphite quits. A note saves once typing has
/// paused for most of a second, so ⌘Q right after typing lost the last words: the window's
/// teardown cancelled the save that was waiting.
public final class GraphiteApplicationDelegate: NSObject, NSApplicationDelegate {
    /// The windows whose saves quitting waits for; `GraphiteMacScenes` sets it.
    @MainActor static weak var openWindows: OpenWindows?
    /// How long quitting waits for the saves. A save still running then keeps running and
    /// Graphite stays open, so what was typed is not lost to a file another app holds.
    private static let saveDeadline = Duration.seconds(5)

    @MainActor public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let windows = Self.openWindows?.all ?? []
        guard !windows.isEmpty else { return .terminateNow }
        let reply = TerminationReply(application: sender)
        Task { @MainActor in
            // One window after another; the first whose save fails keeps Graphite open and says why.
            for window in windows {
                reply.windowSaving = window
                do { try await window.saveOpenDocuments() } catch { return reply.finish(with: .failed(error)) }
            }
            reply.finish(with: .succeeded)
        }
        reply.deadline = Task { @MainActor in
            do { try await Task.sleep(for: Self.saveDeadline) } catch { return }
            reply.finish(with: .timedOut)
        }
        return .terminateLater
    }

    /// Answers the application once, whichever of the saves and the deadline ends first.
    /// The application quits only when every save succeeded; otherwise it stays open and
    /// the window whose save failed, or was still running, shows why.
    @MainActor private final class TerminationReply {
        private let application: NSApplication
        private var hasReplied = false
        var deadline: Task<Void, Never>?
        /// The window whose documents are being saved.
        var windowSaving: OpenWindow?

        init(application: NSApplication) {
            self.application = application
        }

        func finish(with outcome: QuitSaveOutcome) {
            guard !hasReplied else { return }
            hasReplied = true
            deadline?.cancel()
            let decision = QuitSaveDecision(outcome: outcome)
            if let blockingReason = decision.blockingReason {
                windowSaving?.presentProblem(blockingReason.presentedMessage)
            }
            application.reply(toApplicationShouldTerminate: decision.allowsTermination)
        }
    }
}
#endif
