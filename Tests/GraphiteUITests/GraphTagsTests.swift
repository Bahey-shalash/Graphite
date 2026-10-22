import XCTest
import GraphiteCore
@testable import GraphiteUI

/// Tags in the graph: shown unless the person hides them, chosen with a tap to bring out
/// their notes, drawn larger the more notes carry them, and named from further out than notes.
@MainActor
final class GraphTagsTests: XCTestCase {
    func testTheGraphsShowTagsUnlessThePersonHidesThem() {
        XCTAssertTrue(GraphSettingDefault.showsTags)
        XCTAssertTrue(GraphSettingDefault.localShowsTags)
    }

    func testTheOtherDefaultsAreObsidians() {
        XCTAssertFalse(GraphSettingDefault.showsAttachments)
        XCTAssertTrue(GraphSettingDefault.showsExistingFilesOnly)
        XCTAssertTrue(GraphSettingDefault.showsOrphans)
        XCTAssertFalse(GraphSettingDefault.showsArrows)
        XCTAssertEqual(GraphSettingDefault.localDepth, 1)
        XCTAssertTrue(GraphSettingDefault.localFollowsIncomingLinks)
        XCTAssertTrue(GraphSettingDefault.localFollowsOutgoingLinks)
        XCTAssertTrue(GraphSettingDefault.localShowsNeighborLinks)
        XCTAssertFalse(GraphSettingDefault.localShowsAttachments)
        XCTAssertTrue(GraphSettingDefault.localShowsExistingFilesOnly)
    }

    func testATappedTagIsChosenRatherThanOpenedAndANoteOpensKeepingIt() throws {
        let model = loadedModel()
        defer { model.stop() }
        let tag = try XCTUnwrap(model.index(of: "#exam"))
        let lecture = try XCTUnwrap(model.index(of: "Lecture.md"))

        XCTAssertEqual(model.tap(nodeAt: tag, chosenTag: nil), .choose("#exam"),
                       "A tag is not opened: the search would take the person away from the graph.")
        XCTAssertEqual(model.tap(nodeAt: lecture, chosenTag: "#exam"), .open(GraphNode(id: "Lecture.md", kind: .note)),
                       "A note opens, and the chosen tag is left as it is, so its notes can be opened one after another.")
        XCTAssertEqual(model.tap(nodeAt: tag, chosenTag: "#exam"), .choose(nil), "Choosing the tag again lets it go.")
        XCTAssertEqual(model.tap(nodeAt: try XCTUnwrap(model.index(of: "#lab")), chosenTag: "#exam"), .choose("#lab"))
        XCTAssertEqual(model.tap(nodeAt: nil, chosenTag: "#exam"), .choose(nil), "A tap beside the nodes lets it go.")
    }

    func testATagCarriedByMoreNotesIsDrawnLarger() throws {
        let model = loadedModel()
        defer { model.stop() }
        let often = try XCTUnwrap(model.index(of: "#exam"))
        let once = try XCTUnwrap(model.index(of: "#lab"))
        XCTAssertGreaterThan(model.radii[often], model.radii[once])
    }

    func testATagsNameShowsFromFurtherOutThanANotes() {
        XCTAssertTrue(GraphCanvas.showsName(of: .tag, atScale: 0.7))
        XCTAssertFalse(GraphCanvas.showsName(of: .note, atScale: 0.7))
        XCTAssertFalse(GraphCanvas.showsName(of: .tag, atScale: 0.5))
        XCTAssertTrue(GraphCanvas.showsName(of: .note, atScale: 1.4))
    }

    // MARK: Helpers

    /// Lecture → Exam; #exam on all three notes, #lab on Lab only.
    private static let graph: LinkGraph = {
        let lecture = path("Lecture.md"), exam = path("Exam.md"), lab = path("Lab.md")
        return LinkGraph.build(files: [lecture, exam, lab], links: [(lecture, exam)], unresolvedLinks: [],
                               tags: [(lecture, "exam"), (exam, "exam"), (lab, "exam"), (lab, "lab")])
    }()

    private static func path(_ text: String) -> VaultPath {
        guard let path = try? VaultPath(text) else { preconditionFailure("Invalid test path \(text)") }
        return path
    }

    private func loadedModel() -> GraphCanvasModel {
        let model = GraphCanvasModel()
        model.load(Self.graph, forces: GraphLayout.Forces(), previousPositions: [:])
        return model
    }
}
