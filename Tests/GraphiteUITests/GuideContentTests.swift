import XCTest
@testable import GraphiteUI

/// The Guide's topics: what each needs to show, how its search finds them, and which topics
/// the Mac leaves out.
final class GuideContentTests: XCTestCase {
    func testEveryTopicHasATitleASummaryAndSteps() {
        for topic in GuideTopic.allCases {
            let content = topic.content
            XCTAssertFalse(content.title.isEmpty, "\(topic)")
            XCTAssertFalse(content.summary.isEmpty, "\(topic)")
            XCTAssertFalse(content.steps.isEmpty, "\(topic)")
            XCTAssertTrue(content.steps.allSatisfy { step in !step.text.isEmpty }, "\(topic)")
        }
    }

    func testTopicTitlesAreDistinct() {
        let titles = GuideTopic.allCases.map(\.content.title)
        XCTAssertEqual(Set(titles).count, titles.count)
    }

    func testEverySectionHasTopicsAndEveryTopicIsInOneSection() {
        for section in GuideSection.allCases {
            XCTAssertFalse(section.topicsOnThisPlatform.isEmpty, "\(section)")
        }
        let listed = GuideSection.allCases.flatMap(\.topicsOnThisPlatform)
        XCTAssertEqual(Set(listed).count, listed.count, "No topic is listed twice.")
        XCTAssertEqual(Set(listed), Set(GuideTopic.allCases.filter(\.isOnThisPlatform)))
    }

    func testTheGuideStartsWithVaultsAndTheFirstNote() {
        let topics = GuideSection.allCases.flatMap(\.topicsOnThisPlatform)
        XCTAssertEqual(Array(topics.prefix(2)), [.vaults, .firstNote])
    }

    func testSearchFindsTopicsByTheirWordsIgnoringCaseAndOrder() {
        XCTAssertTrue(GuideTopic.tables.matches("TABLE"))
        XCTAssertTrue(GuideTopic.tables.matches("column row"))
        XCTAssertTrue(GuideTopic.templatesAndDailyNotes.matches("{{date"), "Examples are searched too.")
        XCTAssertFalse(GuideTopic.tables.matches("table recording"), "Every word must appear.")
        XCTAssertTrue(GuideTopic.recording.matches("   "), "A blank search matches everything.")
    }

    func testTheMacLeavesOutOnlyThePencilTopics() {
        XCTAssertEqual(Set(GuideTopic.allCases.filter(\.needsApplePencilFeatures)), [.drawings, .pencilTools, .notebooks])
        #if os(macOS)
        XCTAssertTrue(GuideTopic.allCases.filter(\.needsApplePencilFeatures).allSatisfy { topic in !topic.isOnThisPlatform })
        XCTAssertEqual(GuideSection.handwritingAndPDFs.topicsOnThisPlatform, [.annotatingPDFs], "The Mac keeps what it can do with PDFs.")
        #else
        XCTAssertTrue(GuideTopic.allCases.allSatisfy(\.isOnThisPlatform))
        #endif
    }

    func testTheSourceCodeTopicLinksToTheRepository() {
        XCTAssertEqual(GuideTopic.sourceCodeAndFeedback.section, .customizing)
        let summary = GuideText.styled(GuideTopic.sourceCodeAndFeedback.content.summary)
        XCTAssertTrue(summary.runs.contains { run in run.link?.absoluteString == "https://github.com/Graphite-Note/Graphite" })
        XCTAssertTrue(GuideTopic.sourceCodeAndFeedback.matches("github issue"))
    }

    func testBoldWordsAreStyledAndTheMarksRemoved() {
        let styled = GuideText.styled("Tap **New**, then **Note**.")
        XCTAssertEqual(String(styled.characters), "Tap New, then Note.")
        let boldRuns = styled.runs.filter { run in run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
        XCTAssertEqual(boldRuns.count, 2)
    }
}
