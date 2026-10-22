import XCTest
@testable import MermaidDiagrams

final class SequenceParserTests: XCTestCase {
    private func sequence(_ body: String) throws -> SequenceDiagram {
        try SequenceReading.sequence("sequenceDiagram\n" + body)
    }

    private func readError(_ body: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        SequenceReading.readError("sequenceDiagram\n" + body, limits: limits)
    }

    private func onlyMessage(_ body: String) throws -> SequenceMessage {
        let messages = try sequence(body).messages
        XCTAssertEqual(messages.count, 1, body)
        return try XCTUnwrap(messages.first)
    }

    // MARK: Participants

    func testParticipantsAreInTheOrderTheyAreFirstNamed() throws {
        let diagram = try sequence("participant Bob\nAlice->>Bob: Hi\nCarol->>Alice: Hello\nNote right of Dan: Late")
        XCTAssertEqual(diagram.participantIdentifiers, ["Bob", "Alice", "Carol", "Dan"])
        XCTAssertEqual(diagram.participants.map(\.kind), [.participant, .participant, .participant, .participant])
    }

    func testAnAliasGivesTheTextAndTheKeywordGivesTheKind() throws {
        let diagram = try sequence("participant A as Alice<br/>Johnson\nactor B\nactor C as Carl")
        XCTAssertEqual(diagram.participants, [
            SequenceParticipant(identifier: "A", label: DiagramLabel(lines: ["Alice", "Johnson"])),
            SequenceParticipant(identifier: "B", label: DiagramLabel("B"), kind: .actor),
            SequenceParticipant(identifier: "C", label: DiagramLabel("Carl"), kind: .actor),
        ])
    }

    func testADeclarationOfANamedParticipantChangesItOnlyWithAnAlias() throws {
        let diagram = try sequence("A->>B: Hi\nactor A\nactor B as Bobby\nparticipant B")
        XCTAssertEqual(diagram.participantIdentifiers, ["A", "B"])
        XCTAssertEqual(diagram.participants[0].kind, .participant, "Mermaid keeps a participant redeclared without an alias as it was")
        XCTAssertEqual(diagram.participants[1], SequenceParticipant(identifier: "B", label: DiagramLabel("Bobby"), kind: .actor))
    }

    func testNamesMayHoldSpacesHyphensAndEqualsSigns() throws {
        let diagram = try sequence("participant Web server\nAlice-in-Wonderland->>Web server: Hi\nAlice=Wonderland -->> Bob : Hello")
        XCTAssertEqual(diagram.participantIdentifiers, ["Web server", "Alice-in-Wonderland", "Alice=Wonderland", "Bob"])
    }

    func testANameBeforeAsOrAttributesHoldsNoSpaceAndAWideNameEndsAtAComment() throws {
        XCTAssertEqual(try sequence("participant Alice Smith as AS").participants.first?.identifier, "Alice Smith as AS")
        XCTAssertEqual(try sequence("participant A #comment, with a comma").participants.first?.identifier, "A")
        XCTAssertEqual(readError("participant SAS My service <br> description"), .invalidSyntax(line: 2, problem: .unexpectedText("SAS My service <br> desc")))
    }

    // MARK: Messages

    func testEachArrowGivesItsStrokeAndHead() throws {
        let cases: [(String, SequenceArrow)] = [
            ("->", SequenceArrow(stroke: .solid, head: .none)), ("-->", SequenceArrow(stroke: .dotted, head: .none)),
            ("->>", SequenceArrow(stroke: .solid, head: .arrow)), ("-->>", SequenceArrow(stroke: .dotted, head: .arrow)),
            ("-x", SequenceArrow(stroke: .solid, head: .cross)), ("--x", SequenceArrow(stroke: .dotted, head: .cross)),
            ("-X", SequenceArrow(stroke: .solid, head: .cross)), ("-)", SequenceArrow(stroke: .solid, head: .open)),
            ("--)", SequenceArrow(stroke: .dotted, head: .open)),
            ("<<->>", SequenceArrow(stroke: .solid, head: .arrow, pointsBothWays: true)),
            ("<<-->>", SequenceArrow(stroke: .dotted, head: .arrow, pointsBothWays: true)),
        ]
        for (written, arrow) in cases {
            let message = try onlyMessage("Alice\(written)Bob: Hi")
            XCTAssertEqual(message.arrow, arrow, written)
            XCTAssertEqual(message.text, DiagramLabel("Hi"), written)
        }
    }

    func testAMessageToItselfNamesOneParticipant() throws {
        let diagram = try sequence("John->>John: Fight against hypochondria")
        XCTAssertEqual(diagram.participantIdentifiers, ["John"])
        XCTAssertEqual(diagram.messages.first.map { message in diagram.endpoints(of: message).target }, "John")
    }

