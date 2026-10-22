import XCTest
@testable import GraphiteUI
import GraphiteTestSupport

/// Which core plugins are on: each plugin's default, what Settings changes in the two
/// recorded lists (`GraphiteDisabledCorePlugins` and `GraphiteEnabledCorePlugins`, `ST-04`),
/// and that a fresh device starts with Read Aloud off and every other plugin on.
@MainActor
final class CorePluginSwitchesTests: XCTestCase {
    private var device: IsolatedWorkspaceDevice!

    override func setUp() async throws {
        device = try IsolatedWorkspaceDevice.make(for: self)
    }

    override func tearDown() async throws {
        device = nil
    }

    func testAFreshDeviceHasReadAloudAndThePostgreSQLMirrorOffAndEveryOtherPluginOn() {
        let preferences = device.makeServices().preferences

        XCTAssertFalse(preferences.isEnabled(.readAloud))
        XCTAssertFalse(preferences.isEnabled(.postgreSQLMirror))
        for plugin in CorePlugin.allCases where plugin != .readAloud && plugin != .postgreSQLMirror {
            XCTAssertTrue(preferences.isEnabled(plugin), "\(plugin.rawValue) is on until it is turned off.")
        }
    }

    func testBuildingTheServicesOfAFreshDeviceRecordsThatTheMigrationRan() {
        XCTAssertNil(device.defaults.object(forKey: "GraphiteEnabledCorePlugins"))

        _ = device.makeServices()

        XCTAssertEqual(device.defaults.stringArray(forKey: "GraphiteEnabledCorePlugins"), [])
        XCTAssertNil(device.defaults.object(forKey: "GraphiteDisabledCorePlugins"), "The migration records nothing as turned off.")
    }

    func testOnlyReadAloudAndThePostgreSQLMirrorAreOffByDefault() {
        let offByDefault = CorePlugin.allCases.filter { plugin in !plugin.isEnabledByDefault }

        XCTAssertEqual(offByDefault, [.readAloud, .postgreSQLMirror], "The mirror sends notes to a server only once the person turns it on.")
    }

    func testTurningReadAloudOnStoresItInTheEnabledListAndAnotherLaunchReadsItBack() {
        let preferences = device.makeServices().preferences

        preferences.setEnabled(.readAloud, true)

        XCTAssertEqual(device.defaults.stringArray(forKey: "GraphiteEnabledCorePlugins"), ["readAloud"])
        XCTAssertEqual(device.defaults.stringArray(forKey: "GraphiteDisabledCorePlugins"), [], "Read Aloud is never recorded as turned off.")
        XCTAssertTrue(preferences.isEnabled(.readAloud))
        XCTAssertTrue(GraphitePreferences(defaults: device.defaults).isEnabled(.readAloud))
    }

    func testTurningReadAloudOffAgainRemovesItFromTheEnabledList() {
        let preferences = device.makeServices().preferences
        preferences.setEnabled(.readAloud, true)

        preferences.setEnabled(.readAloud, false)

        XCTAssertEqual(device.defaults.stringArray(forKey: "GraphiteEnabledCorePlugins"), [])
        XCTAssertEqual(device.defaults.stringArray(forKey: "GraphiteDisabledCorePlugins"), [], "Off is its default, so nothing is recorded as turned off.")
        XCTAssertFalse(GraphitePreferences(defaults: device.defaults).isEnabled(.readAloud))
    }

    func testAPluginThatIsOnByDefaultTurnedOffIsStoredInTheDisabledListOnly() {
        let preferences = device.makeServices().preferences

        preferences.setEnabled(.graph, false)

        XCTAssertEqual(device.defaults.stringArray(forKey: "GraphiteDisabledCorePlugins"), ["graph"])
        XCTAssertEqual(device.defaults.stringArray(forKey: "GraphiteEnabledCorePlugins"), [])
        XCTAssertFalse(GraphitePreferences(defaults: device.defaults).isEnabled(.graph))
    }

    func testAnUnknownPluginInTheEnabledListIsIgnored() {
        device.defaults.set(["aPluginThatWasRemoved", "readAloud"], forKey: "GraphiteEnabledCorePlugins")

        let switches = CorePluginSwitches(storedIn: device.defaults)

        XCTAssertEqual(switches.turnedOn, [.readAloud])
        XCTAssertEqual(switches.turnedOff, [])
    }

    func testAnEnabledListWithOnlyAnUnknownPluginLeavesReadAloudOff() {
        device.defaults.set(["aPluginThatWasRemoved"], forKey: "GraphiteEnabledCorePlugins")

        XCTAssertFalse(GraphitePreferences(defaults: device.defaults).isEnabled(.readAloud))
    }

    func testAPluginOnByDefaultListedAsEnabledStaysOnAndTurningItOffRemovesItFromThatList() {
        var switches = CorePluginSwitches(turnedOff: [], turnedOn: [.graph])
        XCTAssertTrue(switches.isEnabled(.graph))

        switches.setEnabled(.graph, false)

        XCTAssertEqual(switches.turnedOn, [])
        XCTAssertEqual(switches.turnedOff, [.graph])
    }
}
