import XCTest
@testable import GraphiteCore

final class VaultURITests: XCTestCase {
    private func uri(_ text: String) -> VaultURI? {
        URL(string: text).flatMap(VaultURI.init(url:))
    }

    func testReadsObsidiansActions() {
        XCTAssertEqual(uri("graphite://open?vault=Physics&file=Course%2FLecture%201"), VaultURI(vault: "Physics", action: .open(file: "Course/Lecture 1", path: nil)))
        XCTAssertEqual(uri("obsidian://open?vault=Physics&file=Lecture%201%23Aliasing"), VaultURI(vault: "Physics", action: .open(file: "Lecture 1#Aliasing", path: nil)),
                       "A link copied from Obsidian works as it is.")
        XCTAssertEqual(uri("graphite://open?vault=Physics"), VaultURI(vault: "Physics", action: .open(file: nil, path: nil)))
        XCTAssertEqual(uri("graphite://open?path=%2FUsers%2Fme%2FPhysics%2FLecture.md"), VaultURI(vault: nil, action: .open(file: nil, path: "/Users/me/Physics/Lecture.md")))
        XCTAssertEqual(uri("graphite://search?vault=Physics&query=tag%3A%23exam"), VaultURI(vault: "Physics", action: .search(query: "tag:#exam")))
        XCTAssertEqual(uri("graphite://daily?vault=Physics"), VaultURI(vault: "Physics", action: .daily))
        XCTAssertEqual(uri("GRAPHITE://OPEN?Vault=Physics&FILE=Note"), VaultURI(vault: "Physics", action: .open(file: "Note", path: nil)), "Ignoring capitals.")
        XCTAssertEqual(uri("obsidian:open?vault=Physics&file=Note"), VaultURI(vault: "Physics", action: .open(file: "Note", path: nil)))
        XCTAssertEqual(uri("obsidian://vault/Physics/Course/Lecture%201"), VaultURI(vault: "Physics", action: .open(file: "Course/Lecture 1", path: nil)))
    }

    func testReadsNewNotes() {
        XCTAssertEqual(uri("graphite://new?vault=Inbox&name=Idea&content=Buy%20milk%0Aand%20bread"),
                       VaultURI(vault: "Inbox", action: .new(name: "Idea", file: nil, content: "Buy milk\nand bread", opensNote: true, mode: .unique)))
        XCTAssertEqual(uri("graphite://new?file=Inbox%2FIdea&content=More&append"),
                       VaultURI(vault: nil, action: .new(name: nil, file: "Inbox/Idea", content: "More", opensNote: true, mode: .append)), "A flag without a value is on.")
        XCTAssertEqual(uri("graphite://new?name=Idea&overwrite=true&append=true&silent=true"),
                       VaultURI(vault: nil, action: .new(name: "Idea", file: nil, content: "", opensNote: false, mode: .overwrite)), "Overwrite wins over append.")
        XCTAssertEqual(uri("graphite://new?name=Idea&silent=false"),
                       VaultURI(vault: nil, action: .new(name: "Idea", file: nil, content: "", opensNote: true, mode: .unique)))
    }

    func testAppendsOnALineOfItsOwn() {
        XCTAssertEqual(VaultURI.appending("new", to: "old"), "old\nnew")
        XCTAssertEqual(VaultURI.appending("new", to: "old\n"), "old\nnew")
        XCTAssertEqual(VaultURI.appending("new", to: ""), "new")
        XCTAssertEqual(VaultURI.appending("", to: "old"), "old")
    }

    func testRefusesOtherLinks() {
        XCTAssertNil(uri("https://obsidian.md/open?vault=Physics"))
        XCTAssertNil(uri("graphite://delete?file=Note"))
        XCTAssertNil(uri("graphite://vault"))
    }

    func testWritesLinksAsObsidianDoes() throws {
        XCTAssertEqual(VaultURI.openingLink(to: try VaultPath("Course/Lecture 1.md"), inVaultNamed: "My Physics"),
                       "graphite://open?vault=My%20Physics&file=Course/Lecture%201")
        XCTAssertEqual(VaultURI.openingLink(to: try VaultPath("Media/Figure #2.png"), inVaultNamed: "V"), "graphite://open?vault=V&file=Media/Figure%20%232.png")
        let link = VaultURI.openingLink(to: try VaultPath("Études/Zoë & co?.md"), inVaultNamed: "Café")
        XCTAssertEqual(uri(link), VaultURI(vault: "Café", action: .open(file: "Études/Zoë & co?", path: nil)), "What is written reads back.")
    }
}
