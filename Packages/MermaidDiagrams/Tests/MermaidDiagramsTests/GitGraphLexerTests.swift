import XCTest
@testable import MermaidDiagrams

/// Tokens as the lexer of Mermaid's Git graph grammar reads them, quirks included: the first token type in Mermaid's
/// order wins, and a keyword followed by more of a name is that name.
final class GitGraphLexerTests: XCTestCase {
    private func tokens(_ text: String) throws -> [GitGraphToken] {
        var lexer = GitGraphLexer(cursor: MermaidTextCursor(bytes: Array(text.utf8)))
        var read: [GitGraphToken] = []
        while true {
            let token = try lexer.readToken().token
            if token == .endOfText { return read }
            read.append(token)
        }
    }

    func testAKeywordFollowedByMoreOfANameIsThatName() throws {
        XCTAssertEqual(try tokens("commits TBD LRU cherry-pick03 checkout02 mergeX"),
                       [.name("commits"), .name("TBD"), .name("LRU"), .name("cherry-pick03"), .name("checkout02"), .name("mergeX")])
        XCTAssertEqual(try tokens("commit TB cherry-pick switch HIGHLIGHT"),
                       [.statement(.commit), .direction(.topToBottom), .statement(.cherryPick), .statement(.checkout), .commitType(.highlight)])
    }

    func testANameRunsOverDotsSlashesAndHyphensAndEndsWithNoDotOrSlash() throws {
        XCTAssertEqual(try tokens("feature/x_y-z 1.0.1 a.b/c- _a"), [.name("feature/x_y-z"), .name("1.0.1"), .name("a.b/c-"), .name("_a")])
    }

    func testWholeNumbersAreReadAsMermaidsExpressionMatchesThem() throws {
        XCTAssertEqual(try tokens("0 12 007 12.5 1.0"),
                       [.integer(0), .integer(12), .integer(0), .integer(0), .integer(7), .integer(1), .name("2.5"), .name("1.0")])
        XCTAssertEqual(try tokens(String(repeating: "9", count: 40)), [.integer(Int.max)])
    }

    func testAWordThatStartsWithTitleIsTheTitleKeyword() throws {
        XCTAssertEqual(try tokens("titlepage"), [.title(""), .name("page")])
        XCTAssertEqual(try tokens("title  A \t b %% a comment\ncommit"), [.title("A b"), .lineBreak, .statement(.commit)])
    }

    func testQuotedTextReadsItsEscapesAndMayRunOverLines() throws {
        XCTAssertEqual(try tokens(#""a\"b" 'c\n'"#), [.quotedText("a\"b"), .quotedText("c\n")])
        XCTAssertEqual(try tokens("\"two\nlines\""), [.quotedText("two\nlines")])
        XCTAssertThrowsError(try tokens("\"a\\\nb\""))
    }

    func testAttributesNeedTheirColonRightAfterTheWord() throws {
        XCTAssertEqual(try tokens("id: id : order:1 parent:"),
                       [.attribute(.identifier), .name("id"), .colon, .attribute(.order), .integer(1), .attribute(.parent)])
        XCTAssertEqual(try tokens("tag:type:msg:"), [.attribute(.tag), .attribute(.type), .attribute(.message)])
    }

    func testTheDiagramKeywordStandsAloneOrWithItsColon() throws {
        XCTAssertEqual(try tokens("gitGraph gitGraph: gitGraphs gitGraph%%"), [.diagramKeyword, .diagramKeywordWithColon, .name("gitGraphs"), .diagramKeyword])
    }

    func testCommentsAndDirectivesAreSkippedAndALineBreakIsAToken() throws {
        XCTAssertEqual(try tokens("commit %% x\r\n%%{init: {}}%%\ncommit\rcommit"),
                       [.statement(.commit), .lineBreak, .lineBreak, .statement(.commit), .lineBreak, .statement(.commit)])
        XCTAssertEqual(try tokens("%%{ never closed\ncommit\n%%{ nor this one"), [.lineBreak, .statement(.commit), .lineBreak])
    }

    func testADirectiveThatSetsOptionsOfGitGraphsIsNoted() throws {
        var lexer = GitGraphLexer(cursor: MermaidTextCursor(bytes: Array("%%{init: {'theme': 'dark'}}%%\ncommit".utf8)))
        _ = try lexer.readToken()
        XCTAssertFalse(lexer.hasSkippedOptionsDirective)
        lexer = GitGraphLexer(cursor: MermaidTextCursor(bytes: Array("%%{init: { 'gitGraph': {'showBranches': false}} }%%\ncommit".utf8)))
        _ = try lexer.readToken()
        XCTAssertTrue(lexer.hasSkippedOptionsDirective)
    }

    func testACharacterNoTokenStartsWithIsUnexpected() {
        XCTAssertThrowsError(try tokens("commit é")) { error in
            XCTAssertEqual(error as? MermaidDiagramReadError, .invalidSyntax(line: 1, problem: .unexpectedText("é")))
        }
        XCTAssertThrowsError(try tokens("a.")) { error in
            XCTAssertEqual(error as? MermaidDiagramReadError, .invalidSyntax(line: 1, problem: .unexpectedText(".")))
        }
    }
}
