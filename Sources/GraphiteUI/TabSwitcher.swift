/**
 * File: TabSwitcher.swift
 * -----------------------
 * Layer: UI
 * Description: The open tabs on a phone, as a sheet listing both sides of a split, and the Tabs button that shows
 *              how many are open as a numbered square symbol.
 *
 * Authors: Bahey Shalash
 * Version: 0.3
 * Date: 21/10/2026
 */

import SwiftUI
import GraphiteCore

/// The open tabs on a phone, where no tab bar fits: a list to switch to a tab, close one
/// with a swipe, or open a new one, as Obsidian mobile's tab switcher. Both sides of a
/// split are listed, so the other side is one tap away.
struct TabSwitcher: View {
    @Bindable var workspace: WorkspaceModel
    @Environment(\.dismiss) private var dismiss

    private var layout: TabLayout { workspace.layout }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(layout.groups.enumerated()), id: \.element.id) { groupIndex, group in
                    Section {
                        ForEach(group.tabs) { tab in
                            row(for: tab, in: group)
                        }
                    } header: {
                        if layout.isSplit { Text(groupIndex == 0 ? "Left" : "Right") }
                    }
                }
            }
            #if canImport(UIKit)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle(layout.allTabs.count == 1 ? "1 Tab" : "\(layout.allTabs.count) Tabs")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Tab", systemImage: "plus") {
                        workspace.openNewTab(inGroup: layout.focusedGroupID)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(for tab: WorkspaceTab, in group: TabGroup) -> some View {
        let isShown = tab.id == layout.activeTab.id
        return Button {
            workspace.activateTab(tab.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: tab.path.map { path in DocumentKind(path: path).systemImage } ?? "doc")
                    .font(.body)
                    .foregroundStyle(Color.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(workspace.title(ofTab: tab))
                        .foregroundStyle(Color.primary)
                        .fontWeight(isShown ? .semibold : .regular)
                        .lineLimit(1)
                    if let folder = tab.path?.parent.rawValue, !folder.isEmpty {
                        Text(folder)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                Spacer(minLength: 8)
                if tab.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .accessibilityLabel("Pinned")
                }
                if isShown {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isShown ? .isSelected : [])
        .swipeActions(edge: .trailing) {
            Button("Close", systemImage: "xmark", role: .destructive) {
                Task { await workspace.closeTab(tab.id) }
            }
        }
        .contextMenu {
            Button("Close", systemImage: "xmark") { Task { await workspace.closeTab(tab.id) } }
            Button("Close Other Tabs", systemImage: "xmark.square") { Task { await workspace.closeOtherTabs(keeping: tab.id) } }
                .disabled(group.tabs.count == 1)
            Button(tab.isPinned ? "Unpin" : "Pin", systemImage: tab.isPinned ? "pin.slash" : "pin") { workspace.togglePin(tab.id) }
            if let path = tab.path { OpenInNewWindowButton { Task { await workspace.open(path, placement: .newWindow) } } }
        }
    }
}

/// The open tabs' button: "Tabs", shown as their number in a rounded square, as Safari and
/// Obsidian mobile show it. The number is a symbol, not drawn text, so the button moves with
/// the rest of the bar to the side of iPhone Duo's display, where the system keeps items
/// showing text in a horizontal bar. Past the highest numbered square, a stack of squares.
struct TabCountLabel: View {
    let count: Int
    static let highestNumberedSquare = 50

    var body: some View {
        Label("Tabs", systemImage: Self.systemImage(forCount: count))
    }

    static func systemImage(forCount count: Int) -> String {
        (0...highestNumberedSquare).contains(count) ? "\(count).square" : "square.on.square"
    }
}
