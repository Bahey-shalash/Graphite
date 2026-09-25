import Foundation

/// Changes one frontmatter property of a note for inline editing in a base, leaving
/// everything after the frontmatter byte-for-byte unchanged.
public enum BasePropertyEditing {
    private static let frontmatterPattern = try? NSRegularExpression(pattern: "\\A---\\r?\\n(?:([\\s\\S]*?)\\r?\\n)?(?:---|\\.\\.\\.)[ \\t]*(?:\\r?\\n|$)")

    /// The note text with `key` set to `value`, added when missing, or removed when
    /// `value` is nil. Every other property keeps its exact YAML. Refuses rather than risk
    /// changing other properties: invalid YAML, a nested list Graphite would flatten, a
    /// value that would not read back as written, a new value for a property holding a
    /// mapping, or any other property whose YAML would change after rewriting the frontmatter.
    public static func settingProperty(_ key: String, to value: PropertyValue?, in noteText: String, declaredTypes: [String: PropertyType] = [:]) throws -> String {
        let trimmedKey = key.trimmingCharacters(in: .whitespaces)
        guard !trimmedKey.isEmpty else { throw GraphiteError.invalidFile("A property needs a name.") }
        let yaml = frontmatterYAML(in: noteText) ?? ""
        guard let properties = NoteProperties.parse(yaml, declaredTypes: declaredTypes),
              // `BaseFrontmatter` reads comment-only YAML as invalid; it holds no properties.
              let originalEntries = comparableEntries(ofYAML: yaml) ?? (properties.isEmpty ? [] : nil) else {
            throw GraphiteError.invalidFile("This note's properties are not valid YAML, so Graphite leaves them unchanged. Fix them in the note first.")
        }
        var updatedProperties = properties
        let existingIndex = updatedProperties.firstIndex { property in property.key == trimmedKey }
            ?? updatedProperties.firstIndex { property in property.key.caseInsensitiveCompare(trimmedKey) == .orderedSame }
        let changedKey = existingIndex.map { index in properties[index].key } ?? trimmedKey
        // Untouched properties are copied as they are written, so only the property being
        // replaced could lose the mappings or lists inside it. Removing it loses nothing
        // the user did not ask to remove.
        if value != nil, let originalEntry = originalEntries.first(where: { entry in entry.key == changedKey }) {
            if case .mapping = originalEntry.node {
                throw GraphiteError.invalidFile("This property holds nested values that Graphite cannot edit here. Edit it in the note.")
            }
            if containsNestedSequenceItems(originalEntry.node) {
                throw GraphiteError.invalidFile("This property holds lists of nested values that Graphite cannot write back without changing them. Edit this property in the note.")
            }
        }
        switch (existingIndex, value) {
        case (let index?, let value?): updatedProperties[index].value = value
        case (let index?, nil): updatedProperties.remove(at: index)
        case (nil, let value?): updatedProperties.append(NoteProperty(key: trimmedKey, value: value))
        case (nil, nil): return noteText
        }
        let updatedText = NoteProperties.replacingFrontmatter(in: noteText, with: updatedProperties, declaredTypes: declaredTypes)
        try verifyOtherPropertiesUnchanged(originalEntries, in: updatedText, except: changedKey)
        try verifyChangedProperty(changedKey, readsBackAs: value, in: updatedText, declaredTypes: declaredTypes)
        return updatedText
    }

    public static func frontmatterYAML(in noteText: String) -> String? {
        let foundationText = noteText as NSString
        guard let match = frontmatterPattern?.firstMatch(in: noteText, range: NSRange(location: 0, length: foundationText.length)) else { return nil }
        let yamlRange = match.range(at: 1)
        return yamlRange.location == NSNotFound ? "" : foundationText.substring(with: yamlRange)
    }

    /// The entries read as if more YAML followed, so that a block scalar at the end
    /// (`desc: >`) reads the same before and after a property is appended after it.
    private static func comparableEntries(ofYAML yaml: String) -> [BaseFrontmatterEntry]? {
        BaseFrontmatter.entries(fromYAML: yaml + "\n")
    }

    /// A list holding lists or mappings, which the base editor would write back as a list
    /// of text items.
    private static func containsNestedSequenceItems(_ node: BaseFrontmatterNode) -> Bool {
        switch node {
        case .scalar: return false
        case .sequence(let items): return items.contains { item in if case .scalar = item { return false } else { return true } }
        case .mapping(let entries): return entries.contains { entry in containsNestedSequenceItems(entry.node) }
        }
    }

    /// Compares the YAML nodes themselves (text, quoting, nesting), not their interpreted
    /// values: `007` rewritten as `7`, or a large ID rounded by a Double, reads as the same
    /// number but is a different property.
    private static func verifyOtherPropertiesUnchanged(_ originalEntries: [BaseFrontmatterEntry], in updatedText: String, except changedKey: String) throws {
        let updatedEntries = comparableEntries(ofYAML: frontmatterYAML(in: updatedText) ?? "") ?? []
        func otherNodes(_ entries: [BaseFrontmatterEntry]) -> [String: BaseFrontmatterNode] {
            var nodes: [String: BaseFrontmatterNode] = [:]
            for entry in entries where entry.key != changedKey { nodes[entry.key] = entry.node }
            return nodes
        }
        guard otherNodes(originalEntries) == otherNodes(updatedEntries) else {
            throw GraphiteError.invalidFile("Saving would change other properties of this note, so Graphite left it unchanged. Edit this property in the note.")
        }
    }

    /// The new value must read back as the value set: text that YAML cuts short at a ` #`
    /// or that makes the frontmatter invalid is refused instead of saved.
    private static func verifyChangedProperty(_ changedKey: String, readsBackAs value: PropertyValue?, in updatedText: String, declaredTypes: [String: PropertyType]) throws {
        let refusal = GraphiteError.invalidFile("Graphite cannot write this value so that it reads back the same. Edit this property in the note.")
        guard let updatedProperties = NoteProperties.parse(frontmatterYAML(in: updatedText) ?? "", declaredTypes: declaredTypes) else { throw refusal }
        let writtenValue = updatedProperties.first { property in property.key == changedKey }?.value
        switch (value, writtenValue) {
        case (nil, nil): return
        // Types differ by design (a number set on a text property reads back as text, an
        // empty value on `tags` as an empty list), so the shown text is what must survive.
        case (let value?, let writtenValue?) where value.displayText == writtenValue.displayText: return
        // Text set on `tags` reads back as the tags it names, as Obsidian reads it.
        case (.text(let text)?, .list(let tags)?) where tags == NoteProperties.tagNames(inText: text): return
        default: throw refusal
        }
    }
}
