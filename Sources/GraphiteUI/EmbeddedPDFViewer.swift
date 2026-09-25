import SwiftUI
import PDFKit
import GraphiteCore
import GraphiteApple
#if canImport(UIKit)
import UIKit
#endif

/// An Obsidian-style PDF embed for `![[lecture.pdf]]` in the reading view: a framed,
/// scrollable viewer of every page with thumbnails, zoom, a page field, and in-place
/// annotation that saves through the same session as the PDF pane.
///
/// The PDF loads when the embed scrolls into view and is saved and released shortly after
/// it leaves, so a note with many embeds keeps only the visible ones in memory.
struct EmbeddedPDFViewer: View {
    static let defaultHeight: CGFloat = 560
    /// A viewer that is scrolled away only briefly keeps its document.
    private static let releaseDelay = Duration.seconds(1.5)
    private static let zoomStep: CGFloat = 1.25
    private static let thumbnailSize = CGSize(width: 76, height: 100)

    let location: URL
    let startPageNumber: Int?
    let height: CGFloat
    /// Opens the PDF in the full PDF pane at a zero-based page index.
    let openInPane: (Int) -> Void

    @State private var session: PDFSession?
    @State private var loadingError: String?
    @State private var isVisible = false
    @State private var loadGeneration = 0
    @State private var isAnnotating = false
    /// Other embeds of the PDF are saved, and a stale copy refreshed, before annotating starts.
    @State private var isPreparingToAnnotate = false
    @State private var showsThumbnails = false
    @State private var pageText = ""
    /// The page field's text when it was focused; leaving it unchanged does not navigate.
    @State private var pageTextWhenEditingBegan: String?
    @State private var showsReloadConfirmation = false
    @State private var conflictNotice: ConflictNotice?
    @State private var thumbnailRenderer = PDFThumbnailRenderer()
    @FocusState private var isEditingPageNumber: Bool
    @AppStorage(PDFAnnotationPreferenceKey.drawsWithFinger) private var drawsWithFinger = false
    @Environment(\.scenePhase) private var scenePhase

    /// What the conflict banner says instead of its default text.
    private enum ConflictNotice {
        /// Names the copy while it still holds every annotation made in this embed.
        case savedCopy(fileName: String, changeVersion: Int)
        case resolveBeforeOpeningPane
    }

