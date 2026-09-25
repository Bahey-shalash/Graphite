import Foundation

public struct VaultEntry: Sendable, Identifiable, Hashable {
    public var id: VaultPath { path }
    public let path: VaultPath
    public let isDirectory: Bool
    public let size: Int
    public let modified: Date
    /// The modification date when the file system does not record creation.
    public let created: Date
    public var kind: DocumentKind { DocumentKind(path: path) }
    public init(path: VaultPath, isDirectory: Bool, size: Int, modified: Date, created: Date? = nil) {
        self.path = path; self.isDirectory = isDirectory; self.size = size; self.modified = modified; self.created = created ?? modified
    }
}

/// Obsidian's "Deleted files" setting (`trashOption` in `.obsidian/app.json`).
public enum DeletionMethod: String, CaseIterable, Identifiable, Sendable {
    /// Move to the system's trash (`system`), Obsidian's default.
    case systemTrash = "system"
    /// Move to the vault's own `.trash` folder (`local`).
    case vaultTrash = "local"
    /// Delete for good (`none`).
    case permanent = "none"
    public var id: String { rawValue }
}

public enum DeletionOutcome: Equatable, Sendable {
    case movedToSystemTrash
    case movedToVaultTrash(VaultPath)
    case deleted
}

/// Names Graphite accepts for new and renamed files, following Obsidian's rules.
public enum FileNameRules {
    /// Characters no file name may contain on the platforms a vault syncs to.
    static let forbiddenCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
    /// Characters that would break links to a note (`[[Name#Heading]]`, `[[Name|alias]]`).
    static let linkBreakingCharacters = CharacterSet(charactersIn: "#^[]|")
    /// Line breaks, tabs and the other C0 and C1 control characters. No link syntax can
    /// contain a line break, and none of them can be typed into a name field on purpose.
    /// Format characters such as the zero-width joiner in emoji stay allowed.
    static let controlCharacters = CharacterSet(charactersIn: "\u{0}"..."\u{1F}")
        .union(CharacterSet(charactersIn: "\u{7F}"..."\u{9F}"))
        .union(.newlines)
    /// The longest file name Apple file systems store, in UTF-8 bytes.
    static let maximumFileNameBytes = 255
    /// Room kept for what Graphite adds to a typed name: an extension of up to eight
    /// characters (".md", ".base", ".markdown") and a number that tells it from an
    /// existing file (" 100000" at most).
    static let reservedSuffixBytes = 16

    /// Why `name` cannot be used, or nil when it can.
    public static func problem(with name: String, isNote: Bool) -> String? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { return "Enter a name." }
        if trimmedName.hasPrefix(".") { return "A name cannot start with a dot, or the file would be hidden." }
        if trimmedName.rangeOfCharacter(from: forbiddenCharacters) != nil { return "A name cannot contain any of these characters: / \\ : * ? \" < > |" }
        if trimmedName.rangeOfCharacter(from: controlCharacters) != nil { return "A name cannot contain line breaks or tabs." }
        if isNote, trimmedName.rangeOfCharacter(from: linkBreakingCharacters) != nil { return "A note's name cannot contain # ^ [ ] or |, which would break links to it." }
        if trimmedName.utf8.count > maximumFileNameBytes - reservedSuffixBytes { return "The name is too long." }
        return nil
    }
}

