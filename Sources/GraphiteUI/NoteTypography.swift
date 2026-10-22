import SwiftUI
import CoreText
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The font families installed on this device, looked up by name without regard to case as
/// CSS looks font families up. Listed once and again only when fonts are added, so a font
/// setting is resolved without asking the system for every family each time.
@MainActor
enum InstalledFontFamilies {
    private static var familiesByLowercasedName: [String: String]?

    /// Every installed family, in the system's spelling, sorted by name.
    static var all: [String] {
        Array(lookup.values).sorted { leftFamily, rightFamily in leftFamily.localizedStandardCompare(rightFamily) == .orderedAscending }
    }

    /// The installed family `name` means, or nil when no installed family has that name.
    static func family(named name: String) -> String? {
        #if os(macOS)
        // The Mac answers for one family, ignoring case and in the system's spelling, as the
        // whole list does: listing every installed family took a tenth of a second each
        // time a vault opened (measured 2026-10-16).
        if familiesByLowercasedName == nil {
            guard let fontName = NSFontManager.shared.availableMembers(ofFontFamily: name)?.first?.first as? String,
                  let family = NSFont(name: fontName, size: NSFont.systemFontSize)?.familyName,
                  // Family names starting with a dot are the system font's private faces.
                  !family.hasPrefix(".") else { return nil }
            return family
        }
        #endif
        return lookup[name.lowercased()]
    }

    /// Lists the families again, after fonts were installed or activated while Graphite runs.
    static func refresh() {
        familiesByLowercasedName = nil
    }

    private static var lookup: [String: String] {
        if let familiesByLowercasedName { return familiesByLowercasedName }
        #if canImport(UIKit)
        let families = UIFont.familyNames
        #else
        let families = NSFontManager.shared.availableFontFamilies
        #endif
        // Family names starting with a dot are the system font's private faces.
        let listed = Dictionary(families.filter { family in !family.hasPrefix(".") }.map { family in (family.lowercased(), family) }) { firstFamily, _ in firstFamily }
        familiesByLowercasedName = listed
        return listed
    }

    #if os(iOS)
    /// The request itself, outside the main actor: Core Text answers on a queue of its own,
    /// and a closure made on the main actor would trap there.
    private nonisolated static func requestFonts(_ descriptors: CFArray, requestedCount: Int, answer: @escaping @Sendable (Bool) -> Void) {
        CTFontManagerRequestFonts(descriptors) { unresolvedDescriptors in
            answer(CFArrayGetCount(unresolvedDescriptors) < requestedCount)
        }
    }
    #endif

    /// Asks the system to make fonts available that were installed through Settings ›
    /// General › Fonts by another app: those are not listed until an app asks for them by
    /// name or someone picks them in the system's font picker. Calls `completion` with
    /// whether any of `families` became available.
    static func requestInstalledFonts(named families: [String], completion: @escaping @MainActor (Bool) -> Void) {
        #if os(iOS)
        guard !families.isEmpty else { completion(false); return }
        let descriptors = families.map { family in
            CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
        } as CFArray
        requestFonts(descriptors, requestedCount: families.count) { becameAvailable in
            Task { @MainActor in
                if becameAvailable { refresh() }
                completion(becameAvailable)
            }
        }
        #else
        completion(false)
        #endif
    }
}

/// The fonts notes and Graphite's content lists are drawn with, resolved from the vault's
/// Obsidian appearance settings once each time they change, never while typing.
struct NoteTypography: Hashable, Sendable {
    /// The font of notes, for body text and headings.
    var textFamily: ResolvedFontFamily = .system(.standard)
    /// The font of code, inline code and frontmatter shown as source.
    var monospaceFamily: ResolvedFontFamily = .system(.monospaced)
    /// The font of the file list, outline, tab titles, search results and backlinks.
    /// Controls, menus, alerts and Settings keep the system font, as Apple's guidelines ask.
    var interfaceFamily: ResolvedFontFamily = .system(.standard)
    /// Whether `appearance.json` names the text font, which then wins over a theme's heading fonts.
    var usesAppearanceTextFont = false

    /// Graphite's default fonts: the system font, and SF Mono for code.
    static let standard = NoteTypography()

    /// The first installed family of each of the vault's font lists, or the default where none is.
    /// The vault's theme gives its text and monospace fonts where `appearance.json` names
    /// none, as Obsidian's font settings override a theme's fonts.
    @MainActor
    init(appearance: ObsidianAppearance, theme: NoteThemeStyle? = nil) {
        let installedFamily: (String) -> String? = { name in InstalledFontFamilies.family(named: name) }
        textFamily = appearance.textFontFamilies.firstAvailableFamily(installedFamily: installedFamily) ?? theme?.textFamily ?? .system(.standard)
        monospaceFamily = appearance.monospaceFontFamilies.firstAvailableFamily(installedFamily: installedFamily) ?? theme?.monospaceFamily ?? .system(.monospaced)
        usesAppearanceTextFont = !appearance.textFontFamilies.isEmpty
        interfaceFamily = appearance.interfaceFontFamilies.firstAvailableFamily(installedFamily: installedFamily) ?? .system(.standard)
    }

    init() {}

    // MARK: UIKit and AppKit fonts

    func textFont(ofSize size: CGFloat, weight: PlatformFont.Weight = .regular) -> PlatformFont {
        Self.font(textFamily, size: size, weight: weight)
    }

    func monospaceFont(ofSize size: CGFloat, weight: PlatformFont.Weight = .regular) -> PlatformFont {
        Self.font(monospaceFamily, size: size, weight: weight)
    }

