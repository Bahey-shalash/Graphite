import SwiftUI
import GraphiteCore

/// The same reading/writing switch for notes, PDF notebooks and canvases: one pencil that
/// is picked up to write and put down to read, as Obsidian's view toggle, rather than a
/// wide segmented control. Writing is marked by the accent and a faint fill, not by color
/// alone, and VoiceOver reads the state. A toolbar too narrow for it moves it into its
/// overflow menu as a checked item, where a segmented control was not offered at all.
struct DocumentModeToggle: View {
    @Binding var isWriting: Bool
    /// Drawn by Graphite, for rows outside the window's toolbar such as the tab bar; the
    /// toolbar draws its own toggles.
    var drawsOwnBackground = false
    @Environment(\.accent) private var accent

    var body: some View {
        Group {
            if drawsOwnBackground {
                Button { isWriting.toggle() } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: isWriting ? .semibold : .regular))
                        .foregroundStyle(isWriting ? accent : Color.secondary)
                        .frame(width: 34, height: 30)
                        .background(isWriting ? accent.opacity(0.14) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: GraphiteChrome.cornerRadius, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Write")
                .accessibilityValue(isWriting ? "On" : "Off")
                .accessibilityAddTraits(isWriting ? .isSelected : [])
            } else {
                Toggle(isOn: $isWriting) {
                    Label("Write", systemImage: "pencil")
                }
                .toggleStyle(.button)
                // The toolbar's buttons are neutral; the toggle in use takes the accent.
                .tint(accent)
            }
        }
        .help(isWriting ? "Writing. Choose to read." : "Reading. Choose to write.")
        .accessibilityIdentifier("documentModePicker")
    }
}

/// A row of its own for Write, Undo, and Redo, when neither the window's toolbar nor the
/// tab bar has room for them (`DocumentToolbarLayout`): quiet, in the page's color, with
/// the controls at its trailing end in the toolbar's order.
struct DocumentControlRow<TrailingControls: View>: View {
    @Binding var isWriting: Bool
    @ViewBuilder var trailingControls: TrailingControls

    var body: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 8)
            // Neutral, as in the toolbar; the accent marks selection and links.
            trailingControls
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .tint(.secondary)
            DocumentModeToggle(isWriting: $isWriting, drawsOwnBackground: true)
        }
        .padding(.horizontal, 12)
        .frame(height: GraphiteChrome.barHeight)
        .background(GraphiteChrome.barBackground)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// Where a document puts its Write toggle, Undo, and Redo.
enum DocumentToolbarLayout {
    /// The window's toolbar holds the navigation buttons, the title, recording, the
    /// document's own tools, Undo, Redo, Write and More. Narrower than this, iPadOS moves
    /// the last buttons into an overflow menu, where Undo and Redo would be a menu away,
    /// so they move below the toolbar instead: to the end of the tab bar, or to a row of
    /// their own where that has no room either.
    static let minimumDetailWidthForToolbarControls: CGFloat = 1_100

    /// The narrowest tab bar that holds the controls and still shows two tabs. Its own
    /// buttons and the controls take about 250 points.
    static let minimumTabBarWidthForControls: CGFloat = 480

    /// Whether the controls leave the window's toolbar for the tab bar or a row below it.
    /// A compact width never does: there, as on a phone, the navigation bar holds only the
    /// document's controls, and moving between files happens in the bottom bar.
    /// - Parameter detailWidth: The width of the documents area, nil when unknown.
    static func usesControlRow(detailWidth: CGFloat?, horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        if horizontalSizeClass == .compact { return false }
        guard let detailWidth else { return false }
        return detailWidth < minimumDetailWidthForToolbarControls
    }

    /// Whether the controls the toolbar has no room for go to the end of a side's tab bar.
    /// A row of their own would take a strip of the page for three controls; the tab bar is
    /// there anyway and mostly empty.
    /// - Parameter tabBarWidth: The width of that side, nil when unknown.
    static func showsControlsInTabBar(usesControlRow: Bool, showsTabBar: Bool, tabBarWidth: CGFloat?) -> Bool {
        guard usesControlRow, showsTabBar, let tabBarWidth else { return false }
        return tabBarWidth >= minimumTabBarWidthForControls
    }

