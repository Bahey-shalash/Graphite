#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import GraphiteUI

/// A link's frame, reported in its window's own coordinates (AppKit's, with the origin at the
/// bottom left), lands where it is in the view the cards are drawn in, whose origin is its top
/// left corner as in SwiftUI.
@MainActor
final class LinkPreviewWindowSpaceTests: XCTestCase {
    func testAFrameInTheWindowIsFoundInTheCardsViewFromItsTopLeftCorner() throws {
        let space = LinkPreviewWindowSpace()
        let content = Color.clear
            .frame(width: 200, height: 100)
            .background(LinkPreviewWindowSpaceReader(space: space))
            .padding(.leading, 50)
            .padding(.top, 30)
            .frame(width: 400, height: 300, alignment: .topLeading)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        defer { window.close() }
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertNil(LinkPreviewWindowSpace().overlayRect(fromWindowRect: .zero), "Without its view in a window there is no answer.")
        // A link 60 points from the left and 40 from the top of the window's content.
        let linkInWindow = hostingView.convert(CGRect(x: 60, y: 40, width: 30, height: 12), to: nil)
        let linkInCardsView = try XCTUnwrap(space.overlayRect(fromWindowRect: linkInWindow))
        XCTAssertEqual(linkInCardsView.origin.x, 10, accuracy: 0.5)
        XCTAssertEqual(linkInCardsView.origin.y, 10, accuracy: 0.5)
        XCTAssertEqual(linkInCardsView.size, CGSize(width: 30, height: 12))
    }
}
#endif
