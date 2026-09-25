import Foundation

/// Obsidian's Templates settings, stored in `.obsidian/templates.json`.
public struct TemplateSettings: Equatable, Sendable {
    public static let configurationPath = ".obsidian/templates.json"

    /// The folder templates are chosen from; empty when none is set.
    public var folder: String
    public var dateFormat: String
    public var timeFormat: String

    public init(folder: String = "", dateFormat: String = MomentDateFormat.defaultDateFormat, timeFormat: String = MomentDateFormat.defaultTimeFormat) {
        self.folder = folder
        self.dateFormat = dateFormat
        self.timeFormat = timeFormat
    }

    /// Reads the file Obsidian writes; missing keys and empty formats take Obsidian's defaults.
    public init(configurationData: Data?) {
        let configuration = configurationData.flatMap { data in try? JSONSerialization.jsonObject(with: data) as? [String: Any] } ?? [:]
        self.init(folder: PluginConfiguration.folder(configuration["folder"]),
                  dateFormat: PluginConfiguration.nonEmpty(configuration["dateFormat"]) ?? MomentDateFormat.defaultDateFormat,
                  timeFormat: PluginConfiguration.nonEmpty(configuration["timeFormat"]) ?? MomentDateFormat.defaultTimeFormat)
    }

    /// The file with these settings, keeping any other keys it has.
    public func mergedConfigurationData(existingData: Data?) throws -> Data {
        try PluginConfiguration.merged(existingData: existingData, values: [
            "folder": folder, "dateFormat": dateFormat, "timeFormat": timeFormat,
        ])
    }

    public var folderPath: VaultPath? {
        folder.isEmpty ? nil : try? VaultPath(folder)
    }
}

/// Obsidian's Daily notes settings, stored in `.obsidian/daily-notes.json`.
public struct DailyNoteSettings: Equatable, Sendable {
    public static let configurationPath = ".obsidian/daily-notes.json"

    /// The note's name as a date format; it may contain `/` for folders by year or month.
    public var format: String
    public var folder: String
    /// The template's vault path, with or without `.md`; empty for none.
    public var template: String
    /// "Open daily note on startup".
    public var opensOnStartup: Bool

    public init(format: String = MomentDateFormat.defaultDateFormat, folder: String = "", template: String = "", opensOnStartup: Bool = false) {
        self.format = format
        self.folder = folder
        self.template = template
        self.opensOnStartup = opensOnStartup
    }

    public init(configurationData: Data?) {
        let configuration = configurationData.flatMap { data in try? JSONSerialization.jsonObject(with: data) as? [String: Any] } ?? [:]
        self.init(format: PluginConfiguration.nonEmpty(configuration["format"]) ?? MomentDateFormat.defaultDateFormat,
                  folder: PluginConfiguration.folder(configuration["folder"]),
                  template: PluginConfiguration.folder(configuration["template"]),
                  opensOnStartup: configuration["autorun"] as? Bool ?? false)
    }

    public func mergedConfigurationData(existingData: Data?) throws -> Data {
        try PluginConfiguration.merged(existingData: existingData, values: [
            "format": format == MomentDateFormat.defaultDateFormat ? "" : format, "folder": folder, "template": template, "autorun": opensOnStartup,
        ])
    }

    /// Where the daily note of `date` is: the folder, then the date in the format.
    public func notePath(for date: Date, timeZone: TimeZone = .current) throws -> VaultPath {
        let name = MomentDateFormat.string(from: date, format: format, timeZone: timeZone)
        guard !name.isEmpty else { throw GraphiteError.invalidPath(format) }
        let relativePath = (folder.isEmpty ? "" : folder + "/") + name + ".md"
        return try VaultPath(relativePath)
    }

    /// The day a note in the daily notes folder is for, from its path.
    public func date(ofNoteAt path: VaultPath, timeZone: TimeZone = .current) -> Date? {
        guard path.fileExtension.lowercased() == "md" else { return nil }
        var relativePath = String(path.rawValue.dropLast(3))
        if !folder.isEmpty {
            guard relativePath.hasPrefix(folder + "/") else { return nil }
            relativePath = String(relativePath.dropFirst(folder.count + 1))
        }
        return MomentDateFormat.date(from: relativePath, format: format, timeZone: timeZone)
    }

    public var templatePath: VaultPath? {
        guard !template.isEmpty else { return nil }
        return try? VaultPath(template.lowercased().hasSuffix(".md") ? template : template + ".md")
    }
}

