#if os(macOS)
import AppKit
import SwiftUI
import XCTest
import Textual
@testable import GraphiteUI
import GraphiteTestSupport

/// Graphite's addition to Textual (`Vendor/textual/GRAPHITE-PATCHES.md`, section 12) on the
/// Mac: selectable text tells its link hover action when the pointer comes onto a link, with
/// the link's frame in the window, and when it leaves; without an action, nothing watches the
/// pointer.
@MainActor
final class TextLinkHoverActionTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.contentView = nil
            window.orderOut(nil)
        }
        windows = []
        try await super.tearDown()
    }

    private final class HoverLog {
        var hovers: [TextLinkHover] = []
    }

    /// `markdown` as the reading view draws text, in a window, with `action`; answers the view
    /// that takes the pointer over it.
    private func showText(_ markdown: String, action: TextLinkHoverAction?) throws -> NSView {
        let text = StructuredText(markdown: markdown)
            .textual.textSelection(.enabled)
            .textual.linkHoverAction(action)
            .frame(width: 400, height: 200, alignment: .topLeading)
        let hostingView = NSHostingView(rootView: text)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        windows.append(window)
        window.contentView = hostingView
        window.showInvisibly()
        hostingView.layoutSubtreeIfNeeded()
        return try XCTUnwrap(Self.interactionView(in: hostingView), "The selectable text has its interaction view.")
    }

    private static func interactionView(in view: NSView) -> NSView? {
        if String(describing: type(of: view)) == "NSTextInteractionView" { return view }
        for subview in view.subviews { if let found = interactionView(in: subview) { return found } }
        return nil
    }

    private func movePointer(to windowPoint: CGPoint, over view: NSView) throws {
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: windowPoint, modifierFlags: [], timestamp: 0,
                                                     windowNumber: view.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        view.mouseMoved(with: event)
    }

    /// Moves the pointer along the first line of the text, left to right, until it comes onto a link.
    private func movePointerAlongTheFirstLine(of view: NSView, until log: HoverLog) throws -> CGPoint? {
        for offset in stride(from: CGFloat(2), through: 380, by: 4) {
            let windowPoint = view.convert(CGPoint(x: offset, y: 8), to: nil)
            try movePointer(to: windowPoint, over: view)
            if !log.hovers.isEmpty { return windowPoint }
        }
        return nil
    }

    func testThePointerComingOntoALinkAndLeavingItIsToldWithTheLinksFrame() async throws {
        let log = HoverLog()
        let view = try showText("[Other note](graphite://open?target=Other) and words after it.", action: TextLinkHoverAction { hover in log.hovers.append(hover) })
        await Task.yield()
        let onLink = try XCTUnwrap(try movePointerAlongTheFirstLine(of: view, until: log), "Some point of the first line is on the link.")
        guard case .entered(let location, let frame) = try XCTUnwrap(log.hovers.first) else { return XCTFail("The pointer came onto the link: \(log.hovers)") }
        XCTAssertEqual(location, URL(string: "graphite://open?target=Other"))
        XCTAssertTrue(frame.insetBy(dx: -1, dy: -1).contains(onLink), "The frame, in window coordinates, is where the pointer is.")

        try movePointer(to: view.convert(CGPoint(x: 390, y: 190), to: nil), over: view)
        XCTAssertEqual(log.hovers.count, 2)
        XCTAssertEqual(log.hovers.last, .exited(location))
    }

    func testWithoutAnActionThePointerIsNotWatched() async throws {
        let view = try showText("[Other note](graphite://open?target=Other) and words.", action: nil)
        let withoutAction = view.trackingAreas.count
        let watched = try showText("[Other note](graphite://open?target=Other) and words.", action: TextLinkHoverAction { _ in })
        XCTAssertEqual(watched.trackingAreas.count, withoutAction + 1, "Only an action adds the area that follows the pointer.")
    }
}
#endif
