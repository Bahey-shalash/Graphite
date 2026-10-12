import Foundation
import GraphiteCore

/// Native note styling from the vault's Obsidian theme (Phase 1 of theme support): the theme
/// and snippets are resolved in WebKit off the main thread's work, cached on the device, and
/// handed to notes as one `NoteThemeStyle`.
extension WorkspaceModel {
    /// How long theme changes rest before they are resolved: a burst of file events, a
    /// Style Settings slider, or a theme and its snippets chosen together resolve once.
    static let themeRefreshDelay = Duration.milliseconds(300)

    /// Resolves the theme again after anything it depends on changed.
    func scheduleThemeRefresh() {
        themeRefreshTask?.cancel()
        themeRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.themeRefreshDelay) } catch { return }
            await self?.refreshVaultTheme()
        }
    }

    /// Reads the theme's inputs, and resolves them when they changed. Without a theme or
    /// snippets, or with the setting off, notes keep Graphite's look.
    func refreshVaultTheme() async {
        guard let store, preferences.usesVaultTheme else { applyNoteTheme(nil); return }
        let appearance = vaultAppearance
        let themeStyleSheet = appearance.cssTheme.isEmpty ? nil : await store.themeStyleSheet(named: appearance.cssTheme)
        var snippetStyleSheets: [String] = []
        for snippetName in appearance.enabledCssSnippets {
            if let snippet = await store.snippetStyleSheet(named: snippetName) { snippetStyleSheets.append(snippet) }
        }
        guard self.store === store else { return }
        guard themeStyleSheet != nil || !snippetStyleSheets.isEmpty else { applyNoteTheme(nil); lastThemeInputs = nil; return }
        // With community plugins running, Style Settings' values and the classes and variables
        // theme settings plugins set on their page apply too, as they do in Obsidian.
        let host = communityPlugins
        let pluginStyles = host.isRuntimeRunning ? host.pluginStyleSheets : ""
        // Obsidian gives its accent to themes as a hue, saturation and lightness.
        let accentStyle = CommunityPluginHost.hueSaturationLightness(ofHex: preferences.accentHex).map { accent in
            "--accent-h: \(accent.hue); --accent-s: \(accent.saturation)%; --accent-l: \(accent.lightness)%; "
        } ?? ""
        let inputs = ThemeResolverInputs(themeName: appearance.cssTheme,
                                         styleSheets: ([themeStyleSheet ?? ""] + snippetStyleSheets + [pluginStyles]).joined(separator: "\n"),
                                         bodyClasses: host.isRuntimeRunning ? host.pluginBodyClasses : "",
                                         bodyStyle: host.isRuntimeRunning ? host.pluginBodyStyle : "", accentStyle: accentStyle)
        guard inputs != lastThemeInputs || noteTheme == nil else { return }
        lastThemeInputs = inputs
        do {
            let tokens = try await themeResolver.tokens(for: inputs)
            guard self.store === store, lastThemeInputs == inputs, preferences.usesVaultTheme else { return }
            applyNoteTheme(NoteThemeStyle(tokens: tokens, graphiteAccent: PlatformColor.graphiteAccent(hex: preferences.accentHex) ?? .systemBlue))
        } catch {
            // A theme that cannot be measured leaves notes in Graphite's look; nothing is lost.
            lastThemeInputs = nil
            applyNoteTheme(nil)
        }
    }

    private func applyNoteTheme(_ style: NoteThemeStyle?) {
        guard style != noteTheme else { return }
        noteTheme = style
        // The theme's fonts apply where `appearance.json` names none.
        resolveNoteTypography()
    }
}
