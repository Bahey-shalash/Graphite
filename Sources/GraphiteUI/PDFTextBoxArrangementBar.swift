#if canImport(UIKit)
import SwiftUI
import GraphiteCore
import GraphiteApple

/// Shown while a text box is selected or typed in, where the Pencil palette otherwise is: the
/// box's format, typing in it, duplicating and deleting it, and Done.
struct PDFTextBoxArrangementBar: View {
    let session: PDFSession
    @State private var showsFormat = false

    var body: some View {
        HStack(spacing: 16) {
            Text(session.textBoxActivity.isEditing ? "Type, or write with Apple Pencil."
                 : "Drag the box to move it, a corner to change its width, or the arrow handle to rotate it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Group {
                Button("Format", systemImage: "textformat") { showsFormat = true }
                    .popover(isPresented: $showsFormat) { formatPopover }
                if !session.textBoxActivity.isEditing {
                    Button("Edit Text", systemImage: "character.cursor.ibeam") { beginEditing() }
                    Button("Duplicate Text Box", systemImage: "plus.square.on.square") { run { try session.duplicateSelectedTextBox() } }
                    Button("Delete Text Box", systemImage: "trash", role: .destructive) { run { try session.deleteSelectedTextBox() } }
                }
            }
            .labelStyle(.iconOnly)
            .tint(.primary)
            Button("Done") { session.textBoxActivity = .idle }
                .fontWeight(.semibold)
                .tint(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private var formatPopover: some View {
        let format = session.textBoxFormat ?? PDFTextBoxDefaults.original
        PDFTextFormatControls(attributes: format.attributes, style: format.boxStyle) { change in
            session.applyTextBoxFormat?(change)
        }
        .presentationCompactAdaptation(.popover)
    }

    private func beginEditing() {
        guard case .selected(let selection) = session.textBoxActivity else { return }
        session.textBoxActivity = .editing(selection)
    }

    private func run(_ change: () throws -> Void) {
        do { try change() } catch { session.reportFailedChange(error) }
    }
}
#endif
