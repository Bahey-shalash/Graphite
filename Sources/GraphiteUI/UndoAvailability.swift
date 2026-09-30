import Foundation
import Observation

/// Whether a document's undo history can undo or redo, for the toolbar's Undo and Redo
/// buttons, and the actions that do it. It follows one undo manager at a time: a note's
/// text view, which owns its history, or a PDF session's history.
@MainActor @Observable
final class UndoAvailability {
    private(set) var canUndo = false
    private(set) var canRedo = false
    /// The name of the step Undo would reverse, such as "Rotate Page"; empty when unnamed.
    private(set) var undoActionName = ""
    private(set) var redoActionName = ""
    @ObservationIgnored private weak var followedUndoManager: UndoManager?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// The notifications after which `canUndo` or `canRedo` can have changed.
    private static let changeNotifications: [Notification.Name] = [
        .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
        .NSUndoManagerCheckpoint, .NSUndoManagerDidOpenUndoGroup,
    ]

    init(following undoManager: UndoManager? = nil) {
        follow(undoManager)
    }

    isolated deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    /// Starts following another undo manager, or none (a note with no editor on screen).
    func follow(_ undoManager: UndoManager?) {
        guard undoManager !== followedUndoManager || (undoManager == nil && !observers.isEmpty) else {
            refresh()
            return
        }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        followedUndoManager = undoManager
        if let undoManager {
            observers = Self.changeNotifications.map { name in
                // Undo managers post on the thread that uses them, which here is the main
                // thread; without a queue the state is current when the post returns.
                NotificationCenter.default.addObserver(forName: name, object: undoManager, queue: nil) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                }
            }
        }
        refresh()
    }

    func undo() {
        guard let followedUndoManager, followedUndoManager.canUndo else { return }
        followedUndoManager.undo()
        refresh()
    }

    func redo() {
        guard let followedUndoManager, followedUndoManager.canRedo else { return }
        followedUndoManager.redo()
        refresh()
    }

    /// Reads the followed history again, for changes that post no notification, such as
    /// removing every action.
    func refresh() {
        let newCanUndo = followedUndoManager?.canUndo ?? false
        let newCanRedo = followedUndoManager?.canRedo ?? false
        let newUndoActionName = newCanUndo ? followedUndoManager?.undoActionName ?? "" : ""
        let newRedoActionName = newCanRedo ? followedUndoManager?.redoActionName ?? "" : ""
        // Assigned only when they change: the toolbar reads them.
        if canUndo != newCanUndo { canUndo = newCanUndo }
        if canRedo != newCanRedo { canRedo = newCanRedo }
        if undoActionName != newUndoActionName { undoActionName = newUndoActionName }
        if redoActionName != newRedoActionName { redoActionName = newRedoActionName }
    }
}
