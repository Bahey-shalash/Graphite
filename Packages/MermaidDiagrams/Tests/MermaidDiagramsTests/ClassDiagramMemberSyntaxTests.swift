import XCTest
@testable import MermaidDiagrams

/// Members split as Mermaid's `ClassMember` splits them, on the inputs of Mermaid 12.1.0's `classTypes.spec.ts`.
final class ClassDiagramMemberSyntaxTests: XCTestCase {
    private func shown(_ text: String) -> (text: String, classifier: ClassDiagramMemberClassifier, isMethod: Bool) {
        let (member, isMethod) = ClassDiagramMemberSyntax.member(from: text)
        return (member.text, member.classifier, isMethod)
    }

    func testMethodsKeepTheirVisibilityAndLoseTheirClassifierMark() {
        let methods = ["getTime()", "getTime(int)", "getTime(int count)", "getTime(count int)", "getTimes(List~T~)", "getTimes(List~T~, List~OT~)",
                       "getTimetableList(List~List~T~~)", "getTimes(List~K, V~)"]
        let expected = ["getTime()", "getTime(int)", "getTime(int count)", "getTime(count int)", "getTimes(List<T>)", "getTimes(List<T>, List<OT>)",
                        "getTimetableList(List<List<T>>)", "getTimes(List<K, V>)"]
        for (method, text) in zip(methods, expected) {
            for visibility in ["", "+", "-", "#", "~"] {
                let member = shown(visibility + method)
                XCTAssertEqual(member.text, visibility + text, visibility + method)
                XCTAssertTrue(member.isMethod, visibility + method)
                XCTAssertEqual(member.classifier, .plain, visibility + method)
            }
            XCTAssertEqual(shown(method + "$").text, text, method)
            XCTAssertEqual(shown(method + "$").classifier, .static, method)
            XCTAssertEqual(shown(method + "*").classifier, .abstract, method)
        }
    }

    func testAReturnTypeFollowsAColonAndMayCarryTheClassifier() {
        XCTAssertEqual(shown("getTimes() List~T~").text, "getTimes() : List<T>")
        XCTAssertEqual(shown("+getTimetableList() List~List~T~~").text, "+getTimetableList() : List<List<T>>")
        XCTAssertEqual(shown("getTimes() List~T~$").text, "getTimes() : List<T>")
        XCTAssertEqual(shown("getTimes() List~T~$").classifier, .static)
        XCTAssertEqual(shown("getTimes() List~T~*").classifier, .abstract)
        XCTAssertEqual(shown("getObjects() Object[]").text, "getObjects() : Object[]")
        let generic = shown("getTime~T~(this T, int seconds)$ DateTime")
        XCTAssertEqual(generic.text, "getTime<T>(this T, int seconds) : DateTime")
        XCTAssertEqual(generic.classifier, .static)
    }

    func testAttributesKeepTheirVisibilityAndLoseTheirClassifierMark() {
        for visibility in ["", "+", "#", "-", "~"] {
            XCTAssertEqual(shown(visibility + "name String").text, visibility + "name String")
            XCTAssertFalse(shown(visibility + "name String").isMethod)
        }
        XCTAssertEqual(shown("name String$").text, "name String")
        XCTAssertEqual(shown("name String$").classifier, .static)
        XCTAssertEqual(shown("name String*").classifier, .abstract)
        XCTAssertEqual(shown("std::map ~int,string~ pMap;").text, "std::map <int,string> pMap;")
        XCTAssertEqual(shown("-idCard : IdCard").text, "-idCard : IdCard")
    }

    func testTextWithAClosingButNoOpeningParenthesisIsAnAttribute() {
        XCTAssertFalse(shown("run)").isMethod)
        XCTAssertEqual(shown("run)").text, "run)")
        XCTAssertFalse(shown("(x)").isMethod, "The opening parenthesis must come after the first character")
    }

    func testANameKeepsOneSpaceAfterTheVisibilityMarkAndEntitiesAreRead() {
        XCTAssertEqual(shown("+ getName()").text, "+ getName()")
        XCTAssertEqual(shown("+amp #38; #lt;tag#gt;").text, "+amp & <tag>")
        XCTAssertEqual(shown("+x <b>bold</b>").text, "+x <b>bold</b>", "Members are shown as written, without markup")
        XCTAssertEqual(shown("+op(a *b, c *d)").text, "+op(a *b, c *d)")
    }

    func testTildesPairFromTheOutsideIn() {
        XCTAssertEqual(ClassDiagramMemberSyntax.angleBracketed("List~int~"), "List<int>")
        XCTAssertEqual(ClassDiagramMemberSyntax.angleBracketed("Map~K, V~"), "Map<K, V>")
        XCTAssertEqual(ClassDiagramMemberSyntax.angleBracketed("~T~~"), "~T<>", "A leading odd tilde stays")
        XCTAssertEqual(ClassDiagramMemberSyntax.angleBracketed("one~"), "one~")
        XCTAssertEqual(ClassDiagramMemberSyntax.angleBracketed("plain"), "plain")
    }
}
