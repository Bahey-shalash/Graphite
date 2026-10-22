import Foundation

/// The class diagram inputs: Mermaid's 38 class diagram documentation examples as Pele collects them, the class
/// diagram of Pele's comparison with Mermaid, and hierarchies generated for scale.
enum ClassDiagramCorpus {
    /// The four-class diagram of Pele's comparison with Mermaid (`scripts/bench-mermaid.mjs`).
    static let fourClassDiagram = """
    classDiagram
      class Animal {
        +String name
        +int age
        +eat() void
      }
      class Dog {
        +bark() void
      }
      class Cat {
        +meow() void
      }
      class Bird {
        +bool canFly
        +fly() void
      }
      Animal <|-- Dog
      Animal <|-- Cat
      Animal <|-- Bird
    """

    static func documentationExamples() throws -> [String] {
        guard let location = Bundle.module.url(forResource: "class-docs", withExtension: "json", subdirectory: "Resources") else {
            throw FlowchartCorpus.MissingResource()
        }
        return try JSONDecoder().decode([String].self, from: Data(contentsOf: location))
    }

    /// `classCount` classes, each with two attributes and a method, each but the first inheriting from the one
    /// `fan` places before it, and every fifth composed of the next with cardinalities and text: Graphite's own,
    /// since Pele's benchmark generates no class diagram.
    static func hierarchy(classCount: Int, fan: Int = 3) -> String {
        var source = "classDiagram\n"
        for index in 0..<classCount {
            source += "  class Type\(index) {\n    +String name\(index)\n    -int count\n    +update(int value) bool\n  }\n"
        }
        for index in 1..<classCount { source += "  Type\((index - 1) / fan) <|-- Type\(index)\n" }
        for index in stride(from: 0, to: classCount - 1, by: 5) { source += "  Type\(index) \"1\" *-- \"*\" Type\(index + 1) : holds\n" }
        return source
    }
}
