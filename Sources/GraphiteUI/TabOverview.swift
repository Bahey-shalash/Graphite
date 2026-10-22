import SwiftUI
import GraphiteCore
import GraphiteApple

/// Every open tab as a card, as Safari's tab overview: a thumbnail of the tab as it was last
/// seen, or the preview its file has in the library until it has one, its name below, and a
/// close button on the card. The tab in use is outlined in the accent; a side of a split has
/// a section of its own. A floating bar in Liquid Glass opens a new tab, searches the tabs by
/// name and folder, and leaves the overview (Done, or Esc). Choosing a card shows its tab.
struct TabOverview: View {
    let model: TabOverviewModel
    let actions: TabOverviewActions
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accent) private var accent

    private var isCompactWidth: Bool { horizontalSizeClass == .compact }

    var body: some View {
        let layout = actions.layout()
        let sections = TabOverviewSection.sections(of: layout, matching: searchText, title: actions.title)
        GeometryReader { proxy in
            let cardAspectRatio = Self.cardAspectRatio(documentArea: model.thumbnails.aspectRatio(ofGroup: layout.focusedGroupID),
                                                       overview: proxy.size)
            ScrollViewReader { scrollProxy in
                ScrollView { cardGrid(sections: sections, layout: layout, aspectRatio: cardAspectRatio) }
                    #if canImport(UIKit)
                    .scrollDismissesKeyboard(.immediately)
                    #endif
                    .onAppear { scrollProxy.scrollTo(layout.activeTab.id, anchor: .center) }
            }
            // The cards scroll on under the bar, which lets them show through its glass.
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar(tabCount: layout.allTabs.count) }
        }
        .background { Rectangle().fill(.regularMaterial).ignoresSafeArea() }
        .onAppear {
            #if canImport(UIKit)
            // Keys typed now go to the overview's search, not to a note behind it.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #else
            isSearchFieldFocused = true
            #endif
        }
        .accessibilityAddTraits(.isModal)
    }

    // The grid's measures, which a card's place follows.
    static func horizontalPaddingPoints(isCompactWidth: Bool) -> CGFloat { isCompactWidth ? 16 : 28 }
    static func minimumCardWidthPoints(isCompactWidth: Bool) -> CGFloat { isCompactWidth ? 150 : 220 }
    static let maximumCardWidthPoints: CGFloat = 360
    static let topPaddingPoints: CGFloat = 24
    static let cardSpacingPoints: CGFloat = 20
    static let rowSpacingPoints: CGFloat = 24
    static let sectionSpacingPoints: CGFloat = 28

    /// Cards take the shape of the focused side's document area, which their thumbnails show,
    /// kept between a tall phone page and a wide window.
    static func cardAspectRatio(documentArea: CGFloat?, overview: CGSize) -> CGFloat {
        let shape = documentArea ?? (overview.height > 0 ? overview.width / overview.height : 0.75)
        return min(max(shape, 0.62), 1.6)
    }

    private func cardGrid(sections: [TabOverviewSection], layout: TabLayout, aspectRatio: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Self.sectionSpacingPoints) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    if let sectionTitle = section.title {
                        Text(sectionTitle)
                            .interfaceFont(.title3)
                            .fontWeight(.semibold)
                            .padding(.leading, 4)
                    }
                    LazyVGrid(columns: [cardColumn], alignment: .leading, spacing: Self.rowSpacingPoints) {
                        ForEach(section.tabs) { tab in
                            card(for: tab, in: section, isActive: tab.id == layout.activeTab.id, aspectRatio: aspectRatio).id(tab.id)
                        }
                    }
                }
            }
            if sections.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
            }
        }
        .padding(.horizontal, Self.horizontalPaddingPoints(isCompactWidth: isCompactWidth))
        .padding(.top, Self.topPaddingPoints)
        .padding(.bottom, 24)
    }

    private var cardColumn: GridItem {
        GridItem(.adaptive(minimum: Self.minimumCardWidthPoints(isCompactWidth: isCompactWidth), maximum: Self.maximumCardWidthPoints),
                 spacing: Self.cardSpacingPoints, alignment: .top)
    }

    private func card(for tab: WorkspaceTab, in section: TabOverviewSection, isActive: Bool, aspectRatio: CGFloat) -> some View {
        TabOverviewCard(tab: tab, title: actions.title(tab), folder: tab.path?.parent.rawValue,
                        thumbnail: model.thumbnails.thumbnail(of: tab.id), filePreview: tab.path.flatMap { path in model.filePreviews[path] },
                        aspectRatio: aspectRatio, isActive: isActive,
                        show: { actions.showTab(tab.id) }, close: { actions.closeTab(tab.id) })
            .contextMenu {
                Button("Close", systemImage: "xmark") { actions.closeTab(tab.id) }
                Button("Close Other Tabs", systemImage: "xmark.square") { actions.closeOtherTabs(tab.id) }
                    .disabled(section.tabCount == 1)
                Button(tab.isPinned ? "Unpin" : "Pin", systemImage: tab.isPinned ? "pin.slash" : "pin") { actions.togglePin(tab.id) }
                if let path = tab.path { OpenInNewWindowButton { actions.openInNewWindow(path) } }
            }
    }

    // MARK: Bar

    private func bottomBar(tabCount: Int) -> some View {
        TabOverviewGlassGroup {
            HStack(spacing: 12) {
                Button(action: actions.openNewTab) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .tabOverviewGlass(in: Circle(), isInteractive: true)
                .accessibilityLabel("New Tab")
                .help("New tab (⌘T)")
                searchField(tabCount: tabCount)
                Button(action: model.dismiss) {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .frame(height: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .tabOverviewGlass(in: Capsule(), tint: accent, isInteractive: true)
                .keyboardShortcut(.cancelAction)
            }
            .frame(maxWidth: 600)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func searchField(tabCount: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(tabCount == 1 ? "Search 1 Tab" : "Search \(tabCount) Tabs", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFieldFocused)
                .autocorrectionDisabled()
                .onSubmit(showFirstMatch)
                #if canImport(UIKit)
                .submitLabel(.go)
                #else
                .onExitCommand(perform: model.dismiss)
                #endif
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .tabOverviewGlass(in: Capsule())
    }

    /// Return in the search field shows the first tab found.
    private func showFirstMatch() {
        guard !searchText.isEmpty,
              let tab = TabOverviewSection.sections(of: actions.layout(), matching: searchText, title: actions.title).first?.tabs.first else { return }
        actions.showTab(tab.id)
    }
}

/// Every open tab as a card, as Safari's tab overview, over the whole window while the
/// window's overview model is presented.
struct TabOverviewOverlay: View {
    let model: TabOverviewModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        if model.isPresented && workspace.store != nil {
            TabOverview(model: model, actions: workspace.tabOverviewActions(dismiss: model.dismiss))
                .tint(workspace.preferences.accentColor)
                .environment(\.accent, workspace.preferences.accentColor)
                // Zooms out of the page as it opens and back into it as it closes.
                .transition(GraphiteMotion.isReduced ? .opacity : .opacity.combined(with: .scale(scale: 1.06)))
        }
    }
}

/// What the tab overview reads from the window's tabs and asks of them. Showing a tab or
/// opening a new one also leaves the overview.
struct TabOverviewActions {
    /// The tabs and sides now, read while the overview is drawn.
    let layout: () -> TabLayout
    let title: (WorkspaceTab) -> String
    let showTab: (UUID) -> Void
    let closeTab: (UUID) -> Void
    let closeOtherTabs: (UUID) -> Void
    let togglePin: (UUID) -> Void
    let openInNewWindow: (VaultPath) -> Void
    let openNewTab: () -> Void
}

/// Shows the tab overview of the window. Any two values are equal, as for
/// `TemplatePickerAction`, so the views that read it do not update needlessly.
struct TabOverviewAction: Equatable {
    let show: () -> Void
    static func == (leftAction: TabOverviewAction, rightAction: TabOverviewAction) -> Bool { true }
}

extension EnvironmentValues {
    /// Nil outside a window that shows the overview.
    @Entry var showTabOverview: TabOverviewAction? = nil
}

/// A side's tabs in the overview: those whose name or folder holds every word searched for.
struct TabOverviewSection: Identifiable {
    /// The tab group's identifier.
    let id: UUID
    /// "Left" or "Right" when the layout is split; nil otherwise.
    let title: String?
    let tabs: [WorkspaceTab]
    /// How many tabs the side has, found or not.
    let tabCount: Int

    static func sections(of layout: TabLayout, matching search: String, title: (WorkspaceTab) -> String) -> [TabOverviewSection] {
        let words = search.split(whereSeparator: \.isWhitespace).map(String.init)
        return layout.groups.enumerated().compactMap { groupIndex, group in
            let tabs = group.tabs.filter { tab in
                let searchedText = title(tab) + " " + (tab.path?.parent.rawValue ?? "")
                return words.allSatisfy { word in searchedText.localizedStandardContains(word) }
            }
            guard !tabs.isEmpty else { return nil }
            return TabOverviewSection(id: group.id, title: layout.isSplit ? (groupIndex == 0 ? "Left" : "Right") : nil, tabs: tabs, tabCount: group.tabs.count)
        }
    }
}

// MARK: Card

private struct TabOverviewCard: View {
    let tab: WorkspaceTab
    let title: String
    let folder: String?
    let thumbnail: CGImage?
    /// What the card shows until the tab has a thumbnail: the preview its file has in the library.
    let filePreview: LibraryTilePreview?
    let aspectRatio: CGFloat
    let isActive: Bool
    let show: () -> Void
    let close: () -> Void
    @Environment(\.accent) private var accent
    @Environment(\.displayScale) private var displayScale

    private static let cornerRadiusPoints: CGFloat = 16

    private var symbol: String {
        tab.path.map { path in DocumentKind(path: path).systemImage } ?? (title == "New Tab" ? "plus.square" : "rectangle.on.rectangle")
    }

    var body: some View {
        // The close button is over the card, not in it: a button inside another's label
        // would not take its own clicks.
        ZStack(alignment: .topTrailing) {
            Button(action: show) {
                VStack(spacing: 8) {
                    preview
                    HStack(spacing: 5) {
                        Image(systemName: symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(title)
                            .interfaceFont(.subheadline)
                            .fontWeight(isActive ? .semibold : .regular)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(TabOverviewCardButtonStyle())
            .accessibilityIdentifier("tabOverviewCard")
            .accessibilityLabel(title)
            .accessibilityValue(folder.map { folder in folder.isEmpty ? "" : "In \(folder)" } ?? "")
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .accessibilityAction(named: "Close", close)
            closeButton.padding(8)
        }
    }

    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadiusPoints, style: .continuous)
        return Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay(alignment: .top) { previewContent }
            .background(GraphiteChrome.barBackground)
            .clipShape(shape)
            .overlay { shape.strokeBorder(isActive ? accent : GraphiteChrome.hairline, lineWidth: isActive ? 3 : 1) }
            .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }

    @ViewBuilder private var previewContent: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            switch filePreview {
            case .picture(let image)?:
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .scaledToFill()
            case .note(let summary, let notePicture)?:
                LibraryNotePage(summary: summary, picture: notePicture, displayScale: displayScale, pageAspectRatio: aspectRatio)
            case .notDownloaded?:
                kindSymbol("icloud.and.arrow.down")
            case .kindIcon?, nil:
                kindSymbol(symbol)
            }
        }
    }

    private func kindSymbol(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 34, weight: .light))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var closeButton: some View {
        if tab.isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .tabOverviewGlass(in: Circle())
                .accessibilityHidden(true)
        } else {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .tabOverviewGlass(in: Circle(), isInteractive: true)
            .accessibilityHidden(true)
        }
    }
}