enum PluginConfiguration {
    static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return text
    }

    /// A folder or file path as Obsidian stores it, without surrounding slashes.
    static func folder(_ value: Any?) -> String {
        ((value as? String) ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

    static func merged(existingData: Data?, values: [String: Any]) throws -> Data {
        var configuration: [String: Any] = [:]
        if let existingData, !existingData.isEmpty {
            guard let existing = try JSONSerialization.jsonObject(with: existingData) as? [String: Any] else {
                throw GraphiteError.invalidFile("The plugin's settings file is not a JSON object.")
            }
            configuration = existing
        }
        configuration.merge(values) { _, newValue in newValue }
        return try JSONSerialization.data(withJSONObject: configuration, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

/// Fills in Obsidian's template variables: `{{title}}`, `{{date}}` and `{{time}}`, each
/// with an optional format (`{{date:dddd, MMMM Do}}`). Graphite also reads date offsets
/// (`{{date+1d:YYYY-MM-DD}}`), `{{yesterday}}` and `{{tomorrow}}`, which daily-note
/// templates made for community plugins such as Periodic Notes use; Obsidian's own
/// Templates plugin leaves those as written.
public enum TemplateRenderer {
    private static let variablePattern = try? NSRegularExpression(
        pattern: "\\{\\{\\s*(title|date|time|yesterday|tomorrow)\\s*(?:([+-]\\d+)\\s*([yQMwdhms]))?\\s*(?::(.*?))?\\s*\\}\\}",
        options: .caseInsensitive)

    public static func render(_ template: String, title: String, date: Date, dateFormat: String, timeFormat: String, timeZone: TimeZone = .current) -> String {
        guard let variablePattern else { return template }
        let source = template as NSString
        var result = ""
        var location = 0
        for match in variablePattern.matches(in: template, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: location, length: match.range.location - location))
            location = NSMaxRange(match.range)
            let name = source.substring(with: match.range(at: 1)).lowercased()
            let format = match.range(at: 4).location == NSNotFound ? nil : source.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
            if name == "title" {
                result += title
                continue
            }
            var day = date
            if name == "yesterday" { day = offset(day, by: -1, unit: "d") }
            if name == "tomorrow" { day = offset(day, by: 1, unit: "d") }
            if match.range(at: 2).location != NSNotFound, let amount = Int(source.substring(with: match.range(at: 2))) {
                day = offset(day, by: amount, unit: source.substring(with: match.range(at: 3)))
            }
            let defaultFormat = name == "time" ? timeFormat : dateFormat
            result += MomentDateFormat.string(from: day, format: format.flatMap { format in format.isEmpty ? nil : format } ?? defaultFormat, timeZone: timeZone)
        }
        return result + source.substring(from: location)
    }

    private static func offset(_ date: Date, by amount: Int, unit: String) -> Date {
        let component: Calendar.Component
        var multiplier = 1
        switch unit {
        case "y": component = .year
        case "Q": component = .month; multiplier = 3
        case "M": component = .month
        case "w": component = .day; multiplier = 7
        case "d": component = .day
        case "h": component = .hour
        case "m": component = .minute
        default: component = .second
        }
        return Calendar(identifier: .gregorian).date(byAdding: component, value: amount * multiplier, to: date) ?? date
    }
}

/// A template inserted into a note, as Obsidian's Templates plugin does it: the body at
/// the cursor, and the template's properties added to the note's.
public enum TemplateInsertion {
    /// The template's properties and the text after them. Properties are nil when the
    /// template has none, or YAML that is not a key/value mapping (then it stays text).
    public static func parts(of renderedTemplate: String) -> (properties: [NoteProperty]?, body: String) {
        let source = renderedTemplate as NSString
        let frontmatterLength = FrontmatterLocator.length(in: source)
        guard frontmatterLength > 0, let frontmatter = try? MarkdownSemantics.parse(renderedTemplate).frontmatter,
              let properties = NoteProperties.parse(frontmatter) else { return (nil, renderedTemplate) }
        return (properties, source.substring(from: frontmatterLength))
    }

    /// The note's properties with the template's added. A property the note already has
    /// keeps its value, except that lists (tags, aliases, and other lists) gain the
    /// template's items they lack.
    public static func mergedProperties(note: [NoteProperty], template: [NoteProperty]) -> [NoteProperty] {
        var merged = note
        for templateProperty in template {
            guard let index = merged.firstIndex(where: { property in property.key == templateProperty.key }) else {
                merged.append(templateProperty)
                continue
            }
            switch (merged[index].value, templateProperty.value) {
            case (.list(let noteItems), .list(let templateItems)):
                merged[index].value = .list(noteItems + templateItems.filter { item in !noteItems.contains(item) })
            case (.list(let noteItems), .text(let templateItem)) where !templateItem.isEmpty:
                if !noteItems.contains(templateItem) { merged[index].value = .list(noteItems + [templateItem]) }
            case (.empty, _):
                merged[index].value = templateProperty.value
            default:
                break
            }
        }
        return merged
    }

    /// The edit that inserts a rendered template into `text` at `selection`.
    public static func edit(inserting renderedTemplate: String, into text: String, at selection: NSRange,
                            declaredTypes: [String: PropertyType] = [:]) -> MarkdownTextEdit {
        let source = text as NSString
        let frontmatterLength = FrontmatterLocator.length(in: source)
        // The body never goes inside the note's frontmatter.
        let location = min(max(selection.location, frontmatterLength), source.length)
        let length = min(max(0, NSMaxRange(selection) - location), source.length - location)
        let (templateProperties, body) = parts(of: renderedTemplate)
        let noteProperties: [NoteProperty]? = {
            guard frontmatterLength > 0 else { return [] }
            guard let frontmatter = try? MarkdownSemantics.parse(text).frontmatter else { return nil }
            return NoteProperties.parse(frontmatter, declaredTypes: declaredTypes)
        }()
        guard let templateProperties, !templateProperties.isEmpty, let noteProperties else {
            // Without properties to merge, or with note frontmatter Graphite cannot read,
            // the template goes in as it is.
            let insertion = templateProperties == nil ? renderedTemplate : body
            return MarkdownTextEdit(range: NSRange(location: location, length: length), replacement: insertion,
                                    selectionAfter: NSRange(location: location + (insertion as NSString).length, length: 0))
        }
        // One edit from the start of the note to the cursor, so it can be undone at once.
        let merged = mergedProperties(note: noteProperties, template: templateProperties)
        let lineEnding = text.contains("\r\n") ? "\r\n" : "\n"
        let newFrontmatter = "---" + lineEnding + NoteProperties.serialize(merged, lineEnding: lineEnding) + "---" + lineEnding
        let between = source.substring(with: NSRange(location: frontmatterLength, length: location - frontmatterLength))
        let replacement = newFrontmatter + between + body
        return MarkdownTextEdit(range: NSRange(location: 0, length: location + length), replacement: replacement,
                                selectionAfter: NSRange(location: (replacement as NSString).length, length: 0))
    }
}
