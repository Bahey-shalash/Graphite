import Foundation
import Observation
import GraphiteCore
import GraphiteApple

/// What one tab has open: the editor session of its note or PDF, and a heading or search
/// match waiting to be shown there.
@MainActor @Observable
final class TabDocument {
    /// The file the sessions belong to; nil until the tab's file is loaded. A tab restored
    /// at launch, or whose file was renamed, loads when it is shown.
    var loadedPath: VaultPath?
    var markdownSession: MarkdownSession?
    var pdfSession: PDFSession?
    /// A heading to show once the note is open (from `[[Note#Heading]]` or the outline).
    var headingScrollRequest: HeadingScrollRequest?
    /// The view a `[[Books.base#Gallery]]` link asked the tab's base to show.
    var baseViewRequest: BaseViewRequest?
    var isOpening = false
    /// Why the tab's file could not be opened, shown in the tab until it is tried again.
    var loadFailure: LoadFailure?
    /// Identifies the latest open request, so a slower earlier one cannot replace it.
    @ObservationIgnored var requestIdentifier = UUID()
    /// A PDF let go of while its tab was hidden, and the page it reopens at.
    @ObservationIgnored var releasedPDFPage: (path: VaultPath, pageIndex: Int)?
    /// When the tab was last seen on screen, to keep the most recently hidden PDF open.
    @ObservationIgnored var lastVisibleTime = ContinuousClock.now

    var hasUnsavedChanges: Bool {
        markdownSession?.hasUnsavedChanges == true || pdfSession?.hasUnsavedChanges == true
    }

    /// Forgets the sessions after their file moved; the tab loads the file again.
    func unload() {
        loadedPath = nil; markdownSession = nil; pdfSession = nil
    }

    func save() async throws {
        try await markdownSession?.save()
        try await pdfSession?.save()
    }

    /// Saves until nothing is left unsaved. The editor stays editable while a save runs, so
    /// a single save can miss text typed during it; callers let the sessions go right after.
    func saveAllChanges() async throws {
        repeat { try await save() } while hasUnsavedChanges
    }
}

/// A view of a `.base` file to show, named by a link's `#View` part.
struct BaseViewRequest: Equatable {
    let path: VaultPath
    let viewName: String
}

/// A file a tab could not open, and why.
struct LoadFailure: Equatable {
    let path: VaultPath
    let message: String
    /// A PDF that opens only with its password, which the tab asks for.
    var needsPassword = false
    /// The page a link asked for, shown once the PDF is unlocked.
    var requestedPageIndex: Int?
}

/// Where a file opens.
enum TabPlacement {
    /// The active tab, or a new tab beside it when the active tab is pinned.
    case currentTab
    case newTab
    /// The other side of the split, created when needed ("Open to the right").
    case otherGroup
}

/// Tabs and the split, as in Obsidian: each tab has its own file, history, and pin; the
/// layout is remembered per vault.
extension WorkspaceModel {
    static func tabLayoutKey(for vaultIdentifier: UUID) -> String {
        "GraphiteTabLayout." + vaultIdentifier.uuidString
    }

    var activeDocument: TabDocument { document(for: layout.activeTab.id) }

    /// What opening a file on the other side is called: that side is on the left while
    /// the right side is focused.
    var openOnOtherSideTitle: String {
        layout.isSplit && layout.groups.last?.id == layout.focusedGroupID ? "Open to the Left" : "Open to the Right"
    }

    func document(for tabID: UUID) -> TabDocument {
        if let document = tabDocuments[tabID] { return document }
        let document = TabDocument()
        // A view can still ask for a tab that has just closed; its document is not kept.
        if layout.tab(withID: tabID) != nil { tabDocuments[tabID] = document }
        return document
    }

    /// The open note with this path, in whichever tab it is.
    func openMarkdownSession(at path: VaultPath) -> MarkdownSession? {
        tabDocuments.values.lazy.compactMap(\.markdownSession).first { session in session.path == path }
    }

    // MARK: Switching

    /// Shows a tab and focuses its side. The tab it replaces on screen is saved, since its
    /// editor, and the editor's pending autosave, go away.
    func activateTab(_ tabID: UUID) {
        // Every text view that takes focus asks for this; writing `layout` for the tab that
        // already has focus would redraw every view that reads it.
        guard layout.activeTab.id != tabID else { return }
        let previousTabID = layout.group(containing: tabID)?.activeTabID
        layout.focus(tabID: tabID)
        if let previousTabID, previousTabID != tabID { saveInBackground(previousTabID) }
    }

