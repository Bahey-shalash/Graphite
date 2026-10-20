import Foundation

/// An Obsidian community plugin's `manifest.json`, as Obsidian reads it from
/// `.obsidian/plugins/<folder>/manifest.json`. The file's own bytes are kept, so the
/// plugin runtime receives every key the author wrote, including ones Graphite does not read.
public struct CommunityPluginManifest: Equatable, Sendable {
    /// `id`: the identifier commands, settings and `community-plugins.json` use.
    public let identifier: String
    public let name: String
    public let version: String
    /// `minAppVersion`: the oldest Obsidian whose plugin API the plugin was written for.
    public let minimumApplicationVersion: String?
    public let summary: String
    public let author: String
    /// `authorUrl`.
    public let authorAddress: String?
    /// `isDesktopOnly`: the plugin needs Node.js or Electron, which Obsidian mobile and
    /// Graphite do not have.
    public let isDesktopOnly: Bool
    /// The manifest as written.
    public let manifestData: Data

    /// Manifests larger than this are not plugin manifests.
    public static let maximumManifestBytes = 256 * 1024

    public init(manifestData: Data) throws {
        guard manifestData.count <= Self.maximumManifestBytes else { throw GraphiteError.oversized("This plugin's manifest is too large to be a plugin manifest.") }
        guard let object = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any] else {
            throw GraphiteError.invalidFile("This plugin's manifest.json is not a JSON object.")
        }
        guard let identifier = object["id"] as? String, Self.isUsableIdentifier(identifier) else {
            throw GraphiteError.invalidFile("This plugin's manifest has no usable “id”.")
        }
        guard let name = object["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GraphiteError.invalidFile("The plugin “\(identifier)” has no name in its manifest.")
        }
        self.identifier = identifier
        self.name = name
        version = object["version"] as? String ?? ""
        minimumApplicationVersion = object["minAppVersion"] as? String
        summary = object["description"] as? String ?? ""
        author = object["author"] as? String ?? ""
        authorAddress = object["authorUrl"] as? String
        isDesktopOnly = object["isDesktopOnly"] as? Bool ?? false
        self.manifestData = manifestData
    }

    /// An identifier names a folder and prefixes command identifiers, so it must be one
    /// plain path component: no separators, no dots alone, no control characters.
    public static func isUsableIdentifier(_ identifier: String) -> Bool {
        guard !identifier.isEmpty, identifier.utf8.count <= 128, identifier != ".", identifier != ".." else { return false }
        let forbidden = CharacterSet(charactersIn: "/\\:").union(.controlCharacters).union(.newlines)
        return identifier.rangeOfCharacter(from: forbidden) == nil && !identifier.hasPrefix(".")
    }
}

/// Compares Obsidian version numbers (`1.4.10` after `1.4.9`), part by part, as semantic
/// versions: a leading `v` is ignored, and a pre-release (`1.2.0-beta.3`) comes before
/// its release, so an update never installs a beta in place of the stable version.
public enum ObsidianVersionNumber {
    public static func compare(_ firstVersion: String, _ secondVersion: String) -> ComparisonResult {
        let first = Parsed(firstVersion), second = Parsed(secondVersion)
        for partIndex in 0..<max(first.numbers.count, second.numbers.count) {
            let firstPart = partIndex < first.numbers.count ? first.numbers[partIndex] : 0
            let secondPart = partIndex < second.numbers.count ? second.numbers[partIndex] : 0
            if firstPart != secondPart { return firstPart < secondPart ? .orderedAscending : .orderedDescending }
        }
        switch (first.preRelease, second.preRelease) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case (let firstLabel?, let secondLabel?): return comparePreReleases(firstLabel, secondLabel)
        }
    }

    /// The numbers before any `-` or `+`, and the pre-release label after a `-`.
    private struct Parsed {
        let numbers: [Int]
        let preRelease: String?

        init(_ version: String) {
            var text = Substring(version.trimmingCharacters(in: .whitespaces))
            if text.first == "v" || text.first == "V" { text = text.dropFirst() }
            if let buildStart = text.firstIndex(of: "+") { text = text[..<buildStart] }
            var core = text
            var label: String?
            if let labelStart = text.firstIndex(of: "-") {
                core = text[..<labelStart]
                label = String(text[text.index(after: labelStart)...])
            }
            numbers = core.split(separator: ".").map { part in Int(part.prefix { character in character.isASCII && character.isNumber }) ?? 0 }
            preRelease = label
        }
    }

    /// Semantic versioning's order for pre-release labels: numeric identifiers by value,
    /// below alphanumeric ones, and a shorter list of identifiers first when the rest match.
    private static func comparePreReleases(_ firstLabel: String, _ secondLabel: String) -> ComparisonResult {
        let firstIdentifiers = firstLabel.split(separator: "."), secondIdentifiers = secondLabel.split(separator: ".")
        for (firstIdentifier, secondIdentifier) in zip(firstIdentifiers, secondIdentifiers) where firstIdentifier != secondIdentifier {
            switch (Int(firstIdentifier), Int(secondIdentifier)) {
            case (let firstNumber?, let secondNumber?): return firstNumber < secondNumber ? .orderedAscending : .orderedDescending
            case (_?, nil): return .orderedAscending
            case (nil, _?): return .orderedDescending
            case (nil, nil): return firstIdentifier < secondIdentifier ? .orderedAscending : .orderedDescending
            }
        }
        if firstIdentifiers.count == secondIdentifiers.count { return .orderedSame }
        return firstIdentifiers.count < secondIdentifiers.count ? .orderedAscending : .orderedDescending
    }
}