    /// - Parameters:
    ///   - startPageNumber: One-based page to show first, from `#page=N`.
    ///   - height: Viewer height in points, from `#height=N`; defaults to 560.
    ///   - openInPane: Opens the PDF in the full PDF pane at the page shown here.
    init(location: URL, startPageNumber: Int? = nil, height: CGFloat? = nil, openInPane: @escaping (Int) -> Void) {
        self.location = location
        self.startPageNumber = startPageNumber
        self.height = height.map { requestedHeight in min(max(requestedHeight, CGFloat(PDFEmbedOptions.minimumHeight)), CGFloat(PDFEmbedOptions.maximumHeight)) } ?? Self.defaultHeight
        self.openInPane = openInPane
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            statusBanner
            content
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .onDisappear { scheduleRelease() }
        // Runs each time the embed appears, and again after a reload.
        .task(id: loadGeneration) {
            isVisible = true
            await loadIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard let session else { return }
            Task {
                do {
                    if phase == .active {
                        if try await session.hasChangedExternally(), !session.hasUnsavedChanges { reload() }
                    } else {
                        try await Self.withBackgroundTime { try await session.save() }
                    }
                } catch {
                    session.errorMessage = error.localizedDescription
                }
            }
        }
        .onChange(of: session?.currentPageIndex) { _, pageIndex in
            if !isEditingPageNumber, let pageIndex { pageText = "\(pageIndex + 1)" }
        }
        // A released or replaced document takes its thumbnails with it. A new one is mapped
        // before its first save replaces the file it was read from.
        .onChange(of: session.map { session in ObjectIdentifier(session) }) { _, _ in
            thumbnailRenderer.removeThumbnails()
            if let session { thumbnailRenderer.prepare(for: session.document) }
        }
        // Another embed of this PDF started annotating; only one edits it at a time.
        .onChange(of: EmbeddedPDFSessions.shared.annotatingSession(at: location)) { _, annotatingSession in
            if isAnnotating, let session, annotatingSession != ObjectIdentifier(session) { isAnnotating = false }
        }
        .confirmationDialog("Discard your annotations in this embed and show the version saved by the other app?", isPresented: $showsReloadConfirmation, titleVisibility: .visible) {
            Button("Use Other Version", role: .destructive) { reload() }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 4) {
            Group {
                toolbarButton(showsThumbnails ? "Hide Thumbnails" : "Show Thumbnails", systemImage: "sidebar.left", isActive: showsThumbnails) {
                    withAnimation(.snappy) { showsThumbnails.toggle() }
                }
                toolbarButton("Zoom Out", systemImage: "minus.magnifyingglass") { zoom(by: 1 / Self.zoomStep) }
                toolbarButton("Zoom In", systemImage: "plus.magnifyingglass") { zoom(by: Self.zoomStep) }
                pageField
            }
            .disabled(session == nil)
            Spacer(minLength: 8)
            Text(location.deletingPathExtension().lastPathComponent)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if let session, session.isSaving || session.hasUnsavedChanges {
                Text(session.isSaving ? "Saving…" : "Edited").font(.caption2).foregroundStyle(.secondary)
            }
            #if canImport(UIKit)
            toolbarButton(isAnnotating ? "Stop Annotating" : "Annotate", systemImage: isAnnotating ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle", isActive: isAnnotating) {
                if isAnnotating {
                    stopAnnotating()
                } else if let session {
                    startAnnotating(session)
                }
            }
            // Annotating can always be stopped, also after a conflict appeared meanwhile.
            .disabled(session == nil || isPreparingToAnnotate || (!isAnnotating && !canStartAnnotating))
            #endif
            toolbarButton("Open in PDF View", systemImage: "arrow.up.left.and.arrow.down.right") { openFullPane() }
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
    }

    private func toolbarButton(_ title: String, systemImage: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: 34, height: 32)
            .background(isActive ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 7))
            .help(title)
    }

    private var pageField: some View {
        HStack(spacing: 4) {
            TextField("Page", text: $pageText)
                .focused($isEditingPageNumber)
                #if canImport(UIKit)
                .keyboardType(.numberPad)
                #endif
                .multilineTextAlignment(.center)
                .font(.callout.monospacedDigit())
                .frame(width: 44)
                .textFieldStyle(.roundedBorder)
                .onSubmit(goToTypedPage)
                .onChange(of: isEditingPageNumber) { _, isEditing in
                    if isEditing {
                        pageTextWhenEditingBegan = pageText
                    } else {
                        finishEditingPageNumber()
                    }
                }
                .accessibilityLabel("Page number")
            Text("of \(session?.pageCount ?? 0)").font(.callout.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
        }
        .padding(.leading, 4)
    }

    // MARK: Content

    @ViewBuilder private var statusBanner: some View {
        if let session, session.hasExternalConflict {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(conflictBannerText(for: session)).font(.caption)
                Spacer()
                Button("Save a Copy") { saveCopy(of: session) }.font(.caption)
                Button("Use Other Version") { showsReloadConfirmation = true }.font(.caption)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.orange.opacity(0.12))
        } else if let errorMessage = session?.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.red.opacity(0.08))
        } else if let session, session.isProtected {
            Label("This PDF is protected by a password, so Graphite shows it without changing it: annotating is off.", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(.quaternary.opacity(0.5))
        }
    }

    private func conflictBannerText(for session: PDFSession) -> String {
        switch conflictNotice {
        case .savedCopy(let fileName, let changeVersion) where changeVersion == session.changeVersion:
            "Your annotations were saved as “\(fileName)”."
        case .resolveBeforeOpeningPane:
            "Save a copy or use the other version before opening this PDF in the PDF view."
        case .savedCopy, nil:
            "This PDF changed in another app. Your annotations are still here."
        }
    }

    /// A protected PDF is shown without changes, and a conflict must be resolved first.
    private var canStartAnnotating: Bool {
        guard let session else { return false }
        return !session.hasExternalConflict && !session.isProtected
    }

    @ViewBuilder private var content: some View {
        if let session {
            HStack(spacing: 0) {
                if showsThumbnails {
                    thumbnailStrip(for: session)
                        .frame(width: Self.thumbnailSize.width + 24)
                        .transition(.move(edge: .leading))
                    Divider()
                }
                // A refreshed or recovered session opens where its viewer was; a new one at
                // the start page, which loading made current.
                GraphitePDFView(session: session,
                                input: PDFAnnotationInput(isEnabled: isAnnotating && !session.isProtected, drawsWithFinger: drawsWithFinger,
                                                          showsToolPicker: isAnnotating && !session.isProtected),
                                isEmbedded: true,
                                initialPageIndex: session.currentPageIndex)
                    // A reloaded file is a new session; its view and canvases start fresh.
                    .id(ObjectIdentifier(session))
            }
        } else if let loadingError {
            ContentUnavailableView {
                Label("Cannot Show PDF", systemImage: "doc.questionmark")
            } description: {
                Text(loadingError)
            } actions: {
                Button("Try Again") { self.loadingError = nil; loadGeneration += 1 }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func thumbnailStrip(for session: PDFSession) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    let _ = session.pageListVersion
                    ForEach(PDFThumbnailListPage.pages(of: session.document)) { listPage in
                        thumbnailButton(for: listPage, in: session)
                    }
                }
                .padding(.vertical, 8)
            }
            .onAppear { session.document.page(at: session.currentPageIndex).map { page in scrollProxy.scrollTo(ObjectIdentifier(page), anchor: .center) } }
            .onChange(of: session.currentPageIndex) { _, pageIndex in
                guard let page = session.document.page(at: pageIndex) else { return }
                withAnimation { scrollProxy.scrollTo(ObjectIdentifier(page), anchor: .center) }
            }
        }
    }

    private func thumbnailButton(for listPage: PDFThumbnailListPage, in session: PDFSession) -> some View {
        let isCurrent = listPage.pageIndex == session.currentPageIndex
        return Button {
            session.go(to: listPage.pageIndex)
        } label: {
            VStack(spacing: 3) {
                PDFPageThumbnail(page: listPage.page, version: session.appearanceVersion(of: listPage.page), renderer: thumbnailRenderer, size: Self.thumbnailSize)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                Text("\(listPage.pageIndex + 1)").font(.caption2.monospacedDigit())
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .padding(4)
            .background(isCurrent ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(listPage.pageIndex + 1)")
    }

    // MARK: Actions

    /// Leaving the field without typing keeps the page scrolled to meanwhile.
    private func finishEditingPageNumber() {
        defer { pageTextWhenEditingBegan = nil }
        guard pageText != pageTextWhenEditingBegan else {
            if let session { pageText = "\(session.currentPageIndex + 1)" }
            return
        }
        goToTypedPage()
    }

    private func goToTypedPage() {
        guard let session else { return }
        guard let pageNumber = Int(pageText.trimmingCharacters(in: .whitespaces)), (1...max(1, session.pageCount)).contains(pageNumber) else {
            pageText = "\(session.currentPageIndex + 1)"
            return
        }
        session.go(to: pageNumber - 1)
    }

    private func zoom(by factor: CGFloat) {
        guard let pdfView = session?.pdfView else { return }
        pdfView.autoScales = false
        pdfView.scaleFactor = min(max(pdfView.scaleFactor * factor, pdfView.minScaleFactor), pdfView.maxScaleFactor)
    }

    private func openFullPane() {
        guard let session else {
            openInPane(max((startPageNumber ?? 1) - 1, 0))
            return
        }
        // The pane opens its own session from the file, so it must see these edits; with a
        // conflict they cannot be saved, and the banner says what to do first.
        guard !session.hasExternalConflict else {
            conflictNotice = .resolveBeforeOpeningPane
            return
        }
        Task {
            do {
                try await session.saveBeforeClosing()
                stopAnnotating()
                openInPane(session.currentPageIndex)
            } catch {
                session.errorMessage = error.localizedDescription
            }
        }
    }

    private func saveCopy(of session: PDFSession) {
        // The copy holds the edits made before it was started; strokes made while it is
        // written are not in it.
        let copiedChangeVersion = session.changeVersion
        Task {
            do {
                let copyLocation = try await session.saveSeparateCopy()
                conflictNotice = .savedCopy(fileName: copyLocation.lastPathComponent, changeVersion: copiedChangeVersion)
            } catch {
                session.errorMessage = error.localizedDescription
            }
        }
    }

    private func reload() {
        if let session { EmbeddedPDFSessions.shared.remove(session) }
        stopAnnotating()
        session = nil
        conflictNotice = nil
        loadGeneration += 1
    }

    // MARK: Annotating

    private func startAnnotating(_ session: PDFSession) {
        isPreparingToAnnotate = true
        let sessions = EmbeddedPDFSessions.shared
        Task {
            defer { isPreparingToAnnotate = false }
            do {
                let annotatedSession = try await sessions.prepareToAnnotate(session)
                if self.session === session {
                    self.session = annotatedSession
                } else if annotatedSession !== session {
                    sessions.remove(annotatedSession)
                }
                // Released, reloaded, or another embed started annotating meanwhile.
                guard self.session === annotatedSession, sessions.annotatingSession(at: location) == ObjectIdentifier(annotatedSession),
                      !annotatedSession.isProtected else {
                    sessions.endAnnotating(annotatedSession)
                    return
                }
                isAnnotating = true
            } catch {
                session.errorMessage = error.localizedDescription
            }
        }
    }

    private func stopAnnotating() {
        isAnnotating = false
        if let session { EmbeddedPDFSessions.shared.endAnnotating(session) }
    }

    // MARK: Loading and releasing

    private func loadIfNeeded() async {
        guard isVisible, session == nil, loadingError == nil else { return }
        let sessions = EmbeddedPDFSessions.shared
        // A session whose closing save failed comes back with its edits and its banner.
        if let keptSession = sessions.takeKeptSession(at: location) {
            sessions.add(keptSession)
            session = keptSession
            pageText = "\(keptSession.currentPageIndex + 1)"
            return
        }
        do {
            let openedSession = try await sessions.openSession(at: location)
            guard !Task.isCancelled, isVisible, session == nil else { return }
            let initialPage = startPageNumber.map { pageNumber in min(max(0, pageNumber - 1), max(0, openedSession.pageCount - 1)) } ?? 0
            openedSession.currentPageIndex = initialPage
            sessions.add(openedSession)
            session = openedSession
            pageText = "\(initialPage + 1)"
        } catch {
            guard !Task.isCancelled else { return }
            loadingError = error.localizedDescription
        }
    }

    /// Saves and releases the document once the embed has stayed out of view. The task
    /// keeps the session alive until its edits are written, even if this view is gone.
    private func scheduleRelease() {
        isVisible = false
        stopAnnotating()
        guard let closingSession = session else { return }
        Task {
            try? await Task.sleep(for: Self.releaseDelay)
            guard !isVisible else { return }
            let sessions = EmbeddedPDFSessions.shared
            do {
                try await closingSession.saveBeforeClosing()
            } catch {
                closingSession.errorMessage = error.localizedDescription
                // Shown again meanwhile: the banner offers a copy or reload.
                if isVisible, session === closingSession { return }
                // The note may be gone with this view. The session and its edits are kept
                // until an embed of this PDF shows them again, with the banner.
                if session === closingSession { session = nil }
                sessions.remove(closingSession)
                sessions.keep(closingSession)
                return
            }
            guard !isVisible, session === closingSession else { return }
            session = nil
            sessions.remove(closingSession)
        }
    }

    // MARK: Background time

    /// Asks iOS for time to finish a save after the app leaves the screen, so a long PDF
    /// write is not suspended halfway and the app ended with the edits unsaved.
    @MainActor private static func withBackgroundTime(_ operation: () async throws -> Void) async throws {
        #if canImport(UIKit)
        let backgroundTime = PDFSaveBackgroundTime()
        defer { backgroundTime.end() }
        #endif
        try await operation()
    }
}

#if canImport(UIKit)
/// A request for background execution time that ends once, when the save finishes or when
/// iOS says the time is up.
@MainActor
private final class PDFSaveBackgroundTime {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Save PDF annotations") { [weak self] in
            self?.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
#endif

/// The PDF sessions of the embeds in every open note, by file.
///
/// Embeds are created by separate notes and reading views that share no owner, so this
/// registry is app-wide. It keeps two embeds of one PDF from editing it from separate
/// copies, and it keeps a session whose closing save failed, with its unsaved edits, until
/// an embed of that PDF shows it again.
@MainActor @Observable
final class EmbeddedPDFSessions {
    static let shared = EmbeddedPDFSessions()

    private struct ShownSession {
        weak var session: PDFSession?
    }

    /// How sessions of one vault's PDFs save. The writer coordinates with the vault's
    /// file presenter, so the embeds' own saves do not come back as external changes;
    /// `didSave` tells the workspace instead, which refreshes the index and open tabs.
    struct VaultSaving {
        let writer: AtomicFileWriter
        let didSave: @MainActor (URL) -> Void
    }

    /// Embeds are drawn by reading views and Live Preview widgets that have no workspace
    /// to ask, so each workspace registers its open vault here, by root folder.
    @ObservationIgnored private var vaultSavingByRootPath: [String: (owner: ObjectIdentifier, saving: VaultSaving)] = [:]
    @ObservationIgnored private var shownSessionsByLocation: [URL: [ShownSession]] = [:]
    @ObservationIgnored private var keptSessionsByLocation: [URL: [PDFSession]] = [:]
    /// The session of the one embed annotating each PDF.
    private var annotatingSessionsByLocation: [URL: ObjectIdentifier] = [:]

    private static func key(for location: URL) -> URL { location.standardizedFileURL }

    /// Makes PDFs inside `root` save through `saving`, replacing any vault `owner`
    /// registered before, as when a workspace switches vaults.
    func useVault(root: URL, owner: AnyObject, saving: VaultSaving) {
        stopUsingVaults(of: owner)
        vaultSavingByRootPath[WorkspaceModel.comparablePath(of: root)] = (ObjectIdentifier(owner), saving)
    }

    func stopUsingVaults(of owner: AnyObject) {
        vaultSavingByRootPath = vaultSavingByRootPath.filter { _, entry in entry.owner != ObjectIdentifier(owner) }
    }

    /// Opens a PDF for an embed, saving through its vault's writer when a workspace has
    /// that vault open.
    func openSession(at location: URL) async throws -> PDFSession {
        let saving = vaultSaving(containing: location)
        let session = try await PDFSession.open(location, writer: saving?.writer ?? AtomicFileWriter())
        session.didSave = saving?.didSave
        return session
    }

    private func vaultSaving(containing location: URL) -> VaultSaving? {
        guard !vaultSavingByRootPath.isEmpty else { return nil }
        let locationPath = WorkspaceModel.comparablePath(of: location)
        // A vault inside another vault's folder saves its own files.
        return vaultSavingByRootPath.filter { rootPath, _ in locationPath.hasPrefix(rootPath + "/") }
            .max { leftEntry, rightEntry in leftEntry.key.count < rightEntry.key.count }?.value.saving
    }

    func add(_ session: PDFSession) {
        let key = Self.key(for: session.location)
        var shownSessions = shownSessionsByLocation[key, default: []].filter { shownSession in shownSession.session != nil }
        if !shownSessions.contains(where: { shownSession in shownSession.session === session }) { shownSessions.append(ShownSession(session: session)) }
        shownSessionsByLocation[key] = shownSessions
    }

    func remove(_ session: PDFSession) {
        let key = Self.key(for: session.location)
        let shownSessions = shownSessionsByLocation[key, default: []].filter { shownSession in
            shownSession.session != nil && shownSession.session !== session
        }
        shownSessionsByLocation[key] = shownSessions.isEmpty ? nil : shownSessions
        endAnnotating(session)
    }

    func otherSessions(showing location: URL, besides session: PDFSession) -> [PDFSession] {
        shownSessionsByLocation[Self.key(for: location), default: []].compactMap(\.session).filter { shownSession in shownSession !== session }
    }

    func annotatingSession(at location: URL) -> ObjectIdentifier? {
        annotatingSessionsByLocation[Self.key(for: location)]
    }

    /// Other embeds of the PDF stop annotating when they see this change.
    func beginAnnotating(_ session: PDFSession) {
        annotatingSessionsByLocation[Self.key(for: session.location)] = ObjectIdentifier(session)
    }

    func endAnnotating(_ session: PDFSession) {
        let key = Self.key(for: session.location)
        if annotatingSessionsByLocation[key] == ObjectIdentifier(session) { annotatingSessionsByLocation[key] = nil }
    }

    /// Makes `session` the one that annotates its PDF, and returns the session to annotate.
    ///
    /// Separate copies of one PDF would each refuse the other's save as a change made
    /// outside Graphite. So the other embeds of the PDF stop annotating and are saved
    /// first, and a session without edits is replaced by a fresh one, on the same page,
    /// when they (or the PDF view) changed the file since it was read.
    func prepareToAnnotate(_ session: PDFSession) async throws -> PDFSession {
        beginAnnotating(session)
        do {
            for otherSession in otherSessions(showing: session.location, besides: session) {
                try await otherSession.saveBeforeClosing()
            }
            guard !session.hasUnsavedChanges, try await session.hasChangedExternally() else { return session }
            let refreshedSession = try await openSession(at: session.location)
            refreshedSession.currentPageIndex = min(session.currentPageIndex, max(0, refreshedSession.pageCount - 1))
            let isStillClaimed = annotatingSession(at: session.location) == ObjectIdentifier(session)
            remove(session)
            add(refreshedSession)
            if isStillClaimed { beginAnnotating(refreshedSession) }
            return refreshedSession
        } catch {
            endAnnotating(session)
            throw error
        }
    }

    func keep(_ session: PDFSession) {
        keptSessionsByLocation[Self.key(for: session.location), default: []].append(session)
    }

    func takeKeptSession(at location: URL) -> PDFSession? {
        let key = Self.key(for: location)
        guard var keptSessions = keptSessionsByLocation[key], !keptSessions.isEmpty else { return nil }
        let keptSession = keptSessions.removeFirst()
        keptSessionsByLocation[key] = keptSessions.isEmpty ? nil : keptSessions
        return keptSession
    }
}