    /// Shows a tab in its group without moving focus, as when a link shows a file
    /// already open on the other side.
    func revealTab(_ tabID: UUID) {
        let previousTabID = layout.group(containing: tabID)?.activeTabID
        layout.activateWithoutFocus(tabID: tabID)
        if let previousTabID, previousTabID != tabID { saveInBackground(previousTabID) }
    }

    func focusGroup(_ groupID: UUID) {
        guard layout.focusedGroupID != groupID else { return }
        layout.focus(groupID: groupID)
    }

    func activateNeighborTab(forward: Bool) {
        let previousTabID = layout.activeTab.id
        layout.activateNeighborTab(forward: forward)
        if layout.activeTab.id != previousTabID { saveInBackground(previousTabID) }
    }

    func activateTab(atPosition position: Int) {
        let previousTabID = layout.activeTab.id
        layout.activateTab(atPosition: position)
        if layout.activeTab.id != previousTabID { saveInBackground(previousTabID) }
    }

    func openNewTab(inGroup groupID: UUID? = nil) {
        let previousTabID = layout.activeTab.id
        layout.addTab(inGroup: groupID)
        saveInBackground(previousTabID)
    }

    /// Opens an empty group on the right, or focuses it when the layout is already split.
    func splitRight() {
        layout.openOtherGroup()
    }

    func togglePin(_ tabID: UUID) {
        guard let tab = layout.tab(withID: tabID) else { return }
        layout.setPinned(!tab.isPinned, tabID: tabID)
    }

    func moveTabToOtherGroup(_ tabID: UUID) {
        layout.moveTabToOtherGroup(tabID)
    }

    func moveTab(_ tabID: UUID, toGroup groupID: UUID, at position: Int) {
        layout.moveTab(tabID, toGroup: groupID, at: position)
    }

    // MARK: Closing

    /// Closes a tab after saving its file. A tab whose file cannot be saved stays open.
    func closeTab(_ tabID: UUID) async {
        guard await saveBeforeClosing([tabID]) else { return }
        layout.closeTab(tabID)
        tabDocuments[tabID] = nil
    }

    func closeOtherTabs(keeping tabID: UUID) async {
        guard let group = layout.group(containing: tabID) else { return }
        let closingTabs = group.tabs.filter { tab in tab.id != tabID && !tab.isPinned }.map(\.id)
        guard await saveBeforeClosing(closingTabs) else { return }
        for closedTabID in layout.closeOtherTabs(keeping: tabID) { tabDocuments[closedTabID] = nil }
    }

    /// Closes one side of the split with its tabs.
    func closeGroup(_ groupID: UUID) async {
        guard let group = layout.groups.first(where: { group in group.id == groupID }) else { return }
        guard await saveBeforeClosing(group.tabs.map(\.id)) else { return }
        for closedTabID in layout.closeGroup(groupID) { tabDocuments[closedTabID] = nil }
    }

    func reopenClosedTab() async {
        guard let path = layout.popClosedPath() else { return }
        await open(path, placement: .newTab)
    }

    private func saveBeforeClosing(_ tabIDs: [UUID]) async -> Bool {
        // A tab on screen stays editable while the others save, so all are checked again.
        repeat {
            for tabID in tabIDs {
                guard let document = tabDocuments[tabID] else { continue }
                do { try await document.saveAllChanges() } catch {
                    let name = layout.tab(withID: tabID)?.path?.name ?? "The file"
                    errorMessage = "“\(name)” could not be saved, so its tab stays open. " + error.localizedDescription
                    return false
                }
            }
        } while tabIDs.contains { tabID in tabDocuments[tabID]?.hasUnsavedChanges == true }
        return true
    }

