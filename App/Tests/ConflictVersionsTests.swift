#if os(iOS)
import XCTest
import SwiftUI
import GraphiteApple
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI

/// Versions kept by a file provider, in the running app on iPadOS, with versions from
/// `TestConflictVersionStore`: the banner over the open note, the mark in the sidebar,
/// the Versions sheet and a version's comparison, and the note reloading after a choice.
@MainActor
final class ConflictVersionsTests: XCTestCase {
    private var windows: [UIWindow] = []
    private var temporaryFolders: [URL] = []

    override func tearDown() async throws {
        for window in windows { window.isHidden = true; window.rootViewController = nil }
        windows = []
        for folder in temporaryFolders { try? FileManager.default.removeItem(at: folder) }
        temporaryFolders = []
    }

    func testTheOpenNoteShowsItsOtherVersionAndReloadsWhenOneIsChosen() async throws {
        let (workspace, store, vault) = try await makeWorkspace(files: ["Lecture.md": "# Lecture\n\nThe current paragraph.\n"])
        let path = try VaultPath("Lecture.md")
        let location = vault.appendingPathComponent("Lecture.md")
        await workspace.open(path)
        let session = try XCTUnwrap(workspace.markdownSession)
        session.viewMode = .source
        let controller = try host(AnyView(NavigationStack {
            WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }))
        let editor = try await visibleEditor(in: controller, showing: session)
        let editorTopWithoutBanner = editor.convert(editor.bounds, to: nil).minY

        let version = try store.addVersion(of: location, contents: Data("# Lecture\n\nThe paragraph as written on the Mac.\n".utf8),
                                           deviceName: "MacBook Pro", modified: .now)
        workspace.checkConflictVersions(of: [path])
        try await waitUntil { workspace.conflictedPaths.contains(path) }
        // The banner takes its place above the note, which moves down to make room.
        try await waitUntil { editor.convert(editor.bounds, to: nil).minY > editorTopWithoutBanner + 20 }
        attachScreenshot(named: "Banner over a note with another version")

        let listing = try await workspace.conflictVersionListing(of: path)
        try await workspace.replaceCurrentVersion(of: path, with: version, listedIn: listing)

        XCTAssertEqual(session.text, "# Lecture\n\nThe paragraph as written on the Mac.\n")
        try await waitUntil { editor.text == "# Lecture\n\nThe paragraph as written on the Mac.\n" }
        XCTAssertFalse(workspace.conflictedPaths.contains(path))
        try await waitUntil { abs(editor.convert(editor.bounds, to: nil).minY - editorTopWithoutBanner) < 1 }
        attachScreenshot(named: "The note after the version replaced it")
    }

    func testTheSidebarMarksAFileWithAnotherVersion() async throws {
        let (workspace, store, vault) = try await makeWorkspace(files: ["Lecture.md": "# Lecture\n", "Slides.pdf": "not a real PDF", "Summary.md": "# Summary\n"])
        try store.addVersion(of: vault.appendingPathComponent("Lecture.md"), contents: Data("# Lecture from the iPhone\n".utf8), deviceName: "iPhone", modified: .now)
        await workspace.refreshDirectory()
        try await waitUntil { workspace.conflictedPaths == [try VaultPath("Lecture.md")] }

        _ = try host(AnyView(NavigationStack {
            VaultSidebar(workspace: workspace, creation: .constant(nil), showsSettings: .constant(false), showsVaultManager: .constant(false))
        }))
        try await Task.sleep(for: .milliseconds(500))
        attachScreenshot(named: "Sidebar with a marked file")
    }

    func testTheVersionsSheetAndAComparison() async throws {
        let (workspace, store, vault) = try await makeWorkspace(files: ["Lecture.md": "# Lecture\n\nIntroduction.\nThe current paragraph.\nConclusion.\n"])
        let path = try VaultPath("Lecture.md")
        let location = vault.appendingPathComponent("Lecture.md")
        let version = try store.addVersion(of: location, contents: Data("# Lecture\n\nIntroduction.\nThe paragraph as written on the Mac.\nA sentence added there.\nConclusion.\n".utf8),
                                           deviceName: "MacBook Pro", modified: Date.now.addingTimeInterval(-600), savedBy: nil)
        try store.addVersion(of: location, contents: Data("# Lecture\n".utf8), deviceName: "iPhone", modified: Date.now.addingTimeInterval(-3_600))

        _ = try host(AnyView(ConflictVersionsSheet(workspace: workspace, request: ConflictVersionsRequest(path: path))))
        try await Task.sleep(for: .milliseconds(800))
        attachScreenshot(named: "Versions sheet")

        let model = ConflictVersionsModel(path: path, workspace: workspace)
        await model.load()
        _ = try host(AnyView(NavigationStack { ConflictVersionPreview(workspace: workspace, model: model, version: version) {} }))
        try await Task.sleep(for: .milliseconds(800))
        attachScreenshot(named: "A version compared with the current note")
    }

    // MARK: Helpers

    private func makeFolder(_ prefix: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        temporaryFolders.append(folder)
        return folder
    }

    private func makeWorkspace(files: [String: String]) async throws -> (WorkspaceModel, TestConflictVersionStore, URL) {
        let vault = try makeFolder("ConflictVersionsVault")
        for (relativePath, contents) in files {
            let location = vault.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: location)
        }
        let workspace = WorkspaceModel()
        workspace.folderAccess = FolderAccess(root: vault)
        workspace.store = VaultStore(root: vault)
        workspace.index = try VaultIndex(databaseURL: try makeFolder("ConflictVersionsIndex").appendingPathComponent("index.sqlite"))
        let store = try TestConflictVersionStore()
        workspace.conflictVersionStore = store
        return (workspace, store, vault)
    }

    private func host(_ view: AnyView) throws -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: view)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        windows.append(window)
        return controller
    }

    private func visibleEditor(in controller: UIViewController, showing session: MarkdownSession) async throws -> MarkdownTextView {
        try await waitUntil { self.editors(in: controller).contains { editor in editor.text == session.text && editor.bounds.width > 0 } }
        return try XCTUnwrap(editors(in: controller).first { editor in editor.text == session.text })
    }

    private func editors(in controller: UIViewController) -> [MarkdownTextView] {
        descendants(of: controller.view, matching: MarkdownTextView.self).filter { editor in editor.window != nil }
    }

    private func descendants<View: UIView>(of parent: UIView, matching type: View.Type) -> [View] {
        parent.subviews.flatMap { child in ((child as? View).map { [$0] } ?? []) + descendants(of: child, matching: type) }
    }

    private func attachScreenshot(named name: String) {
        guard let window = windows.last else { return }
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntil(timeoutSeconds: Double = 10, _ condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while try !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertTrue(try condition(), "The hosted workspace did not reach the expected state.")
    }
}
#endif