    func testTheTextIsDecodedAndMayBeEmpty() throws {
        XCTAssertEqual(try onlyMessage("A->>B:").text, DiagramLabel(""))
        XCTAssertEqual(try onlyMessage("A->>B: I #9829; you #infin; times").text, DiagramLabel("I ♥ you ∞ times"))
        XCTAssertEqual(try onlyMessage("A->>B: Hello John,<br/>how are you?").text.lines, ["Hello John,", "how are you?"])
        XCTAssertEqual(try onlyMessage("A->>B: Not so good :(").text, DiagramLabel("Not so good :("))
    }

    func testWrapPrefixesSayWhetherTheTextWraps() throws {
        XCTAssertFalse(try onlyMessage("A->>B: plain").wrapsText)
        XCTAssertTrue(try onlyMessage("A->>B:wrap: long text").wrapsText)
        XCTAssertEqual(try onlyMessage("A->>B: wrap: long text").text, DiagramLabel("long text"))
        XCTAssertFalse(try onlyMessage("A->>B:nowrap: short").wrapsText)
    }

    func testASemicolonOrAHashEndsTheText() throws {
        XCTAssertEqual(try onlyMessage("Alice->Bob: -:<>,;# comment").text, DiagramLabel("-:<>,"))
        XCTAssertEqual(try sequence("Alice->Bob: one; Bob->Alice: two").messages.map(\.text), [DiagramLabel("one"), DiagramLabel("two")])
    }

    // MARK: Activations

    func testPlusStartsTheTargetsActivationAndMinusEndsTheSources() throws {
        let diagram = try sequence("Alice->>+John: Hello\nJohn-->>- Alice: Great")
        XCTAssertEqual(diagram.events.count, 4)
        XCTAssertEqual(diagram.events[1], .activationStart(participantIndex: 1))
        XCTAssertEqual(diagram.events[3], .activationEnd(participantIndex: 1))
    }

    func testActivateAndDeactivateAreEventsOfTheirOwn() throws {
        let diagram = try sequence("Alice->>John: Hello\nactivate John\nJohn-->>Alice: Great\ndeactivate John")
        XCTAssertEqual(diagram.events[1], .activationStart(participantIndex: 1))
        XCTAssertEqual(diagram.events[3], .activationEnd(participantIndex: 1))
    }

    func testDeactivatingAParticipantWithNoActivationIsAnErrorOnItsLine() {
        XCTAssertEqual(readError("A->>+B: one\nB-->>-A: two\nB-->>-A: three"),
                       .invalidSyntax(line: 4, problem: .sequence(.inactiveParticipantDeactivated(identifier: "B"))))
        XCTAssertEqual(readError("deactivate A"), .invalidSyntax(line: 2, problem: .sequence(.inactiveParticipantDeactivated(identifier: "A"))))
    }

    func testAnActivationOfAParticipantNamedLaterPointsAtItAndOneNeverNamedIsDropped() throws {
        let diagram = try sequence("activate Bob\nactivate Ghost\nAlice->>Bob: Hi\ndeactivate Bob")
        XCTAssertEqual(diagram.participantIdentifiers, ["Alice", "Bob"])
        XCTAssertEqual(diagram.events.count, 3)
        XCTAssertEqual(diagram.events[0], .activationStart(participantIndex: 1))
        XCTAssertEqual(diagram.events[2], .activationEnd(participantIndex: 1))
    }

    // MARK: Notes

    func testNotesTakeTheirPlacement() throws {
        let diagram = try sequence("""
            Alice->>John: Hi
            Note left of Alice: one
            note RIGHT OF John: two
            Note over John: three
            Note over Alice,John: four
            """)
        let notes = diagram.events.compactMap { event -> SequenceNote? in
            guard case .note(let note) = event else { return nil }
            return note
        }
        XCTAssertEqual(notes.map(\.placement), [.leftOf(participantIndex: 0), .rightOf(participantIndex: 1),
                                                 .over(firstParticipantIndex: 1, lastParticipantIndex: 1),
                                                 .over(firstParticipantIndex: 0, lastParticipantIndex: 1)])
        XCTAssertEqual(notes.map(\.text), ["one", "two", "three", "four"].map(DiagramLabel.init))
    }

    // MARK: Blocks

    func testBlocksAreFlatEventsWithTheirSections() throws {
        let diagram = try sequence("""
            alt is sick
                Bob->>Alice: Not so good
            else is well
                Bob->>Alice: Fresh
            end
            loop Every minute
                par_over Overlap
                    Alice->>Bob: Ping
                end
            end
            """)
        XCTAssertEqual(diagram.events.filter { event in !isMessage(event) }, [
            .blockStart(kind: .alternatives, label: DiagramLabel("is sick")), .blockSection(label: DiagramLabel("is well")), .blockEnd,
            .blockStart(kind: .loop, label: DiagramLabel("Every minute")), .blockStart(kind: .parallel, label: DiagramLabel("Overlap")),
            .blockEnd, .blockEnd,
        ])
    }

