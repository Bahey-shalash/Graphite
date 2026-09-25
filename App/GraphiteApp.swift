import SwiftUI
import GraphiteUI

@main
struct GraphiteApp: App {
    var body: some Scene {
        #if os(macOS)
        // A single window. Each window builds its own workspace, which reopens the last
        // vault with its own index on the same cache file, recorder and autosave; two of
        // them would fail each other's index writes ("database is locked") and delete
        // each other's rows on rescan. A macOS WindowGroup also opens more windows from
        // the window tab bar even though the New Window menu item is replaced.
        Window("Graphite", id: "main") { GraphiteRootView() }
            .defaultSize(width: 1200, height: 820)
            .commands { GraphiteCommands() }
        #else
        // iPadOS keeps this to one scene: Info.plist sets UIApplicationSupportsMultipleScenes to false.
        WindowGroup { GraphiteRootView() }
            .defaultSize(width: 1200, height: 820)
            .commands { GraphiteCommands() }
        #endif
    }
}
