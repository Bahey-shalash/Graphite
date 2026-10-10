import Foundation

/// What Graphite can tell about a plugin before running it: whether it can load at all,
/// and which modules its code asks for that Graphite does not provide.
public struct CommunityPluginCompatibility: Equatable, Sendable {
    /// The Obsidian plugin API version Graphite's runtime follows (`apiVersion`). Parts it
    /// does not implement report themselves as unsupported when a plugin uses them.
    public static let providedApiVersion = "1.14.4"

    public enum Blocker: Equatable, Sendable {
        /// `isDesktopOnly`: Obsidian mobile does not load it either.
        case desktopOnly
        /// `minAppVersion` is newer than the API Graphite provides.
        case needsNewerApi(required: String)
        /// The package has no `main.js`.
        case missingMainScript
    }

    public enum ModuleKind: Equatable, Sendable {
        /// Node.js or Electron, which only Obsidian's desktop app has.
        case desktopOnly
        /// CodeMirror, Obsidian's editor; Graphite's editor is native.
        case codeMirror
        /// A module Obsidian does not provide to plugins either.
        case unknown
    }

    public struct RequiredModule: Equatable, Sendable {
        public let name: String
        public let kind: ModuleKind
    }

    public let blockers: [Blocker]
    /// Modules the code mentions in `require(…)` that Graphite lacks. A plugin may only
    /// reach them on desktop, so they are reported rather than refused.
    public let missingModules: [RequiredModule]

    public var canLoad: Bool { blockers.isEmpty }

    static let desktopModuleNames: Set<String> = [
        "electron", "fs", "fs/promises", "path", "os", "child_process", "crypto", "http", "https", "net", "tls", "dns", "zlib",
        "stream", "util", "url", "events", "buffer", "assert", "worker_threads", "readline", "process", "module", "vm",
        "querystring", "string_decoder", "timers", "tty", "dgram", "cluster", "perf_hooks", "v8", "original-fs",
    ]

    private static let requirePattern = try? NSRegularExpression(pattern: #"\brequire\(\s*["']([^"'\s]{1,200})["']\s*\)"#)

    public static func assess(manifest: CommunityPluginManifest, mainScript: String?, providedApiVersion: String = providedApiVersion) -> Self {
        var blockers: [Blocker] = []
        if manifest.isDesktopOnly { blockers.append(.desktopOnly) }
        if let required = manifest.minimumApplicationVersion, ObsidianVersionNumber.compare(required, providedApiVersion) == .orderedDescending {
            blockers.append(.needsNewerApi(required: required))
        }
        guard let mainScript else { return Self(blockers: blockers + [.missingMainScript], missingModules: []) }
        return Self(blockers: blockers, missingModules: missingModules(in: mainScript))
    }

    static func missingModules(in mainScript: String) -> [RequiredModule] {
        guard let requirePattern else { return [] }
        let source = mainScript as NSString
        var seenNames: Set<String> = []
        var modules: [RequiredModule] = []
        for match in requirePattern.matches(in: mainScript, range: NSRange(location: 0, length: source.length)) {
            let name = source.substring(with: match.range(at: 1))
            guard name != "obsidian", !name.hasPrefix("."), seenNames.insert(name).inserted else { continue }
            let baseName = name.hasPrefix("node:") ? String(name.dropFirst("node:".count)) : name
            let kind: ModuleKind
            if desktopModuleNames.contains(baseName) || desktopModuleNames.contains(String(baseName.split(separator: "/").first ?? "")) {
                kind = .desktopOnly
            } else if baseName.hasPrefix("@codemirror/") || baseName.hasPrefix("@lezer/") {
                kind = .codeMirror
            } else {
                kind = .unknown
            }
            modules.append(RequiredModule(name: baseName, kind: kind))
        }
        return modules.sorted { firstModule, secondModule in firstModule.name < secondModule.name }
    }
}

/// A plugin folder in `.obsidian/plugins`, read without running anything.
public struct InstalledCommunityPlugin: Identifiable, Equatable, Sendable {
    public var id: String { manifest.identifier }
    /// The plugin's folder, which Obsidian names after the identifier but does not require to.
    public let folder: VaultPath
    public let manifest: CommunityPluginManifest
    public let compatibility: CommunityPluginCompatibility
}

/// Everything the runtime needs to load a plugin.
public struct CommunityPluginPackage: Sendable {
    public let plugin: InstalledCommunityPlugin
    public let mainScript: String
    public let styles: String
}

/// A plugin folder that could not be read as a plugin, with the reason.
public struct UnreadableCommunityPlugin: Identifiable, Equatable, Sendable {
    public var id: VaultPath { folder }
    public let folder: VaultPath
    public let reason: String
}

public struct CommunityPluginInventory: Equatable, Sendable {
    public let plugins: [InstalledCommunityPlugin]
    public let unreadableFolders: [UnreadableCommunityPlugin]
}

public extension VaultStore {
    /// The largest `main.js` Graphite reads. Obsidian sets no limit; the largest popular
    /// plugins bundle about 10 MB.
    static let maximumPluginScriptBytes = 48 * 1_048_576
    static let maximumPluginStylesBytes = 8 * 1_048_576

    /// Every plugin folder in `.obsidian/plugins`, sorted by name. Plugin code is read only
    /// to list the modules it asks for; nothing runs.
    func installedCommunityPlugins() throws -> CommunityPluginInventory {
        let pluginsFolder = try VaultPath(CommunityPluginList.pluginsFolderPath)
        guard try fileExists(pluginsFolder) else { return CommunityPluginInventory(plugins: [], unreadableFolders: []) }
        var plugins: [InstalledCommunityPlugin] = []
        var unreadableFolders: [UnreadableCommunityPlugin] = []
        for entry in try children(of: pluginsFolder) where entry.isDirectory {
            do {
                let manifestSnapshot = try read(entry.path.appending("manifest.json"), maximumBytes: CommunityPluginManifest.maximumManifestBytes)
                let manifest = try CommunityPluginManifest(manifestData: manifestSnapshot.data)
                let mainScriptPath = try entry.path.appending("main.js")
                let mainScript = try fileExists(mainScriptPath)
                    ? String(decoding: try read(mainScriptPath, maximumBytes: Self.maximumPluginScriptBytes).data, as: UTF8.self)
                    : nil
                plugins.append(InstalledCommunityPlugin(folder: entry.path, manifest: manifest, compatibility: .assess(manifest: manifest, mainScript: mainScript)))
            } catch {
                unreadableFolders.append(UnreadableCommunityPlugin(folder: entry.path, reason: error.localizedDescription))
            }
        }
        plugins.sort { firstPlugin, secondPlugin in firstPlugin.manifest.name.localizedStandardCompare(secondPlugin.manifest.name) == .orderedAscending }
        return CommunityPluginInventory(plugins: plugins, unreadableFolders: unreadableFolders)
    }

    /// The plugin's code and styles, read again so the runtime loads what is on disk now.
    func communityPluginPackage(for plugin: InstalledCommunityPlugin) throws -> CommunityPluginPackage {
        let mainScriptData = try read(plugin.folder.appending("main.js"), maximumBytes: Self.maximumPluginScriptBytes).data
        let stylesPath = try plugin.folder.appending("styles.css")
        let styles = try fileExists(stylesPath) ? String(decoding: try read(stylesPath, maximumBytes: Self.maximumPluginStylesBytes).data, as: UTF8.self) : ""
        return CommunityPluginPackage(plugin: plugin, mainScript: String(decoding: mainScriptData, as: UTF8.self), styles: styles)
    }
}
