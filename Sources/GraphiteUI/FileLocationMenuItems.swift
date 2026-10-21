/**
 * File: FileLocationMenuItems.swift
 * ---------------------------------
 * Layer: UI
 * Description: Where a file is: Reveal in Finder for a file, folder or the vault itself (Mac only), and the
 *              open file's Copy Graphite URL with Reveal in Finder for the "…" menus of notes and canvases.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import SwiftUI
import GraphiteCore
#if os(macOS)
import AppKit
#endif

/// Opens a Finder window with a file or folder of the vault selected, as Obsidian's Reveal in
/// Finder does. A folder is selected in its parent, not opened. Only the Mac has Finder:
/// elsewhere the button is left out.
struct RevealInFinderButton: View {
    let path: VaultPath
    /// The vault folder; nil while no vault is open, which disables the button.
    let vaultRoot: URL?
    var title = "Reveal in Finder"

    var body: some View {
        #if os(macOS)
        Button(title, systemImage: "finder") { reveal() }
            .disabled(vaultRoot == nil)
        #endif
    }

    #if os(macOS)
    private func reveal() {
        guard let vaultRoot, let location = try? path.url(in: vaultRoot) else { return } // A path leading outside the vault has nothing to show.
        NSWorkspace.shared.activateFileViewerSelecting([location])
    }
    #endif
}

/// The open file's Copy Graphite URL and Reveal in Finder, for the "…" menus of notes and
/// canvases.
struct FileLocationMenuItems: View {
    let path: VaultPath
    let openingLink: String
    let vaultRoot: URL?

    var body: some View {
        Button("Copy Graphite URL", systemImage: "link") { Pasteboard.copy(openingLink) }
        RevealInFinderButton(path: path, vaultRoot: vaultRoot)
    }
}
