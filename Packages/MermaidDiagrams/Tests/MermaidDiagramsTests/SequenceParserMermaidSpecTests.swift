import XCTest
@testable import MermaidDiagrams

/// The parsing cases of Mermaid 12.1.0's `sequenceDiagram.spec.js`, with their inputs as Pele's compatibility suite
/// keeps them (`tests/compat/sequence`, MIT; Mermaid's spec is MIT too). Mermaid's model is one list of "messages"
/// holding notes, activations, block lines and numbering too; `MermaidMessage` shows `SequenceDiagram.events` the
/// same way, so the assertions read as the spec's. Cases that check pixel positions of Mermaid's own renderer are left
/// out, as Pele leaves them out.
final class SequenceParserMermaidSpecTests: XCTestCase {
    /// One entry of Mermaid's message list: its `LINETYPE` name, `from`, `to` and text lines.
    private struct MermaidMessage: Equatable {
        let type: String
        let from: String?
        let to: String?
        let lines: [String]
    }

    private func read(_ source: String) throws -> SequenceDiagram {
        try SequenceReading.sequence(source)
    }

    private func fails(_ source: String) -> Bool {
        SequenceReading.readError(source) != nil
    }

    private func messages(_ diagram: SequenceDiagram) -> [MermaidMessage] {
        var openKinds: [SequenceBlockKind] = []
        func name(_ index: Int) -> String { diagram.participants[index].identifier }
        return diagram.events.map { event in
            switch event {
            case .message(let message):
                return MermaidMessage(type: Self.lineType(message.arrow), from: name(message.sourceIndex), to: name(message.targetIndex), lines: message.text.lines)
            case .note(let note):
                let (first, last) = switch note.placement {
                case .leftOf(let index), .rightOf(let index): (index, index)
                case .over(let first, let last): (first, last)
                }
                return MermaidMessage(type: "NOTE", from: name(first), to: name(last), lines: note.text.lines)
            case .activationStart(let index): return MermaidMessage(type: "ACTIVE_START", from: name(index), to: nil, lines: [])
            case .activationEnd(let index): return MermaidMessage(type: "ACTIVE_END", from: name(index), to: nil, lines: [])
            case .blockStart(let kind, let label):
                openKinds.append(kind)
                return MermaidMessage(type: Self.blockName(kind) + "_START", from: nil, to: nil, lines: label.lines)
            case .blockSection(let label):
                let section = switch openKinds.last {
                case .alternatives: "ALT_ELSE"
                case .parallel: "PAR_AND"
                default: "CRITICAL_OPTION"
                }
                return MermaidMessage(type: section, from: nil, to: nil, lines: label.lines)
            case .blockEnd:
                return MermaidMessage(type: Self.blockName(openKinds.removeLast()) + "_END", from: nil, to: nil, lines: [])
            case .numbering: return MermaidMessage(type: "AUTONUMBER", from: nil, to: nil, lines: [])
            }
        }
    }

    private static func lineType(_ arrow: SequenceArrow) -> String {
        let stroke = arrow.stroke == .solid ? "SOLID" : "DOTTED"
        if arrow.pointsBothWays { return "BIDIRECTIONAL_" + stroke }
        switch arrow.head {
        case .none: return stroke + "_OPEN"
        case .arrow: return stroke
        case .cross: return stroke + "_CROSS"
        case .open: return stroke + "_POINT"
        }
    }

    private static func blockName(_ kind: SequenceBlockKind) -> String {
        switch kind {
        case .loop: "LOOP"
        case .alternatives: "ALT"
        case .optional: "OPT"
        case .parallel: "PAR"
        case .critical: "CRITICAL"
        case .break: "BREAK"
        case .highlight: "RECT"
        }
    }

    private func label(_ diagram: SequenceDiagram, _ identifier: String) -> [String]? {
        diagram.participants.first { participant in participant.identifier == identifier }?.label.lines
    }

    // MARK: when parsing a sequenceDiagram