/// A card sinks a little while pressed, as Safari's do.
private struct TabOverviewCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !GraphiteMotion.isReduced ? 0.97 : 1)
            .animation(GraphiteMotion.animation(.snappy(duration: 0.15)), value: configuration.isPressed)
    }
}

// MARK: Liquid Glass

/// Glass shapes near one another blend, as Liquid Glass bars do. Before iOS 26, the shapes
/// stand on their own.
private struct TabOverviewGlassGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else {
            content
        }
    }
}

extension View {
    /// Liquid Glass in the shape, tinted when a tint is given, as the overview's bar and its
    /// cards' buttons are drawn; a material with a hairline before iOS 26.
    @ViewBuilder func tabOverviewGlass(in shape: some Shape, tint: Color? = nil, isInteractive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(isInteractive), in: shape)
        } else if let tint {
            background(tint, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay { shape.stroke(GraphiteChrome.hairline) }
        }
    }
}

/// The open tabs' button: "Tabs", shown as their number in a rounded square, as Safari and
/// Obsidian mobile show it. The number is a symbol, not drawn text, so the button moves with
/// the rest of the bar to the side of iPhone Duo's display, where the system keeps items
/// showing text in a horizontal bar. Past the highest numbered square, a stack of squares.
struct TabCountLabel: View {
    let count: Int
    static let highestNumberedSquare = 50

    var body: some View {
        Label("Tabs", systemImage: Self.systemImage(forCount: count))
    }

    static func systemImage(forCount count: Int) -> String {
        (0...highestNumberedSquare).contains(count) ? "\(count).square" : "square.on.square"
    }
}
