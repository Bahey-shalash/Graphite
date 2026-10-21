import Foundation

/// One community plugin runtime per open vault, shared by the vault's windows and acting on
/// the window in front, so a plugin never runs twice on the same files (owner, 2026-10-21).
/// The first window on a vault loads its plugins; the last to leave unloads them.
@MainActor
final class CommunityPluginHosts {
    private final class SharedHost {
        let host: CommunityPluginHost
        /// What makes each window on the vault the host's window, by window.
        var adoptions: [ObjectIdentifier: () -> Void] = [:]
        /// The windows, the one most recently in front last.
        var frontOrder: [ObjectIdentifier] = []

        init(host: CommunityPluginHost) {
            self.host = host
        }
    }

    private let defaults: UserDefaults
    private var hostsByVault: [UUID: SharedHost] = [:]

    /// Hosts that keep plugin consent in `defaults`.
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The vault's host for `window`, which `adopt` makes the host's window; the first window
    /// on the vault is told so, to load its plugins.
    func join(vault vaultIdentifier: UUID, window: ObjectIdentifier, adopt: @escaping () -> Void) -> (host: CommunityPluginHost, isFirstWindow: Bool) {
        let shared = hostsByVault[vaultIdentifier] ?? SharedHost(host: CommunityPluginHost(defaults: defaults))
        let isFirstWindow = shared.adoptions.isEmpty
        hostsByVault[vaultIdentifier] = shared
        shared.adoptions[window] = adopt
        shared.frontOrder.removeAll { frontWindow in frontWindow == window }
        shared.frontOrder.append(window)
        return (shared.host, isFirstWindow)
    }

    /// `window` came to the front: the vault's plugins act on it.
    func windowCameToFront(vault vaultIdentifier: UUID, window: ObjectIdentifier) {
        guard let shared = hostsByVault[vaultIdentifier], let adopt = shared.adoptions[window] else { return }
        shared.frontOrder.removeAll { frontWindow in frontWindow == window }
        shared.frontOrder.append(window)
        adopt()
    }

    /// `window` left the vault: the plugins act on the window on it in front most recently,
    /// or, for the last window, unload, as when Obsidian closes a vault.
    func leave(vault vaultIdentifier: UUID, window: ObjectIdentifier) async {
        guard let shared = hostsByVault[vaultIdentifier], shared.adoptions.removeValue(forKey: window) != nil else { return }
        shared.frontOrder.removeAll { frontWindow in frontWindow == window }
        if let frontWindow = shared.frontOrder.last {
            shared.adoptions[frontWindow]?()
            return
        }
        hostsByVault[vaultIdentifier] = nil
        await shared.host.vaultWillClose()
    }
}
