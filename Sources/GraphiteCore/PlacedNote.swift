import Foundation

/// A note placed on the map by one of its properties.
public struct PlacedNote: Hashable, Sendable, Identifiable {
    public let path: VaultPath
    public let coordinate: BaseCoordinate
    public var id: VaultPath { path }

    public init(path: VaultPath, coordinate: BaseCoordinate) {
        self.path = path
        self.coordinate = coordinate
    }

    /// The property that places a note in any vault: `coordinates`, which Bases' map view and
    /// Obsidian's Maps plugin read. It holds `[lat, lng]` or `"lat, lng"`.
    public static let defaultPropertyNames = ["coordinates"]
    /// The property the Map View community plugin reads when its settings name none.
    static let mapViewDefaultPropertyName = "location"

    /// A plugin's settings file larger than this is not read: it is untrusted input.
    static let maximumSettingsBytes = 1_048_576

    /// The properties this vault places notes with, in the order they are read: the one the
    /// Geocoding Properties plugin is set to write coordinates into, the one the Map View
    /// plugin reads when it is installed (`location` unless its settings name another), then
    /// `defaultPropertyNames`. A vault whose plugins write `Coordonnées` is placed by
    /// `Coordonnées`, as in Obsidian; a vault without Map View is not placed by `location`.
    /// Reads two small files, so it is called off the main thread.
    public static func propertyNames(vaultRoot: URL) -> [String] {
        var names: [String] = []
        func add(_ name: String?) {
            guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  !names.contains(where: { listedName in listedName.caseInsensitiveCompare(name) == .orderedSame }) else { return }
            names.append(name)
        }
        let pluginsFolder = vaultRoot.appendingPathComponent(CommunityPluginList.pluginsFolderPath, isDirectory: true)
        if let settings = settingsObject(at: pluginsFolder.appendingPathComponent("geocoding-properties/data.json")),
           let location = (settings["properties"] as? [String: Any])?["location"] as? [String: Any],
           location["enabled"] as? Bool != false {
            add(location["frontmatterKey"] as? String)
        }
        let mapViewFolder = pluginsFolder.appendingPathComponent("obsidian-map-view", isDirectory: true)
        if (try? mapViewFolder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { // Unreadable: no Map View.
            add(settingsObject(at: mapViewFolder.appendingPathComponent("data.json"))?["frontMatterKey"] as? String ?? mapViewDefaultPropertyName)
        }
        for name in defaultPropertyNames { add(name) }
        return names
    }

    private static func settingsObject(at location: URL) -> [String: Any]? {
        guard let size = try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maximumSettingsBytes,
              let data = try? Data(contentsOf: location) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// The place a note's properties give, or nil. The first of `propertyNames` that reads
    /// as a coordinate wins; a value that is not one, such as an address or a city written as
    /// text, places nothing rather than being guessed at.
    public static func coordinate(in properties: [BaseFrontmatterEntry], propertyNames: [String], source: VaultPath,
                                  calendar: Calendar = .current) -> BaseCoordinate? {
        for name in propertyNames {
            for entry in properties where entry.key.caseInsensitiveCompare(name) == .orderedSame {
                let value = BaseFrontmatter.value(of: entry.node, declaredType: nil, source: source, calendar: calendar)
                if let coordinate = BaseCoordinate(value: value) { return coordinate }
            }
        }
        return nil
    }
}
