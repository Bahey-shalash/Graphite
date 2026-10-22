#if os(macOS)
import XCTest
import SwiftUI
import AppKit
import GraphiteCore
import GraphiteApple
@testable import GraphiteUI
import GraphiteTestSupport

/// The tab overview, as Safari's: every open tab as a card with a thumbnail of the tab as it
/// was last seen or the preview its file has in the library, searched by name and folder, and
/// a card chosen to show its tab.
@MainActor
final class TabOverviewTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        TabTestBed.close(windows)
        windows.removeAll()
    }

    func testOpeningTheOverviewCapturesTheShownTabAndItsCardsCloseAndShowTabs() async throws {
        let bed = try await TabTestBed.make(notes: ["First", "Second", "Third"], frontmatter: "course: Physics", for: self)
        let model = TabOverviewModel(clock: ManualClock())
        let window = TabTestBed.window(width: 1_300, height: 850, showing: OverviewHost(workspace: bed.workspace, model: model))
        windows.append(window)
        try await waitUntil("the third note is shown") { TabTestBed.shownNoteTitles(in: window) == ["Third"] }

        model.present(layout: bed.workspace.layout, vaultIdentifier: bed.workspace.currentVaultIdentifier, previewLoader: bed.workspace.libraryPreviewLoader)
        XCTAssertTrue(model.isPresented)
        let thumbnail = try XCTUnwrap(model.thumbnails.thumbnail(of: bed.tabs[2]), "The shown tab was captured as the overview opened.")
        XCTAssertLessThanOrEqual(max(thumbnail.width, thumbnail.height), Int(TabThumbnails.longestSidePixels))
        XCTAssertGreaterThan(darkPixelFraction(of: thumbnail), 0.002, "The thumbnail shows the note's text, not an empty page.")

        let settled = ContinuousClock.now + .milliseconds(800)
        try await waitUntil("the overview has zoomed into place") { TabTestBed.layOut(window); return ContinuousClock.now > settled }
        // AppKit hands clicks to a window on screen only.
        window.showInvisibly()
        click(window, at: cardPoint(1, in: window, model: model, workspace: bed.workspace, closeButton: true))
        try await waitUntil("the second tab is closed") { bed.workspace.layout.allTabs.map(\.id) == [bed.tabs[0], bed.tabs[2]] }
        XCTAssertTrue(model.isPresented, "Closing a card leaves the overview open.")
        click(window, at: cardPoint(0, in: window, model: model, workspace: bed.workspace))
        try await waitUntil("the first note is shown") { !model.isPresented && TabTestBed.shownNoteTitles(in: window) == ["First"] }
        XCTAssertEqual(bed.workspace.layout.activeTab.id, bed.tabs[0])
    }

    func testATabOnScreenForAMomentIsCapturedAndATabPassedThroughIsNot() async throws {
        let bed = try await TabTestBed.make(notes: ["First", "Second", "Third"], for: self)
        let clock = ManualClock()
        let model = TabOverviewModel(clock: clock)
        let panes = NavigationStack {
            WorkspacePanes(workspace: bed.workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
        }
        let window = TabTestBed.window(width: 1_100, showing: panes.environment(model))
        windows.append(window)
        try await waitUntil("the third note is shown") { TabTestBed.shownNoteTitles(in: window) == ["Third"] }
        bed.workspace.activateTab(bed.tabs[1])
        try await waitUntil("the second note is shown") { TabTestBed.shownNoteTitles(in: window) == ["Second"] }
        bed.workspace.activateTab(bed.tabs[0])
        try await waitUntil("the first note is shown") { TabTestBed.shownNoteTitles(in: window) == ["First"] }
        try await waitUntil("one capture waits") { clock.pendingSleepCount == 1 }
        XCTAssertEqual(model.thumbnails.thumbnailCount, 0, "A switch captures nothing.")

        clock.advance(by: .milliseconds(TabOverviewModel.settleDelayMilliseconds))
        try await waitUntil("the first tab is captured") { model.thumbnails.thumbnail(of: bed.tabs[0]) != nil }
        XCTAssertNil(model.thumbnails.thumbnail(of: bed.tabs[1]), "A tab passed through on the way is not captured.")
        XCTAssertNil(model.thumbnails.thumbnail(of: bed.tabs[2]))
    }

    func testTheFilesOfTabsWithoutAThumbnailArePreviewedAsTheLibraryPreviewsThem() async throws {
        let bed = try await TabTestBed.make(notes: ["First", "Second"], frontmatter: "course: Physics", for: self)
        let model = TabOverviewModel(clock: ManualClock())
        model.present(layout: bed.workspace.layout, vaultIdentifier: bed.workspace.currentVaultIdentifier, previewLoader: bed.workspace.libraryPreviewLoader)
        let firstPath = try VaultPath("First.md")
        try await waitUntil("both notes are previewed") { model.filePreviews.count == 2 }
        guard case .note(let summary, let picture) = model.filePreviews[firstPath] else {
            return XCTFail("A note's card shows its note: \(String(describing: model.filePreviews[firstPath]))")
        }
        XCTAssertNil(picture)
        guard case .heading(let level, let text) = summary.blocks.first else { return XCTFail("The note's start: \(summary.blocks)") }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(String(text.characters), "First", "Its frontmatter is left out, as in reading view.")

        model.dismiss()
        XCTAssertFalse(model.isPresented)
        XCTAssertTrue(model.filePreviews.isEmpty, "The previews go with the overview.")
    }

    func testTheSearchFindsTabsByNameAndFolderOnEachSide() async throws {
        let bed = try await TabTestBed.make(notes: ["Physics/Waves", "Physics/Optics", "History/Rome"], for: self)
        bed.workspace.moveTabToOtherGroup(bed.tabs[2])
        let layout = bed.workspace.layout
        let title = bed.workspace.title(ofTab:)

        let everyTab = TabOverviewSection.sections(of: layout, matching: "", title: title)
        XCTAssertEqual(everyTab.map(\.title), ["Left", "Right"])
        XCTAssertEqual(everyTab.map { section in section.tabs.map(\.id) }, [[bed.tabs[0], bed.tabs[1]], [bed.tabs[2]]])
        XCTAssertEqual(TabOverviewSection.sections(of: layout, matching: "physics", title: title).flatMap { section in section.tabs.map(\.id) },
                       [bed.tabs[0], bed.tabs[1]], "A folder's name finds its notes.")
        XCTAssertEqual(TabOverviewSection.sections(of: layout, matching: "opt phys", title: title).flatMap { section in section.tabs.map(\.id) },
                       [bed.tabs[1]], "Every word has to be found.")
        let onlyRome = TabOverviewSection.sections(of: layout, matching: "rome", title: title)
        XCTAssertEqual(onlyRome.map(\.title), ["Right"], "A side with no tab found has no section.")
        XCTAssertEqual(onlyRome.first?.tabCount, 1)
    }

    func testCardsTakeTheDocumentAreasShapeWithinLimits() {
        XCTAssertEqual(TabOverview.cardAspectRatio(documentArea: 1.2, overview: CGSize(width: 400, height: 800)), 1.2)
        XCTAssertEqual(TabOverview.cardAspectRatio(documentArea: 0.4, overview: .zero), 0.62, "A phone's tall page is kept readable.")
        XCTAssertEqual(TabOverview.cardAspectRatio(documentArea: 3, overview: .zero), 1.6)
        XCTAssertEqual(TabOverview.cardAspectRatio(documentArea: nil, overview: CGSize(width: 1_000, height: 800)), 1.25)
    }

    // MARK: Helpers

    /// The panes with the tab overview over them, as the window's root view shows them.
    private struct OverviewHost: View {
        let workspace: WorkspaceModel
        let model: TabOverviewModel

        var body: some View {
            ZStack {
                NavigationStack {
                    WorkspacePanes(workspace: workspace, showsLinksInspector: .constant(false), create: { _ in }, showQuickSwitcher: {})
                }
                if model.isPresented {
                    TabOverview(model: model, actions: workspace.tabOverviewActions(dismiss: model.dismiss))
                }
            }
            .environment(model)
        }
    }

    /// The middle of a card's thumbnail, or of its close button, in the window, from the grid's measures.
    private func cardPoint(_ position: Int, in window: NSWindow, model: TabOverviewModel, workspace: WorkspaceModel, closeButton: Bool = false) -> CGPoint {
        let size = window.contentView?.bounds.size ?? .zero
        // The toolbar covers the top of the window's content.
        let topInset = size.height - window.contentLayoutRect.maxY
        let padding = TabOverview.horizontalPaddingPoints(isCompactWidth: false)
        let minimumWidth = TabOverview.minimumCardWidthPoints(isCompactWidth: false)
        let spacing = TabOverview.cardSpacingPoints
        let available = size.width - 2 * padding
        let columnCount = max(1, ((available + spacing) / (minimumWidth + spacing)).rounded(.down))
        let cardWidth = (available - (columnCount - 1) * spacing) / columnCount
        let aspectRatio = TabOverview.cardAspectRatio(documentArea: model.thumbnails.aspectRatio(ofGroup: workspace.layout.focusedGroupID), overview: size)
        let cardLeadingEdge = padding + CGFloat(position) * (cardWidth + spacing)
        let top = size.height - topInset - TabOverview.topPaddingPoints
        if closeButton { return CGPoint(x: cardLeadingEdge + cardWidth - 22, y: top - 22) }
        return CGPoint(x: cardLeadingEdge + cardWidth / 2, y: top - cardWidth / aspectRatio / 2)
    }

    private func click(_ window: NSWindow, at point: CGPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(event)
            }
        }
    }

    /// The share of a thumbnail's pixels dark enough to be text.
    private func darkPixelFraction(of image: CGImage) -> Double {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Double(pixels.filter { pixel in pixel < 110 }.count) / Double(pixels.count)
    }
}
#endif