    func testShouldHandleASequenceDiagramDefinition() throws {
        let diagram = try read("\nsequenceDiagram\nAlice->Bob:Hello Bob, how are you?\nNote right of Bob: Bob thinks\nBob-->Alice: I am good thanks!")
        XCTAssertEqual(label(diagram, "Alice"), ["Alice"])
        let list = messages(diagram)
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list[0].from, "Alice")
        XCTAssertEqual(list[2].from, "Bob")
    }

    func testShouldAllowSequenceNumbersToHaveDecimalsUpToTheHundredthsPlace() {
        XCTAssertFalse(fails("""
                    sequenceDiagram
                    autonumber 10.1 .01
                    Alice->Bob:Hello Bob, how are you?
                    Note right of Bob: Bob thinks
                    Bob-->Alice: I am good thanks!
            """))
        XCTAssertTrue(fails("""
                  sequenceDiagram
                  autonumber 10.001
                  Alice->Bob:Hello Bob, how are you?
            """))
    }

    func testShouldHandleATitleWithAndWithoutAColon() throws {
        for header in ["title: Diagram Title", "title Diagram Title"] {
            let diagram = try read("\nsequenceDiagram\n\(header)\nAlice->Bob:Hello Bob, how are you?\nNote right of Bob: Bob thinks\nBob-->Alice: I am good thanks!")
            XCTAssertEqual(diagram.title, "Diagram Title")
            XCTAssertNil(diagram.accessibilityDescription)
            XCTAssertEqual(messages(diagram).count, 3)
        }
    }

    func testShouldHandleAnAccessibilityTitleAndDescription() throws {
        let diagram = try read("\nsequenceDiagram\ntitle: Diagram Title\naccTitle: This is the title\naccDescr: Accessibility Description\nAlice->Bob:Hello Bob, how are you?\n")
        XCTAssertEqual(diagram.title, "Diagram Title")
        XCTAssertEqual(diagram.accessibilityTitle, "This is the title")
        XCTAssertEqual(diagram.accessibilityDescription, "Accessibility Description")
        let multiline = try read("\nsequenceDiagram\naccTitle: This is the title\naccDescr {\nAccessibility\nDescription\n}\nAlice->Bob:Hello Bob, how are you?\n")
        XCTAssertEqual(multiline.accessibilityDescription, "Accessibility\nDescription")
    }

    func testShouldHandleSpacesDashesAndEqualsInNames() throws {
        let spaced = try read("\nsequenceDiagram\nAlice->Bob:Hello Bob, how are - you?\nBob-->Alice: I am good thanks!")
        XCTAssertEqual(messages(spaced).map(\.from), ["Alice", "Bob"])
        XCTAssertEqual(messages(spaced)[0].lines, ["Hello Bob, how are - you?"])
        let dashed = try read("\nsequenceDiagram\nAlice-in-Wonderland->Bob:Hello Bob, how are - you?\nBob-->Alice-in-Wonderland:I am good thanks!")
        XCTAssertEqual(messages(dashed).map(\.from), ["Alice-in-Wonderland", "Bob"])
        let declared = try read("\nsequenceDiagram\nparticipant Alice-in-Wonderland\nparticipant Bob\nAlice-in-Wonderland->Bob:Hello Bob, how are - you?")
        XCTAssertEqual(declared.participantIdentifiers, ["Alice-in-Wonderland", "Bob"])
        let equals = try read("\nsequenceDiagram\nparticipant Alice=Wonderland\nparticipant Bob\nAlice=Wonderland->Bob:Hello Bob, how are - you?\nBob-->Alice=Wonderland:I am good thanks!")
        XCTAssertEqual(equals.participantIdentifiers, ["Alice=Wonderland", "Bob"])
        XCTAssertEqual(messages(equals).map(\.from), ["Alice=Wonderland", "Bob"])
    }

    func testShouldAliasParticipantsAndActors() throws {
        let participants = try read("\nsequenceDiagram\nparticipant A as Alice\nparticipant B as Bob\nA->B:Hello Bob, how are you?\nB-->A: I am good thanks!")
        XCTAssertEqual(participants.participantIdentifiers, ["A", "B"])
        XCTAssertEqual(label(participants, "A"), ["Alice"])
        XCTAssertEqual(label(participants, "B"), ["Bob"])
        let mixed = try read("""

            sequenceDiagram
              actor Alice as Alice2
              actor Bob
              participant John as John2
              participant Mandy
              Alice->>Bob: Hi Bob
              Bob->>Alice: Hi Alice
              Alice->>John: Hi John
              John->>Mandy: Hi Mandy
              Mandy ->>Joan: Hi Joan
            """)
        XCTAssertEqual(mixed.participantIdentifiers, ["Alice", "Bob", "John", "Mandy", "Joan"])
        XCTAssertEqual(label(mixed, "Alice"), ["Alice2"])
        XCTAssertEqual(mixed.participants.map(\.kind), [.actor, .actor, .participant, .participant, .participant])
        XCTAssertEqual(messages(mixed).count, 5)
        XCTAssertEqual(messages(mixed)[4].to, "Joan")
        let actors = try read("\nsequenceDiagram\nactor A as Alice\nactor B as Bob\nA->B:Hello Bob, how are you?\nB-->A: I am good thanks!")
        XCTAssertEqual(actors.participants.map(\.label), [DiagramLabel("Alice"), DiagramLabel("Bob")])
    }

    func testShouldHandleEachKindOfMessage() throws {
        let cases = [("-x", "SOLID_CROSS"), ("--x", "DOTTED_CROSS"), ("-)", "SOLID_POINT"), ("--)", "DOTTED_POINT"), ("->>", "SOLID"),
                     ("-->>", "DOTTED"), ("<<->>", "BIDIRECTIONAL_SOLID"), ("<<-->>", "BIDIRECTIONAL_DOTTED")]
        for (arrow, type) in cases {
            let diagram = try read("\nsequenceDiagram\nAlice\(arrow)Bob:Hello Bob, how are you?")
            XCTAssertEqual(label(diagram, "Bob"), ["Bob"])
            XCTAssertEqual(messages(diagram).map(\.type), [type], arrow)
        }
    }

    func testShouldHandleActorActivation() throws {
        let explicit = try read("""

            sequenceDiagram
            Alice-->>Bob:Hello Bob, how are you?
            activate Bob
            Bob-->>Alice:Hello Alice, I'm fine and  you?
            deactivate Bob
            """)
        XCTAssertEqual(messages(explicit).map(\.type), ["DOTTED", "ACTIVE_START", "DOTTED", "ACTIVE_END"])
        XCTAssertEqual(messages(explicit)[1].from, "Bob")
        XCTAssertEqual(messages(explicit)[3].from, "Bob")
        let oneLine = try read("\n    sequenceDiagram\n    Alice-->>+Bob:Hello Bob, how are you?\n    Bob-->>- Alice:Hello Alice, I'm fine and  you?")
        XCTAssertEqual(messages(oneLine).map(\.type), ["DOTTED", "ACTIVE_START", "DOTTED", "ACTIVE_END"])
        XCTAssertEqual(messages(oneLine)[3].from, "Bob")
    }

    func testShouldHandleStackedActivations() throws {
        let diagram = try read("""

                  sequenceDiagram
                  Alice-->>+Bob:Hello Bob, how are you?
                  Bob-->>+Carol:Carol, let me introduce Alice?
                  Bob-->>- Alice:Hello Alice, please meet Carol?
                  Carol->>- Bob:Oh Bob, I'm so happy to be here!
            """)
        let list = messages(diagram)
        XCTAssertEqual(list.count, 8)
        XCTAssertEqual(list[1].type, "ACTIVE_START")
        XCTAssertEqual(list[1].from, "Bob")
        XCTAssertEqual(list[3].from, "Carol")
        XCTAssertEqual(list[5].type, "ACTIVE_END")
        XCTAssertEqual(list[5].from, "Bob")
        XCTAssertEqual(list[7].from, "Carol")
    }

    func testShouldFailWhenDeactivatingAnInactiveParticipant() {
        XCTAssertTrue(fails("""

                  sequenceDiagram
                  participant user as End User
                  participant Server as Server
                  participant System as System
                  participant System2 as System2

                  user->>+Server: Test
                  user->>+Server: Test2
                  user->>System: Test
                  Server->>-user: Test
                  Server->>-user: Test2

                  %% The following deactivation of Server will fail
                  Server->>-user: Test3
            """))
    }

    func testShouldHandleCommentsNewLinesSemicolonsAndLeadingSpaces() throws {
        let sources = [
            "\n      sequenceDiagram\n      Alice->Bob: Hello Bob, how are you?\n      %% Comment\n      Note right of Bob: Bob thinks\n      Bob-->Alice: I am good thanks!",
            "\n      sequenceDiagram\n      Alice->Bob: Hello Bob, how are you?\n\n      %% Comment\n      Note right of Bob: Bob thinks\n      Bob-->Alice: I am good thanks!\n      ",
            "\nsequenceDiagram;Alice->Bob: Hello Bob, how are you?;Note right of Bob: Bob thinks;Bob-->Alice: I am good thanks!;",
            "\nsequenceDiagram\n Alice->Bob: Hello Bob, how are you?\n\n%% Comment\nNote right of Bob: Bob thinks\nBob-->Alice: I am good thanks!",
        ]
        for source in sources {
            let list = messages(try read(source))
            XCTAssertEqual(list.count, 3, source)
            XCTAssertEqual(list.first?.from, "Alice", source)
            XCTAssertEqual(list.last?.from, "Bob", source)
        }
    }

    func testShouldHandleDifferentLineBreaks() throws {
        // `<br \t/>`, the spec's fourth spelling, is not one of the breaks the package's label decoder reads.
        let diagram = try read("""

            sequenceDiagram
            participant 1 as multiline<br>text
            participant 2 as multiline<br/>text
            participant 3 as multiline<br />text
            1->>2: multiline<br>text
            note right of 2: multiline<br>text
            2->>3: multiline<br/>text
            note right of 3: multiline<br/>text
            3->>1: multiline<br />text
            note right of 1: multiline<br />text

            """)
        for identifier in ["1", "2", "3"] { XCTAssertEqual(label(diagram, identifier), ["multiline", "text"]) }
        XCTAssertTrue(messages(diagram).allSatisfy { message in message.lines == ["multiline", "text"] })
    }

    func testShouldHandleNotesAndMessagesWithAndWithoutWrap() throws {
        let unwrapped = try read("""

            sequenceDiagram
            participant 1
            participant 2
            participant 3
            1->>2: single-line text
            note right of 2: single-line text
            2->>3:nowrap: single-line text
            note right of 3:nowrap: single-line text

            """)
        XCTAssertTrue(messages(unwrapped).allSatisfy { message in message.lines == ["single-line text"] })
        let wrapped = try read("\nsequenceDiagram\nparticipant 1\nparticipant 2\n1->>2:wrap: single-line text\nnote right of 2:wrap: single-line text\n")
        XCTAssertEqual(wrapped.messages.map(\.wrapsText), [true])
        XCTAssertEqual(messages(wrapped).map(\.lines), [["single-line text"], ["single-line text"]])
        XCTAssertFalse(unwrapped.messages.contains(where: \.wrapsText))
    }

    func testShouldHandleNotesOverOneAndSeveralActors() throws {
        let single = messages(try read("\nsequenceDiagram\nAlice->Bob: Hello Bob, how are you?\nNote over Bob: Bob thinks\n"))
        XCTAssertEqual(single[1].from, "Bob")
        XCTAssertEqual(single[1].to, "Bob")
        let several = messages(try read("\nsequenceDiagram\nAlice->Bob: Hello Bob, how are you?\nNote over Alice,Bob: confusion\nNote over Bob,Alice: resolution\n"))
        XCTAssertEqual([several[1].from, several[1].to, several[2].from, several[2].to], ["Alice", "Bob", "Bob", "Alice"])
    }

    func testShouldHandleLoopOptAltCriticalBreakAndParStatements() throws {
        let loop = try read("\nsequenceDiagram\nAlice->Bob: Hello Bob, how are you?\n\n%% Comment\nNote right of Bob: Bob thinks\nloop Multiple happy responses\n\nBob-->Alice: I am good thanks!\nend")
        XCTAssertEqual(messages(loop).count, 5)
        let alt = try read("""

            sequenceDiagram
            Alice->Bob: Hello Bob, how are you?

            %% Comment
            Note right of Bob: Bob thinks
            alt isWell

            Bob-->Alice: I am good thanks!
            else isSick
            Bob-->Alice: Feel sick...
            else default
            Bob-->Alice: :-)
            end
            """)
        XCTAssertEqual(messages(alt).map(\.type), ["SOLID_OPEN", "NOTE", "ALT_START", "DOTTED_OPEN", "ALT_ELSE", "DOTTED_OPEN", "ALT_ELSE", "DOTTED_OPEN", "ALT_END"])
        XCTAssertEqual(messages(alt)[7].lines, [":-)"])
        let critical = try read("""

            sequenceDiagram
                critical Establish a connection to the DB
                    Service-->DB: connect
                option Network timeout
                    Service-->Service: Log error
                option Credentials rejected
                    Service-->Service: Log different error
                end
            """)
        XCTAssertEqual(messages(critical).map(\.type),
                       ["CRITICAL_START", "DOTTED_OPEN", "CRITICAL_OPTION", "DOTTED_OPEN", "CRITICAL_OPTION", "DOTTED_OPEN", "CRITICAL_END"])
        let breaking = try read("""

            sequenceDiagram
                Consumer-->API: Book something
                API-->BookingService: Start booking process
                break when the booking process fails
                    API-->Consumer: show failure
                end
                API-->BillingService: Start billing process
            """)
        XCTAssertEqual(messages(breaking).map(\.type), ["DOTTED_OPEN", "DOTTED_OPEN", "BREAK_START", "DOTTED_OPEN", "BREAK_END", "DOTTED_OPEN"])
        let parallel = try read("""

            sequenceDiagram
            par Parallel one
            Alice->>Bob: Hello Bob, how are you?
            Bob-->>Alice: I am good thanks!
            and Parallel two
            Alice->>Bob: Are you OK?
            Bob-->>Alice: Fine!
            and Parallel three
            Alice->>Bob: What do you think about it?
            Bob-->>Alice: It's good!
            end
            """)
        XCTAssertEqual(messages(parallel).count, 10)
        XCTAssertEqual(messages(parallel)[0].lines, ["Parallel one"])
        let overlapping = try read("\nsequenceDiagram\npar_over Parallel overlap\nAlice ->> Bob: Message\nNote left of Alice: Alice note\nNote right of Bob: Bob note\nend")
        XCTAssertEqual(messages(overlapping).count, 5)
        XCTAssertEqual(messages(overlapping)[0].lines, ["Parallel overlap"])
        XCTAssertEqual(messages(overlapping).dropFirst().prefix(3).map(\.from), ["Alice", "Alice", "Bob"])
    }

    func testShouldAddRectsAroundSequencesNestedOrNot() throws {
        let nested = try read("""

                  sequenceDiagram
                    Alice->Bob: Hello Bob, how are you?
                    %% Comment
                    rect rgb(200, 255, 200)
                    rect rgb(0, 0, 0)
                    Note right of Bob: Bob thinks
                    end
                    Bob-->Alice: I am good thanks
                    end
            """)
        XCTAssertEqual(messages(nested).map(\.type), ["SOLID_OPEN", "RECT_START", "RECT_START", "NOTE", "RECT_END", "DOTTED_OPEN", "RECT_END"])
        XCTAssertEqual(nested.events[1], .blockStart(kind: .highlight(SequenceHighlightColor(red: 200.0 / 255, green: 1, blue: 200.0 / 255)), label: DiagramLabel(lines: [])))
        XCTAssertEqual(nested.events[2], .blockStart(kind: .highlight(SequenceHighlightColor(red: 0, green: 0, blue: 0)), label: DiagramLabel(lines: [])))
    }

    func testShouldHandleSpecialCharactersInSignalsNotesAndBlocks() throws {
        let signal = messages(try read("sequenceDiagram\nAlice->Bob: -:<>,;# comment"))
        XCTAssertEqual(signal[0].lines, ["-:<>,"])
        let note = messages(try read("\nsequenceDiagram\nAlice->Bob: Hello Bob, how are you?\nNote right of Bob: -:<>,;# comment"))
        XCTAssertEqual(note[1].lines, ["-:<>,"])
        for (keyword, section) in [("loop", nil), ("opt", nil), ("alt", "else"), ("par", "and")] {
            let sectionLines = section.map { word in "\n\(word) ,<>:-#; comment\nBob-->Alice: I am good thanks!" } ?? ""
            let list = messages(try read("\nsequenceDiagram\nAlice->Bob: Hello Bob, how are you?\n\(keyword) -:<>,;# comment\nBob-->Alice: I am good thanks!\(sectionLines)\nend"))
            XCTAssertEqual(list[1].lines, ["-:<>,"], keyword)
            if section != nil { XCTAssertEqual(list[3].lines, [",<>:-"], keyword) }
        }
    }

    func testShouldHandleBlocksWithoutLabels() throws {
        let loop = messages(try read("\nsequenceDiagram\nAlice->Bob: Hello Bob, how are you?\nloop\nBob-->Alice: I am good thanks!\nend"))
        XCTAssertEqual(loop[1].lines, [""])
        XCTAssertEqual(loop[2].lines, ["I am good thanks!"])
        let opt = messages(try read("\nsequenceDiagram\nAlice->Bob: Hello Bob, how are you?\nopt # comment\nBob-->Alice: I am good thanks!\nend"))
        XCTAssertEqual(opt[1].lines, [""])
        for (keyword, section) in [("alt", "else"), ("par", "and")] {
            let list = messages(try read("\nsequenceDiagram\nAlice->Bob: Hello Bob, how are you?\n\(keyword);Bob-->Alice: I am good thanks!\n\(section) # comment\nBob-->Alice: I am good thanks!\nend"))
            XCTAssertEqual(list[1].lines, [""], keyword)
            XCTAssertEqual(list[2].lines, ["I am good thanks!"], keyword)
            XCTAssertEqual(list[3].lines, [""], keyword)
        }
    }

    func testShouldUseLinkAsADeclaredOrImplicitMessageEndpoint() throws {
        for identifier in ["Link", "link", "LINK"] {
            let declared = try read("\nsequenceDiagram\nparticipant A\nparticipant \(identifier) as Channel\nA->>\(identifier): message\n\(identifier)-->>A: reply\n")
            XCTAssertEqual(declared.participantIdentifiers, ["A", identifier])
            XCTAssertEqual(label(declared, identifier), ["Channel"])
            XCTAssertEqual(messages(declared).map(\.lines), [["message"], ["reply"]])
            let implicit = try read("\nsequenceDiagram\n\(identifier)->>A: message\nA-->>\(identifier): reply\n")
            XCTAssertEqual(implicit.participantIdentifiers, [identifier, "A"])
        }
    }

    func testMenusBoxesCreationAndDestructionAreReadAndNotLaidOut() throws {
        let menus = try read("""

            sequenceDiagram
            participant a as Alice
            participant b as Bob
            participant c as Charlie
            links a: { "Repo": "https://repo.contoso.com/", "Dashboard": "https://dashboard.contoso.com/" }
            link a: Tests @ https://tests.contoso.com/?svc=alice@contoso.com
            properties b: {"class": "external-service-actor", "icon": "@computer"}
            """)
        XCTAssertEqual(menus.statementsNotLaidOut, [.participantMenu])
        let box = try read("\nsequenceDiagram\nbox green Group 1\nparticipant a as Alice\nparticipant b as Bob\nend\nparticipant c as Charlie\n")
        XCTAssertEqual(box.statementsNotLaidOut, [.box])
        XCTAssertEqual(box.participantIdentifiers, ["a", "b", "c"])
        let lifetimes = try read("""

              sequenceDiagram
              a ->>b: Hello Bob?
              create participant c
              b ->>c: Hello c!
              c ->> b: Hello b?
              destroy c
              b ->> c : Bye c !
            """)
        XCTAssertEqual(lifetimes.statementsNotLaidOut, [.participantCreation, .participantDestruction])
        XCTAssertEqual(lifetimes.participantIdentifiers, ["a", "b", "c"])
    }

    func testShouldHandleTheSameActorDeclaredSeveralTimes() throws {
        XCTAssertEqual(try read("\nsequenceDiagram\nparticipant Alice\nparticipant Alice\nparticipant Alice\n").participantIdentifiers, ["Alice"])
    }

    func testShouldAllowObjectPropertyNamesAsActorNames() throws {
        for name in ["__proto__", "constructor"] {
            XCTAssertEqual(try read("\nsequenceDiagram\n\(name)-->>A: Hello, how are you?").participantIdentifiers, [name, "A"])
        }
    }

    // MARK: sequence db class

    func testShouldParseAMessageWithATrailingColonButNoContent() throws {
        let list = messages(try read("\nsequenceDiagram\nAlice->>Bob:\nBob->>Alice:Got it!\n"))
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0], MermaidMessage(type: "SOLID", from: "Alice", to: "Bob", lines: [""]))
    }

    func testHalfArrowsAndCentralConnectionsAreReadAndNotLaidOut() throws {
        let halfArrows = try read("""

                sequenceDiagram
                actor Bob
                actor Alice
                    Bob -|\\ Alice: Hello Alice, how are you?
                    Bob -|/ Alice: Hello Alice, how are you?
                    Bob -// Alice: Hello Alice, how are you?
                    Bob -\\\\ Alice: Hello Alice, how are you?

                    Bob \\|- Alice: Hello Alice, how are you?
                    Bob /|- Alice: Hello Alice, how are you?
                    Bob //- Alice: Hello Alice, how are you?
                    Bob \\\\- Alice: Hello Alice, how are you?
            """)
        XCTAssertEqual(halfArrows.statementsNotLaidOut, [.halfArrow])
        XCTAssertEqual(halfArrows.participantIdentifiers, ["Bob", "Alice"])
        let central = try read("\n    sequenceDiagram\n    actor Bob\n    actor Alice\n      Alice ()<<->>() Bob: hey?\n    ")
        XCTAssertEqual(central.statementsNotLaidOut, [.centralConnection])
        XCTAssertEqual(messages(central).map(\.type), ["BIDIRECTIONAL_SOLID"])
    }

    // MARK: extended participant syntax

    func testParticipantAttributesAreReadAndNotLaidOut() throws {
        let diagram = try read("""

              sequenceDiagram
                  participant Alice@{ "type" : "database" }
                  participant Carl@{ type: "database" }
                  participant Harry @{ "type" : "database" }
                  actor kebab-case@{ "type" : "control" } as Kebab-Cased
                  participant web-ui@{ "type" : "entity" } as Web UI
                  actor A@{ "type" : "database" } AS Database Server
                  Alice->>+Carl: Hi Carl
            """)
        XCTAssertEqual(diagram.statementsNotLaidOut, [.participantAttributes])
        XCTAssertEqual(diagram.participantIdentifiers, ["Alice", "Carl", "Harry", "kebab-case", "web-ui", "A"])
        XCTAssertEqual(diagram.participants.map(\.label.lines), [["Alice"], ["Carl"], ["Harry"], ["Kebab-Cased"], ["Web UI"], ["Database Server"]])
        XCTAssertEqual(messages(diagram).count, 2)
    }

    func testShouldFailForAttributesMissingTheirClosingBrace() {
        XCTAssertTrue(fails("\n    sequenceDiagram\n      participant E@{ \"type\": \"entity\"\n      E ->> E: process\n  "))
        // Mermaid also refuses attributes that are not valid YAML; Graphite does not read their contents, and the
        // diagram stays code because its attributes are not laid out.
        XCTAssertEqual(try read("sequenceDiagram\nparticipant D@{ \"type: \"entity\" }").statementsNotLaidOut, [.participantAttributes])
    }

    func testShouldFailWhenAnAliasConflictsOrHasNoSpace() {
        XCTAssertTrue(fails("\n        sequenceDiagram\n        participant SAS MyServiceWithMoreThan20Chars <br> service decription\n       "))
        XCTAssertTrue(fails("\n          sequenceDiagram\n          participant X_AutoPublishable asAAAAAAAAAAAAA:AAAAAAAAAAAAA\n        "))
    }
}
