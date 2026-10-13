import SwiftUI
import GraphiteUI

@main
struct GraphiteApp: App {
    init() {
        // Hang and crash reports, and a record of any freeze, in Library/Diagnostics.
        GraphiteDiagnostics.start()
    }

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
        WindowGroup {
            // A launch argument opens the voice measuring screen instead; see NeuralVoiceBenchmarkScreen.
            if NeuralVoiceBenchmarkScreen.isRequested { NeuralVoiceBenchmarkScreen() } else { GraphiteRootView() }
        }
            // No default size here, unlike the Mac: iPadOS 27 took it as the window's
            // smallest and largest size alike (1,200 by 852 points), so a window tiled beside
            // another app was laid out 1,065 points wide and cut off at its right edge
            // (reported by the owner, 2026-10-13). iPadOS sizes the window itself.
            .commands { GraphiteCommands() }
            // Read Aloud voices download in a background session that can finish while
            // Graphite is closed; iOS then wakes it to receive the files.
            .backgroundTask(.urlSession(GraphiteVoiceDownloads.sessionIdentifier)) {
                await GraphiteVoiceDownloads.handleBackgroundEvents()
            }
        #endif
    }
}