public actor VaultStore {
    public nonisolated let root: URL
    public nonisolated let writer: AtomicFileWriter
    private static let applicationConfigurationPath = ".obsidian/app.json"
    private static let maximumConfigurationBytes = 1_048_576
    /// The Obsidian settings Graphite last read or saved, which a save without an explicit
    /// starting point compares against: only the keys that differ are written, so a key
    /// Obsidian changed since then keeps its new value.
    private var settingsBaseline: ObsidianSettings?

    public init(root: URL, filePresenter: (any NSFilePresenter & Sendable)? = nil) {
        self.root = root
        writer = AtomicFileWriter(filePresenter: filePresenter)
    }

    public func children(of directory: VaultPath, sortedBy sortOrder: FileSortOrder = .alphabetical) throws -> [VaultEntry] {
        let url = try directory.url(in: root)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        let entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]).compactMap { child -> VaultEntry? in
            // One child that vanished since the listing, or that has a name no vault path
            // can hold, is left out instead of failing the whole folder.
            guard let values = try? child.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true,
                  let childPath = try? directory.appending(child.lastPathComponent) else { return nil }
            return VaultEntry(path: childPath, isDirectory: values.isDirectory == true, size: values.fileSize ?? 0,
                              modified: values.contentModificationDate ?? .distantPast, created: values.creationDate)
        }
        return sortOrder.sorted(entries)
    }

    public func read(_ path: VaultPath, maximumBytes: Int? = nil) throws -> FileSnapshot {
        try writer.read(path.url(in: root), maximumBytes: maximumBytes)
    }

    public func save(_ data: Data, at path: VaultPath, expecting: WriteExpectation) throws -> FileRevision {
        try writer.write(data, to: path.url(in: root), expecting: expecting)
    }

    public func fileExists(_ path: VaultPath) throws -> Bool {
        FileManager.default.fileExists(atPath: try path.url(in: root).path)
    }

    public func settings() throws -> ObsidianSettings {
        let url = try VaultPath(Self.applicationConfigurationPath).url(in: root)
        let settings = FileManager.default.fileExists(atPath: url.path)
            ? try ObsidianSettings(applicationConfigurationData: writer.read(url, maximumBytes: Self.maximumConfigurationBytes).data)
            : ObsidianSettings()
        settingsBaseline = settings
        return settings
    }

    /// Property types assigned in Obsidian (`.obsidian/types.json`). Missing or unreadable
    /// files mean no assignments, and types are then inferred from values.
    public func propertyTypes() -> [String: PropertyType] {
        guard let url = try? VaultPath(Self.propertyTypesPath).url(in: root),
              FileManager.default.fileExists(atPath: url.path),
              let snapshot = try? writer.read(url, maximumBytes: Self.maximumConfigurationBytes),
              let configuration = try? JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any],
              let assignedTypes = configuration["types"] as? [String: String] else { return [:] }
        return assignedTypes.compactMapValues(PropertyType.init(rawValue:))
    }

    /// Assigns a type to a property in `.obsidian/types.json`, as Obsidian's Properties view
    /// does, keeping the rest of the file. The values in notes are not converted.
    public func setPropertyType(_ type: PropertyType, forKey key: String) throws {
        try updatePropertyTypeAssignments { assignments in
            let existingKey = assignments.keys.first { assignedKey in assignedKey.caseInsensitiveCompare(key) == .orderedSame } ?? key
            assignments[existingKey] = type.rawValue
        }
    }

    /// Moves a property's assigned type to its new name after a rename.
    public func movePropertyType(from oldKey: String, to newKey: String) throws {
        try updatePropertyTypeAssignments { assignments in
            guard let assignedKey = assignments.keys.first(where: { assignedKey in assignedKey.caseInsensitiveCompare(oldKey) == .orderedSame }),
                  let type = assignments.removeValue(forKey: assignedKey) else { return }
            assignments[newKey] = type
        }
    }

    private static var propertyTypesPath: String { ".obsidian/types.json" }

    private func updatePropertyTypeAssignments(_ update: (inout [String: Any]) -> Void) throws {
        try saveConfiguration(at: Self.propertyTypesPath) { existingData in
            var configuration: [String: Any] = [:]
            if let existingData, !existingData.isEmpty {
                guard let existing = try JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
                    throw GraphiteError.invalidFile("“.obsidian/types.json” is not a JSON object, so Graphite leaves it unchanged.")
                }
                configuration = existing
            }
            var assignments = configuration["types"] as? [String: Any] ?? [:]
            let original = assignments as NSDictionary
            update(&assignments)
            // Unchanged assignments leave the file as it was, formatting included.
            if let existingData, original.isEqual(to: assignments) { return existingData }
            configuration["types"] = assignments
            return try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        }
    }

    /// Obsidian's bookmarks (`.obsidian/bookmarks.json`); none when missing.
    public func bookmarks() throws -> BookmarkList {
        try BookmarkList(configurationData: configurationData(at: BookmarkList.configurationPath))
    }

    /// Applies `change` to the bookmarks as they are in the file now, so a change made
    /// elsewhere meanwhile is kept, and returns the result.
    @discardableResult
    public func updateBookmarks(_ change: (inout BookmarkList) -> Void) throws -> BookmarkList {
        var updated = BookmarkList()
        // A vault without bookmarks gets a file only once there is one to keep.
        if configurationData(at: BookmarkList.configurationPath) == nil {
            change(&updated)
            if updated.items.isEmpty { return updated }
            updated = BookmarkList()
        }
        try saveConfiguration(at: BookmarkList.configurationPath) { existingData in
            let existing = try BookmarkList(configurationData: existingData)
            updated = existing
            change(&updated)
            // Unchanged bookmarks leave the file as it was, formatting included.
            if updated == existing, let existingData { return existingData }
            return try updated.configurationData()
        }
        return updated
    }

    /// Obsidian's Templates settings (`.obsidian/templates.json`); defaults when missing.
    public func templateSettings() -> TemplateSettings {
        TemplateSettings(configurationData: configurationData(at: TemplateSettings.configurationPath))
    }

    public func saveTemplateSettings(_ settings: TemplateSettings) throws {
        try saveConfiguration(at: TemplateSettings.configurationPath) { existingData in try settings.mergedConfigurationData(existingData: existingData) }
    }

    /// Obsidian's Daily notes settings (`.obsidian/daily-notes.json`); defaults when missing.
    public func dailyNoteSettings() -> DailyNoteSettings {
        DailyNoteSettings(configurationData: configurationData(at: DailyNoteSettings.configurationPath))
    }

    public func saveDailyNoteSettings(_ settings: DailyNoteSettings) throws {
        try saveConfiguration(at: DailyNoteSettings.configurationPath) { existingData in try settings.mergedConfigurationData(existingData: existingData) }
    }

    private func configurationData(at relativePath: String) -> Data? {
        guard let url = try? VaultPath(relativePath).url(in: root), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? writer.read(url, maximumBytes: Self.maximumConfigurationBytes).data
    }

    /// Rewrites an Obsidian settings file with `merge`, failing instead of overwriting
    /// when the file changes in the meantime.
    private func saveConfiguration(at relativePath: String, merge: (Data?) throws -> Data) throws {
        let path = try VaultPath(relativePath)
        let url = try path.url(in: root)
        try createDirectory(path.parent)
        let existingSnapshot = FileManager.default.fileExists(atPath: url.path) ? try writer.read(url, maximumBytes: Self.maximumConfigurationBytes) : nil
        let mergedConfiguration = try merge(existingSnapshot?.data)
        guard mergedConfiguration != existingSnapshot?.data else { return }
        try writer.write(mergedConfiguration, to: url, expecting: existingSnapshot.map { snapshot in .revision(snapshot.revision) } ?? .absent)
    }

    /// Writes the Graphite settings that changed into `.obsidian/app.json`, preserving
    /// everything else in the file. Fails instead of overwriting when the file changes
    /// during the merge.
    /// - Parameter previousSettings: The settings the caller changed, such as the copy a
    ///   settings screen shows. Only keys that differ from them are written, so a key
    ///   Obsidian changed since the caller's copy was read keeps its new value. Without
    ///   them, the settings Graphite last read or saved are the starting point.
    public func saveSettings(_ settings: ObsidianSettings, changedFrom previousSettings: ObsidianSettings? = nil) throws {
        let path = try VaultPath(Self.applicationConfigurationPath)
        let url = try path.url(in: root)
        let fileExists = FileManager.default.fileExists(atPath: url.path)
        let startingSettings = previousSettings ?? settingsBaseline
        // Without a file, a save that changes nothing has nothing to write.
        guard fileExists || settings != (startingSettings ?? ObsidianSettings()) else {
            settingsBaseline = settings
            return
        }
        try createDirectory(path.parent)
        let existingSnapshot = fileExists ? try writer.read(url, maximumBytes: Self.maximumConfigurationBytes) : nil
        let mergedConfiguration = try settings.mergedApplicationConfigurationData(existingData: existingSnapshot?.data, changedFrom: startingSettings)
        if mergedConfiguration != existingSnapshot?.data {
            try writer.write(mergedConfiguration, to: url, expecting: existingSnapshot.map { snapshot in .revision(snapshot.revision) } ?? .absent)
        }
        settingsBaseline = settings
    }

    public func createDirectory(_ path: VaultPath) throws {
        let url = try path.url(in: root)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try writer.createDirectory(at: url)
    }

    // MARK: File management

    /// Moves or renames a file or folder. Never replaces another item; a change of
    /// capitals alone is allowed, since case-insensitive volumes see the same item.
    public func move(_ path: VaultPath, to destination: VaultPath) throws {
        guard !path.rawValue.isEmpty, !destination.rawValue.isEmpty else { throw GraphiteError.invalidPath(path.rawValue) }
        guard !destination.isInside(path) || destination == path else { throw GraphiteError.unavailable("A folder cannot be moved into itself.") }
        let sourceLocation = try path.url(in: root)
        let destinationLocation = try destination.url(in: root)
        guard FileManager.default.fileExists(atPath: sourceLocation.path) else { throw GraphiteError.unavailable("“\(path.name)” is no longer in the vault.") }
        // The path check above compares names exactly. On a case-insensitive volume `a/B`
        // is inside `A` too, so the destination's existing folders are compared by identity.
        var destinationAncestor = destination.parent
        while destinationAncestor != .root {
            if Self.isSameItem(sourceLocation, try destinationAncestor.url(in: root)) { throw GraphiteError.unavailable("A folder cannot be moved into itself.") }
            destinationAncestor = destinationAncestor.parent
        }
        if FileManager.default.fileExists(atPath: destinationLocation.path), !Self.isSameItem(sourceLocation, destinationLocation) {
            throw GraphiteError.unavailable("“\(destination.rawValue)” already exists.")
        }
        try createDirectory(destination.parent)
        let coordinator = writer.makeCoordinator()
        var coordinationError: NSError?
        var moveResult: Result<Void, Error>?
        coordinator.coordinate(writingItemAt: sourceLocation, options: .forMoving, writingItemAt: destinationLocation, options: .forReplacing, error: &coordinationError) { coordinatedSource, coordinatedDestination in
            moveResult = Result {
                coordinator.item(at: coordinatedSource, willMoveTo: coordinatedDestination)
                try FileManager.default.moveItem(at: coordinatedSource, to: coordinatedDestination)
                coordinator.item(at: coordinatedSource, didMoveTo: coordinatedDestination)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let moveResult else { throw GraphiteError.unavailable("The file provider did not allow the move.") }
        try moveResult.get()
    }

    private static func isSameItem(_ firstLocation: URL, _ secondLocation: URL) -> Bool {
        guard let firstIdentifier = try? firstLocation.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let secondIdentifier = try? secondLocation.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else { return false }
        return firstIdentifier.isEqual(secondIdentifier)
    }

    /// Copies a file or folder beside itself as "Name 1", like Obsidian's "Make a copy".
    public func duplicate(_ path: VaultPath) throws -> VaultPath {
        let sourceLocation = try path.url(in: root)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceLocation.path, isDirectory: &isDirectory) else { throw GraphiteError.unavailable("“\(path.name)” is no longer in the vault.") }
        let copyPath = try availablePath(in: path.parent, stem: isDirectory.boolValue ? path.name : path.stem,
                                         extension: isDirectory.boolValue ? "" : (path.name as NSString).pathExtension, firstSuffix: 1)
        let copyLocation = try copyPath.url(in: root)
        if isDirectory.boolValue {
            var coordinationError: NSError?
            var copyResult: Result<Void, Error>?
            writer.makeCoordinator().coordinate(readingItemAt: sourceLocation, options: [], writingItemAt: copyLocation, options: .forReplacing, error: &coordinationError) { coordinatedSource, coordinatedCopy in
                copyResult = Result { try FileManager.default.copyItem(at: coordinatedSource, to: coordinatedCopy) }
            }
            if let coordinationError { throw coordinationError }
            guard let copyResult else { throw GraphiteError.unavailable("The file provider did not allow the copy.") }
            try copyResult.get()
        } else {
            try writer.copy(from: sourceLocation, to: copyLocation, expecting: .absent)
        }
        return copyPath
    }

    /// Creates an empty folder; fails if something already has that name.
    public func createFolder(named name: String, in directory: VaultPath) throws -> VaultPath {
        if let problem = FileNameRules.problem(with: name, isNote: false) { throw GraphiteError.unavailable(problem) }
        let path = try directory.appending(name.trimmingCharacters(in: .whitespaces))
        guard !FileManager.default.fileExists(atPath: try path.url(in: root).path) else { throw GraphiteError.unavailable("“\(path.name)” already exists.") }
        try createDirectory(path)
        return path
    }

    /// Removes a file or folder the way the vault's "Deleted files" setting says.
    public func delete(_ path: VaultPath, method: DeletionMethod) throws -> DeletionOutcome {
        guard !path.rawValue.isEmpty else { throw GraphiteError.invalidPath(path.rawValue) }
        let location = try path.url(in: root)
        guard FileManager.default.fileExists(atPath: location.path) else { throw GraphiteError.unavailable("“\(path.name)” is no longer in the vault.") }
        switch method {
        case .systemTrash:
            do {
                // A coordinated deletion first asks other apps and file providers presenting
                // the item to save and let go of it; `trashItem` does not tell them on macOS.
                // The call stays outside that accessor: on iPadOS `trashItem` coordinates the
                // move itself, and nesting it inside a coordinated write of the same item
                // deadlocked the vault's file actor.
                try coordinateDeletion(at: location) { _ in }
                try FileManager.default.trashItem(at: location, resultingItemURL: nil)
                return .movedToSystemTrash
            } catch {
                // Some file providers have no trash; the vault's own trash keeps the file safe.
                return .movedToVaultTrash(try moveToVaultTrash(path))
            }
        case .vaultTrash:
            return .movedToVaultTrash(try moveToVaultTrash(path))
        case .permanent:
            try coordinateDeletion(at: location) { coordinatedLocation in try FileManager.default.removeItem(at: coordinatedLocation) }
            return .deleted
        }
    }

    /// Obsidian's `.trash` folder at the vault's root.
    private func moveToVaultTrash(_ path: VaultPath) throws -> VaultPath {
        let trashDirectory = try VaultPath(".trash")
        try createDirectory(trashDirectory)
        let location = try path.url(in: root)
        let isDirectory = (try? location.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let trashedPath = try availablePath(in: trashDirectory, stem: isDirectory ? path.name : path.stem,
                                            extension: isDirectory ? "" : (path.name as NSString).pathExtension, firstSuffix: nil)
        try move(path, to: trashedPath)
        return trashedPath
    }

    private func coordinateDeletion(at location: URL, _ deletion: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var deletionResult: Result<Void, Error>?
        writer.makeCoordinator().coordinate(writingItemAt: location, options: .forDeleting, error: &coordinationError) { coordinatedLocation in
            deletionResult = Result { try deletion(coordinatedLocation) }
        }
        if let coordinationError { throw coordinationError }
        guard let deletionResult else { throw GraphiteError.unavailable("The file provider did not allow the deletion.") }
        try deletionResult.get()
    }

    /// "Name.md", else "Name 1.md", "Name 2.md"… (or starting at `firstSuffix`).
    private func availablePath(in directory: VaultPath, stem: String, extension fileExtension: String, firstSuffix: Int?) throws -> VaultPath {
        func name(_ suffix: Int?) -> String {
            let base = stem + (suffix.map { number in " \(number)" } ?? "")
            return fileExtension.isEmpty ? base : base + "." + fileExtension
        }
        func isAvailable(_ path: VaultPath) throws -> Bool { !FileManager.default.fileExists(atPath: try path.url(in: root).path) }
        if firstSuffix == nil {
            let path = try directory.appending(name(nil))
            if try isAvailable(path) { return path }
        }
        for suffix in max(firstSuffix ?? 1, 1)...100_000 {
            let path = try directory.appending(name(suffix))
            if try isAvailable(path) { return path }
        }
        throw GraphiteError.unavailable("Choose another name.")
    }

    /// "Name.ext", else "Name 1.ext", "Name 2.ext"…, the names Obsidian gives new files.
    /// A file without an extension gets no trailing dot, and leading dots are dropped from
    /// the stem, since a hidden file would vanish from Files and the sidebar while a note
    /// still embeds it (an imported `.env` becomes `env`).
    public func uniquePath(directory: VaultPath, stem: String, extension fileExtension: String) throws -> VaultPath {
        let trimmedStem = String(stem.trimmingCharacters(in: .whitespacesAndNewlines).drop { character in character == "." })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedStem.isEmpty, !trimmedStem.contains("/"), !trimmedStem.contains("\\"), !trimmedStem.contains("\n") else { throw GraphiteError.invalidPath(stem) }
        return try availablePath(in: directory, stem: trimmedStem, extension: fileExtension, firstSuffix: nil)
    }
}
