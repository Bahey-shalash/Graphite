#if os(iOS)
import XCTest
import UIKit
import GraphiteCore
@testable import GraphiteUI

/// The iPad runs several Graphite windows and the iPhone one (owner, 2026-10-21): the scene
/// manifest says so, and a window asked for with a dragged file's activity connects a scene
/// of its own beside the app's window.
@MainActor
final class MultipleWindowsHostedTests: XCTestCase {
    func testTheIPadRunsSeveralWindowsAndTheIPhoneOne() {
        XCTAssertEqual(UIApplication.shared.supportsMultipleScenes, UIDevice.current.userInterfaceIdiom == .pad)
    }

    func testADraggedFilesActivityOpensAWindowOfItsOwn() async throws {
        // The iPhone runs one window, which the test above checks.
        guard UIApplication.shared.supportsMultipleScenes else { return }
        let scenesBefore = Set(UIApplication.shared.connectedScenes.map(ObjectIdentifier.init))
        let appScene = try XCTUnwrap(UIApplication.shared.connectedScenes.first { scene in scene.activationState == .foregroundActive } as? UIWindowScene)
        let content = GraphiteWindowContent.showing(try VaultPath("Note.md"), inVault: UUID())
        var activationError: (any Error)?

        UIApplication.shared.activateSceneSession(for: UISceneSessionActivationRequest(userActivity: content.userActivity)) { error in
            activationError = error
        }
        try await waitUntil("a second window connects") { UIApplication.shared.connectedScenes.count == scenesBefore.count + 1 }

        XCTAssertNil(activationError)
        let newScene = try XCTUnwrap(UIApplication.shared.connectedScenes.first { scene in !scenesBefore.contains(ObjectIdentifier(scene)) } as? UIWindowScene)
        try await waitUntil("the new window shows a Graphite window") { newScene.windows.contains { window in window.rootViewController != nil } }
        UIApplication.shared.requestSceneSessionDestruction(newScene.session, options: nil)
        try await waitUntil("the new window closes again") { UIApplication.shared.connectedScenes.count == scenesBefore.count }
        // The app's own window comes to the front again: the tests that follow draw in it.
        UIApplication.shared.activateSceneSession(for: UISceneSessionActivationRequest(session: appScene.session)) { error in activationError = error }
        try await waitUntil("the app's window is in front again") { appScene.activationState == .foregroundActive }
        XCTAssertNil(activationError)
    }
}
#endif
