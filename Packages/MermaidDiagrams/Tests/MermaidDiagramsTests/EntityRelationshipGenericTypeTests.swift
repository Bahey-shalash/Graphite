import XCTest
@testable import MermaidDiagrams

final class EntityRelationshipGenericTypeTests: XCTestCase {
    func testPairsOfTildesBecomeAngleBracketsFromTheOutsideIn() {
        XCTAssertEqual(EntityRelationshipGenericType.angleBracketed("List~int~"), "List<int>")
        XCTAssertEqual(EntityRelationshipGenericType.angleBracketed("List~List~int~~"), "List<List<int>>")
        XCTAssertEqual(EntityRelationshipGenericType.angleBracketed("string"), "string")
    }

    func testTwoPartsWithOneTildeEachPairAcrossTheirComma() {
        XCTAssertEqual(EntityRelationshipGenericType.angleBracketed("Map~K,V~"), "Map<K,V>")
        XCTAssertEqual(EntityRelationshipGenericType.angleBracketed("a~b~,c~d~"), "a<b>,c<d>")
    }

    func testATildeWithoutAPairStays() {
        XCTAssertEqual(EntityRelationshipGenericType.angleBracketed("a~b"), "a~b")
        XCTAssertEqual(EntityRelationshipGenericType.angleBracketed("~a~b~"), "~a<b>")
        XCTAssertEqual(EntityRelationshipGenericType.angleBracketed("x~y,z"), "x~y,z")
    }
}
