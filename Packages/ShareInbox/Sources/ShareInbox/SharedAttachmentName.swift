import Foundation

/// Names of the files of a shared item. The app gives each its final name in the vault;
/// these only keep the item's own folder safe and readable.
public enum SharedAttachmentName {
    /// The stem of a file shared without a name ("Shared image" or "Shared file", say)
    /// gets the time it was shared, like Obsidian's "Pasted image 20261021153000".
    public static func fileName(suggestedName: String?, fileExtension: String?, unnamedStem: String, sharedAt date: Date, calendar: Calendar) -> String {
        let extensionSuffix = fileExtension.map { fileExtension in fileExtension.isEmpty ? "" : "." + fileExtension } ?? ""
        let trimmedSuggestion = (suggestedName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSuggestion.isEmpty else {
            let hasExtension = !extensionSuffix.isEmpty && trimmedSuggestion.lowercased().hasSuffix(extensionSuffix.lowercased())
            return plainFileName(hasExtension ? trimmedSuggestion : trimmedSuggestion + extensionSuffix)
        }
        return plainFileName(unnamedStem + " " + timestamp(of: date, calendar: calendar) + extensionSuffix)
    }

    /// `name` as one file name: its last path component, without control characters or
    /// colons, leading dots or surrounding spaces; "Shared file" when nothing is left.
    public static func plainFileName(_ name: String) -> String {
        let lastComponent = name.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        let unwantedCharacters = CharacterSet.controlCharacters.union(.newlines).union(CharacterSet(charactersIn: ":"))
        let cleaned = String(String.UnicodeScalarView(lastComponent.unicodeScalars.filter { scalar in !unwantedCharacters.contains(scalar) }))
        let withoutLeadingDots = String(cleaned.trimmingCharacters(in: .whitespaces).drop { character in character == "." })
            .trimmingCharacters(in: .whitespaces)
        return withoutLeadingDots.isEmpty ? unnamedFileName : withoutLeadingDots
    }

    /// Whether `name` is already what `plainFileName` makes of it, so it cannot leave the
    /// item's folder.
    public static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && plainFileName(name) == name
    }

    /// `fileName`, or "Name 2.ext", "Name 3.ext"… when it is in `existingNames`.
    public static func freeName(for fileName: String, avoiding existingNames: Set<String>) -> String {
        guard existingNames.contains(fileName) else { return fileName }
        let fileExtension = (fileName as NSString).pathExtension
        let stem = (fileName as NSString).deletingPathExtension
        var number = 2
        while true {
            let candidate = stem + " \(number)" + (fileExtension.isEmpty ? "" : "." + fileExtension)
            if !existingNames.contains(candidate) { return candidate }
            number += 1
        }
    }

    static let unnamedFileName = "Shared file"

    /// `yyyyMMddHHmmss` in the Gregorian calendar, the digits of Obsidian's pasted images.
    static func timestamp(of date: Date, calendar: Calendar) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = gregorian.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = String(format: "%04d", components.year ?? 0)
        let rest = [components.month, components.day, components.hour, components.minute, components.second]
            .map { component in String(format: "%02d", component ?? 0) }
        return year + rest.joined()
    }
}
