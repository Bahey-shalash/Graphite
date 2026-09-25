import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import GraphiteApple

/// Page thumbnails with selection and page actions, and the PDF's outline and bookmarks.
struct PDFPagesSidebar: View {
    private enum Content: Hashable { case pages, outline }
    private static let thumbnailSize = CGSize(width: 150, height: 200)
    private static let dragPreviewSize = CGSize(width: 75, height: 100)

    @Bindable var session: PDFSession
    let commands: PDFPageCommands
    let renderer: PDFThumbnailRenderer
    @State private var content = Content.pages
    @State private var isSelecting = false
    @State private var selectedPages = PDFPageSelection()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Show", selection: $content) {
                Text("Pages").tag(Content.pages)
                Text("Outline").tag(Content.outline)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            switch content {
            case .pages: pagesList
            case .outline: outlineList
            }
        }
        .background(.background.secondary)
        .onChange(of: session.pageListVersion) { selectedPages.removePages(notIn: session.document) }
    }

    // MARK: Pages

    private var pagesList: some View {
        let bookmarkedPages = session.bookmarkedPageIndices
        return VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        // Reading the version refreshes the rows after pages are inserted, deleted, or moved.
                        let _ = session.pageListVersion
                        ForEach(PDFThumbnailListPage.pages(of: session.document)) { listPage in
                            pageRow(page: listPage.page, pageIndex: listPage.pageIndex, isBookmarked: bookmarkedPages.contains(listPage.pageIndex))
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onAppear { scrollToCurrentPage(with: scrollProxy, animated: false) }
                .onChange(of: session.currentPageIndex) { scrollToCurrentPage(with: scrollProxy, animated: true) }
            }
            Divider()
            selectionBar
        }
    }

    private func scrollToCurrentPage(with scrollProxy: ScrollViewProxy, animated: Bool) {
        guard let page = session.document.page(at: session.currentPageIndex) else { return }
        withAnimation(animated ? .default : nil) { scrollProxy.scrollTo(ObjectIdentifier(page), anchor: .center) }
    }

    private func pageRow(page: PDFPage, pageIndex: Int, isBookmarked: Bool) -> some View {
        let isCurrent = pageIndex == session.currentPageIndex
        let isSelected = selectedPages.contains(page)
        return Button {
            if isSelecting {
                selectedPages.toggle(page)
            } else {
                session.go(to: pageIndex)
            }
        } label: {
            VStack(spacing: 6) {
                PDFSessionPageThumbnail(session: session, page: page, renderer: renderer, size: Self.thumbnailSize)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    .overlay(alignment: .topTrailing) {
                        if isBookmarked {
                            Image(systemName: "bookmark.fill").foregroundStyle(.red).padding(4).accessibilityLabel("Bookmarked")
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if isSelecting {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                .background(Circle().fill(.background))
                                .padding(6)
                        }
                    }
                Text("\(pageIndex + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .padding(8)
            .background(isCurrent && !isSelecting ? AnyShapeStyle(.tint.opacity(0.14)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(pageIndex + 1)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            // A protected PDF is shown without changes, so its pages have no actions.
            if !session.isProtected { pageMenu(for: pageIndex, isBookmarked: isBookmarked) }
        }
        .draggable(PDFPageDragItem(sessionIdentifier: session.identifier, pageIndex: pageIndex)) {
            // Rendered at the row's size and shown smaller: the renderer keeps one image per
            // page whatever its size, so a small render would come back blurry in the row.
            PDFSessionPageThumbnail(session: session, page: page, renderer: renderer, size: Self.thumbnailSize)
                .scaleEffect(Self.dragPreviewSize.width / Self.thumbnailSize.width)
                .frame(width: Self.dragPreviewSize.width, height: Self.dragPreviewSize.height)
        }
        .dropDestination(for: PDFPageDragItem.self) { droppedItems, _ in
            guard !session.isProtected, let droppedItem = droppedItems.first, droppedItem.sessionIdentifier == session.identifier,
                  droppedItem.pageIndex != pageIndex else { return false }
            commands.move(page: droppedItem.pageIndex, to: pageIndex)
            return true
        }
    }

    @ViewBuilder private func pageMenu(for pageIndex: Int, isBookmarked: Bool) -> some View {
        Section {
            Button("Move Up", systemImage: "arrow.up") { commands.move(page: pageIndex, to: pageIndex - 1) }.disabled(pageIndex == 0)
            Button("Move Down", systemImage: "arrow.down") { commands.move(page: pageIndex, to: pageIndex + 1) }.disabled(pageIndex >= session.pageCount - 1)
        }
        Menu("Insert Page Before", systemImage: "arrow.up.doc") {
            ForEach(PaperTemplate.allCases) { template in
                Button(template.title, systemImage: template.symbolName) { commands.insertPaper(template, at: pageIndex) }
            }
        }
        Menu("Insert Page After", systemImage: "arrow.down.doc") {
            ForEach(PaperTemplate.allCases) { template in
                Button(template.title, systemImage: template.symbolName) { commands.insertPaper(template, at: pageIndex + 1) }
            }
        }
        PDFPageActionsMenuContent(commands: commands, pageIndices: [pageIndex], isBookmarked: isBookmarked)
    }

    @ViewBuilder private var selectionBar: some View {
        HStack {
            if isSelecting {
                let selectedPageIndices = selectedPages.pageIndices(in: session.document)
                Menu {
                    PDFPageActionsMenuContent(commands: commands, pageIndices: selectedPageIndices,
                                              isBookmarked: selectedPageIndices.count == 1 && selectedPageIndices.first.map(session.bookmarkedPageIndices.contains) == true)
                } label: {
                    Label("\(selectedPageIndices.count) Selected", systemImage: "ellipsis.circle")
                }
                .disabled(selectedPageIndices.isEmpty)
                Spacer()
                Button("Done") { isSelecting = false; selectedPages.removeAll() }.bold()
            } else if !session.isProtected {
                Button("Select") {
                    isSelecting = true
                    selectedPages = PDFPageSelection(pages: [session.document.page(at: session.currentPageIndex)].compactMap { page in page })
                }
                Spacer()
                Text("\(session.pageCount) pages").font(.caption).foregroundStyle(.secondary)
            } else {
                Spacer()
                Text("\(session.pageCount) pages").font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    // MARK: Outline

    @ViewBuilder private var outlineList: some View {
        let entries = session.outlineEntries
        if entries.isEmpty {
            ContentUnavailableView {
                Label("No Bookmarks", systemImage: "bookmark")
            } description: {
                Text("Bookmark a page from its menu. Bookmarks are saved in the PDF's outline, which other PDF apps show too.")
            } actions: {
                if !session.isProtected {
                    Button("Bookmark This Page") { commands.toggleBookmark(page: session.currentPageIndex) }
                }
            }
        } else {
            List(entries) { entry in
                Button {
                    if let pageIndex = entry.pageIndex { session.go(to: pageIndex) }
                } label: {
                    HStack {
                        if entry.isBookmark { Image(systemName: "bookmark.fill").foregroundStyle(.red).imageScale(.small) }
                        Text(entry.label).lineLimit(2)
                        Spacer()
                        if let pageIndex = entry.pageIndex { Text("\(pageIndex + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    }
                    .padding(.leading, CGFloat(entry.depth) * 14)
                }
                .disabled(entry.pageIndex == nil)
                .contextMenu {
                    Button(entry.isBookmark ? "Remove Bookmark" : "Remove from Outline", systemImage: "trash", role: .destructive) {
                        commands.removeOutlineEntry(entry)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

/// The pages chosen in the sidebar's Select mode. Pages are kept as objects, not indices,
/// so inserting, duplicating, moving, or deleting pages never moves the selection onto
/// pages the user did not choose.
struct PDFPageSelection {
    private var pagesByIdentifier: [ObjectIdentifier: PDFPage] = [:]

    init(pages: [PDFPage] = []) {
        for page in pages { pagesByIdentifier[ObjectIdentifier(page)] = page }
    }

    func contains(_ page: PDFPage) -> Bool { pagesByIdentifier[ObjectIdentifier(page)] != nil }

    mutating func toggle(_ page: PDFPage) {
        let identifier = ObjectIdentifier(page)
        if pagesByIdentifier[identifier] == nil { pagesByIdentifier[identifier] = page } else { pagesByIdentifier[identifier] = nil }
    }

    mutating func removeAll() { pagesByIdentifier.removeAll() }

    /// Forgets deleted pages. The selection holds its pages, so a deleted page's object
    /// cannot be reused for a new page while it is selected.
    mutating func removePages(notIn document: PDFDocument) {
        pagesByIdentifier = pagesByIdentifier.filter { _, page in document.index(for: page) != NSNotFound }
    }

    /// Where the selected pages are now, in page order, leaving out deleted pages.
    func pageIndices(in document: PDFDocument) -> [Int] {
        pagesByIdentifier.values.map(document.index(for:)).filter { pageIndex in pageIndex != NSNotFound }.sorted()
    }
}

/// A page thumbnail that reads the page's appearance version itself, so a stroke on one
/// page re-evaluates only that page's row and not the whole list.
private struct PDFSessionPageThumbnail: View {
    let session: PDFSession
    let page: PDFPage
    let renderer: PDFThumbnailRenderer
    let size: CGSize

    var body: some View {
        PDFPageThumbnail(page: page, version: session.appearanceVersion(of: page), renderer: renderer, size: size)
    }
}

/// A page dragged within the sidebar to reorder it. The index means something only in the
/// PDF it came from, so the payload names that session and has a type of its own, which
/// other apps and other drop targets do not accept.
struct PDFPageDragItem: Codable, Transferable {
    let sessionIdentifier: UUID
    let pageIndex: Int
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .graphitePDFPage)
    }
}

extension UTType {
    /// Used only for drags inside Graphite. Like the vault item and tab types, it must be
    /// declared in the app's Info.plist for drops to accept it.
    static let graphitePDFPage = UTType(exportedAs: "com.graphite.study.pdf-page", conformingTo: .data)
}