    func testEachBlockKeywordGivesItsKind() throws {
        let cases: [(String, SequenceBlockKind, String?)] = [
            ("loop", .loop, nil), ("alt", .alternatives, "else"), ("opt", .optional, nil), ("par", .parallel, "and"),
            ("critical", .critical, "option"), ("break", .break, nil),
        ]
        for (keyword, kind, sectionKeyword) in cases {
            let section = sectionKeyword.map { word in "\n\(word) other\nB->>A: no" } ?? ""
            let diagram = try sequence("\(keyword) text\nA->>B: yes\(section)\nend")
            XCTAssertEqual(diagram.events.first, .blockStart(kind: kind, label: DiagramLabel("text")), keyword)
            XCTAssertEqual(diagram.events.last, .blockEnd, keyword)
        }
    }

    func testABlockWithoutTextHasAnEmptyLabel() throws {
        let diagram = try sequence("alt;Bob-->Alice: fine\nelse # comment\nBob-->Alice: fine\nend")
        XCTAssertEqual(diagram.events[0], .blockStart(kind: .alternatives, label: DiagramLabel("")))
        XCTAssertEqual(diagram.events[2], .blockSection(label: DiagramLabel("")))
    }

    func testASectionOutsideItsBlockIsAnError() {
        XCTAssertEqual(readError("loop x\nelse y\nend"), .invalidSyntax(line: 3, problem: .sequence(.sectionOutsideItsBlock(keyword: "else"))))
        XCTAssertEqual(readError("alt x\nand y\nend"), .invalidSyntax(line: 3, problem: .sequence(.sectionOutsideItsBlock(keyword: "and"))))
        XCTAssertEqual(readError("option y"), .invalidSyntax(line: 2, problem: .sequence(.sectionOutsideItsBlock(keyword: "option"))))
    }

    func testAnEndWithoutABlockAndABlockLeftOpenAreErrors() {
        XCTAssertEqual(readError("A->>B: x\nend"), .invalidSyntax(line: 3, problem: .sequence(.endWithoutBlock)))
        XCTAssertEqual(readError("loop outer\nopt inner\nA->>B: x\nend"), .invalidSyntax(line: 2, problem: .sequence(.unclosedBlock(keyword: "loop"))))
    }

    func testRectShadesWithTheColorItNames() throws {
        let diagram = try sequence("rect rgb(200, 255, 200)\nA->>B: x\nend\nrect\nA->>B: y\nend")
        let expected = SequenceHighlightColor(red: 200.0 / 255, green: 1, blue: 200.0 / 255)
        XCTAssertEqual(diagram.events[0], .blockStart(kind: .highlight(expected), label: DiagramLabel(lines: [])))
        XCTAssertEqual(diagram.events[3], .blockStart(kind: .highlight(nil), label: DiagramLabel(lines: [])))
    }

    // MARK: Numbering, titles and comments

    func testAutonumberTakesItsStartAndStepInHundredths() throws {
        let diagram = try sequence("autonumber\nautonumber 10.1 .01\nautonumber 5\nautonumber off")
        XCTAssertEqual(diagram.events, [
            .numbering(SequenceNumbering(firstNumberInHundredths: nil, stepInHundredths: nil, isVisible: true)),
            .numbering(SequenceNumbering(firstNumberInHundredths: 1010, stepInHundredths: 1, isVisible: true)),
            .numbering(SequenceNumbering(firstNumberInHundredths: 500, stepInHundredths: 100, isVisible: true)),
            .numbering(SequenceNumbering(firstNumberInHundredths: nil, stepInHundredths: nil, isVisible: false)),
        ])
    }

    func testAutonumberRefusesMoreThanTwoDecimals() {
        XCTAssertEqual(readError("autonumber 10.001\nA->>B: x"), .invalidSyntax(line: 2, problem: .unexpectedText("10.001")))
    }

    func testTheTitleComesFromAStatementOrTheFrontMatter() throws {
        XCTAssertEqual(try sequence("title Diagram Title\nA->>B: x").title, "Diagram Title")
        XCTAssertEqual(try sequence("title: Diagram Title\nA->>B: x").title, "Diagram Title")
        XCTAssertEqual(try SequenceReading.sequence("---\ntitle: Front\n---\nsequenceDiagram\nA->>B: x").title, "Front")
        XCTAssertEqual(try SequenceReading.sequence("---\ntitle: Front\n---\nsequenceDiagram\ntitle Body\nA->>B: x").title, "Body")
    }

