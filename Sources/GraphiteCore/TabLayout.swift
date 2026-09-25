import Foundation

/// One tab: the file it shows (none in a new tab), whether it is pinned, and its own back
/// and forward history, as each tab has in Obsidian.
public struct WorkspaceTab: Identifiable, Equatable, Sendable {
    public let id: UUID
    public fileprivate(set) var path: VaultPath?
    /// A pinned tab keeps its file: opening another file from it uses a new tab.
    public fileprivate(set) var isPinned: Bool
    public fileprivate(set) var history: NavigationHistory

    init(path: VaultPath? = nil, isPinned: Bool = false) {
        id = UUID()
        self.path = path
        self.isPinned = isPinned
        history = NavigationHistory()
        if let path { history.visit(path) }
    }
}

/// The tabs of one side of the split. A group always has at least one tab.
public struct TabGroup: Identifiable, Equatable, Sendable {
    public let id: UUID
    public fileprivate(set) var tabs: [WorkspaceTab]
    public fileprivate(set) var activeTabID: UUID

    fileprivate init(tabs: [WorkspaceTab], activeTabID: UUID? = nil) {
        id = UUID()
        let tabs = tabs.isEmpty ? [WorkspaceTab()] : tabs
        self.tabs = tabs
        self.activeTabID = activeTabID.flatMap { identifier in tabs.contains { tab in tab.id == identifier } ? identifier : nil } ?? tabs[0].id
    }

    public var activeTab: WorkspaceTab { tabs.first { tab in tab.id == activeTabID } ?? tabs[0] }
    public var activeTabIndex: Int { tabs.firstIndex { tab in tab.id == activeTabID } ?? 0 }
}

/// The open tabs, in one group or two side by side, as in Obsidian's workspace after
/// "Split right". Only the layout lives here; the documents open in the tabs belong to
/// the app.
///
/// A file is open in at most one tab, so two editors never save over each other; opening
/// a file that is already open switches to its tab.
public struct TabLayout: Equatable, Sendable {
    public static let maximumGroupCount = 2
    public static let maximumClosedTabCount = 20
    /// The left group's share of the width, when split.
    public static let splitFractionRange = 0.25...0.75

    public private(set) var groups: [TabGroup]
    public private(set) var focusedGroupID: UUID
    public var splitFraction: Double {
        didSet { splitFraction = min(max(splitFraction, Self.splitFractionRange.lowerBound), Self.splitFractionRange.upperBound) }
    }
    /// Files of recently closed tabs, the most recent last, for "Reopen closed tab".
    public private(set) var closedPaths: [VaultPath] = []

    public init() {
        let group = TabGroup(tabs: [WorkspaceTab()])
        groups = [group]
        focusedGroupID = group.id
        splitFraction = 0.5
    }

    // MARK: Reading

    public var isSplit: Bool { groups.count > 1 }
    public var focusedGroup: TabGroup { groups.first { group in group.id == focusedGroupID } ?? groups[0] }
    public var activeTab: WorkspaceTab { focusedGroup.activeTab }
    public var allTabs: [WorkspaceTab] { groups.flatMap(\.tabs) }

    public func tab(withID identifier: UUID) -> WorkspaceTab? {
        allTabs.first { tab in tab.id == identifier }
    }

    public func group(containing tabID: UUID) -> TabGroup? {
        groups.first { group in group.tabs.contains { tab in tab.id == tabID } }
    }

    /// The tab showing `path`, if one does.
    public func tabID(showing path: VaultPath) -> UUID? {
        allTabs.first { tab in tab.path == path }?.id
    }

    /// The group other than `groupID`, when split.
    public func otherGroup(than groupID: UUID) -> TabGroup? {
        groups.first { group in group.id != groupID }
    }

    // MARK: Focus

    /// Makes the tab active in its group and its group focused.
    public mutating func focus(tabID: UUID) {
        guard let location = location(of: tabID) else { return }
        groups[location.groupIndex].activeTabID = tabID
        focusedGroupID = groups[location.groupIndex].id
    }

    /// Makes the tab active in its group without moving focus, as when a link shows a
    /// file already open on the other side.
    public mutating func activateWithoutFocus(tabID: UUID) {
        guard let location = location(of: tabID) else { return }
        groups[location.groupIndex].activeTabID = tabID
    }

    public mutating func focus(groupID: UUID) {
        guard groups.contains(where: { group in group.id == groupID }) else { return }
        focusedGroupID = groupID
    }

    /// Activates the next or previous tab of the focused group, wrapping around.
    public mutating func activateNeighborTab(forward: Bool) {
        let group = focusedGroup
        guard group.tabs.count > 1 else { return }
        let index = (group.activeTabIndex + (forward ? 1 : group.tabs.count - 1)) % group.tabs.count
        focus(tabID: group.tabs[index].id)
    }

