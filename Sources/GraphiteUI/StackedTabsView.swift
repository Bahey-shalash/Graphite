import SwiftUI
import GraphiteCore

/// A stacked tab group, as Obsidian's "Stack tabs" lays one out after Andy Matuschak's
/// sliding notes: every tab is a pane of its own, side by side in a row that scrolls
/// sideways, its title on a spine at its leading edge. Panes scrolled past stop with their
/// spine showing and the next pane slides over them; panes beyond the trailing edge wait
/// there as spines (`StackedPaneGeometry`). Only the panes whose content shows hold their
/// document; the others are spines alone until they slide into view.
struct StackedTabsView<Document: View>: View {
    let group: TabGroup
    let isFocused: Bool
    let actions: StackedTabActions
    /// The document of a tab whose pane's content shows, and whether that tab is the active one.
    @ViewBuilder let document: (WorkspaceTab, _ isActive: Bool) -> Document


    @State private var scrollOffset: CGFloat = 0
    @State private var scrollPosition = ScrollPosition(x: 0)
    @State private var containerWidth: CGFloat = 0
    #if canImport(UIKit)
    @State private var frameInWindow: CGRect = .zero
    #endif

    private var geometry: StackedPaneGeometry {
        StackedPaneGeometry(paneCount: group.tabs.count, containerWidth: Double(containerWidth),
                            spineWidth: Double(StackedPaneMeasures.spineWidthPoints),
                            preferredContentWidth: Double(StackedPaneMeasures.preferredContentWidthPoints),
                            minimumContentWidth: Double(StackedPaneMeasures.minimumContentWidthPoints))
    }

    var body: some View {
        let geometry = geometry
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Array(group.tabs.enumerated()), id: \.element.id) { index, tab in
                    pane(for: tab, at: index, geometry: geometry)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .scrollPosition($scrollPosition)
        .onScrollGeometryChange(for: CGFloat.self) { scrollGeometry in scrollGeometry.contentOffset.x } action: { _, offset in scrollOffset = offset }
        .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.width } action: { width in containerWidth = width }
        // The active tab's pane slides into view: a tab chosen from the menu or the keyboard,
        // a note opened in a new tab, or the group just stacked.
        .onChange(of: group.activeTabID) { showActivePane(animated: true) }
        .onChange(of: containerWidth) { showActivePane(animated: false) }
        #if canImport(UIKit)
        // A touch on a pane makes its tab the active one. Only observed, as for the split's
        // sides: a gesture over the editor would take its taps.
        .onGeometryChange(for: CGRect.self) { proxy in proxy.frame(in: .global) } action: { frame in frameInWindow = frame }
        .background {
            WindowTouchObserver { windowPoint in
                guard frameInWindow.contains(windowPoint) else { return }
                activatePane(at: windowPoint.x - frameInWindow.minX)
            }
        }
        #endif
    }

    private func pane(for tab: WorkspaceTab, at index: Int, geometry: StackedPaneGeometry) -> some View {
        let unstuckEdge = CGFloat(index) * CGFloat(geometry.paneWidth) - scrollOffset
        let displayedEdge = CGFloat(geometry.displayedLeadingEdge(ofPane: index, scrollOffset: Double(scrollOffset)))
        let showsContent = geometry.visibleContentWidth(ofPane: index, scrollOffset: Double(scrollOffset)) > 0.5
        let isActive = tab.id == group.activeTabID
        return HStack(spacing: 0) {
            StackedTabSpine(title: actions.title(tab), isActive: isActive, marksFocus: isActive && isFocused, isPinned: tab.isPinned,
                            activate: { actions.activate(tab.id) }, close: { actions.close(tab.id) })
                .frame(width: StackedPaneMeasures.spineWidthPoints)
                .contextMenu { spineMenu(for: tab) }
            Group {
                if showsContent {
                    document(tab, isActive)
                } else {
                    Color.clear
                }
            }
            .frame(width: CGFloat(geometry.contentWidth))
        }
        .frame(width: CGFloat(geometry.paneWidth))
        .frame(maxHeight: .infinity)
        // Opaque, so a pane hides the one it slides over.
        .background(GraphiteChrome.barBackground)
        .overlay(alignment: .leading) { Hairline(axis: .vertical) }
        .compositingGroup()
        .shadow(color: .black.opacity(index > 0 ? 0.1 : 0), radius: 6, x: -2)
        .offset(x: displayedEdge - unstuckEdge)
        .zIndex(Double(index))
        #if !canImport(UIKit)
        // A click anywhere on a pane makes its tab the active one.
        .simultaneousGesture(TapGesture().onEnded { actions.activate(tab.id) })
        #endif
    }

    @ViewBuilder private func spineMenu(for tab: WorkspaceTab) -> some View {
        Button("Close", systemImage: "xmark") { actions.close(tab.id) }
        Button("Close Other Tabs", systemImage: "xmark.square") { actions.closeOthers(tab.id) }
            .disabled(group.tabs.count == 1)
        Button(tab.isPinned ? "Unpin" : "Pin", systemImage: tab.isPinned ? "pin.slash" : "pin") { actions.togglePin(tab.id) }
        Divider()
        Button("Unstack Tabs", systemImage: "rectangle", action: actions.unstack)
    }

    private func activatePane(at position: CGFloat) {
        guard let index = geometry.pane(at: Double(position), scrollOffset: Double(scrollOffset)), group.tabs.indices.contains(index) else { return }
        let tab = group.tabs[index]
        if tab.id != group.activeTabID { actions.activate(tab.id) }
    }

    private func showActivePane(animated: Bool) {
        guard containerWidth > 0 else { return }
        let target = CGFloat(geometry.scrollOffset(showingPane: group.activeTabIndex, from: Double(scrollOffset)))
        guard abs(target - scrollOffset) > 0.5 else { return }
        if animated {
            withAnimation(GraphiteMotion.animation(.snappy)) { scrollPosition.scrollTo(x: target) }
        } else {
            scrollPosition.scrollTo(x: target)
        }
    }
}

