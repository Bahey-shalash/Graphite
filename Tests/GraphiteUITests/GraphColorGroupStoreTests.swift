import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// Each vault's graph groups, kept on the device under the vault's identifier and shared by
/// every window, never written into the vault.
@MainActor
final class GraphColorGroupStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let courses = UUID(uuidString: "00000000-0000-0000-0000-00000000000a") ?? UUID()
    private let research = UUID(uuidString: "00000000-0000-0000-0000-00000000000b") ?? UUID()

    override func setUp() async throws {
        defaults = try IsolatedDeviceState.make(prefix: "GraphColorGroupStoreTests", for: self).preferences
    }

    override func tearDown() async throws {
        defaults = nil
    }

    private func makeStore() -> GraphColorGroupStore {
        var identifierNumber = 0
        return GraphColorGroupStore(defaults: defaults) {
            identifierNumber += 1
            return UUID(uuidString: String(format: "00000000-0000-0000-0001-%012d", identifierNumber)) ?? UUID()
        }
    }

    func testAVaultsGroupsAreKeptOnTheDeviceUnderItsIdentifierAndNoOtherVaultSeesThem() {
        let store = makeStore()
        store.loadGroups(ofVault: courses)
        store.addGroup(toVault: courses)
        var group = store.groups(ofVault: courses)[0]
        group.query = "tag:#vlsi"
        store.update(group, inVault: courses)

        XCTAssertNotNil(defaults.data(forKey: "graphColorGroups." + courses.uuidString))
        let otherLaunch = makeStore()
        otherLaunch.loadGroups(ofVault: courses)
        otherLaunch.loadGroups(ofVault: research)
        XCTAssertEqual(otherLaunch.groups(ofVault: courses).map(\.query), ["tag:#vlsi"])
        XCTAssertEqual(otherLaunch.groups(ofVault: research), [])
    }

    func testNewGroupsTakeGraphitesPaletteColorsInTurnAndHaveNoSearch() {
        let store = makeStore()
        store.loadGroups(ofVault: courses)
        for _ in 0..<3 { store.addGroup(toVault: courses) }
        let groups = store.groups(ofVault: courses)
        XCTAssertEqual(groups.map(\.colorHex), PaletteColor.defaultPalette.prefix(3).map(\.hex))
        XCTAssertEqual(groups.map(\.query), ["", "", ""])
        XCTAssertEqual(Set(groups.map(\.id)).count, 3, "Each group has an identifier of its own.")
    }

    func testARemovedGroupIsGoneFromTheDevice() {
        let store = makeStore()
        store.loadGroups(ofVault: courses)
        store.addGroup(toVault: courses)
        store.addGroup(toVault: courses)
        let first = store.groups(ofVault: courses)[0]
        store.removeGroup(identifiedBy: first.id, fromVault: courses)

        let otherLaunch = makeStore()
        otherLaunch.loadGroups(ofVault: courses)
        XCTAssertEqual(otherLaunch.groups(ofVault: courses).count, 1)
        XCTAssertNotEqual(otherLaunch.groups(ofVault: courses).first?.id, first.id)
    }

    func testAStoredValueThatIsNotAListOfGroupsIsKeptAsideRatherThanWrittenOver() {
        let unreadable = Data("{\"written by\":\"a newer build\"}".utf8)
        defaults.set(unreadable, forKey: "graphColorGroups." + courses.uuidString)
        let store = makeStore()
        store.loadGroups(ofVault: courses)

        XCTAssertEqual(store.groups(ofVault: courses), [])
        XCTAssertEqual(defaults.data(forKey: "graphColorGroups." + courses.uuidString + ".unreadable"), unreadable)
        store.addGroup(toVault: courses)
        XCTAssertEqual(defaults.data(forKey: "graphColorGroups." + courses.uuidString + ".unreadable"), unreadable,
                       "A new group does not write over what was kept aside.")
    }

    func testForgettingAVaultTakesItsGroupsOffTheDevice() {
        defaults.set(Data("{}".utf8), forKey: "graphColorGroups." + courses.uuidString)
        let store = makeStore()
        store.loadGroups(ofVault: courses)
        store.addGroup(toVault: courses)
        store.forgetVault(courses)

        XCTAssertNil(defaults.object(forKey: "graphColorGroups." + courses.uuidString))
        XCTAssertNil(defaults.object(forKey: "graphColorGroups." + courses.uuidString + ".unreadable"))
        XCTAssertEqual(store.groups(ofVault: courses), [])
    }

    func testTheGroupsColorTheFilesTheirSearchesMatchWhileTagsAreHidden() throws {
        let lab = try VaultPath("Courses/VLSI/Lab.md"), idea = try VaultPath("Inbox/Idea.md")
        let vaultGraph = LinkGraph.build(files: [lab, idea], links: [], unresolvedLinks: [], tags: [(lab, "vlsi")])
        let groups = [GraphColorGroup(identifier: courses, query: "tag:#vlsi", colorHex: "#e93147"),
                      GraphColorGroup(identifier: research, query: "inbox", colorHex: "not a color")]
        let coloring = GraphGroupColoring(groups: groups, vaultGraph: vaultGraph)

        XCTAssertEqual(coloring.groupIndexByIdentifier, ["Courses/VLSI/Lab.md": 0, "Inbox/Idea.md": 1],
                       "Read on the whole vault's graph, so the tag counts while the filters hide tags.")
        XCTAssertNotNil(coloring.color(ofGroup: 0))
        XCTAssertNil(coloring.color(ofGroup: 1), "A color Graphite cannot read leaves the file its kind's color.")
        XCTAssertNil(coloring.color(ofGroup: 2))
    }
}