    private func saveInBackground(_ tabID: UUID) {
        guard let document = tabDocuments[tabID] else { return }
        Task {
            do {
                try await document.save()
                releaseHiddenPDFSessions()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    /// Hidden tabs keep at most this many PDFs open; the others are let go once saved.
    private static let maximumHiddenPDFSessionCount = 1

    /// Lets go of the PDFs of hidden tabs, beyond the most recently hidden one, so memory
    /// does not grow with every PDF ever opened in a tab. A PDF with unsaved edits, a save
    /// running, or a conflict is kept. A released tab reopens its PDF, at the same page,
    /// when it is shown again, which loses PDFKit's undo history for it.
    private func releaseHiddenPDFSessions() {
        let visibleTabIDs = Set(layout.groups.map(\.activeTabID))
        let now = ContinuousClock.now
        for tabID in visibleTabIDs { tabDocuments[tabID]?.lastVisibleTime = now }
        let hiddenPDFDocuments = tabDocuments.filter { tabID, document in !visibleTabIDs.contains(tabID) && document.pdfSession != nil }
            .values.sorted { leftDocument, rightDocument in leftDocument.lastVisibleTime > rightDocument.lastVisibleTime }
        for document in hiddenPDFDocuments.dropFirst(Self.maximumHiddenPDFSessionCount) {
            guard let session = document.pdfSession, let path = document.loadedPath, !document.isOpening,
                  !session.hasUnsavedChanges, !session.isSaving, !session.hasExternalConflict else { continue }
            document.releasedPDFPage = (path, session.currentPageIndex)
            document.unload()
        }
    }

    // MARK: History

    func goBack() async { await moveInHistory(forward: false) }
    func goForward() async { await moveInHistory(forward: true) }

    /// Moves through the active tab's history. A file already open in another tab is
    /// shown there rather than opened twice.
    private func moveInHistory(forward: Bool) async {
        let tabID = layout.activeTab.id
        guard let target = layout.historyTarget(ofTab: tabID, forward: forward) else { return }
        if let otherTabID = layout.tabID(showing: target), otherTabID != tabID {
            activateTab(otherTabID)
            return
        }
        _ = layout.moveInHistory(ofTab: tabID, forward: forward)
        let didOpen = await load(target, into: tabID, pdfPageIndex: nil, recordsHistory: false)
        if !didOpen, layout.tab(withID: tabID)?.path != target {
            // The tab stays where it was. Only an entry whose file is gone is dropped: a load
            // can also fail for a while, as on a save conflict or a read error.
            _ = layout.moveInHistory(ofTab: tabID, forward: !forward)
            if let root = folderAccess?.root, let location = try? target.url(in: root), !FileManager.default.fileExists(atPath: location.path) {
                layout.removeFromHistory(inside: target, ofTab: tabID)
            }
        }
    }

    // MARK: Loading

    /// Loads the tab's file when it is shown for the first time, or again after it moved.
    func loadDocumentIfNeeded(for tabID: UUID) async {
        guard let path = layout.tab(withID: tabID)?.path else { return }
        let document = document(for: tabID)
        guard document.loadedPath != path, !document.isOpening, document.loadFailure?.path != path else { return }
        // A failure shows in the tab itself; an alert for every restored tab would pile up.
        await load(path, into: tabID, pdfPageIndex: nil, recordsHistory: false, reportsFailure: false)
    }

    /// Opens a password-protected PDF in its tab. The password is kept in memory for this
    /// session only, so the PDF reopens without asking until Graphite quits.
    func unlockPDF(inTab tabID: UUID, password: String) async {
        guard let path = layout.tab(withID: tabID)?.path else { return }
        pdfPasswords[path] = password
        let requestedPageIndex = document(for: tabID).loadFailure?.requestedPageIndex
        let didOpen = await load(path, into: tabID, pdfPageIndex: requestedPageIndex, recordsHistory: false, reportsFailure: false)
        if !didOpen, document(for: tabID).loadFailure?.needsPassword == true { pdfPasswords[path] = nil }
    }

    /// Opens a tab's file again after it could not be opened.
    func retryLoading(tabID: UUID) async {
        document(for: tabID).loadFailure = nil
        await loadDocumentIfNeeded(for: tabID)
    }

    /// Opens `path` in a tab, replacing what it showed, and returns whether it did.
    /// - Parameter reportsFailure: False to show a failure only in the tab, not in an alert.
    @discardableResult
    func load(_ path: VaultPath, into tabID: UUID, pdfPageIndex: Int?, recordsHistory: Bool, reportsFailure: Bool = true) async -> Bool {
        guard let store, let folderAccess else { return false }
        let document = document(for: tabID)
        let pdfPageIndex = pdfPageIndex ?? document.releasedPDFPage.flatMap { releasedPage in releasedPage.path == path ? releasedPage.pageIndex : nil }
        let requestIdentifier = UUID()
        document.requestIdentifier = requestIdentifier
        document.isOpening = true
        defer { if document.requestIdentifier == requestIdentifier { document.isOpening = false } }
        do {
            try await document.save()
            let newMarkdown: MarkdownSession?
            let newPDF: PDFSession?
            switch DocumentKind(path: path) {
            case .markdown:
                let snapshot = try await store.read(path, maximumBytes: MarkdownSession.maximumEditableBytes)
                newMarkdown = try MarkdownSession(path: path, snapshot: snapshot, store: store) { [weak self] savedPath in self?.refreshIndex(for: [savedPath]) }
                newMarkdown?.viewMode = preferences.initialNoteViewMode
                if let newMarkdown { restoreFolds(of: newMarkdown); watchForRecovery(newMarkdown) }
                newPDF = nil
            case .pdf:
                let location = try path.url(in: folderAccess.root)
                // A Graphite drawing saved as PDF opens as a drawing, not as a notebook to annotate.
                if await ImageFileService().isEditableDrawingPDF(at: location) {
                    newPDF = nil
                } else {
                    newPDF = try await openPDFSession(at: location, password: pdfPasswords[path])
                    if let pdfPageIndex, let newPDF { newPDF.currentPageIndex = min(max(pdfPageIndex, 0), max(newPDF.pageCount - 1, 0)) }
                }
                newMarkdown = nil
            default: newPDF = nil; newMarkdown = nil
            }
            // The tab's editor stayed editable while the file loaded, and its session goes away
            // with the swap below, so what was typed in the meantime is saved first.
            try await document.saveAllChanges()
            guard document.requestIdentifier == requestIdentifier, layout.tab(withID: tabID) != nil else { return false }
            // Another tab may have opened the same file in the meantime; it keeps it.
            if let otherTabID = layout.tabID(showing: path), otherTabID != tabID {
                activateTab(otherTabID)
                return false
            }
            document.headingScrollRequest = nil
            if document.baseViewRequest?.path != path { document.baseViewRequest = nil }
            document.loadFailure = nil
            document.releasedPDFPage = nil
            document.markdownSession = newMarkdown; document.pdfSession = newPDF; document.loadedPath = path
            layout.show(path, inTab: tabID, recordsHistory: recordsHistory)
            recentFiles.record(path)
            if let currentVaultIdentifier { vaultLibrary.setLastOpenedDocument(path, inVault: currentVaultIdentifier) }
            releaseHiddenPDFSessions()
            return true
        } catch let passwordRequired as PDFPasswordRequired {
            // The tab asks for the password; an alert would add nothing.
            if document.requestIdentifier == requestIdentifier {
                document.loadFailure = LoadFailure(path: path, message: passwordRequired.localizedDescription, needsPassword: true,
                                                   requestedPageIndex: pdfPageIndex ?? document.loadFailure?.requestedPageIndex)
                if layout.tab(withID: tabID)?.path != path { layout.show(path, inTab: tabID, recordsHistory: recordsHistory) }
            }
            return false
        } catch {
            if document.requestIdentifier == requestIdentifier { document.loadFailure = LoadFailure(path: path, message: error.localizedDescription) }
            if reportsFailure { errorMessage = error.localizedDescription }
            return false
        }
    }

    // MARK: Saving the layout

    func saveTabLayout() {
        guard let layoutVaultIdentifier, let data = try? JSONEncoder().encode(layout.saved) else { return }
        UserDefaults.standard.set(data, forKey: Self.tabLayoutKey(for: layoutVaultIdentifier))
    }

    /// Restores the vault's tabs as they were left; their files load as they are shown.
    /// Before tabs existed Graphite remembered one document, which becomes the only tab.
    func restoreTabLayout() {
        guard let currentVaultIdentifier, let root = folderAccess?.root else { return }
        let fileExists: (VaultPath) -> Bool = { path in
            guard let location = try? path.url(in: root) else { return false }
            return FileManager.default.fileExists(atPath: location.path)
        }
        if let data = UserDefaults.standard.data(forKey: Self.tabLayoutKey(for: currentVaultIdentifier)),
           let saved = try? JSONDecoder().decode(SavedTabLayout.self, from: data) {
            layout = TabLayout(saved: saved, fileExists: fileExists)
        } else if let document = vaultLibrary.vault(withIdentifier: currentVaultIdentifier)?.lastOpenedDocument, fileExists(document) {
            var restoredLayout = TabLayout()
            restoredLayout.show(document, inTab: restoredLayout.activeTab.id, recordsHistory: true)
            layout = restoredLayout
        }
        layoutVaultIdentifier = currentVaultIdentifier
        saveTabLayout()
    }
}
