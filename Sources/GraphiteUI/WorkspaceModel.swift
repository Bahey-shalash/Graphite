import Foundation
import Observation
import GraphiteCore
import GraphiteIndex
import GraphiteApple

@MainActor @Observable
final class WorkspaceModel {
    /// Beyond this many changed paths, one reconciling scan is cheaper than refreshing each.
    static let maximumIncrementalRefreshCount = 200

    var folderAccess: FolderAccess?
    /// The open vault's entry in `vaultLibrary`.
    private(set) var currentVaultIdentifier: UUID?
    let vaultLibrary = VaultLibrary()
    var store: VaultStore?
    var index: VaultIndex?
    var rootEntries: [VaultEntry] = []
    /// Folders open in the sidebar, remembered per vault as Obsidian remembers them.
    var expandedFolders: Set<VaultPath> = [] {
        didSet {
            guard let currentVaultIdentifier, expandedFolders != oldValue else { return }
            UserDefaults.standard.set(expandedFolders.map(\.rawValue).sorted(), forKey: Self.expandedFoldersKey(for: currentVaultIdentifier))
        }
    }

    private static func expandedFoldersKey(for vaultIdentifier: UUID) -> String {
        "GraphiteExpandedFolders." + vaultIdentifier.uuidString
    }
    /// A move whose link updates wait for the person's answer.
    var pendingMove: PendingMove?
    /// A deletion waiting for confirmation ("Confirm file deletion").
    var pendingDeletion: VaultPath?
    /// A rename, move, or new folder sheet on screen.
    var fileSheet: FileSheet?
    /// Files and folders with a move or rename under way; a second request for one is
    /// ignored (the title bar can report the same rename twice).
    var pathsBeingMoved: Set<VaultPath> = []
    /// The open tabs and the split, remembered per vault.
    var layout = TabLayout() {
        didSet {
            guard layout != oldValue else { return }
            // Views that show only the focused file or its history are not redrawn when
            // focus moves within a note, the divider is dragged, or a background tab changes.
            if selection != layout.activeTab.path { selection = layout.activeTab.path }
            if history != layout.activeTab.history { history = layout.activeTab.history }
            // Histories are not saved, so moving through them writes nothing.
            if layout.saved != oldValue.saved { saveTabLayout() }
        }
    }
    /// The vault `layout` is saved for; nil while a vault is being opened, so the layout
    /// being replaced is not saved over the new vault's.
    var layoutVaultIdentifier: UUID?
    /// The documents open in the tabs, by tab.
    @ObservationIgnored var tabDocuments: [UUID: TabDocument] = [:]
    /// Bases inside the open vault's notes keep their results here while scrolled out of
    /// sight. Replaced when another vault opens, since its models read the old vault.
    @ObservationIgnored private(set) var embeddedBaseModelCache = EmbeddedBaseModelCache()
    /// File recovery's copies for the open vault.
    var fileRecovery: FileRecoveryStore?
    /// The File recovery sheet on screen.
    var fileRecoveryRequest: FileRecoveryRequest?
    /// Passwords of protected PDFs unlocked since launch. Kept in memory only, never saved.
    @ObservationIgnored var pdfPasswords: [VaultPath: String] = [:]
    /// Recently opened files, remembered per vault, for the quick switcher.
    var recentFiles = RecentFiles() {
        didSet {
            guard let currentVaultIdentifier, recentFiles != oldValue else { return }
            UserDefaults.standard.set(recentFiles.paths.map(\.rawValue), forKey: Self.recentFilesKey(for: currentVaultIdentifier))
        }
    }

    private static func recentFilesKey(for vaultIdentifier: UUID) -> String {
        "GraphiteRecentFiles." + vaultIdentifier.uuidString
    }

    /// The file of the focused tab. Kept in step with `layout`.
    private(set) var selection: VaultPath?
    /// The focused tab's note or PDF, once loaded.
    var markdownSession: MarkdownSession? { activeDocument.loadedPath == selection ? activeDocument.markdownSession : nil }
    var pdfSession: PDFSession? { activeDocument.loadedPath == selection ? activeDocument.pdfSession : nil }
    /// Back and forward through the focused tab. Kept in step with `layout`.
    private(set) var history = NavigationHistory()
    var searchQuery = ""
    /// Increases when a command asks for the sidebar's search field.
    var searchFocusRequest = 0
    var searchResults: [SearchResult] = []
    /// Where more results start; nil when every result is shown.
    private(set) var searchContinuation: SearchContinuation?
    private(set) var isLoadingMoreSearchResults = false
    var errorMessage: String?
    var indexingMessage = ""
    var isIndexing = false
    var directoryVersion = 0
    /// Changes whenever a drawing file is rewritten, so previews reload its image.
    var drawingVersion = 0
    /// Changes after the index takes in new file contents, so open bases run again.
    var indexVersion = 0
    /// Changes when Graphite writes `.obsidian/types.json`, so lists of property types reload.
    var propertyTypesVersion = 0
    var vaultSettings = ObsidianSettings()
    /// Obsidian's Templates and Daily notes settings for the open vault.
    var templateSettings = TemplateSettings()
    var dailyNoteSettings = DailyNoteSettings()
    /// Obsidian's bookmarks, from `.obsidian/bookmarks.json`.
    var bookmarks = BookmarkList()
    /// The whole vault's graph, built once per index change.
    @ObservationIgnored var graphCache: (indexVersion: Int, graph: LinkGraph)?
    /// Where the graph view left its nodes, so it opens as it was.
    @ObservationIgnored var graphPositions: [String: SIMD2<Double>] = [:]
    /// Whether the graph view is on screen.
    var isGraphPresented = false
    /// An unfinished recording offered back, one at a time.
    var recordingRecoveryOffer: RecoverableRecording?
    var drawingEditorRequest: DrawingEditorRequest?
    /// An image shown full screen, where it can be zoomed, over the open note.
    var viewedImage: VaultPath?
    /// A heading to show in the focused tab's note (from `[[Note#Heading]]` or the outline).
    var headingScrollRequest: HeadingScrollRequest? {
        get { activeDocument.headingScrollRequest }
        set { activeDocument.headingScrollRequest = newValue }
    }
    let preferences = GraphitePreferences()
    let recording = RecordingController()
    /// Set by indexing when a scan of the whole vault finishes; tests that fill the index
    /// themselves set it too.
    var hasCompletedIndexScan = false
    private var monitor: VaultMonitor?
    private var indexingTask: Task<Void, Never>?
    /// Identifies the latest indexing run, so a cancelled run for a previous vault cannot report into this one.
    private var indexingRunIdentifier = UUID()
    /// Notes the last scan found but could not read yet, such as cloud files not downloaded.
    private var pendingContentFileCount = 0
    /// A scan was asked for while one was running. The running scan may already have
    /// passed the folders that changed, so another one follows it.
    private var isIndexScanRequestedDuringScan = false
    private var externalChangeTask: Task<Void, Never>?
    private var pendingExternalChanges: Set<URL> = []
    private let resolver = AttachmentResolver()

    var title: String { folderAccess?.root.lastPathComponent ?? "Graphite" }
    var currentDirectory: VaultPath { selection?.parent ?? .root }

    /// Where a new note, notebook, or base goes: the folder asked for, else the vault's
    /// "Default location for new notes".
    func newFileDirectory(_ requestedDirectory: VaultPath?) -> VaultPath {
        if let requestedDirectory { return requestedDirectory }
        return (try? vaultSettings.newNoteLocation.directory(currentFile: selection)) ?? .root
    }

    // Opening a vault throws instead of setting `errorMessage`, so a vault sheet can show
    // the error itself; the root view's alert cannot appear over a sheet.

    /// Opens a folder the user picked, adding it to the vault list.
    func openFolderAsVault(_ folder: URL) async throws {
        try await openVault(identifier: nil, location: VaultLocator.location(forPickedFolder: folder))
    }

    func openVault(_ vault: KnownVault) async throws {
        guard vault.id != currentVaultIdentifier else { return }
        try await openVault(identifier: vault.id, location: vault.location)
    }