    /// Activates the tab at `position` (zero-based) of the focused group; a position past
    /// the end activates the last tab, as ⌘9 does.
    public mutating func activateTab(atPosition position: Int) {
        let tabs = focusedGroup.tabs
        focus(tabID: tabs[min(max(position, 0), tabs.count - 1)].id)
    }

    // MARK: Adding tabs and groups

    /// Adds a tab after the active tab of the group (the focused group when nil), makes it
    /// active and focused, and returns it.
    @discardableResult
    public mutating func addTab(inGroup groupID: UUID? = nil, showing path: VaultPath? = nil) -> UUID {
        let groupIndex = groups.firstIndex { group in group.id == (groupID ?? focusedGroupID) } ?? 0
        let tab = WorkspaceTab(path: path)
        groups[groupIndex].tabs.insert(tab, at: groups[groupIndex].activeTabIndex + 1)
        groups[groupIndex].activeTabID = tab.id
        focusedGroupID = groups[groupIndex].id
        return tab.id
    }

    /// The tab a file opened "here" goes into: the active tab, or a new tab beside it when
    /// the active tab is pinned to a file.
    public mutating func tabForOpeningHere() -> UUID {
        let tab = activeTab
        return tab.isPinned && tab.path != nil ? addTab() : tab.id
    }

    /// Focuses the group on the right, creating it with an empty tab when there is only
    /// one group, and returns it.
    @discardableResult
    public mutating func openOtherGroup() -> UUID {
        if let other = otherGroup(than: focusedGroupID) {
            focusedGroupID = other.id
            return other.id
        }
        let group = TabGroup(tabs: [WorkspaceTab()])
        groups.append(group)
        focusedGroupID = group.id
        return group.id
    }

    /// The tab a file opened "to the right" goes into: the other group's active tab when it
    /// is empty, else a new tab there. The other group is created when needed.
    public mutating func tabForOpeningInOtherGroup() -> UUID {
        let groupID = openOtherGroup()
        let active = focusedGroup.activeTab
        return active.path == nil ? active.id : addTab(inGroup: groupID)
    }

    // MARK: Showing files

    /// Records that `tabID` now shows `path`. Following a link or choosing a file records
    /// it in the tab's history; going back or forward has already moved through it.
    public mutating func show(_ path: VaultPath, inTab tabID: UUID, recordsHistory: Bool) {
        guard let location = location(of: tabID) else { return }
        groups[location.groupIndex].tabs[location.tabIndex].path = path
        if recordsHistory { groups[location.groupIndex].tabs[location.tabIndex].history.visit(path) }
    }

    /// The file going back (or forward) in the tab's history would show, without moving.
    public func historyTarget(ofTab tabID: UUID, forward: Bool) -> VaultPath? {
        guard let history = tab(withID: tabID)?.history else { return nil }
        if forward { return history.canGoForward ? history.entries[history.currentIndex + 1] : nil }
        return history.canGoBack ? history.entries[history.currentIndex - 1] : nil
    }

    /// Moves back or forward in the tab's history and returns the file to show there.
    public mutating func moveInHistory(ofTab tabID: UUID, forward: Bool) -> VaultPath? {
        guard let location = location(of: tabID) else { return nil }
        return forward ? groups[location.groupIndex].tabs[location.tabIndex].history.goForward()
                       : groups[location.groupIndex].tabs[location.tabIndex].history.goBack()
    }

    /// Forgets a history entry that could not be opened.
    public mutating func removeFromHistory(inside path: VaultPath, ofTab tabID: UUID) {
        guard let location = location(of: tabID) else { return }
        groups[location.groupIndex].tabs[location.tabIndex].history.remove(inside: path)
    }

    public mutating func setPinned(_ isPinned: Bool, tabID: UUID) {
        guard let location = location(of: tabID) else { return }
        groups[location.groupIndex].tabs[location.tabIndex].isPinned = isPinned
    }

    // MARK: Closing

    /// Closes a tab. The tab to its right becomes active, else the one to its left. A group
    /// left without tabs closes when the layout is split, else it gets an empty tab.
    public mutating func closeTab(_ tabID: UUID) {
        guard let removedTab = removeTab(tabID) else { return }
        remember(closedPath: removedTab.path)
    }

    /// Closes every other unpinned tab of the tab's group, and returns the closed tabs.
    @discardableResult
    public mutating func closeOtherTabs(keeping tabID: UUID) -> [UUID] {
        guard let group = group(containing: tabID) else { return [] }
        let closedTabs = group.tabs.filter { tab in tab.id != tabID && !tab.isPinned }
        for tab in closedTabs { closeTab(tab.id) }
        focus(tabID: tabID)
        return closedTabs.map(\.id)
    }

