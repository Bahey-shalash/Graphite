import SwiftUI
import Observation
import GraphiteCore

/// Which callouts the person has expanded or collapsed, per note, shared by the reading view
/// and Live Preview, so Read Aloud reads what is open and skips what is folded. Kept for the
/// session only; the note's own `-` and `+` markers remain the starting point.
@MainActor @Observable
final class CalloutFoldStore {
    private var expansionByNote: [String: [String: Bool]] = [:]

    func expansion(for notePath: String) -> [String: Bool] { expansionByNote[notePath] ?? [:] }

    func isExpanded(notePath: String, key: String, initially: Bool) -> Bool {
        expansionByNote[notePath]?[key] ?? initially
    }

    func setExpanded(_ isExpanded: Bool, notePath: String, key: String) {
        expansionByNote[notePath, default: [:]][key] = isExpanded
    }
}

/// A callout's place in that store: the note it is in and its key.
struct CalloutFoldScope {
    let store: CalloutFoldStore
    let notePath: String
}

extension EnvironmentValues {
    @Entry var calloutFoldNote: (store: CalloutFoldStore, notePath: String)? = nil
}