    /// Creates an empty vault folder in `parentFolder`, or in Graphite's own folder in Files, and opens it.
    func createVault(named name: String, in parentFolder: URL?) async throws {
        // Checked before the folder exists: a refused switch would otherwise leave an empty
        // folder behind, and trying the same name again would find it taken.
        try await prepareToLeaveCurrentVault()
        try await openVault(identifier: nil, location: VaultLocator.createVaultFolder(named: name, in: parentFolder))
    }

    /// Forgets a vault other than the open one, with the folds, recent files, and tabs
    /// remembered for it. Its folder is not touched.
    func removeFromVaultList(_ vault: KnownVault) {
        guard vault.id != currentVaultIdentifier else { return }
        vaultLibrary.remove(vault.id)
        // Its File recovery copies would otherwise stay on the device with nothing to show them.
        if let fileRecovery = try? FileRecoveryStore.forVault(identifier: vault.id) {
            Task.detached(priority: .utility) { try? fileRecovery.removeAllSnapshots() }
        }
        VaultIndex.removeIndex(forVault: vault.id)
        // Opening the folder again makes a new identifier, so nothing would read these again.
        for key in [Self.expandedFoldersKey(for: vault.id), Self.recentFilesKey(for: vault.id), Self.tabLayoutKey(for: vault.id)] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Refuses to leave the vault during a recording, and saves every open document.
    private func prepareToLeaveCurrentVault() async throws {
        guard !recording.state.isActive else { throw GraphiteError.unavailable("Finish the current recording before switching vaults.") }
        try await saveOpenDocuments()
    }

    private func openVault(identifier: UUID?, location: VaultLocation) async throws {
        try await prepareToLeaveCurrentVault()
        let (access, refreshedLocation) = try await VaultLocator.accessInBackground(location)
        let root = access.root
        // Known before anything is recorded, so the index can be named after it.
        let vaultIdentifier = vaultLibrary.existingIdentifier(identifier: identifier, root: root, location: refreshedLocation ?? location) ?? UUID()
        let vaultMonitor = VaultMonitor(root: root, onChange: { [weak self] changedLocation in
            Task { @MainActor in self?.scheduleExternalRefresh(changedLocation) }
        }, onVaultMove: { [weak self] newLocation in
            Task { @MainActor in await self?.vaultFolderDidMove(to: newLocation) }
        })
        // Writes coordinated with our own presenter are not reported back as external.
        let vaultStore = VaultStore(root: root, filePresenter: vaultMonitor)
        let entries: [VaultEntry]
        let vaultIndex: VaultIndex
        // Read first so the root is listed once, in this vault's order. A failed read is
        // reported when the settings are read again below, and Obsidian's defaults apply.
        let settings = (try? await vaultStore.settings()) ?? ObsidianSettings()
        do {
            entries = try await vaultStore.children(of: .root, sortedBy: settings.fileSortOrder)
            let cacheURL = try VaultIndex.cacheURL(forVault: vaultIdentifier, legacyRoot: root)
            vaultIndex = try await Task.detached(priority: .utility) { try VaultIndex(databaseURL: cacheURL) }.value
            // The open editors stayed usable while the vault was read; what was written in
            // them meanwhile is saved before they close. A failed save keeps this vault open.
            try await saveOpenDocuments()
        } catch {
            vaultMonitor.stop()
            throw error
        }
        monitor?.stop(); stopIndexing(); externalChangeTask?.cancel()
        pendingExternalChanges.removeAll(); firstPendingExternalChangeInstant = nil
        indexingMessage = ""
        folderAccess = access; store = vaultStore; index = vaultIndex; monitor = vaultMonitor
        EmbeddedPDFSessions.shared.useVault(root: root, owner: self, saving: embeddedPDFSaving(writer: vaultStore.writer))
        // Nothing open in the vault being left is saved into the new vault's layout.
        layoutVaultIdentifier = nil
        layout = TabLayout(); tabDocuments = [:]; pdfPasswords = [:]
        graphCache = nil; graphPositions = [:]
        embeddedBaseModelCache = EmbeddedBaseModelCache()
        // `expandedFolders` is replaced below, once the new vault is current: clearing it
        // here would save an empty list for the vault being left.
        pendingMove = nil; pendingDeletion = nil; fileSheet = nil
        searchQuery = ""; searchResults = []; searchContinuation = nil
        rootEntries = entries
        hasCompletedIndexScan = false
        // If this vault's settings cannot be read, Obsidian's defaults apply, rather than
        // the last vault's deletion or link settings.
        vaultSettings = settings
        currentVaultIdentifier = vaultLibrary.recordOpening(identifier: vaultIdentifier, root: root, location: refreshedLocation ?? location)
        if let currentVaultIdentifier {
            // Folders renamed or deleted in the meantime simply stay closed.
            let savedFolders = UserDefaults.standard.stringArray(forKey: Self.expandedFoldersKey(for: currentVaultIdentifier)) ?? []
            expandedFolders = Set(savedFolders.compactMap { folder in try? VaultPath(folder) })
            let savedRecentFiles = UserDefaults.standard.stringArray(forKey: Self.recentFilesKey(for: currentVaultIdentifier)) ?? []
            recentFiles = RecentFiles(paths: savedRecentFiles.compactMap { path in try? VaultPath(path) })
        }
        fileRecovery = currentVaultIdentifier.flatMap { identifier in try? FileRecoveryStore.forVault(identifier: identifier) }
        pruneRecoverySnapshots()
        await reloadVaultSettings()
        startIndexing()
        // Returns to where the user left this vault, as Obsidian restores its workspace.
        restoreTabLayout()
        checkForUnfinishedRecordings()
        if preferences.isEnabled(.dailyNotes), dailyNoteSettings.opensOnStartup { await openDailyNote() }
    }

    /// The open vault's folder was moved, renamed, or deleted in another app. Its files,
    /// index and editors still use the old path, so the vault is opened again from its
    /// saved location, whose bookmark follows the folder.
    /// - Parameter newLocation: Where the folder is now; nil when it was deleted.
    func vaultFolderDidMove(to newLocation: URL?) async {
        let reopeningAdvice = "Open it again with Open Folder as Vault."
        guard newLocation != nil, let vaultIdentifier = currentVaultIdentifier,
              let vault = vaultLibrary.list.vaults.first(where: { knownVault in knownVault.id == vaultIdentifier }) else {
            errorMessage = "The vault folder was moved or deleted in another app. " + reopeningAdvice
            return
        }
        guard !recording.state.isActive else {
            errorMessage = "The vault folder was moved in another app. When the recording is finished, open the vault again from the vault list."
            return
        }
        do {
            try await openVault(identifier: vaultIdentifier, location: vault.location)
        } catch {
            errorMessage = "The vault folder was moved in another app, and Graphite couldn't open it at its new place. " + reopeningAdvice + " " + error.localizedDescription
        }
    }

    /// Opens the vault used most recently, at launch.
    func restoreVault() async {
        guard folderAccess == nil, let vault = vaultLibrary.list.mostRecentlyOpened else { return }
        do { try await openVault(identifier: vault.id, location: vault.location) }
        catch { errorMessage = "Graphite couldn't reopen “\(vault.name)”. " + error.localizedDescription }
    }

    // MARK: Settings

    func reloadVaultSettings() async {
        guard let store else { return }
        templateSettings = await store.templateSettings()
        dailyNoteSettings = await store.dailyNoteSettings()
        await reloadBookmarks()
        do {
            let settings = try await store.settings()
            let sortOrderChanged = settings.fileSortOrder != vaultSettings.fileSortOrder
            vaultSettings = settings
            if sortOrderChanged { await refreshDirectory() }
        } catch { errorMessage = "Graphite could not read the Obsidian settings in this vault. " + error.localizedDescription }
    }

    /// Writes the settings Obsidian shares with Graphite into `.obsidian/app.json`.
    func updateVaultSettings(_ settings: ObsidianSettings) async {
        guard let store, settings != vaultSettings else { return }
        do {
            if case .specifiedFolder(let folder) = settings.attachmentLocation {
                try Self.refuseBackslash(in: folder)
                _ = try VaultPath(folder)
            }
            if case .subfolderUnderNote(let folder) = settings.attachmentLocation {
                try Self.refuseBackslash(in: folder)
                _ = try VaultPath.root.appending(folder)
            }
            // The copy the settings screen changed, so only the keys the user changed are
            // written over what Obsidian may have changed meanwhile.
            try await store.saveSettings(settings, changedFrom: vaultSettings)
            let sortOrderChanged = settings.fileSortOrder != vaultSettings.fileSortOrder
            vaultSettings = settings
            if sortOrderChanged { await refreshDirectory() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Documents

    /// Opens a file. A file already open in a tab is shown there, at the requested page
    /// for a PDF, rather than opened twice.
    /// - Parameters:
    ///   - placement: The tab it opens in: the current one, a new one, or one on the other
    ///     side of the split.
    ///   - pdfPageIndex: For a PDF, the zero-based page to show first.
    ///   - takesFocus: False to show a file already open on the other side without
    ///     moving focus there, as a link from a note does.
    /// - Returns: The tab showing the file, or nil when it could not be opened.
    @discardableResult
    func open(_ requestedPath: VaultPath, placement: TabPlacement = .currentTab, pdfPageIndex: Int? = nil, takesFocus: Bool = true) async -> UUID? {
        guard store != nil else { return nil }
        let path = storedPath(for: requestedPath)
        if let existingTabID = layout.tabID(showing: path) {
            if takesFocus { activateTab(existingTabID) } else { revealTab(existingTabID) }
            let document = document(for: existingTabID)
            if document.loadedPath == path {
                if let pdfPageIndex, let pdfSession = document.pdfSession {
                    pdfSession.go(to: min(max(pdfPageIndex, 0), max(pdfSession.pageCount - 1, 0)))
                }
            } else {
                await load(path, into: existingTabID, pdfPageIndex: pdfPageIndex, recordsHistory: false)
            }
            return existingTabID
        }
        let existingTabIDs = Set(layout.allTabs.map(\.id))
        let previousTabID = layout.activeTab.id
        let tabID: UUID
        switch placement {
        case .currentTab: tabID = layout.tabForOpeningHere()
        case .newTab: tabID = layout.addTab()
        case .otherGroup: tabID = layout.tabForOpeningInOtherGroup()
        }
        if tabID != previousTabID, let previousDocument = tabDocuments[previousTabID] {
            do { try await previousDocument.save() } catch { errorMessage = error.localizedDescription }
        }
        let didOpen = await load(path, into: tabID, pdfPageIndex: pdfPageIndex, recordsHistory: true)
        // A tab made for a file that could not be opened goes away again.
        if !didOpen, !existingTabIDs.contains(tabID), layout.tab(withID: tabID)?.path == nil {
            layout.closeTab(tabID)
            tabDocuments[tabID] = nil
        }
        return layout.tabID(showing: path)
    }

    /// Saves every open note and PDF, before files move and when the app leaves the screen.
    func saveOpenDocuments() async throws {
        for document in tabDocuments.values { try await document.save() }
    }

    func refreshDirectory() async {
        guard let store else { return }
        do { rootEntries = try await store.children(of: .root, sortedBy: vaultSettings.fileSortOrder); directoryVersion += 1 }
        catch { errorMessage = error.localizedDescription }
    }

    // MARK: Index

    func startIndexing() {
        guard let index, let root = folderAccess?.root else { return }
        guard !isIndexing else {
            isIndexScanRequestedDuringScan = true
            return
        }
        isIndexing = true; indexingMessage = "Indexing…"
        let runIdentifier = UUID()
        indexingRunIdentifier = runIdentifier
        // Below the editor's priority, so a scan does not compete with typing and scrolling.
        indexingTask = Task(priority: .utility) {
            do {
                let report = try await index.reconcile(root: root)
                guard indexingRunIdentifier == runIdentifier else { return }
                hasCompletedIndexScan = true
                indexVersion += 1
                pendingContentFileCount = report.pendingContentFiles
                describeIndex(fileCount: report.discoveredFiles)
                if !searchQuery.isEmpty { await search() }
            } catch is CancellationError {
                if indexingRunIdentifier == runIdentifier { indexingMessage = "Indexing paused" }
            } catch {
                guard indexingRunIdentifier == runIdentifier else { return }
                indexingMessage = "Index needs attention"; errorMessage = error.localizedDescription
            }
            guard indexingRunIdentifier == runIdentifier else { return }
            isIndexing = false
            if isIndexScanRequestedDuringScan {
                isIndexScanRequestedDuringScan = false
                startIndexing()
            }
        }
    }

    /// Cancels the running scan. Its run identifier changes at once, so a scan that
    /// finishes before it sees the cancellation reports nothing.
    private func stopIndexing() {
        indexingTask?.cancel()
        indexingRunIdentifier = UUID()
        isIndexing = false; isIndexScanRequestedDuringScan = false
    }

    func rebuildIndex() async {
        guard let index, !isIndexing else { return }
        let wasIndexComplete = hasCompletedIndexScan
        // An index being emptied is not complete: a link followed meanwhile creates no note.
        hasCompletedIndexScan = false
        do {
            try await index.removeAllEntries()
        } catch {
            // The removal is one transaction, so the index is as it was.
            if self.index === index { hasCompletedIndexScan = wasIndexComplete }
            errorMessage = error.localizedDescription
            return
        }
        guard self.index === index else { return }
        // A scan that ran during the removal counted entries that are gone; the rebuild's
        // own scan replaces it.
        stopIndexing()
        hasCompletedIndexScan = false
        startIndexing()
    }

    /// Updates only the given files, for Graphite's own saves.
    func refreshIndex(for paths: [VaultPath]) {
        guard let index, let root = folderAccess?.root, !paths.isEmpty else { return }
        Task(priority: .utility) {
            do {
                try await index.refresh(paths: paths, root: root)
                indexVersion += 1
                if !isIndexing, hasCompletedIndexScan, self.index === index { describeIndex(fileCount: try await index.fileCount()) }
            } catch { indexingMessage = "Index needs attention" }
        }
    }

    private func describeIndex(fileCount: Int) {
        indexingMessage = fileCount == 1 ? "1 file" : "\(fileCount.formatted()) files"
        if pendingContentFileCount > 0 { indexingMessage += " · \(pendingContentFileCount.formatted()) not yet searchable" }
    }

    /// Why the search as typed cannot run, such as a `/pattern/` that is not a valid
    /// regular expression; nil when it can. The sidebar shows it in place of results.
    var searchQueryProblem: String? {
        guard let invalidPattern = SearchQueryParser.parse(searchQuery)?.invalidRegularExpressionPatterns.first else { return nil }
        return "/\(invalidPattern)/ is not a valid regular expression."
    }

    func search() async {
        guard let index else { return }
        let query = searchQuery, sortOrder = preferences.searchSortOrder
        // An invalid pattern matches nothing, so excluding it would list every file.
        guard searchQueryProblem == nil else {
            searchResults = []; searchContinuation = nil
            return
        }
        do {
            let page = try await index.search(query, sortOrder: sortOrder)
            guard !Task.isCancelled, query == searchQuery, sortOrder == preferences.searchSortOrder else { return }
            searchResults = page.results
            searchContinuation = page.continuation
        } catch is CancellationError {
            // The query changed while this search ran; the next search shows its results.
        } catch { errorMessage = error.localizedDescription }
    }

    /// Adds the next page of results, as the list scrolls to its end.
    func loadMoreSearchResults() async {
        guard let index, let continuation = searchContinuation, !isLoadingMoreSearchResults else { return }
        let query = searchQuery, sortOrder = preferences.searchSortOrder
        isLoadingMoreSearchResults = true
        defer { isLoadingMoreSearchResults = false }
        do {
            let page = try await index.search(query, sortOrder: sortOrder, after: continuation)
            guard query == searchQuery, sortOrder == preferences.searchSortOrder, searchContinuation == continuation else { return }
            let shownPaths = Set(searchResults.map(\.path))
            searchResults += page.results.filter { result in !shownPaths.contains(result.path) }
            searchContinuation = page.continuation
        } catch is CancellationError {
            // Scrolling away or a new query stopped this page; nothing went wrong.
        } catch { errorMessage = error.localizedDescription }
    }

    /// Opens a note at a search match: the match is shown and marked while editing, and
    /// its section is shown in reading view.
    func open(_ path: VaultPath, at match: SearchMatch) async {
        if path != selection { await open(path) }
        guard selection == path, let text = markdownSession?.text else { return }
        let source = text as NSString
        guard NSMaxRange(NSRange(location: match.location, length: match.length)) <= source.length else { return }
        let precedingHeading = NotePreviewDocument.outline(of: source.substring(to: match.location)).last
        headingScrollRequest = HeadingScrollRequest(anchor: precedingHeading?.anchor ?? "", textRange: NSRange(location: match.location, length: match.length))
    }

    // MARK: Links

    /// The vault file an embed or link target refers to, if exactly one does.
    func resolveLink(_ target: String, from source: VaultPath, isWiki: Bool = true) async -> VaultPath? {
        guard let folderAccess else { return nil }
        for candidate in WikiLinkResolver.directCandidates(target: target, source: source, isWiki: isWiki) {
            guard let location = try? candidate.url(in: folderAccess.root) else { continue }
            // A folder is not a link target: `[[Projects]]` beside a Projects folder names
            // the note Projects.md, as in Obsidian, which creates it when it is missing.
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: location.path, isDirectory: &isDirectory), !isDirectory.boolValue { return storedPath(for: candidate) }
        }
        let matches = (try? await index?.resolve(target, from: source, isWiki: isWiki)) ?? []
        return matches.count == 1 ? matches.first : nil
    }

    /// Follows a link: to a heading or block of a note, a page of a PDF, or any file. A
    /// link to a file that does not exist creates the note, as in Obsidian.
    func follow(_ target: String, from source: VaultPath, isWiki: Bool = true, placement: TabPlacement = .currentTab) async {
        guard let index else { return }
        let parts = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let headingAnchor = parts.count == 2 && !parts[1].hasPrefix("^") ? NotePreviewDocument.anchor(forHeading: parts[1]) : nil
        if parts[0].isEmpty, let headingAnchor {
            let sourceTabID = layout.tabID(showing: source) ?? layout.activeTab.id
            document(for: sourceTabID).headingScrollRequest = HeadingScrollRequest(anchor: headingAnchor)
            return
        }
        if let path = await resolveLink(target, from: source, isWiki: isWiki) {
            // A plain tap shows a file already open on the other side there, and the note
            // keeps focus, so a lecture's page links can be followed one after another.
            let takesFocus = placement != .currentTab
            if DocumentKind(path: path) == .pdf {
                // `#page=3` in a PDF link is a page, not a heading.
                let pageNumber = parts.count == 2 ? PDFEmbedOptions(fragment: parts[1]).startPageNumber : nil
                await open(path, placement: placement, pdfPageIndex: pageNumber.map { number in number - 1 }, takesFocus: takesFocus)
                return
            }
            if DocumentKind(path: path) == .base {
                // `#Gallery` in a base link names one of its views.
                let viewName = parts.count == 2 ? (isWiki ? parts[1] : parts[1].removingPercentEncoding ?? parts[1]) : nil
                await openBase(path, viewName: viewName, placement: placement, takesFocus: takesFocus)
                return
            }
            guard let tabID = await open(path, placement: placement, takesFocus: takesFocus) else { return }
            if let headingAnchor { document(for: tabID).headingScrollRequest = HeadingScrollRequest(anchor: headingAnchor) }
            if parts.count == 2, parts[1].hasPrefix("^") { showBlock(String(parts[1].dropFirst()), inTab: tabID) }
            return
        }
        do {
            let matches = try await index.resolve(target, from: source, isWiki: isWiki)
            if matches.isEmpty {
                // As in Obsidian, following a link to a note that does not exist creates it.
                // Until the first scan finishes the note may exist unindexed, so nothing is created then.
                if hasCompletedIndexScan { await createNote(forLink: target, from: source, isWiki: isWiki) }
                else { errorMessage = "No file matches “\(target)” yet. Graphite is still reading the vault; try again in a moment." }
            }
            else { searchQuery = WikiLinkResolver.pathPart(target); await search(); errorMessage = "Several files match “\(target)”. Choose the intended file in search." }
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: Creation

    func createNote(named name: String, in directory: VaultPath? = nil) async {
        guard let store else { return }
        do {
            if let problem = FileNameRules.problem(with: name, isNote: true) { throw GraphiteError.unavailable(problem) }
            let directory = newFileDirectory(directory)
            try await store.createDirectory(directory)
            let path = try await store.uniquePath(directory: directory, stem: name, extension: "md")
            // Empty, as in Obsidian: the inline title shows the name.
            _ = try await store.save(Data(), at: path, expecting: .absent)
            refreshIndex(for: [path])
            await refreshDirectory(); await open(path)
            // Ready to type, as in Obsidian.
            openMarkdownSession(at: path)?.startsEditingWhenShown = true
        } catch { errorMessage = error.localizedDescription }
    }

    /// Shows the block with this `^id` in the tab's note and marks it.
    func showBlock(_ identifier: String, inTab tabID: UUID) {
        let document = document(for: tabID)
        guard let text = document.markdownSession?.text, let block = NoteBlocks.block(withIdentifier: identifier, in: text) else { return }
        let precedingHeading = NotePreviewDocument.outline(of: (text as NSString).substring(to: block.range.location)).last
        document.headingScrollRequest = HeadingScrollRequest(anchor: precedingHeading?.anchor ?? "", textRange: block.range)
    }

    /// Creates the note an unresolved link names: at the path it gives (`[[Folder/Name]]`,
    /// or a Markdown link relative to the linking note), else in the new-note folder.
    func createNote(forLink target: String, from source: VaultPath, isWiki: Bool) async {
        guard let store else { return }
        var pathText = WikiLinkResolver.pathPart(target)
        if !isWiki { pathText = pathText.removingPercentEncoding ?? pathText }
        let fileName = (pathText as NSString).lastPathComponent
        let fileExtension = (fileName as NSString).pathExtension.lowercased()
        let stem: String
        if fileExtension == "md" {
            stem = (fileName as NSString).deletingPathExtension
        } else if DocumentKind(fileExtension: fileExtension) == .other {
            // A dot that starts no known file type is part of the name, as the resolver
            // reads it: `[[Homework 2.1]]` is Homework 2.1.md.
            stem = fileName
        } else {
            // A missing image, PDF, or other attachment cannot be created as a note.
            errorMessage = "“\(pathText)” is not in this vault."
            return
        }
        do {
            if let problem = FileNameRules.problem(with: stem, isNote: true) { throw GraphiteError.unavailable(problem) }
            let folderText = (pathText as NSString).deletingLastPathComponent
            try Self.refuseBackslash(in: folderText)
            let directory: VaultPath
            if !isWiki { directory = try source.parent.appending(folderText) }
            else if folderText.isEmpty { directory = newFileDirectory(nil) }
            else { directory = try VaultPath(folderText) }
            try await store.createDirectory(directory)
            let path = try directory.appending(stem + ".md")
            _ = try await store.save(Data(), at: path, expecting: .absent)
            refreshIndex(for: [path])
            await refreshDirectory()
            await open(path)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Existing names may contain a backslash, but a folder typed or linked to must not:
    /// Obsidian reads a backslash as a folder separator, so it would find another folder.
    static func refuseBackslash(in folderText: String) throws {
        guard !folderText.contains("\\") else { throw GraphiteError.unavailable("A name cannot contain any of these characters: / \\ : * ? \" < > |") }
    }

    /// A new `.base` file with Obsidian's default: one table view of the whole vault.
    func createBase(named name: String, in directory: VaultPath? = nil) async {
        guard let store else { return }
        do {
            if let problem = FileNameRules.problem(with: name, isNote: false) { throw GraphiteError.unavailable(problem) }
            let directory = newFileDirectory(directory)
            try await store.createDirectory(directory)
            let path = try await store.uniquePath(directory: directory, stem: name, extension: "base")
            _ = try await store.save(Data("views:\n  - type: table\n    name: Table\n".utf8), at: path, expecting: .absent)
            refreshIndex(for: [path])
            await refreshDirectory(); await open(path)
        } catch { errorMessage = error.localizedDescription }
    }

    /// What bases inside `note` need to run; nil when Bases are turned off or no vault is open.
    func baseEmbedContext(for note: VaultPath) -> BaseEmbedContext? {
        guard preferences.isEnabled(.bases), let store, let index else { return nil }
        return BaseEmbedContext(store: store, index: index, embeddingNote: note, contentVersion: indexVersion, isIndexComplete: hasCompletedIndexScan,
                                open: { [weak self] path in Task { await self?.open(path) } },
                                filesChanged: { [weak self] paths in self?.filesSavedOutsideEditors(paths) },
                                openBase: { [weak self] basePath, viewName in Task { await self?.openBase(basePath, viewName: viewName) } },
                                modelCache: embeddedBaseModelCache)
    }

    /// Opens a `.base` file at the named view, as `[[Books.base#Gallery]]` and an embedded
    /// base's Open Base ask. A nil or unknown name shows the base's first view.
    @discardableResult
    func openBase(_ path: VaultPath, viewName: String?, placement: TabPlacement = .currentTab, takesFocus: Bool = true) async -> UUID? {
        guard let tabID = await open(path, placement: placement, takesFocus: takesFocus) else { return nil }
        let requestedViewName = viewName.flatMap { name in name.isEmpty ? nil : name }
        document(for: tabID).baseViewRequest = requestedViewName.map { name in BaseViewRequest(path: storedPath(for: path), viewName: name) }
        return tabID
    }

    /// Files Graphite saved outside their editor tab, such as a property set from a base.
    /// Graphite's own coordinated writes send no external-change notice, so open tabs of
    /// those notes adopt the saved text here; otherwise their next save would conflict.
    @discardableResult
    func filesSavedOutsideEditors(_ paths: [VaultPath]) -> Task<Void, Never> {
        refreshIndex(for: paths)
        let savedPaths = Set(paths)
        return Task { await checkOpenDocumentsForExternalChanges(limitedTo: savedPaths) }
    }

    func createNotebook(named name: String, paper: PaperSpecification, pageCount: Int, in directory: VaultPath? = nil) async {
        guard let store, let root = folderAccess?.root else { return }
        do {
            if let problem = FileNameRules.problem(with: name, isNote: false) { throw GraphiteError.unavailable(problem) }
            let directory = newFileDirectory(directory)
            try await store.createDirectory(directory)
            let path = try await store.uniquePath(directory: directory, stem: name, extension: "pdf")
            _ = try await PDFFileService(writer: store.writer).create(paper: paper, pageCount: pageCount, at: path.url(in: root))
            refreshIndex(for: [path])
            await refreshDirectory(); await open(path)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Imports an outside file into the note's attachment folder and embeds it.
    func importAttachment(from source: URL, into session: MarkdownSession) async {
        guard let store, let root = folderAccess?.root else { return }
        let hasAccess = source.startAccessingSecurityScopedResource()
        defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }
        do {
            let settings = try await store.settings()
            let directory = try resolver.directory(for: settings.attachmentLocation, note: session.path)
            try await store.createDirectory(directory)
            let path = try await store.uniquePath(directory: directory, stem: source.deletingPathExtension().lastPathComponent, extension: source.pathExtension)
            let destination = try path.url(in: root)
            let writer = store.writer
            _ = try await Task.detached { try writer.copy(from: source, to: destination, expecting: .absent) }.value
            insertEmbed(await embed(for: path, in: session.path, settings: settings), of: path, into: session, at: nil, chosenIn: session.text)
            refreshIndex(for: [path])
            await refreshDirectory()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Saves pasted, dropped, photographed, or picked data as an attachment, like
    /// Obsidian's "Pasted image …" files, and embeds it at `range` (the cursor when nil).
    /// - Parameter textWhenChosen: The note's text when `range` was chosen; its text now
    ///   when nil. Text typed while the file is written moves the range along with it.
    func saveAttachment(_ data: Data, stem: String, fileExtension: String, into session: MarkdownSession, at range: NSRange? = nil, textWhenChosen: String? = nil) async {
        guard let store else { return }
        let textWhenChosen = textWhenChosen ?? session.text
        do {
            let settings = try await store.settings()
            let directory = try resolver.directory(for: settings.attachmentLocation, note: session.path)
            try await store.createDirectory(directory)
            let path = try await saveUnderFreeName(data, in: directory, stem: stem, fileExtension: fileExtension, store: store)
            insertEmbed(await embed(for: path, in: session.path, settings: settings), of: path, into: session, at: range, chosenIn: textWhenChosen)
            refreshIndex(for: [path])
            await refreshDirectory()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Inserts the embed of an attachment just written into its note. Writing a large file
    /// takes a while, and the note may have closed or changed in another app meanwhile; the
    /// file then stays in the vault, and the person is told no embed was inserted.
    private func insertEmbed(_ embedText: String, of attachment: VaultPath, into session: MarkdownSession, at range: NSRange?, chosenIn textWhenChosen: String) {
        guard let openSession = openMarkdownSession(at: session.path) else {
            errorMessage = "“\(attachment.rawValue)” was saved, but its note is no longer open, so no embed was inserted."
            return
        }
        guard !openSession.hasExternalConflict else {
            // Choosing the other app's version would drop an embed made now without a word.
            errorMessage = "“\(attachment.rawValue)” was saved, but its note was changed in another app, so no embed was inserted. Resolve the note's conflict, then embed the file."
            return
        }
        // A note opened again has a cursor of its own; a range chosen in the old one means nothing there.
        guard openSession === session, let range else {
            openSession.insertBlock(embedText)
            return
        }
        openSession.insertBlock(embedText, at: Self.insertionRange(range, chosenIn: textWhenChosen, in: session))
    }

    /// Where an insertion chosen at `range` of `textWhenChosen` goes in the session's text
    /// now. When the characters it covered cannot be found again, it goes to the cursor
    /// without replacing anything: replacing characters other than the ones chosen would
    /// delete the person's own text.
    private static func insertionRange(_ range: NSRange, chosenIn textWhenChosen: String, in session: MarkdownSession) -> NSRange {
        insertionRange(range, chosenIn: textWhenChosen, currentText: session.text) ?? NSRange(location: session.selection.location, length: 0)
    }

    /// Where a range chosen in `originalText` is in `currentText`, the same note's text some
    /// time later. Text changed only before the range, or only after it, leaves the range on
    /// the same characters. Nil when the range itself, or text on both sides of it, changed.
    nonisolated static func insertionRange(_ range: NSRange, chosenIn originalText: String, currentText: String) -> NSRange? {
        let originalUnits = originalText.utf16, currentUnits = currentText.utf16
        let rangeEnd = NSMaxRange(range)
        guard range.location >= 0, range.length >= 0, rangeEnd <= originalUnits.count else { return nil }
        if rangeEnd <= currentUnits.count, originalUnits.prefix(rangeEnd).elementsEqual(currentUnits.prefix(rangeEnd)) { return range }
        let followingLength = originalUnits.count - range.location
        guard followingLength <= currentUnits.count, originalUnits.suffix(followingLength).elementsEqual(currentUnits.suffix(followingLength)) else { return nil }
        return NSRange(location: currentUnits.count - followingLength, length: range.length)
    }

    /// How often a new attachment looks for another free name when its first one was taken
    /// before it could be written.
    private static let maximumAttachmentNameAttempts = 20

    /// Writes a new file under the first free name for `stem`. Several drops or pastes save
    /// at once, and images without a name all get the same "Pasted image" name within one
    /// second; each can find that name free before any is written. The one that loses takes
    /// the next free name, rather than failing as if another app had written the file.
    private func saveUnderFreeName(_ data: Data, in directory: VaultPath, stem: String, fileExtension: String, store: VaultStore) async throws -> VaultPath {
        var attemptCount = 0
        while true {
            let path = try await store.uniquePath(directory: directory, stem: stem, extension: fileExtension)
            do {
                _ = try await store.save(data, at: path, expecting: .absent)
                return path
            } catch GraphiteError.conflict where attemptCount + 1 < Self.maximumAttachmentNameAttempts {
                attemptCount += 1
            }
        }
    }

    /// Obsidian's name for a pasted image: "Pasted image 20260923221800".
    static func pastedImageStem(at date: Date = .now) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let digits = [components.year ?? 0, components.month ?? 0, components.day ?? 0, components.hour ?? 0, components.minute ?? 0, components.second ?? 0]
        return "Pasted image " + digits.enumerated().map { position, value in position == 0 ? String(format: "%04d", value) : String(format: "%02d", value) }.joined()
    }

    /// A link to a vault file dropped into a note: an embed for images and media, else a link.
    func linkText(for path: VaultPath, in note: VaultPath) async -> String {
        let settings = vaultSettings
        let target = LinkCompletion.linkTarget(for: path, from: note, settings: settings, isNameUnique: await isNameUnique(path, from: note))
        let embeds = [.image, .media, .pdf].contains(DocumentKind(path: path))
        // These characters end or split a Wikilink target, so such names need a Markdown
        // link, as for embeds of new attachments.
        let wikilinkReservedCharacters = CharacterSet(charactersIn: "|[]#^")
        if settings.usesWikilinks, target.rangeOfCharacter(from: wikilinkReservedCharacters) == nil { return (embeds ? "!" : "") + "[[" + target + "]]" }
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")
        let linkedPath = DocumentKind(path: path) == .markdown ? target + ".md" : target
        let label = VaultIndex.switcherName(path).replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        return (embeds ? "!" : "") + "[" + label + "](" + (linkedPath.addingPercentEncoding(withAllowedCharacters: unreserved) ?? linkedPath) + ")"
    }

    /// Inserts a link to a vault file dropped into a note, where it was dropped. Text typed
    /// while the link is prepared moves that place, or leaves it at the cursor.
    func insertLink(to path: VaultPath, into session: MarkdownSession, at range: NSRange?) async {
        let textWhenDropped = session.text
        let linkText = await linkText(for: path, in: session.path)
        session.insertBlock(linkText, at: range.map { range in Self.insertionRange(range, chosenIn: textWhenDropped, in: session) })
    }

    /// A link to a page of a PDF, as Obsidian writes it (`[[Paper.pdf#page=3|Paper, p.3]]`),
    /// for `note`, or for the PDF's own folder when no note is given.
    func pdfPageLink(to pdf: VaultPath, pageIndex: Int, for note: VaultPath?) async -> String {
        let settings = vaultSettings
        let target = LinkCompletion.linkTarget(for: pdf, from: note ?? pdf, settings: settings, isNameUnique: await isNameUnique(pdf, from: note ?? pdf))
        return PDFCitation.pageLink(linkTarget: target, displayName: pdf.stem, pageNumber: pageIndex + 1, usesWikilinks: settings.usesWikilinks)
    }

    /// The note shown on the other side of the split from a tab, where quotes from a PDF go.
    func noteOnOtherSide(of tabID: UUID) -> MarkdownSession? {
        guard let group = layout.group(containing: tabID), let otherGroup = layout.otherGroup(than: group.id),
              let document = tabDocuments[otherGroup.activeTabID], document.loadedPath == otherGroup.activeTab.path else { return nil }
        return document.markdownSession
    }

    private func embed(for attachment: VaultPath, in note: VaultPath, settings: ObsidianSettings) async -> String {
        resolver.embed(attachment: attachment, note: note, settings: settings, isNameUniqueInVault: await isNameUnique(attachment, from: note))
    }

    /// Whether no other vault file shares the file's name, so a "shortest" link can be
    /// just the name. That needs a complete index to prove; until then it is false, and
    /// the full vault path, always a valid link, is written.
    private func isNameUnique(_ path: VaultPath, from note: VaultPath) async -> Bool {
        guard hasCompletedIndexScan, let index, let fileCount = try? await index.fileCount(named: path.name) else { return false }
        if fileCount == 0 { return true }
        guard fileCount == 1 else { return false }
        return (try? await index.resolve(path.name, from: note)) == [path]
    }

    /// The folder new attachments of `note` go to, for display in settings.
    func attachmentDirectoryDescription(for note: VaultPath?, settings: ObsidianSettings) -> String {
        guard let note else {
            switch settings.attachmentLocation {
            case .vaultFolder: return "Vault folder"
            case .specifiedFolder(let folder): return folder.isEmpty ? "Vault folder" : folder
            case .sameFolderAsNote: return "The note's own folder"
            case .subfolderUnderNote(let folder): return "“\(folder)” inside the note's folder"
            }
        }
        guard let directory = try? resolver.directory(for: settings.attachmentLocation, note: note) else { return "Invalid folder name" }
        return directory.rawValue.isEmpty ? "Vault folder" : directory.rawValue
    }

    // MARK: Drawings

    /// The note's text when the new drawing's editor opened, for placing its embed.
    @ObservationIgnored private var noteTextWhenDrawingBegan: (requestIdentifier: UUID, text: String)?

    #if canImport(UIKit)

    func beginNewDrawing(in session: MarkdownSession) {
        // The drawing goes after selected text rather than replacing it: the embed is
        // inserted only when the full-screen editor closes, where a deletion goes unseen.
        let request = DrawingEditorRequest(
            target: .newDrawing(notePath: session.path, insertionRange: NSRange(location: NSMaxRange(session.selection), length: 0)),
            title: "New Drawing", initialStrokeData: Data(), canvasWidth: nil,
            background: preferences.drawingBackground, format: preferences.drawingFormat)
        noteTextWhenDrawingBegan = (request.id, session.text)
        drawingEditorRequest = request
    }

    func beginEditingDrawing(at path: VaultPath) async {
        guard let store, let root = folderAccess?.root else { return }
        do {
            let location = try path.url(in: root)
            let drawing = try await DrawingFileService(writer: store.writer).openForEditing(location)
            drawingEditorRequest = DrawingEditorRequest(
                target: .existingDrawing(path: path, location: location, revision: drawing.revision),
                title: path.name, initialStrokeData: drawing.payload.strokes, canvasWidth: drawing.payload.width,
                background: drawing.payload.background, format: drawing.format)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Saves the drawing file first, then inserts its embed. If the note cannot take the
    /// embed, the drawing file remains in the attachment folder rather than being lost.
    func saveDrawing(_ content: DrawingContent, format: DrawingFormat, for request: DrawingEditorRequest) async throws {
        guard let store, let root = folderAccess?.root else { throw GraphiteError.unavailable("Open a vault first.") }
        let drawingService = DrawingFileService(writer: store.writer)
        switch request.target {
        case .newDrawing(let notePath, let insertionRange):
            let settings = try await store.settings()
            let directory = try resolver.directory(for: settings.attachmentLocation, note: notePath)
            try await store.createDirectory(directory)
            let path = try await store.uniquePath(directory: directory, stem: resolver.drawingFileStem(createdAt: .now), extension: format.fileExtension)
            _ = try await drawingService.save(content, format: format, to: path.url(in: root), expecting: .absent)
            let embedText = await embed(for: path, in: notePath, settings: settings)
            if let session = openMarkdownSession(at: notePath) {
                if session.hasExternalConflict {
                    // Choosing the other app's version would drop an embed made now, leaving
                    // the drawing unreferenced without a word.
                    errorMessage = "The drawing was saved as “\(path.rawValue)”, but its note was changed in another app, so no embed was inserted. Resolve the note's conflict, then embed the drawing."
                } else if let noteTextWhenDrawingBegan, noteTextWhenDrawingBegan.requestIdentifier == request.id {
                    // The note may have been reloaded from another app's version while the
                    // drawing was made; the embed follows the text it was placed in.
                    session.insertBlock(embedText, at: Self.insertionRange(insertionRange, chosenIn: noteTextWhenDrawingBegan.text, in: session))
                } else {
                    session.insertBlock(embedText, at: insertionRange)
                }
            } else {
                errorMessage = "The drawing was saved as “\(path.rawValue)”, but its note is no longer open, so no embed was inserted."
            }
            if noteTextWhenDrawingBegan?.requestIdentifier == request.id { noteTextWhenDrawingBegan = nil }
            refreshIndex(for: [path])
        case .existingDrawing(let path, let location, let revision):
            _ = try await drawingService.save(content, format: format, to: location, expecting: .revision(revision))
            refreshIndex(for: [path])
        }
        drawingVersion += 1
        await refreshDirectory()
    }

    /// Encodes a copy for sharing; nothing is written into the vault.
    func exportDrawingCopy(_ content: DrawingContent, format: DrawingFormat, title: String) async throws -> URL {
        let fileData = try await DrawingFileService().fileData(for: content, format: format)
        let exportDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("Graphite Exports", isDirectory: true)
        let stem = (title as NSString).deletingPathExtension
        let exportLocation = exportDirectory.appendingPathComponent(stem.isEmpty ? "Drawing" : stem).appendingPathExtension(format.fileExtension)
        // A large drawing's file takes a while to write; the main actor stays free meanwhile.
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            try fileData.write(to: exportLocation, options: .atomic)
        }.value
        return exportLocation
    }
    #endif

    // MARK: Recording

    /// The note a recording was started from, so the finished file can be embedded there.
    private(set) var recordingNotePath: VaultPath?
    /// The vault a recording is saved into, kept accessible until the recording is saved.
    /// A recording whose saving failed can be saved again after another vault opened, and
    /// a folder from Files can be written only while its access lasts.
    @ObservationIgnored private var recordingFolderAccess: FolderAccess?

    /// Records into the attachment folder of the current note, like Obsidian's recorder.
    func startRecording() async {
        guard let store, let folderAccess else { return }
        // A recording that could not be saved is waiting; starting would not record, and the
        // note it will be embedded in must stay the one it was started from.
        guard recording.canStartRecording else { return }
        do {
            let notePath = markdownSession?.path
            let directory = try await recordingDirectory(note: notePath, store: store)
            try await store.createDirectory(directory)
            let path = try await store.uniquePath(directory: directory, stem: "\(selection?.stem ?? title) Recording \(Self.recordingTimestamp())", extension: "m4a")
            recordingNotePath = notePath
            recordingFolderAccess = folderAccess
            // The vault's presenter, so saving the recording is not reported back as a change by another app.
            await recording.start(destination: try path.url(in: folderAccess.root), manifest: RecordingRecoveryManifest(
                vaultIdentifier: currentVaultIdentifier, destinationPath: path.rawValue, notePath: notePath?.rawValue, startedAt: .now),
                                  filePresenter: monitor)
        } catch { errorMessage = error.localizedDescription }
    }

    /// Where a recording goes: the note's attachment folder, as Obsidian's recorder does,
    /// or the current folder when no note is open.
    private func recordingDirectory(note notePath: VaultPath?, store: VaultStore) async throws -> VaultPath {
        guard let notePath else { return currentDirectory }
        return try resolver.directory(for: try await store.settings().attachmentLocation, note: notePath)
    }

    /// Saves a recording that could not be saved into the vault again. Its destination is
    /// worked out afresh, as when it started, since the folder it was going to may have
    /// been renamed or its name taken meanwhile. A recording from a vault that is no longer
    /// open is saved where it was going.
    func retryRecordingPublication() async {
        if let destination = await freshRecordingDestination() {
            await recording.retryPublication(to: destination, filePresenter: monitor)
        } else {
            await recording.retryPublication()
        }
    }

    private func freshRecordingDestination() async -> URL? {
        // Only a recording going into the open vault gets a new place; its path there names it.
        guard let store, let folderAccess, let originalDestination = recording.destination,
              vaultPath(for: originalDestination) != nil else { return nil }
        let stem = originalDestination.deletingPathExtension().lastPathComponent
        do {
            let directory = try await recordingDirectory(note: recordingNotePath, store: store)
            try await store.createDirectory(directory)
            let path = try await store.uniquePath(directory: directory, stem: stem, extension: "m4a")
            return try path.url(in: folderAccess.root)
        } catch {
            return nil
        }
    }

    /// The time in a recording's file name: "2026-09-23 22-15". A fixed 24-hour form, so
    /// morning and evening recordings differ in every region, and no language adds
    /// invisible direction marks or other digits to the name.
    static func recordingTimestamp(at date: Date = .now) -> String {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04ld-%02ld-%02ld %02ld-%02ld", components.year ?? 0, components.month ?? 0, components.day ?? 0, components.hour ?? 0, components.minute ?? 0)
    }

    /// Called when a recording file has been published into the vault.
    func recordingDidFinish(at location: URL) async {
        recordingFolderAccess = nil
        await refreshDirectory()
        guard let path = vaultPath(for: location) else {
            // Saved again after another vault was opened: the file is in the vault it was
            // recorded for, and a note of that vault cannot take its embed now.
            recordingNotePath = nil
            errorMessage = "The recording was saved as “\(location.lastPathComponent)” in the vault it was started in. That vault is no longer open, so no embed was inserted."
            return
        }
        refreshIndex(for: [path])
        guard preferences.embedsRecordingsInNote, let notePath = recordingNotePath, let session = openMarkdownSession(at: notePath),
              let settings = try? await store?.settings() else { return }
        session.insertBlock(await embed(for: path, in: session.path, settings: settings))
        recordingNotePath = nil
    }

    // MARK: Navigation

    /// Keeps tabs, their histories, and recent files pointing at a moved file or folder.
    /// Tabs of moved files load them again from their new place.
    func followMoveInNavigation(from oldPath: VaultPath, to newPath: VaultPath) {
        for tab in layout.allTabs where tab.path?.isInside(oldPath) == true { tabDocuments[tab.id]?.unload() }
        layout.replacePrefix(oldPath, with: newPath)
        recentFiles.replacePrefix(oldPath, with: newPath)
        followMoveInFolds(from: oldPath, to: newPath)
        followMoveInBookmarks(from: oldPath, to: newPath)
        if let fileRecovery {
            // A renamed note keeps its history; for a folder, each note inside does.
            Task.detached(priority: .utility) { try? fileRecovery.followMove(from: oldPath, to: newPath) }
        }
    }

    /// Closes the tabs of a deleted file or folder, without saving into it, and forgets it.
    func forgetInNavigation(_ removedPath: VaultPath) {
        for tabID in layout.removeTabs(inside: removedPath) { tabDocuments[tabID] = nil }
        recentFiles.remove(inside: removedPath)
        forgetFolds(inside: removedPath)
    }

    // MARK: External changes

    private func scheduleExternalRefresh(_ changedLocation: URL?) {
        if let changedLocation { pendingExternalChanges.insert(changedLocation) }
        let now = ContinuousClock.now
        let firstReport = firstPendingExternalChangeInstant ?? now
        firstPendingExternalChangeInstant = firstReport
        let deadline = Self.externalRefreshDeadline(firstReport: firstReport, latestReport: now)
        externalChangeTask?.cancel()
        externalChangeTask = Task {
            do { try await Task.sleep(until: deadline, clock: .continuous) } catch { return }
            let changedLocations = pendingExternalChanges
            pendingExternalChanges.removeAll(); firstPendingExternalChangeInstant = nil
            guard let root = folderAccess?.root, let refreshedStore = store else { return }
            let maximumFileCount = Self.maximumIncrementalRefreshCount
            // Resolving thousands of reported paths takes a noticeable time, so it is kept
            // off the main thread.
            let refresh = await Task.detached(priority: .utility) {
                ExternalChangeRefresh(changedLocations: changedLocations, root: root, maximumFileCount: maximumFileCount)
            }.value
            // Another vault may have opened meanwhile; these paths name files of the old one.
            guard store === refreshedStore else { return }
            // Only the open documents another app is known to have changed are read again.
            switch refresh {
            case .nothingShown: break
            case .files(let changedPaths): await checkOpenDocumentsForExternalChanges(limitedTo: Set(changedPaths))
            case .wholeVault: await checkOpenDocumentsForExternalChanges()
            }
            await refreshDirectory()
            // A new drawing version rebuilds every embed and image shown, so it waits for a
            // change previews can show; Obsidian rewrites `.obsidian` files constantly.
            switch refresh {
            case .nothingShown: break
            case .files(let changedPaths): drawingVersion += 1; refreshIndex(for: changedPaths)
            case .wholeVault: drawingVersion += 1; startIndexing()
            }
        }
    }

    /// How long reported changes settle before the vault is refreshed.
    private static let externalRefreshDelay = Duration.milliseconds(500)
    /// The longest a reported change waits while more keep coming, as during a long sync.
    private static let maximumExternalRefreshDelay = Duration.seconds(2)
    /// When the oldest change waiting for the refresh was reported.
    @ObservationIgnored private var firstPendingExternalChangeInstant: ContinuousClock.Instant?

    /// When a refresh runs: once reports pause for `externalRefreshDelay`, but no later than
    /// `maximumExternalRefreshDelay` after the first change waiting for it.
    static func externalRefreshDeadline(firstReport: ContinuousClock.Instant, latestReport: ContinuousClock.Instant) -> ContinuousClock.Instant {
        min(latestReport + externalRefreshDelay, firstReport + maximumExternalRefreshDelay)
    }

    /// Recently opened files that still exist, most recent first, leaving out `excludedPaths`.
    /// Files deleted or renamed outside Graphite stay in the list until then.
    func existingRecentFiles(limit: Int, excluding excludedPaths: Set<VaultPath> = []) -> [VaultPath] {
        guard let root = folderAccess?.root else { return [] }
        var paths: [VaultPath] = []
        for path in recentFiles.paths where !excludedPaths.contains(path) {
            guard let location = try? path.url(in: root), FileManager.default.fileExists(atPath: location.path) else { continue }
            paths.append(path)
            if paths.count == limit { break }
        }
        return paths
    }

    /// The path as the file system spells it. On a case-insensitive disk, `[[note]]` or an
    /// old recent-files entry finds "Note.md"; using the stored spelling keeps one file from
    /// being open in two tabs under two names.
    func storedPath(for path: VaultPath) -> VaultPath {
        guard let root = folderAccess?.root, let location = try? path.url(in: root),
              let canonicalPath = try? location.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath,
              let stored = vaultPath(for: URL(fileURLWithPath: canonicalPath)) else { return path }
        return stored
    }

    /// Opens a vault PDF for a tab. It saves through the vault's writer, whose presenter
    /// keeps its own writes from coming back as external changes, so the index learns of
    /// each file it writes (the PDF, or a separate copy beside it) from `didSave`.
    func openPDFSession(at location: URL, password: String?) async throws -> PDFSession {
        let session = try await PDFSession.open(location, password: password, writer: store?.writer ?? AtomicFileWriter())
        session.didSave = { [weak self] savedLocation in
            guard let self, let savedPath = vaultPath(for: savedLocation) else { return }
            refreshIndex(for: [savedPath])
        }
        return session
    }

    /// How PDFs embedded in the vault's notes save. An embed's save is not the tab's own,
    /// so an open tab of that PDF is checked as for a change made elsewhere.
    func embeddedPDFSaving(writer: AtomicFileWriter) -> EmbeddedPDFSessions.VaultSaving {
        EmbeddedPDFSessions.VaultSaving(writer: writer) { [weak self] savedLocation in
            guard let self, let savedPath = vaultPath(for: savedLocation) else { return }
            filesSavedOutsideEditors([savedPath])
        }
    }

    /// Maps a URL reported by the file system back into the vault, tolerating the
    /// `/private` prefix that symbolic-link resolution adds or removes on iOS.
    func vaultPath(for location: URL) -> VaultPath? {
        guard let root = folderAccess?.root else { return nil }
        return Self.vaultPath(for: location, root: root)
    }

    nonisolated static func vaultPath(for location: URL, root: URL) -> VaultPath? {
        vaultPath(forComparablePath: comparablePath(of: location), rootPath: comparablePath(of: root))
    }

    /// The vault path of a location, both given as `comparablePath(of:)` makes them.
    nonisolated static func vaultPath(forComparablePath locationPath: String, rootPath: String) -> VaultPath? {
        guard locationPath.hasPrefix(rootPath + "/") else { return nil }
        return try? VaultPath(String(locationPath.dropFirst(rootPath.count + 1)))
    }

    nonisolated static func comparablePath(of location: URL) -> String {
        location.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Reloads notes and PDFs changed by another app, in every tab. A document with
    /// unsaved edits is kept, and its conflict is shown instead.
    /// - Parameter changedPaths: The files known to have changed; nil checks every tab.
    func checkOpenDocumentsForExternalChanges(limitedTo changedPaths: Set<VaultPath>? = nil) async {
        for document in tabDocuments.values {
            if let changedPaths {
                guard let loadedPath = document.loadedPath, changedPaths.contains(loadedPath) else { continue }
            }
            await document.markdownSession?.checkExternalChange()
            guard let pdfSession = document.pdfSession else { continue }
            do {
                guard try await pdfSession.hasChangedExternally(), !pdfSession.hasUnsavedChanges, document.pdfSession === pdfSession else { continue }
                let password = document.loadedPath.flatMap { path in pdfPasswords[path] }
                let reloadedSession = try await openPDFSession(at: pdfSession.location, password: password)
                // Reading a large PDF takes a while, and the old session stays on screen.
                // Another file may have opened in the tab by now, and it stays.
                guard document.pdfSession === pdfSession else { continue }
                // Strokes or page changes made meanwhile are kept, and shown as a conflict
                // with the other app's version, as when they were made before the change.
                guard !pdfSession.hasUnsavedChanges else {
                    pdfSession.hasExternalConflict = true
                    pdfSession.errorMessage = GraphiteError.conflict.localizedDescription
                    continue
                }
                // The reader stays on the page it was reading.
                reloadedSession.currentPageIndex = min(pdfSession.currentPageIndex, max(reloadedSession.pageCount - 1, 0))
                document.pdfSession = reloadedSession
            } catch { pdfSession.errorMessage = error.localizedDescription }
        }
    }

    /// Shows `location` in the tab whose PDF conflicted: the separate copy just saved, or
    /// the other app's version.
    func resolvePDFConflict(opening location: URL, inTab tabID: UUID) async {
        do {
            guard let path = vaultPath(for: location) else { throw GraphiteError.outsideVault }
            // This action is called only after a separate copy was saved or the
            // user explicitly confirmed discarding the open PDF edits.
            let replacement = try await openPDFSession(at: location, password: pdfPasswords[path])
            let document = document(for: tabID)
            document.pdfSession = replacement; document.markdownSession = nil; document.loadedPath = path
            layout.show(path, inTab: tabID, recordsHistory: path != layout.tab(withID: tabID)?.path)
            await refreshDirectory()
        } catch { errorMessage = error.localizedDescription }
    }
}

/// What a batch of changes reported by other apps needs refreshed.
enum ExternalChangeRefresh: Equatable {
    /// Only files the vault does not show changed, such as Obsidian's own `.obsidian` files.
    case nothingShown
    /// These files changed, and are refreshed one by one.
    case files([VaultPath])
    /// Folders, many files, or places that cannot be named changed; one reconciling scan
    /// finds what they were.
    case wholeVault

    init(changedLocations: Set<URL>, root: URL, maximumFileCount: Int) {
        // Resolving a path touches the file system for each of its folders, so the root is
        // resolved once, and each location at most once.
        let rootPath = WorkspaceModel.comparablePath(of: root)
        var changedPaths: [VaultPath] = []
        var hasItemLocation = false
        // Every answer other than refreshing files one by one is a whole-vault scan, so the
        // first location that calls for one decides, and the rest are not resolved.
        for location in changedLocations {
            let locationPath = WorkspaceModel.comparablePath(of: location)
            // The vault folder itself is reported along with the items that changed in it,
            // and those items tell what changed.
            guard locationPath != rootPath else { continue }
            hasItemLocation = true
            guard let path = WorkspaceModel.vaultPath(forComparablePath: locationPath, rootPath: rootPath) else {
                self = .wholeVault
                return
            }
            // Hidden folders and files, like `.obsidian` and `.trash`, are neither listed
            // nor indexed, as in Obsidian.
            guard !path.rawValue.split(separator: "/").contains(where: { component in component.hasPrefix(".") }) else { continue }
            if (try? location.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                self = .wholeVault
                return
            }
            changedPaths.append(path)
            if changedPaths.count > maximumFileCount {
                self = .wholeVault
                return
            }
        }
        // The vault folder reported alone gives no way to tell what changed.
        guard hasItemLocation else {
            self = .wholeVault
            return
        }
        self = changedPaths.isEmpty ? .nothingShown : .files(changedPaths.sorted())
    }
}
