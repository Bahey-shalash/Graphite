import Foundation
import GraphiteCore
import ShareInbox

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
    /// Where the share extension leaves shared items and finds the vault list; nil where
    /// there is no share extension (the Mac) and for a hosted-tests launch.
    let shareInbox: ShareInbox?

    /// Services over `defaults` and `applicationFolders`, with a place store of their own.
    init(defaults: UserDefaults, applicationFolders: ApplicationFolders, shareInbox: ShareInbox? = nil,
         makeReadAloudController: @escaping @MainActor () -> ReadAloudController) {
        self.init(defaults: defaults, applicationFolders: applicationFolders, documentPlaceStore: DocumentPlaceStore(defaults: defaults),
                  shareInbox: shareInbox, makeReadAloudController: makeReadAloudController)
    }

    private init(defaults: UserDefaults, applicationFolders: ApplicationFolders, documentPlaceStore: DocumentPlaceStore, shareInbox: ShareInbox?,
                 makeReadAloudController: @escaping @MainActor () -> ReadAloudController) {
        self.defaults = defaults
        // Before the preferences read the switches: a device that used Read Aloud keeps it on.
        CorePluginSwitchMigration.runIfNeeded(in: defaults, voicesFolder: CorePluginSwitchMigration.voicesFolder(in: applicationFolders))
        self.preferences = GraphitePreferences(defaults: defaults)
        self.vaultLibrary = VaultLibrary(defaults: defaults, sharedVaultListPublisher: shareInbox.map(SharedVaultListPublisher.init(inbox:)))
        self.documentPlaceStore = documentPlaceStore
        self.applicationFolders = applicationFolders
        self.shareInbox = shareInbox
        self.makeReadAloudController = makeReadAloudController
    }

    /// The app's own: the standard preferences, the system's folders, the one place store
    /// every workspace of the app shares, and the share inbox of the App Group.
    static func live() -> WorkspaceDeviceServices {
        WorkspaceDeviceServices(defaults: .standard, applicationFolders: .system, documentPlaceStore: .shared, shareInbox: liveShareInbox(),
                                makeReadAloudController: ReadAloudVoices.makeController)
    }

    /// The `Info.plist` key naming the App Group the app shares with its share extension.
    nonisolated static let applicationGroupInformationKey = "GraphiteApplicationGroup"

    /// The inbox in the App Group named in `Info.plist`, on iOS and iPadOS only: the Mac app
    /// has no share extension, and asking macOS for a group container it is not entitled to
    /// would ask the person for access to other apps' data.
    private static func liveShareInbox() -> ShareInbox? {
        #if os(iOS)
        guard let groupIdentifier = Bundle.main.object(forInfoDictionaryKey: applicationGroupInformationKey) as? String,
              let container = ShareInbox.applicationGroupContainer(identifier: groupIdentifier) else { return nil }
        return ShareInbox(containerFolder: container)
        #else
        return nil
        #endif
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