    /// Closes a whole group and its tabs, and returns the closed tabs. The last group is
    /// left with one empty tab.
    @discardableResult
    public mutating func closeGroup(_ groupID: UUID) -> [UUID] {
        guard let group = groups.first(where: { group in group.id == groupID }) else { return [] }
        for tab in group.tabs {
            if let path = tab.path { remember(closedPath: path) }
        }
        if isSplit {
            groups.removeAll { candidate in candidate.id == groupID }
            focusedGroupID = groups[0].id
        } else {
            groups = [TabGroup(tabs: [WorkspaceTab()])]
            focusedGroupID = groups[0].id
        }
        return group.tabs.map(\.id)
    }

    /// The file of the most recently closed tab that is not open again, removed from the list.
    public mutating func popClosedPath() -> VaultPath? {
        while let path = closedPaths.popLast() {
            if tabID(showing: path) == nil { return path }
        }
        return nil
    }

    // MARK: Moving tabs

    /// Moves a tab into the other group, creating the split when there is only one group.
    public mutating func moveTabToOtherGroup(_ tabID: UUID) {
        guard let sourceGroup = group(containing: tabID), let tab = tab(withID: tabID) else { return }
        // A lone tab of a lone group has nowhere to come from: the split gets it, and the
        // group it leaves gets an empty tab.
        let destinationID = otherGroup(than: sourceGroup.id)?.id
        removeTab(tabID)
        let destinationIndex: Int
        if let destinationID, let index = groups.firstIndex(where: { group in group.id == destinationID }) {
            destinationIndex = index
            groups[index].tabs.insert(tab, at: groups[index].activeTabIndex + 1)
        } else {
            groups.append(TabGroup(tabs: [tab]))
            destinationIndex = groups.count - 1
        }
        groups[destinationIndex].activeTabID = tab.id
        focusedGroupID = groups[destinationIndex].id
    }

    /// Moves a tab to `position` in a group, as when its tab is dragged there.
    public mutating func moveTab(_ tabID: UUID, toGroup groupID: UUID, at position: Int) {
        guard let tab = tab(withID: tabID), let source = location(of: tabID),
              let destinationIndex = groups.firstIndex(where: { group in group.id == groupID }) else { return }
        if groups[source.groupIndex].id == groupID {
            var tabs = groups[destinationIndex].tabs
            tabs.remove(at: source.tabIndex)
            // Positions count the tabs before the move.
            let insertionIndex = min(max(position > source.tabIndex ? position - 1 : position, 0), tabs.count)
            tabs.insert(tab, at: insertionIndex)
            groups[destinationIndex].tabs = tabs
        } else {
            let destinationGroupID = groups[destinationIndex].id
            removeTab(tabID)
            guard let index = groups.firstIndex(where: { group in group.id == destinationGroupID }) else { return }
            groups[index].tabs.insert(tab, at: min(max(position, 0), groups[index].tabs.count))
        }
        focus(tabID: tabID)
    }

    // MARK: Files that moved or went away

    /// Follows a rename or move of a file or folder in every tab and history.
    public mutating func replacePrefix(_ oldPath: VaultPath, with newPath: VaultPath) {
        for groupIndex in groups.indices {
            for tabIndex in groups[groupIndex].tabs.indices {
                if let path = groups[groupIndex].tabs[tabIndex].path {
                    groups[groupIndex].tabs[tabIndex].path = (try? path.replacingPrefix(oldPath, with: newPath)) ?? path
                }
                groups[groupIndex].tabs[tabIndex].history.replacePrefix(oldPath, with: newPath)
            }
        }
        closedPaths = closedPaths.map { path in (try? path.replacingPrefix(oldPath, with: newPath)) ?? path }
    }

    /// Closes the tabs of a deleted file or folder and forgets it everywhere; returns the closed tabs.
    @discardableResult
    public mutating func removeTabs(inside removedPath: VaultPath) -> [UUID] {
        let removedTabs = allTabs.filter { tab in tab.path?.isInside(removedPath) == true }.map(\.id)
        for tabID in removedTabs { removeTab(tabID) }
        for groupIndex in groups.indices {
            for tabIndex in groups[groupIndex].tabs.indices {
                groups[groupIndex].tabs[tabIndex].history.remove(inside: removedPath)
            }
        }
        closedPaths.removeAll { path in path.isInside(removedPath) }
        return removedTabs
    }

    // MARK: Saving

