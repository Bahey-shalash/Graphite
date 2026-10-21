// swift-tools-version: 6.0
import PackageDescription

// Reads Goodnotes (`.goodnotes`) and Notability (`.note`) notebooks page by page and plans each page as plain values
// (page size, background, strokes, pictures, recordings) with a report of what it simplified or left out.
// Foundation, CoreGraphics and zlib only: it knows no app and writes no file.
let package = Package(
    name: "NotebookImport",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "NotebookImport", targets: ["NotebookImport"])
    ],
    targets: [
        .target(name: "NotebookImport"),
        .testTarget(name: "NotebookImportTests", dependencies: ["NotebookImport"])
    ]
)
