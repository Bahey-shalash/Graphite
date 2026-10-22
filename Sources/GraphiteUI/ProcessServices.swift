import Foundation
import GraphiteCore
import GraphiteIndex

/// What every window of the app shares, built once per process (decision 12 of
/// `Docs/solid/rewrite-foundations.md`): the preferences, the vault list, what the device
/// remembers per vault (open folders, recent files, tabs, folds, places, plugin consent), the
/// folders of the files kept for each vault, the add-on packs and each open vault's index.
/// Each window's `WorkspaceModel` holds its own tabs, sidebar and alerts over these; one
/// preferences object for all of them is why a setting changed in one window reaches every
/// other at once.
///
/// The app builds the live ones once, in `GraphiteApp.init`; a test or a hosted launch
/// builds ones of its own, so neither touches the preferences or folders of the device.
@MainActor
public final class ProcessServices {
    /// Where the workspaces write their per-vault keys and what the views read as
    /// `@AppStorage`. The preferences and the vault list are kept in the same one.
    let defaults: UserDefaults
    let preferences: GraphitePreferences
    let vaultLibrary: VaultLibrary
    /// Where documents were left in each vault. One store for every window, so two windows
    /// on one vault do not overwrite each other's places with copies read earlier.
    let documentPlaceStore: DocumentPlaceStore
    /// Each vault's graph groups, for every window. Built the first time a graph or a vault's
    /// removal asks for it, so a launch that shows no graph builds nothing for it.
    private(set) lazy var graphColorGroups = GraphColorGroupStore(defaults: defaults, makeIdentifier: UUID.init)
    let applicationFolders: ApplicationFolders
    /// What this device has downloaded of the extras Graphite does not carry, such as the
    /// welcome tour's pictures; every window and Settings read the same one.
    let addOns: AddOnLibrary
    /// One index per open vault, shared by every window on it.
    let vaultIndexes: VaultIndexRegistry
    /// The unsaved strokes of drawing editors, kept in Application Support for every window.
    let drawingDrafts: DrawingEditorDraftStore
    /// The open windows, for what only one of them may run at a time.
    let openWindows = OpenWindows()
    /// The notes open in every window, so a note open in two windows is one text.
    let openNotes = OpenNoteFiles()
    /// One community plugin runtime per open vault, shared by its windows.
    let communityPluginHosts: CommunityPluginHosts
    /// Builds a window's Read Aloud controller and its speech: the system voice, the
    /// downloaded voices and their renderer, shared by every window. Called only while the
    /// Read Aloud core plugin is on, so a launch with it off creates no speech engine. The
    /// argument says why the window may not start reading now, as while another window reads.
    let makeReadAloudController: @MainActor (_ startRefusal: @escaping @MainActor () -> OtherWindowActivity?) -> ReadAloudController

    /// Services over `defaults` and `applicationFolders`.
    init(defaults: UserDefaults, applicationFolders: ApplicationFolders,
         makeReadAloudController: @escaping @MainActor (_ startRefusal: @escaping @MainActor () -> OtherWindowActivity?) -> ReadAloudController) {
        self.defaults = defaults
        // Before the preferences read the switches: a device that used Read Aloud keeps it on.
        CorePluginSwitchMigration.runIfNeeded(in: defaults, voicesFolder: CorePluginSwitchMigration.voicesFolder(in: applicationFolders))
        preferences = GraphitePreferences(defaults: defaults)
        vaultLibrary = VaultLibrary(defaults: defaults)
        documentPlaceStore = DocumentPlaceStore(defaults: defaults)
        self.applicationFolders = applicationFolders
        addOns = .standard(applicationFolders: applicationFolders)
        vaultIndexes = VaultIndexRegistry(cachesFolder: applicationFolders.cachesFolder)
        drawingDrafts = DrawingEditorDraftStore(directory: DrawingEditorDraftStore.directory(in: applicationFolders))
        communityPluginHosts = CommunityPluginHosts(defaults: defaults)
        self.makeReadAloudController = makeReadAloudController
    }

    /// The app's own: the standard preferences and the system's folders.
    static func live() -> ProcessServices {
        ProcessServices(defaults: .standard, applicationFolders: .system, makeReadAloudController: ReadAloudVoices.makeController)
    }

    /// What a launch in `launchMode` uses. A hosted-tests launch gets a preferences suite of
    /// its own and a temporary root for the Caches and Application Support folders, both
    /// named with a fresh identifier; the operating system clears the temporary folder.
    public static func make(for launchMode: LaunchMode) -> ProcessServices {
        switch launchMode {
        case .normal:
            return live()
        case .hostedTests:
            let uniqueName = "GraphiteHostedTests-" + UUID().uuidString
            // A name that cannot make a suite is not a reason to fall back to the device's
            // own preferences: a hosted run must never write them.
            guard let suite = UserDefaults(suiteName: uniqueName) else {
                preconditionFailure("The preferences suite \(uniqueName) cannot be made, and a hosted-tests launch must not use the device's preferences.")
            }
            let folderRoot = FileManager.default.temporaryDirectory.appendingPathComponent(uniqueName, isDirectory: true)
            return ProcessServices(defaults: suite, applicationFolders: .temporary(below: folderRoot),
                                   makeReadAloudController: ReadAloudVoices.makeController)
        }
    }
}
