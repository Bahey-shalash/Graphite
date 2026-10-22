import Foundation
import GraphiteCore

/// The tab overview of a window: every open tab as a card, as Safari shows them.
extension WorkspaceModel {
    /// Covers the window with every open tab as a card, the sides on screen captured first.
    func presentTabOverview(_ overview: TabOverviewModel) {
        overview.present(layout: layout, vaultIdentifier: currentVaultIdentifier, previewLoader: libraryPreviewLoader)
    }

    /// The tab overview's reads and requests on this window's tabs; `dismiss` leaves the
    /// overview after a tab is shown or opened.
    func tabOverviewActions(dismiss: @escaping () -> Void) -> TabOverviewActions {
        TabOverviewActions(layout: { [weak self] in self?.layout ?? TabLayout() },
                           title: { [weak self] tab in self?.title(ofTab: tab) ?? "" },
                           showTab: { [weak self] tabID in self?.activateTab(tabID); dismiss() },
                           closeTab: { [weak self] tabID in Task { await self?.closeTab(tabID) } },
                           closeOtherTabs: { [weak self] tabID in Task { await self?.closeOtherTabs(keeping: tabID) } },
                           togglePin: { [weak self] tabID in self?.togglePin(tabID) },
                           openInNewWindow: { [weak self] path in Task { await self?.open(path, placement: .newWindow) } },
                           openNewTab: { [weak self] in
                               guard let self else { return }
                               openNewTab(inGroup: layout.focusedGroupID)
                               dismiss()
                           })
    }
}
