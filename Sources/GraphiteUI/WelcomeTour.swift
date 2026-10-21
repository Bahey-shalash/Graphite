import SwiftUI

/// Whether this device has seen the welcome tour. It shows once, the first time Graphite
/// starts; Settings › General › Welcome Tour and the welcome screen show it again.
enum WelcomeTourPreference {
    static let shownKey = "GraphiteWelcomeTourShown"
}

/// Shows the welcome tour the first time Graphite starts on this device, once the last vault
/// has reopened or failed to, so the tour opens over the vault or the welcome screen rather
/// than over a window that is still changing. Closing the tour, by any means, marks it seen.
struct FirstLaunchWelcomeTour: ViewModifier {
    /// False until the launch has settled, and always false for a launch that hosts tests.
    let isReadyToShow: Bool
    @AppStorage(WelcomeTourPreference.shownKey) private var hasBeenShown = false

    func body(content: Content) -> some View {
        content.welcomeTour(isPresented: Binding(get: { isReadyToShow && !hasBeenShown }, set: { isPresented in
            if !isPresented { hasBeenShown = true }
        }))
    }
}

extension View {
    /// Presents the welcome tour: over the whole screen on iPad and iPhone, so the
    /// screenshots are large enough to read, and as a large sheet on the Mac.
    func welcomeTour(isPresented: Binding<Bool>) -> some View {
        #if canImport(UIKit)
        fullScreenCover(isPresented: isPresented) {
            WelcomeTour(pages: WelcomeTourPage.pagesOnThisPlatform)
        }
        #else
        sheet(isPresented: isPresented) {
            WelcomeTour(pages: WelcomeTourPage.pagesOnThisPlatform)
                .frame(minWidth: 960, idealWidth: 1100, minHeight: 680, idealHeight: 760)
        }
        #endif
    }
}

/// The welcome tour: pages that swipe sideways, with Back and Next below and page dots
/// between them. Skip closes it from any page, and the last page's Get Started does too.
struct WelcomeTour: View {
    let pages: [WelcomeTourPage]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @Environment(AddOnLibrary.self) private var addOns: AddOnLibrary?
    /// The page in view, which the scroll position and the buttons both move.
    @State private var visiblePage: WelcomeTourPage?

    private var currentIndex: Int {
        visiblePage.flatMap { page in pages.firstIndex(of: page) } ?? 0
    }
    private var isOnLastPage: Bool { currentIndex == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pages) { page in
                        WelcomeTourPageView(content: page.content)
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visiblePage)
            // `.hidden` still shows a scroller on a Mac set to always show scroll bars.
            .scrollIndicators(.never)
            footer
        }
        .overlay(alignment: .topTrailing) {
            if !isOnLastPage {
                Button("Skip") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .padding(20)
            }
        }
        .tint(accent)
        .onAppear {
            if visiblePage == nil { visiblePage = pages.first }
            // The screenshots are an add-on: fetched the first time the tour opens.
            if let pack = WelcomeTourScreenshotPack.forThisPlatform { addOns?.download(pack) }
        }
    }

    /// Fits an iPhone's width: Back, a dot for each page and Next take about 350 points.
    private var footer: some View {
        HStack(spacing: 12) {
            Button("Back", systemImage: "chevron.backward") { show(pageAt: currentIndex - 1) }
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .opacity(currentIndex == 0 ? 0 : 1)
                .disabled(currentIndex == 0)
            Spacer(minLength: 0)
            WelcomeTourPageDots(count: pages.count, currentIndex: currentIndex) { index in show(pageAt: index) }
            Spacer(minLength: 0)
            Button {
                if isOnLastPage { dismiss() } else { show(pageAt: currentIndex + 1) }
            } label: {
                Text(isOnLastPage ? "Get Started" : "Next").frame(minWidth: 72)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func show(pageAt index: Int) {
        guard pages.indices.contains(index) else { return }
        withAnimation(GraphiteMotion.animation(.smooth(duration: 0.35))) { visiblePage = pages[index] }
    }
}

/// A dot for each page; the current one is wider and in the accent color. Each dot moves to
/// its page.
private struct WelcomeTourPageDots: View {
    let count: Int
    let currentIndex: Int
    let showPage: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Button { showPage(index) } label: {
                    Capsule()
                        .fill(index == currentIndex ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: index == currentIndex ? 20 : 7, height: 7)
                        .contentShape(Rectangle().inset(by: -6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(index + 1) of \(count)")
                .accessibilityAddTraits(index == currentIndex ? .isSelected : [])
            }
        }
        .animation(GraphiteMotion.animation(.snappy(duration: 0.2)), value: currentIndex)
    }
}
