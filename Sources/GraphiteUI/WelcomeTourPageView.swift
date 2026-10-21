import SwiftUI

/// One page of the welcome tour. In a wide window the words sit beside the screenshot; in a
/// narrow one (an iPhone, an iPad in a split) they stack above it. Either way the page
/// scrolls when Dynamic Type makes it taller than the window.
struct WelcomeTourPageView: View {
    let content: WelcomeTourPageContent
    /// The size of the page's window, which picks the layout and centers a short page.
    @State private var viewportSize = CGSize.zero

    private var isWide: Bool { viewportSize.width >= Self.sideBySideMinimumWidth }

    /// Wide enough for a column of words and a screenshot side by side.
    private static let sideBySideMinimumWidth: CGFloat = 820

    var body: some View {
        ScrollView(.vertical) {
            Group {
                if isWide && !content.screenshots.isEmpty {
                    HStack(alignment: .center, spacing: 40) {
                        words.frame(maxWidth: 400)
                        WelcomeTourScreenshots(screenshots: content.screenshots)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 28) {
                        heading
                        if !content.screenshots.isEmpty { WelcomeTourScreenshots(screenshots: content.screenshots) }
                        points
                    }
                    .frame(maxWidth: content.pointLayout.maximumStackedWidth)
                }
            }
            .padding(.horizontal, isWide ? 48 : 24)
            .padding(.top, 52)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, minHeight: viewportSize.height)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGSize.self) { geometry in geometry.size } action: { size in
            viewportSize = size
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading
            points
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: content.systemImage)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 52, height: 52)
                .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            Text(content.title)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(content.summary)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var points: some View {
        switch content.pointLayout {
        case .list:
            VStack(alignment: .leading, spacing: 18) {
                ForEach(content.points) { point in WelcomeTourPointRow(point: point) }
            }
        case .tiles:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
                ForEach(content.points) { point in
                    WelcomeTourPointRow(point: point)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }
}

/// One point of a page: an icon, a title (or Markdown to type) and where to find it.
private struct WelcomeTourPointRow: View {
    let point: WelcomeTourPoint

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: point.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                title
                Text(point.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let destination = point.destination {
                    Link(destination: destination) {
                        Label((destination.host() ?? "") + destination.path(), systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var title: some View {
        switch point.title {
        case .words(let words):
            Text(words).font(.headline)
        case .syntax(let markdown):
            Text(verbatim: markdown)
                .font(.callout.monospaced().weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

/// The page's screenshots. With several, a segmented control above them picks which one
/// shows; each comes from the app's asset catalog in the light and the dark appearance.
private struct WelcomeTourScreenshots: View {
    let screenshots: [WelcomeTourScreenshot]
    @State private var shownScreenshotName: String?

    private var shownScreenshot: WelcomeTourScreenshot? {
        screenshots.first { screenshot in screenshot.assetName == shownScreenshotName } ?? screenshots.first
    }

    var body: some View {
        VStack(spacing: 14) {
            if screenshots.count > 1 {
                Picker("Screenshot", selection: Binding(get: { shownScreenshot?.assetName ?? "" }, set: { name in shownScreenshotName = name })) {
                    ForEach(screenshots) { screenshot in Text(screenshot.label).tag(screenshot.assetName) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if let shownScreenshot {
                Image(shownScreenshot.assetName, bundle: .main)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator, lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.14), radius: 18, y: 8)
                    .accessibilityLabel(shownScreenshot.accessibilityDescription)
                    .id(shownScreenshot.assetName)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(GraphiteMotion.animation(.easeInOut(duration: 0.2)), value: shownScreenshot?.assetName)
    }
}
