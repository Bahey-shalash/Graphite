import SwiftUI
import GraphiteCore

/// What the core plugin Page Preview reads and opens in the open vault (`LinkPreviewLayer`).
extension WorkspaceModel {
    /// How a preview card reads the vault's notes: as an embedded note reads in the reading
    /// view, without properties, at the notes' text size; nil while no vault is open.
    func linkPreviewReading(at dynamicTypeSize: DynamicTypeSize) -> LinkPreviewReading? {
        guard let vault = ReadingVault(folderAccess?.root, index, store: store) else { return nil }
        let configuration = ReadingConfiguration(usesReadableLineLength: false, usesStrictLineBreaks: vaultSettings.usesStrictLineBreaks,
                                                 colorsEnabled: preferences.isEnabled(.colors), paletteHexByName: preferences.colorPaletteHexByName,
                                                 showsProperties: false,
                                                 textSize: GraphitePreferences.noteTextSize(Double(noteBaseFontSize), for: dynamicTypeSize),
                                                 drawingVersion: drawingVersion, indexVersion: indexVersion, marksUnresolvedLinks: noteTheme != nil)
        return LinkPreviewReading(vault: vault, configuration: configuration)
    }

    /// The vault as preview cards read it; their links open as the note's own do, their
    /// PDFs at their page.
    var linkPreviewVault: LinkPreviewVault {
        let actions = LinkPreviewActions(follow: { [weak self] target, isWiki, source in
                                             Task { await self?.follow(target, from: source, isWiki: isWiki) }
                                         },
                                         openPDF: { [weak self] path, pageIndex in
                                             Task { await self?.open(path, pdfPageIndex: pageIndex) }
                                         })
        return LinkPreviewVault(clock: clock, reading: { [weak self] dynamicTypeSize in self?.linkPreviewReading(at: dynamicTypeSize) }, actions: actions)
    }
}
