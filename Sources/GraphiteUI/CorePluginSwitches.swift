import Foundation
import GraphiteCore

/// Which core plugins are on, on this device: each plugin's default, changed by what the
/// person turned off or on in Settings › Core Plugins.
struct CorePluginSwitches: Equatable {
    /// Plugins on by default that the person turned off (`GraphiteDisabledCorePlugins`).
    private(set) var turnedOff: Set<CorePlugin>
    /// Plugins off by default that the person turned on (`GraphiteEnabledCorePlugins`).
    private(set) var turnedOn: Set<CorePlugin>

    static let turnedOffKey = "GraphiteDisabledCorePlugins"
    static let turnedOnKey = "GraphiteEnabledCorePlugins"

    init(turnedOff: Set<CorePlugin>, turnedOn: Set<CorePlugin>) {
        self.turnedOff = turnedOff
        self.turnedOn = turnedOn
    }

    /// The switches as kept in `defaults`; an absent or unreadable list reads as empty.
    init(storedIn defaults: UserDefaults) {
        turnedOff = Self.plugins(storedUnder: Self.turnedOffKey, in: defaults)
        turnedOn = Self.plugins(storedUnder: Self.turnedOnKey, in: defaults)
    }

    func isEnabled(_ plugin: CorePlugin) -> Bool {
        plugin.isEnabledByDefault ? !turnedOff.contains(plugin) : turnedOn.contains(plugin)
    }

    /// Records the choice in the one set that applies to the plugin's default, and drops it
    /// from the other, so a plugin whose default changed keeps only the current answer.
    mutating func setEnabled(_ plugin: CorePlugin, _ isEnabled: Bool) {
        if plugin.isEnabledByDefault {
            turnedOn.remove(plugin)
            if isEnabled { turnedOff.remove(plugin) } else { turnedOff.insert(plugin) }
        } else {
            turnedOff.remove(plugin)
            if isEnabled { turnedOn.insert(plugin) } else { turnedOn.remove(plugin) }
        }
    }

    /// Writes both sets as sorted raw values, the encoding `GraphiteDisabledCorePlugins` has
    /// always had (`ST-04`).
    func store(in defaults: UserDefaults) {
        defaults.set(turnedOff.map(\.rawValue).sorted(), forKey: Self.turnedOffKey)
        defaults.set(turnedOn.map(\.rawValue).sorted(), forKey: Self.turnedOnKey)
    }

    private static func plugins(storedUnder key: String, in defaults: UserDefaults) -> Set<CorePlugin> {
        Set((defaults.stringArray(forKey: key) ?? []).compactMap(CorePlugin.init(rawValue:)))
    }
}

/// The one-time change of 2026-10-19 that made Read Aloud off by default: a device that used
/// Read Aloud before keeps it on, a new install starts with it off. It runs while
/// `GraphiteEnabledCorePlugins` has never been written, and writes it, so it runs once and
/// never turns Read Aloud back on after the person turned it off.
enum CorePluginSwitchMigration {
    /// What tells that Read Aloud was used on this device.
    struct ReadAloudUseEvidence {
        /// A Read Aloud preference is stored (voice, speed, highlight, quality mode,
        /// remembered places, player corner and the others of `ST-12` and `ST-14`).
        let hasReadAloudPreference: Bool
        /// A voice was downloaded; asked only when no preference answered.
        let hasDownloadedVoice: () -> Bool
    }

    /// The plugins that are off by default and turned on after the migration.
    static func turnedOnPlugins(alreadyTurnedOff: Set<CorePlugin>, evidence: ReadAloudUseEvidence) -> Set<CorePlugin> {
        guard !alreadyTurnedOff.contains(.readAloud) else { return [] }
        return evidence.hasReadAloudPreference || evidence.hasDownloadedVoice() ? [.readAloud] : []
    }

    /// Runs the migration on `defaults` when it has not run there yet.
    static func runIfNeeded(in defaults: UserDefaults, voicesFolder: URL?) {
        guard defaults.object(forKey: CorePluginSwitches.turnedOnKey) == nil else { return }
        let storedSwitches = CorePluginSwitches(storedIn: defaults)
        let evidence = ReadAloudUseEvidence(hasReadAloudPreference: hasReadAloudPreference(in: defaults),
                                            hasDownloadedVoice: { voicesFolder.map(folderHoldsVoice) ?? false })
        let turnedOn = turnedOnPlugins(alreadyTurnedOff: storedSwitches.turnedOff, evidence: evidence)
        defaults.set(turnedOn.map(\.rawValue).sorted(), forKey: CorePluginSwitches.turnedOnKey)
    }

    /// The prefixes of every Read Aloud preference name (`ST-12`, `ST-13`, `ST-14`).
    static let readAloudPreferencePrefixes = ["GraphiteReadAloud", "readAloud"]

    static func hasReadAloudPreference(in defaults: UserDefaults) -> Bool {
        defaults.dictionaryRepresentation().keys.contains { key in
            readAloudPreferencePrefixes.contains { prefix in key.hasPrefix(prefix) }
        }
    }

    /// Whether the voices folder holds a voice or a download of one (`RA-08`). The folder is
    /// made empty at every launch that touches Read Aloud, so only what is in it counts. This
    /// lists one small folder once per device, at the launch that runs the migration.
    static func folderHoldsVoice(_ voicesFolder: URL) -> Bool {
        let fileManager = FileManager.default
        let contents = try? fileManager.contentsOfDirectory(at: voicesFolder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) // unlistable: no voice
        return !(contents ?? []).isEmpty
    }

    /// Where downloaded voices are kept: `Voices` in the given Application Support folder,
    /// or in the system's when the workspace uses it (`NeuralVoiceCatalog.voicesFolder`).
    static func voicesFolder(in applicationFolders: ApplicationFolders) -> URL? {
        let fileManager = FileManager.default
        let applicationSupportFolder = applicationFolders.applicationSupportFolder
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return applicationSupportFolder?.appendingPathComponent("Voices", isDirectory: true)
    }
}
