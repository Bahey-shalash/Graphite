import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// When a link's card shows and closes: after the pointer rests on the link, as long as it is
/// on the link or the card, at once for a held link; and what plugins hear of it.
@MainActor
final class LinkPreviewModelTests: XCTestCase {
    private var clock: ManualClock!
    private var model: LinkPreviewModel!
    private var announcedTargets: [String] = []

    override func setUp() async throws {
        clock = ManualClock()
        announcedTargets = []
        model = LinkPreviewModel(clock: clock) { [weak self] request in self?.announcedTargets.append(request.target) }
        model.useReading(try await LinkPreviewTestVault.reading(for: self))
    }

    private func request(_ target: String, trigger: LinkPreviewTrigger = .hover, source: LinkPreviewSource = .editor) throws -> LinkPreviewRequest {
        LinkPreviewRequest(target: target, isWiki: true, sourceNote: try VaultPath("Note.md"), anchor: CGRect(x: 10, y: 10, width: 40, height: 16),
                           trigger: trigger, source: source)
    }

    private var shownRequest: LinkPreviewRequest? {
        if case .shown(let request, _) = model.phase { request } else { nil }
    }

    private var isHidden: Bool {
        if case .hidden = model.phase { true } else { false }
    }

    private func waitForTheCard(of request: LinkPreviewRequest) async throws {
        try await waitUntil("the card of \(request.target) shows") { self.shownRequest == request }
    }

    private func showOnHover(_ hovered: LinkPreviewRequest) async throws {
        model.pointerEntered(hovered)
        try await clock.awaitPendingSleepers()
        clock.advance(by: LinkPreviewModel.showDelay)
        try await waitForTheCard(of: hovered)
    }

    func testAHoveredLinksCardShowsOnceThePointerHasRestedThere() async throws {
        let hovered = try request("Other")
        model.pointerEntered(hovered)
        guard case .waiting(let waiting) = model.phase, waiting == hovered else { return XCTFail("The card is on its way: \(model.phase)") }
        try await clock.awaitPendingSleepers()
        clock.advance(by: LinkPreviewModel.showDelay - .milliseconds(1))
        await ManualClock.letResumedTasksRun()
        XCTAssertNil(shownRequest, "Not before the delay.")
        clock.advance(by: .milliseconds(1))
        try await waitForTheCard(of: hovered)
        guard case .shown(_, let content) = model.phase else { return XCTFail() }
        XCTAssertEqual(content.path, try VaultPath("Other.md"))
    }

    func testThePointerLeavingTheLinkBeforeTheDelayShowsNoCard() async throws {
        let hovered = try request("Other")
        model.pointerEntered(hovered)
        try await clock.awaitPendingSleepers()
        model.pointerLeft(hovered)
        XCTAssertTrue(isHidden)
        clock.advance(by: LinkPreviewModel.showDelay)
        await ManualClock.letResumedTasksRun()
        XCTAssertTrue(isHidden)
    }

    func testAShownCardStaysWhileThePointerReachesItAndClosesOnceThePointerLeftBoth() async throws {
        let hovered = try request("Other")
        try await showOnHover(hovered)

        model.pointerLeft(hovered)
        try await clock.awaitPendingSleepers()
        model.pointerEnteredCard()
        clock.advance(by: LinkPreviewModel.hideDelay)
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(shownRequest, hovered, "The pointer reached the card in time.")

        model.pointerLeftCard()
        try await clock.awaitPendingSleepers()
        clock.advance(by: LinkPreviewModel.hideDelay - .milliseconds(1))
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(shownRequest, hovered)
        clock.advance(by: .milliseconds(1))
        try await waitUntil("the card closes") { self.isHidden }
    }

    func testBackOnTheLinkBeforeTheCardClosesKeepsIt() async throws {
        let hovered = try request("Other")
        try await showOnHover(hovered)
        model.pointerLeft(hovered)
        try await clock.awaitPendingSleepers()
        model.pointerEntered(hovered)
        clock.advance(by: LinkPreviewModel.hideDelay)
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(shownRequest, hovered)
    }

    func testAHeldLinksCardShowsAtOnceAndStaysUntilClosed() async throws {
        let held = try request("Other", trigger: .press)
        model.show(held)
        try await waitForTheCard(of: held)
        model.pointerLeft(held)
        model.pointerLeftCard()
        await ManualClock.letResumedTasksRun()
        XCTAssertEqual(shownRequest, held, "Only closing it closes it.")
        model.close()
        XCTAssertTrue(isHidden)
    }

    func testALinkNothingAnswersShowsNoCard() async throws {
        model.pointerEntered(try request("Nobody"))
        try await clock.awaitPendingSleepers()
        clock.advance(by: LinkPreviewModel.showDelay)
        try await waitUntil("the card gives up") { self.isHidden }
    }

    func testPluginsHearOfEachLinkOfANoteOnceAndNotOfTheirOwn() async throws {
        let inEditor = try request("Other", source: .editor)
        model.pointerEntered(inEditor)
        model.pointerEntered(inEditor)
        model.pointerEntered(try request("Note", source: .reading))
        model.pointerEntered(try request("Other#Plan", source: .plugin))
        XCTAssertEqual(announcedTargets, ["Other", "Note"])
    }

    func testWithoutAReadingAHeldLinkShowsNoCardAndWaitsForNothing() async throws {
        model.useReading(nil)
        model.show(try request("Other", trigger: .press))
        try await waitUntil("the card gives up") { self.isHidden }
    }

    func testWithoutAReadingTheCardCloses() async throws {
        let hovered = try request("Other")
        try await showOnHover(hovered)
        model.useReading(nil)
        XCTAssertTrue(isHidden)
    }
}
