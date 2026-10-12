import Foundation

/// Obsidian's list of enabled community plugins, `.obsidian/community-plugins.json`: a JSON
/// array of plugin identifiers, in the order they were turned on. Obsidian and Graphite
/// share it, so a plugin turned on in one is on in the other.
public struct CommunityPluginList: Equatable, Sendable {
    public static let configurationPath = ".obsidian/community-plugins.json"
    public static let pluginsFolderPath = ".obsidian/plugins"

    public private(set) var enabledIdentifiers: [String]

    public init(enabledIdentifiers: [String] = []) {
        self.enabledIdentifiers = enabledIdentifiers
    }

    /// Reads the file's bytes; a missing or empty file means no plugin is on. Entries that
    /// are not text are left out, as Obsidian ignores them.
    public init(configurationData: Data?) throws {
        guard let configurationData, !configurationData.allSatisfy({ byte in byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 }) else {
            self.init()
            return
        }
        guard let entries = try? JSONSerialization.jsonObject(with: configurationData) as? [Any] else {
            throw GraphiteError.invalidFile("“\(Self.configurationPath)” is not a list of plugins, so Graphite leaves it unchanged.")
        }
        self.init(enabledIdentifiers: entries.compactMap { entry in entry as? String })
    }

    public func isEnabled(_ identifier: String) -> Bool { enabledIdentifiers.contains(identifier) }

    /// Turns a plugin on (added at the end, as Obsidian adds it) or off.
    public mutating func setEnabled(_ identifier: String, _ isEnabled: Bool) {
        if isEnabled {
            if !enabledIdentifiers.contains(identifier) { enabledIdentifiers.append(identifier) }
        } else {
            enabledIdentifiers.removeAll { enabledIdentifier in enabledIdentifier == identifier }
        }
    }

    /// The file as Obsidian writes it: `JSON.stringify(list, null, 2)`.
    public func configurationData() throws -> Data {
        guard !enabledIdentifiers.isEmpty else { return Data("[]".utf8) }
        let entries = try enabledIdentifiers.map { identifier -> String in
            let literal = try JSONSerialization.data(withJSONObject: identifier, options: [.fragmentsAllowed, .withoutEscapingSlashes])
            return "  " + String(decoding: literal, as: UTF8.self)
        }
        return Data(("[\n" + entries.joined(separator: ",\n") + "\n]").utf8)
    }
}

public extension VaultStore {
    /// The vault's enabled community plugins; none when the file is missing.
    func communityPluginList() throws -> CommunityPluginList {
        try CommunityPluginList(configurationData: configurationData(at: CommunityPluginList.configurationPath))
    }

    /// Applies `change` to the list as it is in the file now, so a plugin turned on in
    /// Obsidian meanwhile stays on, and returns the result.
    @discardableResult
    func updateCommunityPluginList(_ change: (inout CommunityPluginList) -> Void) throws -> CommunityPluginList {
        var updated = CommunityPluginList()
        // A vault without the file gets one only once a plugin is on.
        if configurationData(at: CommunityPluginList.configurationPath) == nil {
            change(&updated)
            if updated.enabledIdentifiers.isEmpty { return updated }
            updated = CommunityPluginList()
        }
        try saveConfiguration(at: CommunityPluginList.configurationPath) { existingData in
            let existing = try CommunityPluginList(configurationData: existingData)
            updated = existing
            change(&updated)
            // An unchanged list leaves the file as it was, formatting included.
            if updated == existing, let existingData { return existingData }
            return try updated.configurationData()
        }
        return updated
    }
}
