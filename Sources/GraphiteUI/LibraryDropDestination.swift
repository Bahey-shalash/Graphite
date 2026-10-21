import SwiftUI
import GraphiteCore

/// What a drop on the library does with what it receives.
struct LibraryDropActions {
    /// Takes the dropped item providers for a folder: vault items move into it, as the file
    /// tree's moves do (links updated as the vault's settings say, a folder never into itself),
    /// and files from other apps are copied into it, never moved. False when nothing in the
    /// drop can be used, so the system shows the drop as refused.
    let receive: ([NSItemProvider], VaultPath) -> Bool
}

/// Makes a view take drops into `folder`. `isTargeted` is true while a drag is held over the view.
struct LibraryDropDestination: ViewModifier {
    let folder: VaultPath
    let actions: LibraryDropActions
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        content.onDrop(of: LibraryDropReader.acceptedTypes, isTargeted: $isTargeted) { providers in
            actions.receive(providers, folder)
        }
    }
}

/// The ring drawn round the grid while a drag is held over its empty area.
struct LibraryDropRing: ViewModifier {
    let isTargeted: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isTargeted { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2).padding(6).allowsHitTesting(false) }
        }
    }
}
