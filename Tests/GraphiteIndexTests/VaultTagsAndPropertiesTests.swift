import XCTest
@testable import GraphiteIndex
import GraphiteCore

final class VaultTagsAndPropertiesTests: XCTestCase {
    private var directory: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        try await index.update([
            IndexedFile(path: try VaultPath("Algebra.md"), size: 1, modified: .now,
                        markdown: "---\nstatus: draft\ndue: 2026-10-01\ntags: [course/math]\n---\n#course/math/linear and #exam"),
            IndexedFile(path: try VaultPath("Physics.md"), size: 1, modified: .now,
                        markdown: "---\nStatus: done\nrating: 4\n---\n#course/physics"),
            IndexedFile(path: try VaultPath("Diary.md"), size: 1, modified: .now,
                        markdown: "---\nstatus:\nmood: calm\n---\n#Course and #exam"),
        ], generation: "test")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testNestedTagCountsCountEachNoteOncePerLevel() async throws {
        let counts = try await index.nestedTagCounts()
        let countByTag = Dictionary(uniqueKeysWithValues: counts.map { count in (count.tag.lowercased(), count.fileCount) })
        XCTAssertEqual(countByTag, [
            "course": 3, "course/math": 1, "course/math/linear": 1, "course/physics": 1, "exam": 2,
        ], "Algebra has course/math twice (property and text) and counts once.")
    }

    func testPropertyUsagesIgnoreCapitalsAndKeepSampleValues() async throws {
        let usages = try await index.propertyUsages()
        let usageByKey = Dictionary(uniqueKeysWithValues: usages.map { usage in (usage.key.lowercased(), usage) })
        XCTAssertEqual(Set(usageByKey.keys), ["status", "due", "tags", "rating", "mood"])
        XCTAssertEqual(usageByKey["status"]?.fileCount, 3, "status and Status are one property.")
        XCTAssertEqual(usageByKey["status"]?.sampleValues.count, 3)
        XCTAssertEqual(NoteProperties.type(ofKey: "due", sampleValues: usageByKey["due"]?.sampleValues ?? [], declaredTypes: [:]), .date)
        XCTAssertEqual(NoteProperties.type(ofKey: "rating", sampleValues: usageByKey["rating"]?.sampleValues ?? [], declaredTypes: [:]), .number)

        let statusPaths = try await index.paths(withPropertyKey: "STATUS").map(\.rawValue)
        XCTAssertEqual(statusPaths, ["Algebra.md", "Diary.md", "Physics.md"])
        let moodPaths = try await index.paths(withPropertyKey: "mood").map(\.rawValue)
        XCTAssertEqual(moodPaths, ["Diary.md"])
    }
}

final class VaultGraphTests: XCTestCase {
    func testGraphResolvesLinksAsEverywhereElse() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        func file(_ path: String, _ markdown: String?) throws -> IndexedFile {
            IndexedFile(path: try VaultPath(path), size: 1, modified: .now, markdown: markdown)
        }
        try await index.update([
            try file("Course/Lecture.md", "---\nrelated: \"[[Sampling]]\"\n---\n[[Sampling#Aliasing]] ![[figure.png]] [md](../Summary.md) [[Missing]] [[Twin]] [site](https://example.com) #course"),
            try file("Course/Sampling.md", "Back to [[Lecture]]."),
            try file("Summary.md", "Nothing links out."),
            try file("Course/figure.png", nil),
            try file("A/Twin.md", ""), try file("B/Twin.md", ""),
        ], generation: "test")
        let graph = try await index.linkGraph()
        XCTAssertEqual(Set(graph.edges), [
            GraphEdge(source: "Course/Lecture.md", target: "Course/Sampling.md"),
            GraphEdge(source: "Course/Lecture.md", target: "Course/figure.png"),
            GraphEdge(source: "Course/Lecture.md", target: "Summary.md"),
            GraphEdge(source: "Course/Lecture.md", target: "Missing"),
            GraphEdge(source: "Course/Lecture.md", target: "#course"),
            GraphEdge(source: "Course/Sampling.md", target: "Course/Lecture.md"),
        ], "The property link and the text link are one edge; the ambiguous Twin and the web link are left out.")
        XCTAssertEqual(graph.nodes.first { node in node.id == "Course/figure.png" }?.kind, .attachment)
        XCTAssertEqual(graph.nodes.first { node in node.id == "Missing" }?.kind, .unresolved)
        XCTAssertEqual(graph.nodes.filter { node in node.kind == .note }.count, 5)
    }
}

final class GraphLinkResolverTests: XCTestCase {
    /// The graph resolves links in memory; it must agree with the index everywhere.
    func testResolvesExactlyAsTheIndexDoes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let names = ["Course/Lecture.md", "Course/lecture notes.md", "Archive/Lecture.md", "Homework 2.1.md", "Books/Étude.md", "covers/Book cover.png",
                     "Other/covers/Book cover.png", "Deep/Nested/Plan.MD", "Twin/One.md", "Twin/one.md", "Alias target.md", "Summary.md", "ÄPFEL.md"]
        var files: [IndexedFile] = []
        for name in names {
            let markdown: String? = name.hasSuffix("Alias target.md") ? "---\naliases: [Nickname, SHOUT]\n---\n" : (name.hasSuffix(".png") ? nil : "")
            files.append(IndexedFile(path: try VaultPath(name), size: 1, modified: .now, markdown: markdown))
        }
        try await index.update(files, generation: "test")
        let resolver = try await index.graphLinkResolver()
        let sources = [try VaultPath("Course/Index.md"), try VaultPath("Top.md"), try VaultPath("Deep/Nested/Here.md")]
        let targets = ["Lecture", "lecture", "LECTURE", "Lecture.md", "Course/Lecture", "Archive/Lecture", "lecture notes", "Homework 2.1", "Étude", "e\u{301}tude",
                       "covers/Book cover.png", "COVERS/book cover.png", "Book cover.png", "Plan", "plan.md", "Plan.MD", "One", "one", "Nickname", "nickname",
                       "shout", "Summary#Heading", "#Heading", "Missing", "äpfel", "ÄPFEL", "../Summary.md", "Nested/Plan.MD", ""]
        for source in sources {
            for target in targets {
                for isWiki in [true, false] {
                    let expected = try await index.resolve(target, from: source, isWiki: isWiki).map(\.rawValue)
                    XCTAssertEqual(resolver.resolve(target, from: source, isWiki: isWiki), expected, "\(target) from \(source.rawValue), isWiki \(isWiki)")
                }
            }
        }
    }
}
