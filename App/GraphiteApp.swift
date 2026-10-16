import SwiftUI
import GraphiteUI

@main
struct GraphiteApp: App {
    #if os(macOS)
    /// Saves what is open before Graphite quits.
    @NSApplicationDelegateAdaptor(GraphiteApplicationDelegate.self) private var applicationDelegate
    #endif

    init() {
        // Hang and crash reports, and a record of any freeze, in Library/Diagnostics.
        GraphiteDiagnostics.start()
    }

    var body: some Scene {
        #if os(macOS)
        // The main window and the Settings window, on one workspace.
        GraphiteMacScenes()
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
