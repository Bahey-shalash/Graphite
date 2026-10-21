import XCTest
import GraphiteCore
import GraphiteApple
import ShareInbox
@testable import GraphiteUI
#if canImport(GraphiteTestSupport)
import GraphiteTestSupport
#endif

/// The device state of a workspace under test: a preferences suite of its own and temporary
/// Caches and Application Support folders, so what the workspace remembers per vault, the
/// vault list, its indexes and its File recovery copies never reach the preferences or the
/// folders of the machine that runs the tests, and need no snapshot and restore.
///
/// Both are removed when the test ends. A second workspace made with `makeWorkspace()` is a
/// later launch of the app on the same device: it reads what the first one wrote.
@MainActor
struct IsolatedWorkspaceDevice {
    let deviceState: IsolatedDeviceState
    let temporaryFolders: TemporaryVault

    /// The preferences the workspaces made here write to.
    var defaults: UserDefaults { deviceState.preferences }

    var applicationFolders: ApplicationFolders { .temporary(below: temporaryFolders.root) }

    /// A device that is removed after the test, whatever the test does.
    static func make(for testCase: XCTestCase) throws -> IsolatedWorkspaceDevice {
        let device = try IsolatedWorkspaceDevice()
        testCase.addTeardownBlock { device.remove() }
        return device
    }

    /// A device for a test bed that outlives one test: call `remove()` when it is done.
    init() throws {
        deviceState = try IsolatedDeviceState(prefix: "WorkspaceDevice")
        temporaryFolders = try TemporaryVault(prefix: "WorkspaceDeviceFolders")
    }

    func remove() {
        deviceState.remove()
        temporaryFolders.remove()
    }

    /// Services over this device, built anew: a vault list and preferences that read what
    /// is stored now. Read Aloud, when it is on, speaks through a silent fake that makes no
    /// sound (`PenTestSpeech`), keeps its preferences in this device's suite, and stays off
    /// the lock screen.
    /// `shareInbox` is the share extension's inbox the workspace takes shared items from; none by default.
    func makeServices(shareInbox: ShareInbox? = nil, makeReadAloudController: (@MainActor () -> ReadAloudController)? = nil) -> WorkspaceDeviceServices {
        let defaults = defaults
        return WorkspaceDeviceServices(defaults: defaults, applicationFolders: applicationFolders, shareInbox: shareInbox,
                                       makeReadAloudController: makeReadAloudController ?? {
                                           ReadAloudController(session: ReadAloudSession(speech: PenTestSpeech(), preferences: defaults),
                                                               preferences: defaults)
                                       })
    }

    /// A workspace on this device whose delays run on `clock`.
    func makeWorkspace(clock: any ApplicationClock = LiveApplicationClock(), shareInbox: ShareInbox? = nil,
                       makeReadAloudController: (@MainActor () -> ReadAloudController)? = nil) -> WorkspaceModel {
        WorkspaceModel(deviceServices: makeServices(shareInbox: shareInbox, makeReadAloudController: makeReadAloudController), clock: clock)
    }
}