    func testAccessibilityTitleAndDescriptionAreRead() throws {
        let single = try sequence("accTitle: The title\naccDescr: The description\nA->>B: x")
        XCTAssertEqual(single.accessibilityTitle, "The title")
        XCTAssertEqual(single.accessibilityDescription, "The description")
        XCTAssertEqual(try sequence("accDescr {\n  First line\n  Second line\n}\nA->>B: x").accessibilityDescription, "First line\nSecond line")
        XCTAssertEqual(readError("accDescr {\nnever closed"), .invalidSyntax(line: 2, problem: .unclosedAccessibilityDescription))
    }

    func testKeywordsAreReadInAnyCase() throws {
        let diagram = try sequence("PARTICIPANT A as Alice\nActor B\nLOOP Again\nA->>B: x\nEND\nAUTONUMBER")
        XCTAssertEqual(diagram.participants.map(\.kind), [.participant, .actor])
        XCTAssertEqual(diagram.events.count, 4)
    }

    func testWordsThatOnlyLookLikeKeywordsAreNames() throws {
        let diagram = try sequence("Link->>endpoint: m\ntitle->>loopy: n")
        XCTAssertEqual(diagram.participantIdentifiers, ["Link", "endpoint", "title", "loopy"])
    }

    func testCommentsBlankLinesAndCarriageReturnsAreSkipped() throws {
        let diagram = try sequence("%% a comment\r\n# another\r\n\r\n%%{init: {\"theme\": \"dark\"}}%%\r\nA->>B: x\r\nB-->>A: y %% kept\r\n")
        XCTAssertEqual(diagram.messages.map(\.text), [DiagramLabel("x"), DiagramLabel("y %% kept")])
    }

    // MARK: Statements not laid out

    func testStatementsNotLaidOutAreListedAndWhatTheModelHoldsIsKept() throws {
        let diagram = try sequence("""
            box Purple Group
            participant A
            actor B
            end
            participant C@{ "type": "database" } as Store
            link A: Wiki @ https://example.com
            links B: {"Repo": "https://example.com"}
            properties A: {"class": "x"}
            details A: identifier
            create participant D
            A->>D: Hi
            destroy D
            D-xA: Bye
            A-|\\B: Half
            A()->>B: Circle
            """)
        XCTAssertEqual(diagram.statementsNotLaidOut, Set(SequenceStatementNotLaidOut.allCases))
        XCTAssertEqual(diagram.participantIdentifiers, ["A", "B", "C", "D"])
        XCTAssertEqual(diagram.participants[2].label, DiagramLabel("Store"))
        XCTAssertEqual(diagram.messages.count, 3, "The half arrow is left out")
    }

    func testABoxHoldsParticipantStatementsOnly() {
        XCTAssertEqual(readError("box Group\nA->>B: x\nend"), .invalidSyntax(line: 3, problem: .unexpectedText("A->>B: x")))
    }

    func testAttributesWithoutAClosingBraceAreAnError() {
        XCTAssertEqual(readError("participant E@{ \"type\": \"entity\"\nE ->> E: process"), .invalidSyntax(line: 2, problem: .unclosedAttributes))
    }

    // MARK: Errors and limits

    func testAMissingPartIsATypedErrorOnItsLine() {
        XCTAssertEqual(readError("Alice"), .invalidSyntax(line: 2, problem: .sequence(.expectedArrow)))
        XCTAssertEqual(readError("Alice=>Bob: x"), .invalidSyntax(line: 2, problem: .unexpectedText(">Bob: x")), "An equals sign is part of a name")
        XCTAssertEqual(readError("A->>: x"), .invalidSyntax(line: 2, problem: .sequence(.expectedParticipant)))
        XCTAssertEqual(readError("A->>B x"), .invalidSyntax(line: 2, problem: .sequence(.expectedText)))
        XCTAssertEqual(readError("Note A: x"), .invalidSyntax(line: 2, problem: .sequence(.expectedNotePlacement)))
        XCTAssertEqual(readError("Note over A,: x"), .invalidSyntax(line: 2, problem: .sequence(.expectedParticipant)))
        XCTAssertEqual(readError("participant"), .invalidSyntax(line: 2, problem: .sequence(.expectedParticipant)))
        XCTAssertEqual(readError("create note"), .invalidSyntax(line: 2, problem: .unexpectedText("note")))
    }

    func testTheParticipantAndStatementLimitsAreCheckedBeforeAnythingIsAdded() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 2
        XCTAssertEqual(readError("A->>B: x\nB->>C: y", limits: limits), .tooManyParticipants(limit: 2))
        limits = .standard
        limits.maximumEdgeCount = 2
        XCTAssertEqual(readError("A->>+B: x\nB->>A: y", limits: limits), .tooManySequenceStatements(limit: 2))
    }

    private func isMessage(_ event: SequenceEvent) -> Bool {
        if case .message = event { return true }
        return false
    }
}
