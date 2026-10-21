// swift-tools-version: 6.0
import PackageDescription

// The folder a share extension leaves shared items in for its app, and the list of
// destinations the app publishes for the extension. Foundation only: it knows no app.
let package = Package(
    name: "ShareInbox",
    platforms: [.iOS("27.0"), .macOS("27.0")],
    products: [
        .library(name: "ShareInbox", targets: ["ShareInbox"])
    ],
    targets: [
        .target(name: "ShareInbox"),
        .testTarget(name: "ShareInboxTests", dependencies: ["ShareInbox"])
    ]
)
