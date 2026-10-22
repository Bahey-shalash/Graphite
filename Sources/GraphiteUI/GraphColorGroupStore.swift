import Foundation
import Observation
import OSLog
import GraphiteCore

private let graphColorGroupLog = Logger(subsystem: "com.graphite.study", category: "GraphColorGroups")

/// The graph's color groups of each vault, kept on the device with the graph's other
/// settings, as Obsidian keeps them in its workspace; never written into the vault. A
/// vault's groups are read from the device's preferences when a graph first loads them,
/// then kept in memory and written back when they change. Every window shares one store
/// (`ProcessServices.graphColorGroups`), so a group added in one window colors the graph of
/// every window on that vault.
@MainActor @Observable
final class GraphColorGroupStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let makeIdentifier: () -> UUID
    private var listsByVault: [UUID: GraphColorGroupList] = [:]

    init(defaults: UserDefaults, makeIdentifier: @escaping () -> UUID) {
        self.defaults = defaults
        self.makeIdentifier = makeIdentifier
    }

    /// A vault's groups in the order they win in; none until `loadGroups(ofVault:)`.
    func groups(ofVault vaultIdentifier: UUID) -> [GraphColorGroup] {
        listsByVault[vaultIdentifier]?.groups ?? []
    }

    /// Reads a vault's groups from the device, once. A stored value that is not a list of
    /// groups is moved aside under `GraphSettingKey.unreadableColorGroups(ofVault:)` rather
    /// than written over, and the vault starts without groups.
    func loadGroups(ofVault vaultIdentifier: UUID) {
        guard listsByVault[vaultIdentifier] == nil else { return }
        let key = GraphSettingKey.colorGroups(ofVault: vaultIdentifier)
        guard let storedList = defaults.data(forKey: key) else {
            listsByVault[vaultIdentifier] = GraphColorGroupList()
            return
        }
        guard let list = GraphColorGroupList(decoding: storedList, makeIdentifier: makeIdentifier) else {
            graphColorGroupLog.error("The graph groups kept for a vault are not a list; they are kept aside.")
            defaults.set(storedList, forKey: GraphSettingKey.unreadableColorGroups(ofVault: vaultIdentifier))
            defaults.removeObject(forKey: key)
            listsByVault[vaultIdentifier] = GraphColorGroupList()
            return
        }
        listsByVault[vaultIdentifier] = list
    }

    /// Adds a group without a search, in the next color of Graphite's palette, last, where
    /// it wins over no other group.
    func addGroup(toVault vaultIdentifier: UUID) {
        let palette = PaletteColor.defaultPalette
        let colorHex = palette[groups(ofVault: vaultIdentifier).count % palette.count].hex
        change(vaultIdentifier) { list in list.append(GraphColorGroup(identifier: makeIdentifier(), query: "", colorHex: colorHex)) }
    }

    /// Replaces the group with the same identifier, as after its search or color changed.
    func update(_ group: GraphColorGroup, inVault vaultIdentifier: UUID) {
        change(vaultIdentifier) { list in list.replace(group) }
    }

    func removeGroup(identifiedBy groupIdentifier: String, fromVault vaultIdentifier: UUID) {
        change(vaultIdentifier) { list in list.removeGroup(identifiedBy: groupIdentifier) }
    }

    /// Forgets a vault's groups, in memory and on the device, as when the vault is removed.
    func forgetVault(_ vaultIdentifier: UUID) {
        listsByVault[vaultIdentifier] = nil
        defaults.removeObject(forKey: GraphSettingKey.colorGroups(ofVault: vaultIdentifier))
        defaults.removeObject(forKey: GraphSettingKey.unreadableColorGroups(ofVault: vaultIdentifier))
    }

    private func change(_ vaultIdentifier: UUID, _ edit: (inout GraphColorGroupList) -> Void) {
        loadGroups(ofVault: vaultIdentifier)
        guard var list = listsByVault[vaultIdentifier] else { return }
        edit(&list)
        guard list != listsByVault[vaultIdentifier] else { return }
        listsByVault[vaultIdentifier] = list
        do {
            defaults.set(try list.encoded(), forKey: GraphSettingKey.colorGroups(ofVault: vaultIdentifier))
        } catch {
            // The change stays in memory for this launch; the device keeps the groups written before it.
            graphColorGroupLog.error("The graph groups could not be written: \(String(describing: error), privacy: .public)")
        }
    }
}
