// swift-tools-version: 6.0
import PackageDescription

// Reads Mermaid diagram text, lays the diagram out and draws it into a Core Graphics context, in Pele's visual style.
// Foundation, CoreGraphics and CoreText only: it knows no app, and reads and writes no file.
let package = Package(
    name: "MermaidDiagrams",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "MermaidDiagrams", targets: ["MermaidDiagrams"])
    ],
    targets: [
        .target(name: "MermaidDiagrams"),
        // Times reading, layout and drawing on the inputs of Pele's benchmark (`swift run -c release MermaidDiagramsBenchmark`);
        // its resources are the flowchart examples of Mermaid's documentation, as Pele's benchmark collects them.
        .executableTarget(name: "MermaidDiagramsBenchmark", dependencies: ["MermaidDiagrams"], resources: [.copy("Resources")]),
        .testTarget(name: "MermaidDiagramsTests", dependencies: ["MermaidDiagrams", "MermaidDiagramsBenchmark"])
    ]
)
