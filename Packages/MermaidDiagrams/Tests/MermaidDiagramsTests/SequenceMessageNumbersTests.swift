import XCTest
@testable import MermaidDiagrams

final class SequenceMessageNumbersTests: XCTestCase {
    private func numbers(_ body: String) throws -> [String?] {
        let diagram = try SequenceReading.sequence("sequenceDiagram\n" + body)
        return zip(diagram.events, SequenceMessageNumbers(events: diagram.events).numberTexts).compactMap { event, number in
            guard case .message = event else { return nil }
            return .some(number)
        }
    }

    func testMessagesAreNotNumberedUntilAutonumber() throws {
        XCTAssertEqual(try numbers("A->>B: x\nB->>A: y"), [nil, nil])
    }

    func testEveryMessageTakesTheNextNumberEvenWhileNumbersAreOff() throws {
        XCTAssertEqual(try numbers("A->>B: x\nautonumber\nA->>B: x\nautonumber off\nA->>B: x\nautonumber\nA->>B: x"), [nil, "2", nil, "4"])
    }

    func testAStartAndAStepOfUpToTwoDecimalsCountWithoutRounding() throws {
        XCTAssertEqual(try numbers("autonumber 10.01 .01\nA->>B: x\nB->>A: y\nA->>B: z"), ["10.01", "10.02", "10.03"])
        XCTAssertEqual(try numbers("autonumber 10.1 .1\nA->>B: x\nB->>A: y\nA->>B: z"), ["10.1", "10.2", "10.3"])
        XCTAssertEqual(try numbers("autonumber 0.9 0.05\nA->>B: x\nB->>A: y\nA->>B: z"), ["0.9", "0.95", "1"])
    }

    func testAZeroStartOrStepKeepsCountingAsMermaidDoes() throws {
        XCTAssertEqual(try numbers("autonumber 5 2\nA->>B: x\nautonumber 0 0\nA->>B: y"), ["5", "7"])
    }
}
