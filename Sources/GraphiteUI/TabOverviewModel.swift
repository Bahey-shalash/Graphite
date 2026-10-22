import SwiftUI
import GraphiteCore
import GraphiteApple

/// The tab overview of one window, as Safari's: whether it covers the window, the thumbnails
/// of the tabs as they were last seen, and, while it is shown, the previews of the files of
/// tabs without a thumbnail, which the library's tiles show too.
@MainActor @Observable
final class TabOverviewModel {
    private(set) var isPresented = false
    /// The previews of tabs without a thumbnail, by file, while the overview is shown.
    private(set) var filePreviews: [VaultPath: LibraryTilePreview] = [:]
    @ObservationIgnored let thumbnails = TabThumbnails()
    @ObservationIgnored private let clock: any ApplicationClock
    /// The vault the thumbnails were captured in; another vault's tabs never show them.
    @ObservationIgnored private var thumbnailsVaultIdentifier: UUID?
    /// A side's thumbnail waiting for its tab to settle, by tab group.
    @ObservationIgnored private var settledCaptureTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var filePreviewTask: Task<Void, Never>?

    /// How long a tab is on screen before it is captured, so tabs passed through on the way
    /// to another are not.
    static let settleDelayMilliseconds = 1_500
    /// How many times a tab that is still loading or being typed in is tried again.
    static let maximumSettleAttempts = 4

    init(clock: any ApplicationClock) {
        self.clock = clock
    }

    isolated deinit {
        for task in settledCaptureTasks.values { task.cancel() }
        filePreviewTask?.cancel()
    }

    /// Shows every tab as a card. The sides on screen are captured first, before the overview
    /// covers them; the files of tabs never captured are previewed as the library previews them.
    func present(layout: TabLayout, vaultIdentifier: UUID?, previewLoader: LibraryPreviewLoader?) {
        guard !isPresented else { return }
        forgetThumbnailsOfAnotherVault(vaultIdentifier)
        thumbnails.captureShownTabs(in: layout)
        thumbnails.keepOnly(Set(layout.allTabs.map(\.id)))
        loadFilePreviews(of: layout.allTabs, with: previewLoader)
        withAnimation(GraphiteMotion.animation(.smooth(duration: 0.3))) { isPresented = true }
    }

    func dismiss() {
        filePreviewTask?.cancel()
        filePreviews = [:]
        withAnimation(GraphiteMotion.animation(.smooth(duration: 0.3))) { isPresented = false }
    }

    /// Captures a side's tab once it has been on screen for `settleDelayMilliseconds` and
    /// `isSettled` says its file is loaded and nothing is being typed, so a capture costs no
    /// tab switch and no keystroke. Another tab shown on that side cancels the wait.
    func captureWhenSettled(groupID: UUID, tabID: UUID, vaultIdentifier: UUID?, isSettled: @escaping @MainActor () -> Bool) {
        cancelSettledCapture(ofGroup: groupID)
        settledCaptureTasks[groupID] = Task { [weak self, clock] in
            for _ in 0..<Self.maximumSettleAttempts {
                do { try await clock.sleep(for: .milliseconds(Self.settleDelayMilliseconds)) } catch { return } // Cancelled: another tab is shown.
                guard let self else { return }
                guard !isPresented else { continue }
                if isSettled() {
                    forgetThumbnailsOfAnotherVault(vaultIdentifier)
                    thumbnails.captureActiveTab(ofGroup: groupID, tabID: tabID)
                    settledCaptureTasks[groupID] = nil
                    return
                }
            }
        }
    }

    /// Stops waiting to capture the side's tab, as when the side closes.
    func cancelSettledCapture(ofGroup groupID: UUID) {
        settledCaptureTasks.removeValue(forKey: groupID)?.cancel()
    }

    private func forgetThumbnailsOfAnotherVault(_ vaultIdentifier: UUID?) {
        guard vaultIdentifier != thumbnailsVaultIdentifier else { return }
        thumbnails.removeAllThumbnails()
        thumbnailsVaultIdentifier = vaultIdentifier
    }

    /// Previews the files of the tabs without a thumbnail, one after another, off the main actor.
    private func loadFilePreviews(of tabs: [WorkspaceTab], with loader: LibraryPreviewLoader?) {
        filePreviewTask?.cancel()
        filePreviews = [:]
        guard let loader else { return }
        var seen = Set<VaultPath>()
        let paths = tabs.filter { tab in thumbnails.thumbnail(of: tab.id) == nil }.compactMap(\.path).filter { path in seen.insert(path).inserted }
        filePreviewTask = Task { [weak self] in
            for path in paths {
                let preview = await loader.preview(of: path, longerSidePixels: Int(TabThumbnails.longestSidePixels))
                guard !Task.isCancelled, let self else { return }
                filePreviews[path] = preview
            }
        }
    }
}
