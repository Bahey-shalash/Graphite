import SwiftUI

/// The same reading/writing choice for notes and PDF notebooks.
struct DocumentModePicker: View {
    @Binding var isWriting: Bool
    @ScaledMetric(relativeTo: .body) private var controlWidth = 160.0

    var body: some View {
        Picker("Document Mode", selection: $isWriting) {
            Text("Read").tag(false)
            Text("Write").tag(true)
        }
        .pickerStyle(.segmented)
        .frame(width: controlWidth)
        .accessibilityIdentifier("documentModePicker")
    }
}

/// The row below the navigation bar where the Read/Write control, Undo, and Redo go when
/// the window's toolbar has no room for them (`DocumentToolbarLayout`), rather than into
/// its overflow menu, with the same spacing in every workspace.
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
    /// Read/Write control is not offered at all, so they move to the row below instead.
    static let minimumDetailWidthForToolbarControls: CGFloat = 1_100

    /// - Parameter detailWidth: The width of the documents area, nil when unknown.
    static func usesControlRow(detailWidth: CGFloat?, horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        if horizontalSizeClass == .compact { return true }
        guard let detailWidth else { return false }
        return detailWidth < minimumDetailWidthForToolbarControls
    }
}

extension EnvironmentValues {
    /// Whether documents show Read/Write, Undo, and Redo in the row below the navigation bar
    /// (`DocumentControlRow`); nil where no workspace measured its width, which then
    /// uses the row only in compact widths.
    @Entry var usesDocumentControlRow: Bool? = nil
}
