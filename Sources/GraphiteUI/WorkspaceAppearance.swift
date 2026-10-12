import Foundation
import GraphiteCore

/// The vault's Obsidian appearance settings: fonts, font size and accent, read from and
/// written to `.obsidian/appearance.json` so the vault looks the same in Obsidian.
extension WorkspaceModel {
    /// How long a font size change rests before it is written, so a pinch or a run of ⌘+
    /// presses writes the file once.
    static let appearanceSaveDelay = Duration.milliseconds(600)

    /// Whether `location` is a vault's `.obsidian/appearance.json`.
    nonisolated static func isAppearanceFile(_ location: URL) -> Bool {
        location.lastPathComponent == "appearance.json" && location.deletingLastPathComponent().lastPathComponent == ".obsidian"
    }

    /// The note text size at the default Dynamic Type size: the vault's font size; for a
    /// vault that sets none, the size this device chose before sizes were kept in the vault,
    /// or Obsidian's 16.
    var noteBaseFontSize: Int {
        if let vaultSize = vaultAppearance.baseFontSize { return NoteFontSize.clamped(vaultSize) }
        if let legacySize = preferences.legacyChosenTextSize { return NoteFontSize.clamped(Int(legacySize.rounded())) }
        return NoteFontSize.defaultSize
    }

    /// Shows `appearance`: fonts are resolved again only when a font list changed, and the
    /// vault's accent is handed to the preferences, which use it when no accent was chosen here.
    func applyVaultAppearance(_ appearance: ObsidianAppearance) {
        let fontsChanged = appearance.textFontFamilies != vaultAppearance.textFontFamilies
            || appearance.monospaceFontFamilies != vaultAppearance.monospaceFontFamilies
            || appearance.interfaceFontFamilies != vaultAppearance.interfaceFontFamilies
        if appearance != vaultAppearance { vaultAppearance = appearance }
        if preferences.vaultAccentHex != appearance.accentHex { preferences.vaultAccentHex = appearance.accentHex }
        guard fontsChanged else { return }
        resolveNoteTypography()
        activateMissingFonts()
    }

    /// Resolves the vault's font lists to installed families. Only an actual change is
    /// published, so open notes restyle only when a font they draw with changed.
    func resolveNoteTypography() {
        let resolved = NoteTypography(appearance: vaultAppearance)
        if resolved != noteTypography { noteTypography = resolved }
    }

    /// Fonts installed through Settings › General › Fonts are not listed until asked for by
    /// name; a vault naming one asks for it once, then resolves its fonts again.
    private func activateMissingFonts() {
        let lists = [vaultAppearance.textFontFamilies, vaultAppearance.monospaceFontFamilies, vaultAppearance.interfaceFontFamilies]
        let missingFamilies = Array(Set(lists.flatMap { list in list.missingFamilies { name in InstalledFontFamilies.family(named: name) } }))
        guard !missingFamilies.isEmpty else { return }
        InstalledFontFamilies.requestInstalledFonts(named: missingFamilies) { [weak self] becameAvailable in
            if becameAvailable { self?.resolveNoteTypography() }
        }
    }

    /// Reads `appearance.json` again, after Obsidian or another device changed it.
    func reloadVaultAppearance() async {
        guard let store else { return }
        // A change made here and not written yet is written first, so it is not lost to the
        // file's older value.
        if pendingAppearanceSave != nil { await saveVaultAppearanceNow() }
        do {
            let appearance = try await store.appearance()
            guard self.store === store else { return }
            applyVaultAppearance(appearance)
        } catch {
            errorMessage = "Graphite could not read the Obsidian appearance settings in this vault. " + error.localizedDescription
        }
    }

    /// Applies `change` at once and writes it to `appearance.json` once changes come to rest.
    func updateVaultAppearance(_ change: (inout ObsidianAppearance) -> Void) {
        guard store != nil else { return }
        var appearance = vaultAppearance
        change(&appearance)
        guard appearance != vaultAppearance else { return }
        applyVaultAppearance(appearance)
        pendingAppearanceSave?.cancel()
        pendingAppearanceSave = Task { [weak self] in
            do { try await Task.sleep(for: Self.appearanceSaveDelay) } catch { return }
            await self?.saveVaultAppearanceNow()
        }
    }

    /// Writes the appearance settings changed here, if any are waiting.
    func saveVaultAppearanceNow() async {
        guard let pendingSave = pendingAppearanceSave else { return }
        pendingSave.cancel()
        pendingAppearanceSave = nil
        guard let store else { return }
        do {
            // The store compares with the settings it last read or saved, so only the keys
            // changed here are written over what Obsidian may have changed meanwhile.
            try await store.saveAppearance(vaultAppearance)
        } catch {
            errorMessage = "Graphite could not save the appearance settings to this vault. " + error.localizedDescription
        }
    }

    // MARK: Font size

    /// Sets the vault's font size, kept within the sizes Graphite draws.
    func setNoteBaseFontSize(_ size: Int) {
        let clampedSize = NoteFontSize.clamped(size)
        guard clampedSize != noteBaseFontSize || vaultAppearance.baseFontSize == nil else { return }
        updateVaultAppearance { appearance in appearance.baseFontSize = clampedSize }
    }

    /// Makes notes one size larger or smaller, as ⌘+ and ⌘– do.
    func adjustNoteBaseFontSize(bySteps steps: Int) {
        setNoteBaseFontSize(noteBaseFontSize + steps)
    }

    /// Obsidian's reset: back to 16.
    func resetNoteBaseFontSize() {
        setNoteBaseFontSize(NoteFontSize.defaultSize)
    }

    /// Whether quick adjustment is on and a vault is open, so pinching and ⌘+, ⌘– and ⌘0
    /// change the font size.
    var adjustsNoteFontSizeQuickly: Bool { store != nil && vaultAppearance.adjustsFontSizeQuickly }
}
