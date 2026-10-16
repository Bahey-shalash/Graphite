import Foundation
import GraphiteCore

/// The vault's Obsidian theme and CSS snippets in the plugins' page and its copies (Phase 2
/// of theme support): plugin panels, blocks and views look as the theme makes them look in
/// Obsidian, and Style Settings and Minimal Theme Settings find the theme's settings there.
/// Graphite's own note styling does not use the theme.
extension CommunityPluginHost {
    /// The theme chosen in `appearance.json`, the enabled snippets that exist, and the
    /// installed themes and snippets, as the runtime's `app.customCss` reports them.
    func vaultStyles() async -> [String: Any] {
        guard let workspace, let store = workspace.store else { return [:] }
        let appearance = workspace.vaultAppearance
        var styles: [String: Any] = [
            "installedThemes": await store.installedThemeNames(),
            "snippetNames": await store.snippetNames(),
        ]
        var themeName = ""
        if !appearance.cssTheme.isEmpty, let themeStyleSheet = await store.themeStyleSheet(named: appearance.cssTheme) {
            styles["theme"] = ["name": appearance.cssTheme, "css": themeStyleSheet]
            themeName = appearance.cssTheme
        }
        if activeThemeName != themeName { activeThemeName = themeName }
        // Obsidian gives its accent to the page as a hue, saturation and lightness, which
        // themes derive their accent colors from.
        if let accent = Self.hueSaturationLightness(ofHex: workspace.preferences.accentHex) {
            styles["accent"] = ["hue": accent.hue, "saturation": accent.saturation, "lightness": accent.lightness]
        }
        var snippets: [[String: String]] = []
        for snippetName in appearance.enabledCssSnippets {
            if let snippetStyleSheet = await store.snippetStyleSheet(named: snippetName) { snippets.append(["name": snippetName, "css": snippetStyleSheet]) }
        }
        styles["snippets"] = snippets
        return styles
    }

    /// `.obsidian/appearance.json` as a JSON object, for `vault.getConfig`.
    func appearanceConfiguration() async -> [String: Any] {
        guard let store = workspace?.store, let path = try? VaultPath(ObsidianAppearance.configurationPath),
              (try? await store.fileExists(path)) == true,
              let snapshot = try? await store.read(path, maximumBytes: 1_048_576),
              let configuration = try? JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any] else { return [:] }
        return configuration
    }

    /// Sends the vault's theme, snippets and appearance settings to the page again, after
    /// they changed in Graphite, in Obsidian, or in the theme and snippet files.
    func vaultStylesDidChange() {
        guard isRuntimeRunning else { return }
        styleUpdateTask?.cancel()
        styleUpdateTask = Task {
            // Changes made together (a theme and its snippets, a burst of file events) are sent once.
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            let message: [String: Any] = ["operation": "appearance.styles", "styles": await vaultStyles(),
                                          "appearanceConfiguration": await appearanceConfiguration()]
            guard !Task.isCancelled else { return }
            _ = try? await send(message)
        }
    }

    /// A plugin set an appearance setting Graphite shares with Obsidian (`vault.setConfig`,
    /// `app.customCss.setTheme`, Minimal Theme Settings' text size): Graphite writes it to
    /// `appearance.json` and shows it, as its own settings would.
    func applyAppearanceSetting(_ key: String, value: Any?) {
        guard let workspace else { return }
        workspace.updateVaultAppearance { appearance in
            switch key {
            case ObsidianAppearance.cssThemeKey:
                if let themeName = value as? String, themeName.isEmpty || ObsidianStyleFiles.isUsableName(themeName) { appearance.cssTheme = themeName }
            case ObsidianAppearance.enabledCssSnippetsKey:
                if let snippetNames = value as? [String] { appearance.enabledCssSnippets = snippetNames.filter(ObsidianStyleFiles.isUsableName) }
            case ObsidianAppearance.textFontFamilyKey:
                if let families = value as? String { appearance.textFontFamilies = FontFamilyList(obsidianValue: families) }
            case ObsidianAppearance.interfaceFontFamilyKey:
                if let families = value as? String { appearance.interfaceFontFamilies = FontFamilyList(obsidianValue: families) }
            case ObsidianAppearance.monospaceFontFamilyKey:
                if let families = value as? String { appearance.monospaceFontFamilies = FontFamilyList(obsidianValue: families) }
            case ObsidianAppearance.baseFontSizeKey:
                if let size = (value as? NSNumber)?.doubleValue, size.isFinite { appearance.baseFontSize = NoteFontSize.clamped(size) }
            case ObsidianAppearance.baseFontSizeActionKey:
                if let isOn = value as? Bool { appearance.adjustsFontSizeQuickly = isOn }
            default:
                break
            }
        }
    }

    /// `#rrggbb` as CSS's `hsl()` parts: hue in degrees, saturation and lightness in percent.
    nonisolated static func hueSaturationLightness(ofHex hex: String) -> (hue: Double, saturation: Double, lightness: Double)? {
        guard let canonical = TextColorMarkup.canonicalHex(hex), canonical.count >= 7 else { return nil }
        let digits = Array(canonical.dropFirst())
        func component(_ position: Int) -> Double { Double(Int(String(digits[position..<position + 2]), radix: 16) ?? 0) / 255 }
        let red = component(0), green = component(2), blue = component(4)
        let maximum = max(red, green, blue), minimum = min(red, green, blue), range = maximum - minimum
        let lightness = (maximum + minimum) / 2
        guard range > 0 else { return (0, 0, (lightness * 1000).rounded() / 10) }
        let saturation = range / (1 - abs(2 * lightness - 1))
        var hue: Double
        switch maximum {
        case red: hue = ((green - blue) / range).truncatingRemainder(dividingBy: 6)
        case green: hue = (blue - red) / range + 2
        default: hue = (red - green) / range + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return ((hue * 10).rounded() / 10, (saturation * 1000).rounded() / 10, (lightness * 1000).rounded() / 10)
    }
}
