import Foundation
import GraphiteCore

/// What a workspace reads and writes on the device outside any vault: the preferences, the
/// vault list, what it remembers per vault (open folders, recent files, tabs, folds, places,
/// plugin consent) and the folders of the files it keeps for each vault. The app builds the
/// live ones once, where it creates the workspace; a test or a hosted launch builds ones of
/// its own, so neither touches the preferences or folders of the device.
@MainActor
struct WorkspaceDeviceServices {
    /// Where the workspace writes its per-vault keys and what the views read as
    /// `@AppStorage`. The preferences and the vault list are kept in the same one.
    let defaults: UserDefaults
    let preferences: GraphitePreferences
    let vaultLibrary: VaultLibrary
    let documentPlaceStore: DocumentPlaceStore
    let applicationFolders: ApplicationFolders
    /// Builds the window's Read Aloud controller and its speech: the system voice, the
    /// downloaded voices and their renderer. Called only while the Read Aloud core plugin is
    /// on, so a launch with it off creates no speech engine.
    let makeReadAloudController: @MainActor () -> ReadAloudController

    /// Services over `defaults` and `applicationFolders`, with a place store of their own.
    init(defaults: UserDefaults, applicationFolders: ApplicationFolders, makeReadAloudController: @escaping @MainActor () -> ReadAloudController) {
        self.init(defaults: defaults, applicationFolders: applicationFolders, documentPlaceStore: DocumentPlaceStore(defaults: defaults),
                  makeReadAloudController: makeReadAloudController)
    }

    private init(defaults: UserDefaults, applicationFolders: ApplicationFolders, documentPlaceStore: DocumentPlaceStore,
                 makeReadAloudController: @escaping @MainActor () -> ReadAloudController) {
        self.defaults = defaults
        // Before the preferences read the switches: a device that used Read Aloud keeps it on.
        CorePluginSwitchMigration.runIfNeeded(in: defaults, voicesFolder: CorePluginSwitchMigration.voicesFolder(in: applicationFolders))
        self.preferences = GraphitePreferences(defaults: defaults)
        self.vaultLibrary = VaultLibrary(defaults: defaults)
        self.documentPlaceStore = documentPlaceStore
        self.applicationFolders = applicationFolders
        self.makeReadAloudController = makeReadAloudController
    }

    /// The app's own: the standard preferences, the system's folders and the one place
    /// store every workspace of the app shares.
    static func live() -> WorkspaceDeviceServices {
        WorkspaceDeviceServices(defaults: .standard, applicationFolders: .system, documentPlaceStore: .shared,
                                makeReadAloudController: ReadAloudVoices.makeController)
    }

    /// What a launch in `launchMode` uses. A hosted-tests launch gets a preferences suite of
    /// its own and a temporary root for the Caches and Application Support folders, both
    /// named with a fresh identifier; the operating system clears the temporary folder.
    static func make(for launchMode: LaunchMode) -> WorkspaceDeviceServices {
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
            return WorkspaceDeviceServices(defaults: suite, applicationFolders: .temporary(below: folderRoot),
                                           makeReadAloudController: ReadAloudVoices.makeController)
        }
    }
}