    /// The narrowest a tab bar gives the fixed bar's tools, which scroll sideways where
    /// they need more; narrower, they keep a row of their own.
    static let minimumPencilToolsWidthInTabBar: CGFloat = 320
    /// What a tab bar keeps for its tabs beside the tools: one tab at least.
    static let minimumTabsWidthBesidePencilTools: CGFloat = 160
    /// The tab bar's own buttons, New Tab and Split Right.
    static let tabBarButtonsWidth: CGFloat = 80
    /// Undo, Redo and Write, when the tab bar holds them, with room to spare for larger
    /// Dynamic Type.
    static let documentControlsWidth: CGFloat = 160

    /// Whether a side's tab bar holds the fixed bar's tools, so they take no row of their
    /// own above the page.
    /// - Parameter tabBarWidth: The width of that side, nil when unknown.
    static func showsPencilToolsInTabBar(showsTabBar: Bool, tabBarWidth: CGFloat?, showsDocumentControls: Bool) -> Bool {
        guard showsTabBar, let tabBarWidth else { return false }
        let widthBesideTools = minimumTabsWidthBesidePencilTools + tabBarButtonsWidth + (showsDocumentControls ? documentControlsWidth : 0)
        return tabBarWidth - widthBesideTools >= minimumPencilToolsWidthInTabBar
    }
}

extension EnvironmentValues {
    /// Whether documents show Write, Undo, and Redo below the navigation bar, in the tab
    /// bar or a row of their own (`DocumentControlRow`); nil where no workspace measured
    /// its width, which then keeps them in the toolbar.
    @Entry var usesDocumentControlRow: Bool? = nil
    /// True where the side's tab bar shows those controls (`TabBarDocumentControls`), so
    /// the document shows no row for them.
    @Entry var showsDocumentControlsInTabBar = false
    /// True where the side's tab bar has room for the fixed bar's tools
    /// (`TabBarPencilTools`), so a PDF written on shows no row for them.
    @Entry var showsPencilToolsInTabBar = false
}

/// Undo, Redo and Write of a side's active document, at the end of its tab bar.
struct TabBarDocumentControls: View {
    let tab: WorkspaceTab
    let document: TabDocument
    let defaultEditingMode: EditingMode

    var body: some View {
        // A tab whose file is still loading has the sessions of the file before it.
        if tab.path != nil, document.loadedPath == tab.path {
            if let session = document.markdownSession {
                let isEditing = session.viewMode != .reading
                controls(isWriting: Binding(get: { session.viewMode != .reading }, set: { shouldWrite in
                    if shouldWrite != (session.viewMode != .reading) { session.toggleReadingView(editingMode: defaultEditingMode) }
                })) {
                    #if canImport(UIKit)
                    if isEditing { UndoRedoButtons(availability: session.undoAvailability) }
                    #endif
                }
            } else {
                #if canImport(UIKit)
                if let session = document.canvasSession {
                    controls(isWriting: Binding(get: { session.isWriting }, set: { isWriting in session.isWriting = isWriting })) {
                        if session.isWriting { UndoRedoButtons(availability: session.undoAvailability) }
                    }
                }
                if let session = document.pdfSession, !session.isProtected {
                    controls(isWriting: Binding(get: { session.isWriting }, set: { isWriting in session.isWriting = isWriting })) {
                        UndoRedoButtons(availability: session.undoAvailability)
                    }
                }
                #endif
            }
        }
    }

    /// The same order as in the window's toolbar: the document's buttons, then Write.
    private func controls<Buttons: View>(isWriting: Binding<Bool>, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: 12) {
            buttons()
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .tint(.secondary)
            DocumentModeToggle(isWriting: isWriting, drawsOwnBackground: true)
        }
    }
}
