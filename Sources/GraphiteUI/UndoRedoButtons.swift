import SwiftUI

/// Undo and Redo for a document's toolbar. Every workspace puts them just before its
/// Read/Write control (the drawing editor, which has none, just before Insert or Done),
/// and they act on that document's own history.
struct UndoRedoButtons: View {
    let availability: UndoAvailability

    var body: some View {
        Button("Undo", systemImage: "arrow.uturn.backward") { availability.undo() }
            .disabled(!availability.canUndo)
            .help(availability.undoActionName.isEmpty ? "Undo" : "Undo \(availability.undoActionName)")
            .accessibilityIdentifier("documentUndo")
        Button("Redo", systemImage: "arrow.uturn.forward") { availability.redo() }
            .disabled(!availability.canRedo)
            .help(availability.redoActionName.isEmpty ? "Redo" : "Redo \(availability.redoActionName)")
            .accessibilityIdentifier("documentRedo")
    }
}
