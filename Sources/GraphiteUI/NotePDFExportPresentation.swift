/**
 * File: NotePDFExportPresentation.swift
 * -------------------------------------
 * Layer: UI
 * Description: Export to PDF and Print for a window: the action the note's More menu, the menu bar (Export as
 *              PDF…, Print… ⌘P on the Mac), the command palette and the file list call, and the sheets they open.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 21/10/2026
 */

import SwiftUI
import GraphiteCore

/// What a note's PDF is made for.
enum NotePDFPurpose {
    /// Saved where the person picks, after they choose the options.
    case save
    /// Handed to the system's print panel, made with the last options.
    case print
}

/// Makes a PDF of a note: the note in front when `path` is nil, otherwise the note at `path`.
struct NotePDFExportAction {
    let start: (_ path: VaultPath?, _ purpose: NotePDFPurpose) -> Void
}

extension EnvironmentValues {
    /// Set by `NotePDFExportPresentation` around a window while a vault is open.
    @Entry var notePDFExport: NotePDFExportAction? = nil
}

extension FocusedValues {
    /// The same action, for the menu bar's File menu (`GraphiteCommands`).
    @Entry var notePDFExport: NotePDFExportAction?
}

/// More › Export to PDF… and Print… in a note's menu.
struct NotePDFExportButton: View {
    @Environment(\.notePDFExport) private var notePDFExport

    var body: some View {
        Button("Export to PDF…", systemImage: "doc.richtext") { notePDFExport?.start(nil, .save) }
            .disabled(notePDFExport == nil)
        Button("Print…", systemImage: "printer") { notePDFExport?.start(nil, .print) }
            .disabled(notePDFExport == nil)
    }
}

/// File list › Export to PDF… on a note, which is read from its file unless it is in front.
struct NotePDFFileMenuButton: View {
    let path: VaultPath
    @Environment(\.notePDFExport) private var notePDFExport

    var body: some View {
        Button("Export to PDF…", systemImage: "doc.richtext") { notePDFExport?.start(path, .save) }
            .disabled(notePDFExport == nil)
    }
}

/// The command palette's Export to PDF and Print, added to its commands while a note is in front.
struct NotePDFPaletteCommands<Content: View>: View {
    let hasNoteInFront: Bool
    @ViewBuilder let content: ([PaletteCommand]) -> Content
    @Environment(\.notePDFExport) private var notePDFExport

    var body: some View {
        content(commands)
    }

    private var commands: [PaletteCommand] {
        guard hasNoteInFront, let notePDFExport else { return [] }
        return [PaletteCommand(id: "export-pdf", title: "Export to PDF", systemImage: "doc.richtext") { notePDFExport.start(nil, .save) },
                PaletteCommand(id: "print-file", title: "Print current file", systemImage: "printer") { notePDFExport.start(nil, .print) }]
    }
}

extension View {
    /// Lets the window's menus make a PDF of a note (`NotePDFExportPresentation`).
    func notePDFExport(note: MarkdownSession?, vault: ReadingVault?, preferences: GraphitePreferences, usesStrictLineBreaks: Bool,
                       appearance: NotePDFAppearance) -> some View {
        modifier(NotePDFExportPresentation(focusedNote: note, vault: vault, preferences: preferences, usesStrictLineBreaks: usesStrictLineBreaks,
                                           appearance: appearance))
    }
}

/// Presents a window's Export to PDF sheet, or the progress of a PDF made to print. The note in
/// front is printed as it is now, edits not yet saved included; another note is read from its
/// file. Nothing is written into the vault.
struct NotePDFExportPresentation: ViewModifier {
    /// The note in front, whose text may be ahead of its file.
    let focusedNote: MarkdownSession?
    /// The open vault; nil while none is, which leaves the menu items dimmed.
    let vault: ReadingVault?
    let preferences: GraphitePreferences
    let usesStrictLineBreaks: Bool
    let appearance: NotePDFAppearance
    /// The export whose sheet is on screen; nil while none is.
    @State private var export: NotePDFExport?
    /// A finished PDF, and its title, that the print panel shows once the progress sheet has closed.
    @State private var pendingPrint: (pdf: NotePDF, title: String)?
    @State private var failureMessage: String?

    /// The largest note file read to print, 16 MiB: far beyond any lecture note.
    static let maximumNoteBytes = 16 * 1_048_576

    func body(content: Content) -> some View {
        let action = vault.map { _ in NotePDFExportAction { path, purpose in Task { await start(path, purpose: purpose) } } }
        content
            .environment(\.notePDFExport, action)
            .focusedSceneValue(\.notePDFExport, action)
            .sheet(isPresented: Binding(get: { export != nil }, set: { isShown in if !isShown { export = nil } }), onDismiss: printPending) {
                if let export {
                    switch export.purpose {
                    case .save: NotePDFExportSheet(export: export)
                    case .print: NotePDFPrintProgressSheet(export: export) { pdf in pendingPrint = (pdf, export.title) }
                    }
                }
            }
            .alert("The note could not be read", isPresented: Binding(get: { failureMessage != nil },
                                                                     set: { isShown in if !isShown { failureMessage = nil } })) {
                Button("OK") { failureMessage = nil }
            } message: {
                Text(failureMessage ?? "")
            }
    }

    private func start(_ path: VaultPath?, purpose: NotePDFPurpose) async {
        guard let vault, export == nil else { return }
        do {
            let note = try await printedNote(at: path, in: vault)
            let source = NotePDFSource(text: note.text, path: note.path, vault: vault,
                                       readingConfiguration: readingConfiguration(declaredPropertyTypes: note.declaredPropertyTypes),
                                       title: note.path.stem, appearance: appearance)
            export = NotePDFExport(source: source, defaults: preferences.notePDFExport, purpose: purpose)
        } catch {
            failureMessage = NotePDFExport.message(for: error)
        }
    }

    /// The note's text: the note in front as it is now, another note from its file.
    private func printedNote(at path: VaultPath?, in vault: ReadingVault) async throws
        -> (text: String, path: VaultPath, declaredPropertyTypes: [String: PropertyType]) {
        if let focusedNote, path == nil || path == focusedNote.path {
            return (focusedNote.text, focusedNote.path, focusedNote.declaredPropertyTypes)
        }
        guard let path else { throw NotePDFExportError.noNoteInFront }
        let location = try path.url(in: vault.root)
        let maximumBytes = Self.maximumNoteBytes
        let text = try await Task.detached(priority: .userInitiated) {
            let snapshot = try AtomicFileWriter().read(location, maximumBytes: maximumBytes)
            guard let text = String(data: snapshot.data, encoding: .utf8) else { throw NotePDFExportError.noteNotText }
            return text
        }.value
        return (text, path, [:])
    }

    /// The reading view's settings of this vault that change how a note prints.
    private func readingConfiguration(declaredPropertyTypes: [String: PropertyType]) -> ReadingConfiguration {
        var configuration = ReadingConfiguration()
        configuration.usesStrictLineBreaks = usesStrictLineBreaks
        configuration.colorsEnabled = preferences.isEnabled(.colors)
        configuration.paletteHexByName = preferences.colorPaletteHexByName
        configuration.declaredPropertyTypes = declaredPropertyTypes
        return configuration
    }

    private func printPending() {
        guard let (pdf, title) = pendingPrint else { return }
        pendingPrint = nil
        NotePDFPrinting.showPrintPanel(for: pdf.data, title: title)
    }
}
