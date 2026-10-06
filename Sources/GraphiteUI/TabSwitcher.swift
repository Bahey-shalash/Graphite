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
                    Text(title(of: tab))
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
        }
    }

    private func title(of tab: WorkspaceTab) -> String {
        tab.path.map { path in workspace.preferences.displayName(for: path) } ?? "New Tab"
    }
}

/// The number of open tabs in a rounded square, as Safari and Obsidian mobile show it.
struct TabCountLabel: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .padding(.horizontal, 4)
            .frame(minWidth: 22, minHeight: 22)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(lineWidth: 1.5)
            }
    }
}
