import Foundation

public enum GraphiteError: Error, LocalizedError, Equatable {
    case invalidPath(String), outsideVault, conflict, invalidFile(String), oversized(String), unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path): "Invalid vault path: \(path)"
        case .outsideVault: "This path is outside the selected vault."
        case .conflict: "This file changed outside Graphite. Your edits are still open. Reload the external version or save your work as a separate file."
        case .invalidFile(let reason), .oversized(let reason), .unavailable(let reason): reason
        }
    }
}

/// A vault-relative path. URLs are resolved at the I/O boundary, including symlinks.
///
/// The text is always in Unicode's composed form (NFC), whatever form it arrived in: file
/// URLs report `É` decomposed while typed names and the file system's own names are
/// composed, and anything keyed by the bytes (the index, stored layouts, hashes) would
/// otherwise see one file as two. Apple's file systems find a file in either form.
///
/// Paths split at every "/" Unicode scalar. `String.split` works on characters, and a
/// "/" followed by a combining mark (`Folder/\u{301}note.md`) is one character, so it
/// would hide a separator from the symbolic-link check and from `name` and `parent`.
public struct VaultPath: Hashable, Codable, Sendable, Comparable, Identifiable {
    public let rawValue: String
    public var id: String { rawValue }

    private enum CodingKeys: String, CodingKey { case rawValue }

