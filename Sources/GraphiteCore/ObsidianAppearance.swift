import Foundation

/// A font Graphite draws with, chosen from a CSS font-family list: a family installed on
/// the device, or one of the system font's designs, which CSS's generic families name.
public enum ResolvedFontFamily: Hashable, Sendable {
    /// The system font in one of its designs: San Francisco, New York, SF Mono or SF Rounded.
    case system(SystemFontDesign)
    /// An installed family, spelled as the system lists it.
    case installed(String)

    public enum SystemFontDesign: String, Hashable, Sendable {
        case standard, serif, monospaced, rounded
    }

    /// The family's name for people: an installed family's own name, or what the system
    /// design is called.
    public var displayName: String {
        switch self {
        case .installed(let family): family
        case .system(.standard): "System Font"
        case .system(.serif): "System Serif"
        case .system(.monospaced): "System Monospace"
        case .system(.rounded): "System Rounded"
        }
    }
}

/// A font setting as Obsidian stores it in `appearance.json`: a CSS font-family list, the
/// first family that is installed being the one used. Empty means the default font.
public struct FontFamilyList: Hashable, Sendable {
    /// The families in order of preference, without quotes.
    public var families: [String]

    public init(families: [String] = []) {
        self.families = families.map { family in family.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { family in !family.isEmpty }
    }

    /// Reads the value as Obsidian does: quotes are dropped and the list is split at commas.
    /// Obsidian removes only double quotes; single quotes, which CSS also allows and themes
    /// and hand-edited files use, are removed too when they surround a name.
    public init(obsidianValue: String?) {
        let names = (obsidianValue ?? "").replacingOccurrences(of: "\"", with: "").split(separator: ",").map { name in
            var trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedName.count >= 2, trimmedName.hasPrefix("'"), trimmedName.hasSuffix("'") { trimmedName = String(trimmedName.dropFirst().dropLast()) }
            return trimmedName
        }
        self.init(families: names)
    }

    /// The text Obsidian writes for this list: names joined by commas, without quotes or spaces.
    public var obsidianValue: String { families.joined(separator: ",") }

    public var isEmpty: Bool { families.isEmpty }

    /// CSS's generic families, which name a design of the system font rather than a family.
    private static let systemDesignsByGenericFamily: [String: ResolvedFontFamily.SystemFontDesign] = [
        "sans-serif": .standard, "system-ui": .standard, "-apple-system": .standard, "blinkmacsystemfont": .standard,
        "ui-sans-serif": .standard, "serif": .serif, "ui-serif": .serif, "monospace": .monospaced, "ui-monospace": .monospaced,
        "rounded": .rounded, "ui-rounded": .rounded,
    ]

    /// The first family of the list that can be drawn, as a browser picks one.
    /// - Parameter installedFamily: The installed family a name means, compared without
    ///   regard to case as CSS compares family names; nil when it is not installed.
    /// - Returns: Nil when no family of the list can be drawn, so the default font is used.
    public func firstAvailableFamily(installedFamily: (String) -> String?) -> ResolvedFontFamily? {
        for family in families {
            if let design = Self.systemDesignsByGenericFamily[family.lowercased()] { return .system(design) }
            // A CSS variable or function names no family Graphite can look up.
            if family.contains("(") { continue }
            if let installedName = installedFamily(family) { return .installed(installedName) }
        }
        return nil
    }

    /// The families of the list that are neither installed nor generic, which a device
    /// can lack, such as a font installed on another computer.
    public func missingFamilies(installedFamily: (String) -> String?) -> [String] {
        families.filter { family in
            Self.systemDesignsByGenericFamily[family.lowercased()] == nil && installedFamily(family) == nil
        }
    }
}

/// Obsidian's light, dark or system appearance (`theme`).
public enum ObsidianBaseTheme: String, Sendable {
    /// `moonstone`: light.
    case light = "moonstone"
    /// `obsidian`: dark.
    case dark = "obsidian"
    case system
}

/// The vault's `.obsidian/appearance.json`, as Obsidian 1.x writes it. Graphite reads and
/// writes its fonts and font size, reads its accent color, and keeps the theme and
/// snippets for later; every other key belongs to Obsidian and is kept as written.
public struct ObsidianAppearance: Equatable, Sendable {
    public static let configurationPath = ".obsidian/appearance.json"

    public static let interfaceFontFamilyKey = "interfaceFontFamily"
    public static let textFontFamilyKey = "textFontFamily"
    public static let monospaceFontFamilyKey = "monospaceFontFamily"
    public static let baseFontSizeKey = "baseFontSize"
    public static let baseFontSizeActionKey = "baseFontSizeAction"
    public static let accentColorKey = "accentColor"
    public static let themeKey = "theme"
    public static let cssThemeKey = "cssTheme"
    public static let enabledCssSnippetsKey = "enabledCssSnippets"

    /// Obsidian's font size slider: 10 to 30 pixels, 16 by default.
    public static let baseFontSizeRange: ClosedRange<Int> = 10...30
    public static let defaultBaseFontSize = 16

