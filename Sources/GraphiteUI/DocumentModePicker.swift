import SwiftUI
import GraphiteCore

/// The same reading/writing choice for notes and PDF notebooks.
struct DocumentModePicker: View {
    @Binding var isWriting: Bool
    /// Narrower, for the tab bar, which the control shares with the tabs.
    var isCompact = false
    @ScaledMetric(relativeTo: .body) private var controlWidth = 160.0
    @ScaledMetric(relativeTo: .body) private var compactControlWidth = 132.0

    var body: some View {
        Picker("Document Mode", selection: $isWriting) {
            Text("Read").tag(false)
            Text("Write").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: isCompact ? compactControlWidth : controlWidth)
        .accessibilityIdentifier("documentModePicker")
    }
}

/// A row of their own for the Read/Write control, Undo, and Redo, when neither the window's
/// toolbar nor the tab bar has room for them (`DocumentToolbarLayout`), with the same
/// spacing in every workspace.
struct DocumentControlRow<TrailingControls: View>: View {
    @Binding var isWriting: Bool
    @ViewBuilder var trailingControls: TrailingControls

    var body: some View {
        HStack(spacing: 20) {
            DocumentModePicker(isWriting: $isWriting)
            Spacer(minLength: 8)
            // Neutral, as in the toolbar; the accent marks selection and links.
            trailingControls
                .labelStyle(.iconOnly)
                .tint(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Where a document puts its Read/Write control, Undo, and Redo.
enum DocumentToolbarLayout {
    /// The window's toolbar holds the navigation buttons, the title, recording, the
    /// document's own tools, Undo, Redo, Read/Write and More: about 1,050 points on iPad.
    /// Narrower, iPadOS moves the last buttons into an overflow menu, where a segmented
    /// Read/Write control is not offered at all, so they move below the toolbar instead:
    /// to the end of the tab bar, or to a row of their own where that has no room either.
    static let minimumDetailWidthForToolbarControls: CGFloat = 1_100

    /// The narrowest tab bar that holds the controls and still shows two tabs. Its own
    /// buttons and the controls take about 330 points.
    static let minimumTabBarWidthForControls: CGFloat = 480

    /// - Parameter detailWidth: The width of the documents area, nil when unknown.
    static func usesControlRow(detailWidth: CGFloat?, horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        if horizontalSizeClass == .compact { return true }
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
    /// Read/Write, Undo, Redo and Show Tools, when the tab bar holds them.
    static let documentControlsWidth: CGFloat = 240

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
    /// Whether documents show Read/Write, Undo, and Redo in the row below the navigation bar
    /// (`DocumentControlRow`); nil where no workspace measured its width, which then
    /// uses the row only in compact widths.
    @Entry var usesDocumentControlRow: Bool? = nil
    /// True where the side's tab bar shows those controls (`TabBarDocumentControls`), so
    /// the document shows no row for them.
    @Entry var showsDocumentControlsInTabBar = false
    /// True where the side's tab bar has room for the fixed bar's tools
    /// (`TabBarPencilTools`), so a PDF written on shows no row for them.
    @Entry var showsPencilToolsInTabBar = false
}

/// Read/Write, Undo and Redo of a side's active document, at the end of its tab bar.
struct TabBarDocumentControls: View {
    let tab: WorkspaceTab
    let document: TabDocument
    let defaultEditingMode: EditingMode
    #if canImport(UIKit)
    @AppStorage(PDFAnnotationPreferenceKey.showsToolPicker) private var showsToolPicker = true
    #endif

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
                        if session.isWriting {
                            Button(showsToolPicker ? "Hide Tools" : "Show Tools", systemImage: showsToolPicker ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle") {
                                showsToolPicker.toggle()
                            }
                            .help("Show or hide the Pencil tools. Choose Read to stop drawing.")
                        }
                        UndoRedoButtons(availability: session.undoAvailability)
                    }
                }
                #endif
            }
        }
    }

    /// The same order as in the window's toolbar: the document's buttons, then Read/Write.
    private func controls<Buttons: View>(isWriting: Binding<Bool>, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: 14) {
            buttons()
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .tint(.primary)
            DocumentModePicker(isWriting: isWriting, isCompact: true)
        }
    }
}