    /// The PostScript name diagrams find the text font by when it is an installed family; nil for the system font,
    /// which diagrams draw in its standard design (a font of the system's is not found by name).
    var diagramFontPostScriptName: String? {
        switch textFamily {
        case .installed: textFont(ofSize: PlatformFont.systemFontSize).fontName
        case .system: nil
        }
    }

    /// A font of `family` at `size`, as close to `weight` as the family has.
    static func font(_ family: ResolvedFontFamily, size: CGFloat, weight: PlatformFont.Weight) -> PlatformFont {
        switch family {
        case .system(.standard):
            return PlatformFont.systemFont(ofSize: size, weight: weight)
        case .system(.monospaced):
            return PlatformFont.monospacedSystemFont(ofSize: size, weight: weight)
        case .system(let design):
            let systemFont = PlatformFont.systemFont(ofSize: size, weight: weight)
            #if canImport(UIKit)
            let systemDesign: UIFontDescriptor.SystemDesign = design == .serif ? .serif : .rounded
            guard let descriptor = systemFont.fontDescriptor.withDesign(systemDesign) else { return systemFont }
            return UIFont(descriptor: descriptor, size: size)
            #else
            let systemDesign: NSFontDescriptor.SystemDesign = design == .serif ? .serif : .rounded
            guard let descriptor = systemFont.fontDescriptor.withDesign(systemDesign) else { return systemFont }
            return NSFont(descriptor: descriptor, size: size) ?? systemFont
            #endif
        case .installed(let familyName):
            #if canImport(UIKit)
            let descriptor = UIFontDescriptor(fontAttributes: [.family: familyName, .traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue]])
            return UIFont(descriptor: descriptor, size: size)
            #else
            let descriptor = NSFontDescriptor(fontAttributes: [.family: familyName, .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]])
            return NSFont(descriptor: descriptor, size: size) ?? PlatformFont.systemFont(ofSize: size, weight: weight)
            #endif
        }
    }

    // MARK: SwiftUI fonts

    /// The note's text at a size that already includes Dynamic Type (`noteTextSize`).
    func textSwiftUIFont(size: Double) -> Font {
        Self.swiftUIFont(textFamily, size: size)
    }

    func monospaceSwiftUIFont(size: Double) -> Font {
        Self.swiftUIFont(monospaceFamily, size: size)
    }

    /// The interface font for a text style, scaled with Dynamic Type as the style is.
    func interfaceSwiftUIFont(_ style: Font.TextStyle) -> Font {
        switch interfaceFamily {
        case .system(.standard): .system(style)
        case .system(let design): .system(style, design: Self.swiftUIDesign(design))
        case .installed(let familyName): .custom(familyName, size: Self.defaultPointSize(of: style), relativeTo: style)
        }
    }

    static func swiftUIFont(_ family: ResolvedFontFamily, size: Double) -> Font {
        switch family {
        case .system(let design): .system(size: size, design: swiftUIDesign(design))
        case .installed(let familyName): .custom(familyName, fixedSize: size)
        }
    }

    private static func swiftUIDesign(_ design: ResolvedFontFamily.SystemFontDesign) -> Font.Design {
        switch design {
        case .standard: .default
        case .serif: .serif
        case .monospaced: .monospaced
        case .rounded: .rounded
        }
    }

    /// Each text style's size at the default Dynamic Type size (Large), from Apple's tables.
    private static func defaultPointSize(of style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}

extension EnvironmentValues {
    /// The fonts chosen in Settings › Appearance › Font for this vault.
    @Entry var noteTypography = NoteTypography.standard
}

/// Draws content-like chrome (file names, headings in the outline, tab titles, search results
/// and mentions) in the vault's interface font. Bold Text is honored for an installed
/// family, as the system font honors it by itself.
private struct InterfaceFontModifier: ViewModifier {
    let style: Font.TextStyle
    let weight: Font.Weight?
    @Environment(\.noteTypography) private var typography
    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        var font = typography.interfaceSwiftUIFont(style)
        if let weight {
            font = font.weight(weight)
        } else if legibilityWeight == .bold, case .installed = typography.interfaceFamily {
            font = font.weight(.semibold)
        }
        return content.font(font)
    }
}

extension View {
    /// `.font(style)` in the vault's interface font: the system font unless one is chosen.
    func interfaceFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(InterfaceFontModifier(style: style, weight: weight))
    }
}

/// The note text size as Obsidian sets it: pixels taken as points, at the default Dynamic
/// Type size, so 16 is Obsidian's default and larger system text makes it larger still.
enum NoteFontSize {
    /// Obsidian's slider runs from 10 to 30; Graphite starts at 11, Apple's smallest text
    /// size, so every step of the slider changes what is drawn.
    static let adjustableRange: ClosedRange<Int> = 11...ObsidianAppearance.baseFontSizeRange.upperBound
    static let defaultSize = ObsidianAppearance.defaultBaseFontSize

    static func clamped(_ size: Int) -> Int {
        min(max(size, adjustableRange.lowerBound), adjustableRange.upperBound)
    }

    /// A size from a measure that can be anything, such as a plugin's setting or a pinch's
    /// scale: clamped before it becomes a whole number, as a value past `Int`'s range
    /// would stop the app.
    static func clamped(_ size: Double) -> Int {
        guard size.isFinite else { return defaultSize }
        return Int(min(max(size, Double(adjustableRange.lowerBound)), Double(adjustableRange.upperBound)).rounded())
    }

    /// The size a pinch that has scaled the text by `scale` arrives at, from `startingSize`.
    /// Sizes move in whole steps, as Obsidian's do.
    static func size(afterPinchingBy scale: CGFloat, from startingSize: Int) -> Int {
        guard scale.isFinite, scale > 0 else { return startingSize }
        return clamped(Double(CGFloat(startingSize) * scale))
    }
}
