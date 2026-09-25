import Foundation
import GraphiteCore
import GraphiteIndex

/// A property used somewhere in the vault, as the Properties view lists it.
struct PropertySummary: Identifiable, Equatable {
    let key: String
    let fileCount: Int
    let type: PropertyType
    var id: String { key.lowercased() }
}

/// Obsidian's Tags view and Properties view over the whole vault.
extension WorkspaceModel {
    /// Every tag with the notes using it; with `nested`, every level of nested tags, each
    /// counting the notes under it.
    func vaultTags(nested: Bool) async throws -> [TagCount] {
        guard let index else { return [] }
        return nested ? try await index.nestedTagCounts() : try await index.tags(matching: "", limit: Self.maximumListedTags)
    }

    private static var maximumListedTags: Int { 100_000 }

    func vaultProperties() async throws -> [PropertySummary] {
        guard let index, let store else { return [] }
        let usages = try await index.propertyUsages()
        let declaredTypes = await store.propertyTypes()
        return usages.map { usage in
            PropertySummary(key: usage.key, fileCount: usage.fileCount,
                            type: NoteProperties.type(ofKey: usage.key, sampleValues: usage.sampleValues, declaredTypes: declaredTypes))
        }
    }

    /// Shows the notes with a tag, nested tags included, in the sidebar's search.
    func searchForTag(_ tag: String) {
        searchQuery = "tag:#" + tag
    }

    /// Shows the notes with a property in the sidebar's search.
    func searchForProperty(_ key: String) {
        let needsQuotes = key.contains(where: { character in ":[]() ".contains(character) }) && !key.contains("\"")
        searchQuery = "[" + (needsQuotes ? "\"\(key)\"" : key) + "]"
    }

    /// Assigns a type in `.obsidian/types.json`, as Obsidian's Properties view does.
    func setPropertyType(_ type: PropertyType, forKey key: String) async {
        guard let store else { return }
        do {
            try await store.setPropertyType(type, forKey: key)
            propertyTypesVersion += 1
        } catch { errorMessage = error.localizedDescription }
    }

    /// Renames a property in every note that has it, changing only the name where it is
    /// written. Open notes change through their editors, so each can be undone there;
    /// other notes are written only if they did not change since they were read. Notes
    /// that could not be renamed are reported and left as they were.
    func renameProperty(_ key: String, to newKey: String) async {
        guard let store, let index else { return }
        let newName = newKey.trimmingCharacters(in: .whitespaces)
        // An alert's buttons cannot be disabled, so an empty name can reach here.
        guard !newName.isEmpty else { errorMessage = "A property needs a name."; return }
        guard newName != key else { return }
        do {
            try await saveOpenDocuments()
            let paths = try await index.paths(withPropertyKey: key)
            var renamedPaths: [VaultPath] = []
            var unchangedNotes: [(path: VaultPath, reason: String)] = []
            for path in paths {
                do {
                    if let session = openMarkdownSession(at: path) {
                        guard let edit = try PropertyRenaming.edit(renaming: key, to: newName, in: session.text, selection: session.selection) else { continue }
                        session.apply(edit)
                        // An editor applies the edit on its next update and autosaves it like
                        // typing; without one, the text has already changed.
                        if !session.isEditorAttached { try await session.save() }
                    } else {
                        let snapshot = try await store.read(path, maximumBytes: MarkdownSession.maximumEditableBytes)
                        guard let text = String(data: snapshot.data, encoding: .utf8) else { throw GraphiteError.invalidFile("It is not UTF-8 text.") }
                        guard let edit = try PropertyRenaming.edit(renaming: key, to: newName, in: text) else { continue }
                        let renamedText = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
                        _ = try await store.save(Data(renamedText.utf8), at: path, expecting: .revision(snapshot.revision))
                    }
                    renamedPaths.append(path)
                } catch {
                    unchangedNotes.append((path, error.localizedDescription))
                }
            }
            if !renamedPaths.isEmpty {
                try await store.movePropertyType(from: key, to: newName)
                propertyTypesVersion += 1
                refreshIndex(for: renamedPaths)
            }
            if !unchangedNotes.isEmpty {
                let listed = unchangedNotes.prefix(5).map { note in "“\(note.path.stem)”: \(note.reason)" }.joined(separator: "\n")
                let more = unchangedNotes.count > 5 ? "\nand \(unchangedNotes.count - 5) more." : ""
                errorMessage = "“\(key)” was renamed in \(Self.noteCount(renamedPaths.count)), but not in \(Self.noteCount(unchangedNotes.count)):\n" + listed + more
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private static func noteCount(_ count: Int) -> String { count == 1 ? "1 note" : "\(count) notes" }
}
