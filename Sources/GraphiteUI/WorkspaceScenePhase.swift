import SwiftUI

extension WorkspaceModel {
    /// What the workspace does when the scene's phase changes: places are remembered as the
    /// scene stops being active, then the documents are saved; becoming active again checks
    /// what other apps changed.
    /// - Parameter saveBeforeLeaving: Saves the open documents; the window owns it, since the
    ///   save needs the window's background-task assertion.
    func scenePhaseDidChange(from previousPhase: ScenePhase, to phase: ScenePhase, saveBeforeLeaving: () -> Void) {
        // Taken at once as Graphite stops being active, not in the save that follows: by
        // the time that task runs, iPadOS can have resized the window for its app switcher
        // snapshots, and an editor laid out again then reports a line further down.
        if previousPhase == .active { rememberPlacesOfOpenDocuments() }
        if phase == .active {
            windowCameToFront()
            Task { await checkOpenDocumentsForExternalChanges(); await refreshDirectory(); await reloadVaultSettings() }
        } else {
            // Reading goes on in the background and on the lock screen, like an audiobook.
            saveBeforeLeaving()
        }
    }
}
