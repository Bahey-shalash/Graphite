import SwiftUI
import GraphiteCore

/// Which tiles of the library's folder are chosen while the person selects several, and the
/// rules for choosing: a tap toggles one tile, a click on the Mac replaces the choice, a
/// ⌘-click toggles and a ⇧-click extends from the last tile chosen, as the Finder does.
/// Pure values, so every rule is tested without a window.
struct LibrarySelection: Equatable {
    /// How a click or tap changes the choice.
    enum Gesture: Equatable {
        /// The tile alone is chosen (a click on the Mac).
        case replace
        /// The tile is added when it was not chosen and removed when it was (a tap, a ⌘-click).
        case toggle
        /// Every tile from the last one chosen to this one is added (a ⇧-click).
        case extendRange

        /// The gesture the modifier keys held at a click or tap ask for; nil when neither ⌘ nor ⇧ is held.
        init?(heldKeys: EventModifiers) {
            if heldKeys.contains(.command) {
                self = .toggle
            } else if heldKeys.contains(.shift) {
                self = .extendRange
            } else {
                return nil
            }
        }
    }

    /// Whether tiles are chosen instead of opened.
    private(set) var isSelecting = false
    private(set) var chosenPaths: Set<VaultPath> = []
    /// The tile the next range starts from: the last one chosen or toggled on.
    private(set) var anchorPath: VaultPath?

    var chosenCount: Int { chosenPaths.count }

    /// Starts choosing; a tile may be chosen at once, as a ⌘-click on a tile outside selection does.
    mutating func begin(choosing path: VaultPath? = nil) {
        isSelecting = true
        if let path {
            chosenPaths = [path]
            anchorPath = path
        }
    }

    /// Stops choosing and forgets the choice.
    mutating func end() {
        self = LibrarySelection()
    }

    /// Applies a click or tap on `path`. `orderedPaths` are the tiles in the order shown, which a range follows.
    mutating func apply(_ gesture: Gesture, to path: VaultPath, among orderedPaths: [VaultPath]) {
        switch gesture {
        case .replace:
            chosenPaths = [path]
            anchorPath = path
        case .toggle:
            if chosenPaths.remove(path) == nil {
                chosenPaths.insert(path)
                anchorPath = path
            }
        case .extendRange:
            guard let anchorPath, let anchorPosition = orderedPaths.firstIndex(of: anchorPath),
                  let position = orderedPaths.firstIndex(of: path) else {
                apply(.replace, to: path, among: orderedPaths)
                return
            }
            chosenPaths.formUnion(orderedPaths[min(anchorPosition, position)...max(anchorPosition, position)])
        }
    }

    mutating func selectAll(of orderedPaths: [VaultPath]) {
        chosenPaths = Set(orderedPaths)
        anchorPath = orderedPaths.last
    }

    mutating func deselectAll() {
        chosenPaths = []
        anchorPath = nil
    }

    /// Drops the tiles that are no longer listed, after a move, a deletion or another app's change.
    mutating func keepListed(_ orderedPaths: [VaultPath]) {
        let listedPaths = Set(orderedPaths)
        chosenPaths.formIntersection(listedPaths)
        if let anchorPath, !listedPaths.contains(anchorPath) { self.anchorPath = nil }
    }

    func isChosen(_ path: VaultPath) -> Bool { chosenPaths.contains(path) }

    /// The chosen tiles in the order they are shown.
    func chosenPaths(in orderedPaths: [VaultPath]) -> [VaultPath] {
        orderedPaths.filter(chosenPaths.contains)
    }

    /// Whether every listed tile is chosen: the Select All button then offers to clear the choice.
    /// The choice only holds listed tiles (`keepListed`), so counting is enough.
    func hasChosenAll(listedCount: Int) -> Bool {
        listedCount > 0 && chosenPaths.count == listedCount
    }
}