/// The widths a stacked side lays its panes out with.
enum StackedPaneMeasures {
    static let spineWidthPoints: CGFloat = 36
    /// Obsidian's stacked panes are 700 pixels wide; a note's readable column is about as wide.
    static let preferredContentWidthPoints: CGFloat = 700
    static let minimumContentWidthPoints: CGFloat = 320
}

/// What a stacked side asks of its tabs.
struct StackedTabActions {
    let title: (WorkspaceTab) -> String
    let activate: (UUID) -> Void
    let close: (UUID) -> Void
    let closeOthers: (UUID) -> Void
    let togglePin: (UUID) -> Void
    let unstack: () -> Void
}

/// A stacked pane's spine: its tab's title read downward, as Obsidian draws it, with the close
/// button at the top. The active tab's spine has the faint fill of a tab in use.
private struct StackedTabSpine: View {
    let title: String
    let isActive: Bool
    let marksFocus: Bool
    let isPinned: Bool
    let activate: () -> Void
    let close: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(spacing: 4) {
            closeButtonOrPin
            GeometryReader { proxy in
                Text(title)
                    .interfaceFont(.subheadline)
                    .fontWeight(isActive ? .medium : .regular)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: proxy.size.height, alignment: .leading)
                    .rotationEffect(.degrees(90))
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
        }
        .padding(.vertical, 6)
        .frame(maxHeight: .infinity)
        .background(isActive ? GraphiteChrome.selectedFill : Color.clear)
        .overlay(alignment: .leading) {
            if marksFocus {
                Capsule().fill(accent).frame(width: 2).padding(.vertical, 12)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: activate)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Close", close)
    }

    /// A pinned tab is not closed from its spine; it shows its pin instead.
    @ViewBuilder private var closeButtonOrPin: some View {
        if isPinned {
            Image(systemName: "pin.fill")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(height: 28)
                .accessibilityLabel("Pinned")
        } else {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .tint(.secondary)
            .accessibilityLabel("Close \(title)")
        }
    }
}