    public var saved: SavedTabLayout {
        SavedTabLayout(groups: groups.map { group in
            SavedTabLayout.Group(tabs: group.tabs.map { tab in SavedTabLayout.Tab(path: tab.path?.rawValue, isPinned: tab.isPinned) },
                                 activeTabIndex: group.activeTabIndex)
        }, focusedGroupIndex: groups.firstIndex { group in group.id == focusedGroupID } ?? 0, splitFraction: splitFraction)
    }

    /// Restores a saved layout. Tabs of files that no longer exist are left out, and a
    /// file is kept in its first tab only.
    public init(saved: SavedTabLayout, fileExists: (VaultPath) -> Bool) {
        self.init()
        var seenPaths = Set<VaultPath>()
        var restoredGroups: [TabGroup] = []
        var focusedGroupIndex = 0
        for (savedIndex, savedGroup) in saved.groups.prefix(Self.maximumGroupCount).enumerated() {
            var tabs: [WorkspaceTab] = []
            var activeTabID: UUID?
            for (tabIndex, savedTab) in savedGroup.tabs.enumerated() {
                let path = savedTab.path.flatMap { rawPath in try? VaultPath(rawPath) }
                if savedTab.path != nil {
                    guard let path, fileExists(path), seenPaths.insert(path).inserted else { continue }
                }
                let tab = WorkspaceTab(path: path, isPinned: savedTab.isPinned && path != nil)
                tabs.append(tab)
                if tabIndex <= savedGroup.activeTabIndex || activeTabID == nil { activeTabID = tab.id }
            }
            guard !tabs.isEmpty else { continue }
            if savedIndex == saved.focusedGroupIndex { focusedGroupIndex = restoredGroups.count }
            restoredGroups.append(TabGroup(tabs: tabs, activeTabID: activeTabID))
        }
        if !restoredGroups.isEmpty {
            groups = restoredGroups
            focusedGroupID = restoredGroups[min(focusedGroupIndex, restoredGroups.count - 1)].id
        }
        splitFraction = saved.splitFraction
    }

    // MARK: Private

    private func location(of tabID: UUID) -> (groupIndex: Int, tabIndex: Int)? {
        for (groupIndex, group) in groups.enumerated() {
            if let tabIndex = group.tabs.firstIndex(where: { tab in tab.id == tabID }) { return (groupIndex, tabIndex) }
        }
        return nil
    }

    /// Removes a tab, keeping every group non-empty, and returns it.
    @discardableResult
    private mutating func removeTab(_ tabID: UUID) -> WorkspaceTab? {
        guard let location = location(of: tabID) else { return nil }
        let removedTab = groups[location.groupIndex].tabs.remove(at: location.tabIndex)
        if groups[location.groupIndex].tabs.isEmpty {
            if isSplit {
                let removedGroupID = groups[location.groupIndex].id
                groups.remove(at: location.groupIndex)
                if focusedGroupID == removedGroupID { focusedGroupID = groups[0].id }
            } else {
                let emptyTab = WorkspaceTab()
                groups[location.groupIndex].tabs = [emptyTab]
                groups[location.groupIndex].activeTabID = emptyTab.id
            }
        } else if groups[location.groupIndex].activeTabID == tabID {
            let tabs = groups[location.groupIndex].tabs
            groups[location.groupIndex].activeTabID = tabs[min(location.tabIndex, tabs.count - 1)].id
        }
        return removedTab
    }

    private mutating func remember(closedPath: VaultPath?) {
        guard let closedPath else { return }
        closedPaths.removeAll { path in path == closedPath }
        closedPaths.append(closedPath)
        if closedPaths.count > Self.maximumClosedTabCount { closedPaths.removeFirst(closedPaths.count - Self.maximumClosedTabCount) }
    }
}

/// A tab layout as saved between launches, per vault.
public struct SavedTabLayout: Codable, Equatable, Sendable {
    public struct Group: Codable, Equatable, Sendable {
        public var tabs: [Tab]
        public var activeTabIndex: Int
        public init(tabs: [Tab], activeTabIndex: Int) { self.tabs = tabs; self.activeTabIndex = activeTabIndex }
    }

    public struct Tab: Codable, Equatable, Sendable {
        /// The file's vault path; nil for an empty tab.
        public var path: String?
        public var isPinned: Bool
        public init(path: String?, isPinned: Bool) { self.path = path; self.isPinned = isPinned }
    }

    public var groups: [Group]
    public var focusedGroupIndex: Int
    public var splitFraction: Double

    public init(groups: [Group], focusedGroupIndex: Int, splitFraction: Double) {
        self.groups = groups
        self.focusedGroupIndex = focusedGroupIndex
        self.splitFraction = splitFraction
    }
}
