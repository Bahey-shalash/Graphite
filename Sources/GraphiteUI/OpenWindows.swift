import Foundation

/// One window's part in what the windows of the process share: its name, and whether it
/// records or reads aloud. Its workspace makes it and keeps it; the registry holds it weakly,
/// so a window let go of leaves the list by itself.
@MainActor
final class OpenWindow {
    /// The window as its title bar names it: the document it shows and its vault.
    let name: () -> String
    let isRecording: () -> Bool
    let isReadingAloud: () -> Bool
    let stopReadingAloud: () -> Void

    init(name: @escaping () -> String, isRecording: @escaping () -> Bool, isReadingAloud: @escaping () -> Bool,
         stopReadingAloud: @escaping () -> Void) {
        self.name = name
        self.isRecording = isRecording
        self.isReadingAloud = isReadingAloud
        self.stopReadingAloud = stopReadingAloud
    }
}

/// The windows of the process, for what only one window may run at a time: one recording
/// (one microphone and camera) and one Read Aloud (one audio output and one Now Playing entry).
@MainActor
final class OpenWindows {
    private struct WeakWindow {
        weak var window: OpenWindow?
    }

    private var windows: [WeakWindow] = []

    /// Every open window, in the order they opened.
    var all: [OpenWindow] { windows.compactMap(\.window) }

    func add(_ window: OpenWindow) {
        windows.removeAll { entry in entry.window == nil || entry.window === window }
        windows.append(WeakWindow(window: window))
    }

    func remove(_ window: OpenWindow) {
        windows.removeAll { entry in entry.window == nil || entry.window === window }
    }

    /// The other window recording, if any.
    func windowRecording(besides window: OpenWindow) -> OpenWindow? {
        all.first { otherWindow in otherWindow !== window && otherWindow.isRecording() }
    }

    /// The other window reading aloud, with a passage loaded or being prepared, if any.
    func windowReadingAloud(besides window: OpenWindow) -> OpenWindow? {
        all.first { otherWindow in otherWindow !== window && otherWindow.isReadingAloud() }
    }
}

/// Why a window cannot start what another window runs, naming that window.
enum OtherWindowActivity: LocalizedError, Equatable {
    case recording(windowName: String)
    case readingAloud(windowName: String)

    var errorDescription: String? {
        switch self {
        case .recording(let windowName): "A recording is running in another window (\(windowName)). Stop it there first."
        case .readingAloud(let windowName): "Read Aloud is playing in another window (\(windowName)). Stop it there to read here."
        }
    }
}