    /// "Interface font": the font of lists and other content around notes.
    public var interfaceFontFamilies = FontFamilyList()
    /// "Text font": the font of notes when editing and reading.
    public var textFontFamilies = FontFamilyList()
    /// "Monospace font": code, and properties shown as source.
    public var monospaceFontFamilies = FontFamilyList()
    /// "Font size", or nil when the file does not set one. Kept as written, even outside
    /// Obsidian's range; `effectiveBaseFontSize` is the size that applies.
    public var baseFontSize: Int?
    /// "Quick font size adjustment": changing the font size by pinching or with the keyboard.
    public var adjustsFontSizeQuickly = false
    /// The accent color as `#rrggbb`, or nil for Obsidian's default.
    public private(set) var accentHex: String?
    /// Light, dark or following the system; nil when the file does not say.
    public private(set) var baseTheme: ObsidianBaseTheme?
    /// The community theme's folder under `.obsidian/themes`, or empty for the default theme.
    /// Graphite does not draw themes yet.
    public private(set) var cssTheme = ""
    /// The CSS snippets turned on, by file name under `.obsidian/snippets` without `.css`.
    /// Graphite does not apply snippets yet.
    public private(set) var enabledCssSnippets: [String] = []

    /// Obsidian's defaults, as for a vault without the file.
    public init() {}

    /// Reads the file. A missing or empty file means Obsidian's defaults; a value of the
    /// wrong type is read as its default, as Obsidian treats it.
    public init(configurationData: Data?) throws {
        self.init(configuration: try ApplicationConfigurationObject(data: configurationData))
    }

    private init(configuration: ApplicationConfigurationObject) {
        interfaceFontFamilies = FontFamilyList(obsidianValue: configuration.value(named: Self.interfaceFontFamilyKey) as? String)
        textFontFamilies = FontFamilyList(obsidianValue: configuration.value(named: Self.textFontFamilyKey) as? String)
        monospaceFontFamilies = FontFamilyList(obsidianValue: configuration.value(named: Self.monospaceFontFamilyKey) as? String)
        baseFontSize = Self.wholeNumber(configuration.value(named: Self.baseFontSizeKey))
        adjustsFontSizeQuickly = configuration.value(named: Self.baseFontSizeActionKey) as? Bool ?? false
        accentHex = (configuration.value(named: Self.accentColorKey) as? String).flatMap(TextColorMarkup.canonicalHex)
        baseTheme = (configuration.value(named: Self.themeKey) as? String).flatMap(ObsidianBaseTheme.init(rawValue:))
        cssTheme = configuration.value(named: Self.cssThemeKey) as? String ?? ""
        enabledCssSnippets = (configuration.value(named: Self.enabledCssSnippetsKey) as? [Any])?.compactMap { snippet in snippet as? String } ?? []
    }

    /// The font size that applies: the file's, kept within Obsidian's range, or 16.
    public var effectiveBaseFontSize: Int {
        min(max(baseFontSize ?? Self.defaultBaseFontSize, Self.baseFontSizeRange.lowerBound), Self.baseFontSizeRange.upperBound)
    }

    /// A number Obsidian wrote, which JavaScript may have written with a fraction (`16.5`).
    private static func wholeNumber(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let size = number.doubleValue
        guard size.isFinite, abs(size) < 10_000 else { return nil }
        return Int(size.rounded())
    }

    /// Returns `existingData` with only the keys Graphite writes whose value differs from
    /// `previousAppearance` replaced, laid out as Obsidian writes the file.
    ///
    /// Keys the change did not touch keep what the file holds now, even if Obsidian changed
    /// them since `previousAppearance` was read. Unknown keys and their values survive
    /// exactly as written. Without `previousAppearance`, the file's own values are the
    /// starting point.
    public func mergedConfigurationData(existingData: Data?, changedFrom previousAppearance: ObsidianAppearance? = nil) throws -> Data {
        var configuration: ApplicationConfigurationObject
        do { configuration = try ApplicationConfigurationObject(data: existingData) }
        catch { throw GraphiteError.invalidFile("The Obsidian appearance file is not a JSON object, so Graphite will not change it.") }
        let previousValueTexts = Dictionary((previousAppearance ?? ObsidianAppearance(configuration: configuration)).ownedValueTexts) { firstText, _ in firstText }
        let changedValueTexts = ownedValueTexts.filter { key, valueText in previousValueTexts[key] != valueText }
        if changedValueTexts.isEmpty, let existingData { return existingData }
        for (key, valueText) in changedValueTexts { configuration.setValueText(valueText, forName: key) }
        return configuration.formattedData
    }

    /// Every key Graphite writes with the JSON text Obsidian stores for its value. The font
    /// size is present only once it is set, so a vault that never set it is not given one.
    private var ownedValueTexts: [(key: String, valueText: String)] {
        var valueTexts: [(key: String, valueText: String)] = [
            (Self.interfaceFontFamilyKey, ApplicationConfigurationObject.jsonText(for: interfaceFontFamilies.obsidianValue)),
            (Self.textFontFamilyKey, ApplicationConfigurationObject.jsonText(for: textFontFamilies.obsidianValue)),
            (Self.monospaceFontFamilyKey, ApplicationConfigurationObject.jsonText(for: monospaceFontFamilies.obsidianValue)),
        ]
        if let baseFontSize { valueTexts.append((Self.baseFontSizeKey, String(baseFontSize))) }
        valueTexts.append((Self.baseFontSizeActionKey, String(adjustsFontSizeQuickly)))
        return valueTexts
    }
}
