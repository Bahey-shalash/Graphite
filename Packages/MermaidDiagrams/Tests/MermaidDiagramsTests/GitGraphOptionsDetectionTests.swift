import XCTest
@testable import MermaidDiagrams

/// A Git graph whose front matter or directive sets options of Git graphs is known as such; other configuration and
/// comments are not options.
final class GitGraphOptionsDetectionTests: XCTestCase {
    private func setsOptions(_ source: String) throws -> Bool {
        try GitGraphReading.gitGraph(source).setsGitGraphOptions
    }

    func testFrontMatterThatConfiguresGitGraphsSetsOptions() throws {
        XCTAssertTrue(try setsOptions("---\nconfig:\n  logLevel: 'debug'\n  gitGraph:\n    showBranches: false\n---\n      gitGraph\n        commit"))
        XCTAssertTrue(try setsOptions("---\nconfig: {\"gitGraph\" : {\"parallelCommits\": true}}\n---\ngitGraph\n commit"))
    }

    func testADirectiveBeforeTheKeywordOrAmongTheStatementsSetsOptions() throws {
        XCTAssertTrue(try setsOptions("%%{init: { 'logLevel': 'debug', 'gitGraph': {'showBranches': false}} }%%\ngitGraph\n commit"))
        XCTAssertTrue(try setsOptions("gitGraph\n commit\n %%{init: {\"gitGraph\": {\"mainBranchName\": \"dev\"}}}%%\n commit"))
    }

    func testOtherConfigurationAndCommentsSetNone() throws {
        let themed = "---\ntitle: Example Git diagram\nconfig:\n  theme: base\n  themeVariables:\n    git0: '#ff0000'\n---\ngitGraph\n commit"
        XCTAssertFalse(try setsOptions(themed))
        XCTAssertFalse(try setsOptions("%% gitGraph: release flow\ngitGraph\n commit\n %% gitGraph: a note"))
        XCTAssertFalse(try setsOptions("%%{init: {'theme': 'dark'}}%%\ngitGraph:\n commit"))
    }

    func testTheKeyIsFoundWithItsColonOnly() {
        XCTAssertTrue(GitGraphOptionsDetection.setsOptions(in: Array("  gitGraph:".utf8)[...]))
        XCTAssertTrue(GitGraphOptionsDetection.setsOptions(in: Array("'gitGraph' :".utf8)[...]))
        XCTAssertFalse(GitGraphOptionsDetection.setsOptions(in: Array("gitGraph TB:".utf8)[...]))
        XCTAssertFalse(GitGraphOptionsDetection.setsOptions(in: Array("gitGraph".utf8)[...]))
    }
}