    /// Stored paths go through the same checks and normalization as new ones.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(try container.decode(String.self, forKey: .rawValue))
    }

    /// A backslash is an ordinary character in Apple file names, so a file synced from
    /// another system can carry one. `FileNameRules` still keeps it out of new names.
    public init(_ path: String) throws {
        guard path.unicodeScalars.first != "/", !path.unicodeScalars.contains("\0") else {
            throw GraphiteError.invalidPath(path)
        }
        var parts: [String] = []
        for component in Self.components(of: path) {
            if component == "." { continue }
            if component == ".." {
                guard !parts.isEmpty else { throw GraphiteError.outsideVault }
                parts.removeLast()
            } else { parts.append(component) }
        }
        rawValue = parts.joined(separator: "/").precomposedStringWithCanonicalMapping
    }
    public static let root = VaultPath(unchecked: "")
    private init(unchecked: String) { rawValue = unchecked }

    /// The non-empty components between "/" scalars.
    static func components(of path: String) -> [String] {
        path.unicodeScalars.split(separator: "/").map { componentScalars in String(componentScalars) }
    }

    public var name: String {
        let scalars = rawValue.unicodeScalars
        guard let separatorIndex = scalars.lastIndex(of: "/") else { return rawValue }
        return String(scalars[scalars.index(after: separatorIndex)...])
    }
    public var parent: VaultPath {
        let scalars = rawValue.unicodeScalars
        guard let separatorIndex = scalars.lastIndex(of: "/") else { return .root }
        return VaultPath(unchecked: String(scalars[..<separatorIndex]))
    }
    public var fileExtension: String { (name as NSString).pathExtension.lowercased() }
    public var stem: String { (name as NSString).deletingPathExtension }
    public func appending(_ path: String) throws -> VaultPath {
        try VaultPath(rawValue.isEmpty ? path : rawValue + "/" + path)
    }

    /// The location of this path inside `root`, with every symbolic link on the way resolved
    /// and required to stay inside the vault. Throws `outsideVault` otherwise.
    ///
    /// Components are walked one at a time rather than resolved with `realpath` alone,
    /// because `realpath` gives up on a path whose final component does not exist yet (a
    /// new note or attachment) and would leave a symbolic link in its parents unchecked.
    public func url(in root: URL) throws -> URL {
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        var resolvedLocation = base
        // Components still to visit, last one first.
        var pendingComponents = Array(Self.components(of: rawValue).reversed())
        var followedLinkCount = 0
        while let component = pendingComponents.popLast() {
            let candidate = resolvedLocation.appendingPathComponent(component)
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path) else {
                resolvedLocation = candidate.standardizedFileURL
                guard Self.location(resolvedLocation, isInside: base) else { throw GraphiteError.outsideVault }
                continue
            }
            followedLinkCount += 1
            // Darwin's own limit (MAXSYMLINKS) for links followed in one path; more means a cycle.
            guard followedLinkCount <= 32 else { throw GraphiteError.invalidPath(rawValue) }
            let target = (destination.hasPrefix("/") ? URL(fileURLWithPath: destination) : resolvedLocation.appendingPathComponent(destination)).standardizedFileURL
            // `realpath` resolves the part of the target that exists. The rest is visited
            // like the path's own components, so a link among them is followed and checked.
            var existingAncestor = target
            var missingComponents: [String] = []
            while !FileManager.default.fileExists(atPath: existingAncestor.path), existingAncestor.path != "/" {
                missingComponents.append(existingAncestor.lastPathComponent)
                existingAncestor.deleteLastPathComponent()
            }
            resolvedLocation = existingAncestor.resolvingSymlinksInPath()
            guard Self.location(resolvedLocation, isInside: base) else { throw GraphiteError.outsideVault }
            pendingComponents.append(contentsOf: missingComponents)
        }
        return resolvedLocation
    }

    /// Compares file-system paths byte for byte. Both come from the same resolved base, and
    /// `String.hasPrefix` compares characters, which a combining mark after "/" would merge.
    private static func location(_ location: URL, isInside base: URL) -> Bool {
        let locationBytes = location.path.utf8, basePath = base.path
        return locationBytes.elementsEqual(basePath.utf8) || locationBytes.starts(with: (basePath + "/").utf8)
    }

    public static func < (leftPath: Self, rightPath: Self) -> Bool { leftPath.rawValue < rightPath.rawValue }

    /// The path from `directory` to this path, as a relative link writes it (`../Other/Note.md`).
    public func relativePath(from directory: VaultPath) -> String {
        let directoryComponents = Self.components(of: directory.rawValue)
        let targetComponents = Self.components(of: rawValue)
        let sharedComponentCount = zip(directoryComponents, targetComponents).prefix { directoryComponent, targetComponent in directoryComponent == targetComponent }.count
        let parentSteps = Array(repeating: "..", count: directoryComponents.count - sharedComponentCount)
        return (parentSteps + targetComponents.dropFirst(sharedComponentCount)).joined(separator: "/")
    }

    /// Whether this path or a folder above it is hidden (its name starts with a dot), as
    /// `.obsidian` and `.trash` are.
    public var isHidden: Bool { Self.components(of: rawValue).contains { component in component.hasPrefix(".") } }

    /// Whether this path is `ancestor` or lies inside it. Components compare as Swift
    /// strings, so the same name stored in another Unicode normalization form still matches.
    public func isInside(_ ancestor: VaultPath) -> Bool {
        if ancestor.rawValue.isEmpty || rawValue == ancestor.rawValue { return true }
        let ancestorComponents = Self.components(of: ancestor.rawValue)
        let components = Self.components(of: rawValue)
        return components.count > ancestorComponents.count && zip(components, ancestorComponents).allSatisfy { component, ancestorComponent in component == ancestorComponent }
    }

    /// This path with `oldPrefix` replaced by `newPrefix`, for items inside a moved folder.
    public func replacingPrefix(_ oldPrefix: VaultPath, with newPrefix: VaultPath) throws -> VaultPath {
        guard isInside(oldPrefix) else { return self }
        let remainder = Self.components(of: rawValue).dropFirst(Self.components(of: oldPrefix.rawValue).count).joined(separator: "/")
        return remainder.isEmpty ? newPrefix : try newPrefix.appending(remainder)
    }
}

public enum DocumentKind: String, Codable, Sendable {
    case markdown, pdf, image, media, base, other
    public init(path: VaultPath) {
        self.init(fileExtension: path.fileExtension)
    }

    public init(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "md", "markdown": self = .markdown
        case "base": self = .base
        case "pdf": self = .pdf
        case "png", "jpg", "jpeg", "heic", "gif", "tiff", "webp", "svg": self = .image
        case "m4a", "mp4", "mov", "mp3", "wav", "aac": self = .media
        default: self = .other
        }
    }
}
