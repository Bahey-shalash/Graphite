#if os(macOS)
import Foundation
import GraphiteCore

/// The shortcuts set for menu items in System Settings › Keyboard › Keyboard Shortcuts › App
/// Shortcuts, for Graphite and for all apps (`NSUserKeyEquivalents`). macOS gives them to the
/// menu items whatever Graphite asks for; the Keyboard Shortcuts page shows them on their rows.
enum SystemSettingsAppShortcuts {
    static let defaultsKey = "NSUserKeyEquivalents"

    /// The shortcuts by menu title; Graphite's own take the place of those for all apps.
    static func read(from defaults: UserDefaults, applicationIdentifier: String?) -> [String: KeyCombination?] {
        let allApplications = defaults.persistentDomain(forName: UserDefaults.globalDomain)?[defaultsKey] as? [String: String] ?? [:]
        let graphite = applicationIdentifier.flatMap { identifier in defaults.persistentDomain(forName: identifier)?[defaultsKey] as? [String: String] } ?? [:]
        return UserKeyEquivalents.combinationsByMenuTitle(allApplications.merging(graphite) { _, graphiteEquivalent in graphiteEquivalent })
    }
}
#endif
