import Foundation

/// Why a vault's `.obsidian/hotkeys.json` could not be read. Graphite then uses its default
/// shortcuts and never writes the file.
public enum HotkeyFileProblem: Error, Equatable, Sendable {
    /// The file is not JSON.
    case notJSON
    /// The file is JSON but not an object of command identifiers.
    case notAnObject
}

/// Obsidian's `.obsidian/hotkeys.json`: the shortcuts a vault changed, by command identifier.
/// A command the file does not name keeps its default shortcuts; an empty list means the
/// person removed them. Every entry is kept as it was written, those of commands Graphite does
/// not have and those it cannot read included, so the file is written back with only the
/// entries Graphite changed.
public struct HotkeyFile: Equatable, Sendable {
    public static let configurationPath = ".obsidian/hotkeys.json"

    public private(set) var entries: [String: JSONValue]

    public init() {
        entries = [:]
    }

    /// Reads the file's data; nothing, or an empty or blank file, is a file without changes.
    public init(configurationData: Data?) throws {
        guard let configurationData, !configurationData.allSatisfy({ byte in byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 }) else {
            entries = [:]
            return
        }
        let value: JSONValue
        do { value = try JSONDecoder().decode(JSONValue.self, from: configurationData) } catch { throw HotkeyFileProblem.notJSON }
        guard case .object(let object) = value else { throw HotkeyFileProblem.notAnObject }
        entries = object
    }

    /// The shortcuts the file gives a command: nil when it names no list Graphite can read for
    /// it (the command keeps its defaults), an empty list when its shortcuts were removed.
    public func assignedCombinations(for commandIdentifier: String) -> [KeyCombination]? {
        guard case .array(let hotkeys)? = entries[commandIdentifier] else { return nil }
        let combinations = hotkeys.compactMap(KeyCombination.init(obsidianHotkey:))
        return combinations.count == hotkeys.count ? combinations : nil
    }

    /// Gives a command these shortcuts, or with nil removes its entry so it has its defaults.
    public mutating func assign(_ combinations: [KeyCombination]?, to commandIdentifier: String) {
        entries[commandIdentifier] = combinations.map { combinations in .array(combinations.map(\.obsidianHotkey)) }
    }

    /// The file as Obsidian writes it, `JSON.stringify(hotkeys, null, 2)`.
    public func configurationData() -> Data {
        JSONStringifyLayout.data(.object(entries))
    }
}
