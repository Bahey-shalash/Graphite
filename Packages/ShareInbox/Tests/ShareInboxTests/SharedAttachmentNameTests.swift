import XCTest
@testable import ShareInbox

final class SharedAttachmentNameTests: XCTestCase {
    private var zurich: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Zurich") ?? .gmt
        return calendar
    }

    func testAFileSharedWithoutANameIsNamedForTheTimeItWasShared() {
        let name = SharedAttachmentName.fileName(suggestedName: nil, fileExtension: "jpeg", unnamedStem: "Shared image",
                                                 sharedAt: Date(timeIntervalSince1970: 1_792_000_000), calendar: zurich)
        XCTAssertEqual(name, "Shared image 20261014194640.jpeg")
    }

    func testTheYearIsGregorianWhateverTheDeviceCalendar() {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = .gmt
        let name = SharedAttachmentName.fileName(suggestedName: "", fileExtension: "png", unnamedStem: "Shared image",
                                                 sharedAt: Date(timeIntervalSince1970: 1_792_000_000), calendar: japanese)
        XCTAssertEqual(name, "Shared image 20261014174640.png")
    }

    func testASuggestedNameGetsTheExtensionOnlyWhenItLacksIt() {
        let calendar = zurich
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(SharedAttachmentName.fileName(suggestedName: "Paper", fileExtension: "pdf", unnamedStem: "Shared file", sharedAt: date, calendar: calendar), "Paper.pdf")
        XCTAssertEqual(SharedAttachmentName.fileName(suggestedName: "Paper.PDF", fileExtension: "pdf", unnamedStem: "Shared file", sharedAt: date, calendar: calendar), "Paper.PDF")
        XCTAssertEqual(SharedAttachmentName.fileName(suggestedName: "Notes", fileExtension: nil, unnamedStem: "Shared file", sharedAt: date, calendar: calendar), "Notes")
    }

    func testAPlainFileNameHasNoFolderColonControlOrLeadingDot() {
        XCTAssertEqual(SharedAttachmentName.plainFileName("../../etc/passwd"), "passwd")
        XCTAssertEqual(SharedAttachmentName.plainFileName("Time: 10:30.txt"), "Time 1030.txt")
        XCTAssertEqual(SharedAttachmentName.plainFileName(" .env "), "env")
        XCTAssertEqual(SharedAttachmentName.plainFileName("Line\nbreak.png"), "Linebreak.png")
        XCTAssertEqual(SharedAttachmentName.plainFileName("..."), "Shared file")
        XCTAssertEqual(SharedAttachmentName.plainFileName("Ünïcode café.jpeg"), "Ünïcode café.jpeg")
    }

    func testOnlyPlainNamesAreAccepted() {
        XCTAssertTrue(SharedAttachmentName.isPlainFileName("Board 2.jpeg"))
        XCTAssertFalse(SharedAttachmentName.isPlainFileName("Folder/Board.jpeg"))
        XCTAssertFalse(SharedAttachmentName.isPlainFileName(".."))
        XCTAssertFalse(SharedAttachmentName.isPlainFileName(""))
    }

    func testAFreeNameIsNumberedFromTwo() {
        XCTAssertEqual(SharedAttachmentName.freeName(for: "Photo.jpeg", avoiding: []), "Photo.jpeg")
        XCTAssertEqual(SharedAttachmentName.freeName(for: "Photo.jpeg", avoiding: ["Photo.jpeg", "Photo 2.jpeg"]), "Photo 3.jpeg")
        XCTAssertEqual(SharedAttachmentName.freeName(for: "README", avoiding: ["README"]), "README 2")
    }
}
