import SwiftUI
import WebKit
import GraphiteCore

#if canImport(UIKit)
typealias CommunityPluginPlatformView = UIView
#elseif canImport(AppKit)
typealias CommunityPluginPlatformView = NSView
#endif

/// Moving the plugin web view between the places that show it. There is one web view per
/// vault, so showing it in one place takes it from wherever it was.
@MainActor
enum CommunityPluginWebViewPlacement {
    /// Fills `container` with the web view.
    static func show(_ webView: WKWebView, in container: CommunityPluginPlatformView) {
        guard webView.superview !== container else { return }
        webView.removeFromSuperview()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    /// Puts the web view in the window's parking place when nothing shows it. Outside a
    /// window, WebKit treats the page as hidden: it slows the plugins' timers to about one a
    /// second and draws no animation frames (measured in the iPad simulator, 2026-10-10).
    static func parkIfDetached(_ webView: WKWebView?, in parkingView: CommunityPluginPlatformView?) {
        guard let webView, let parkingView, webView.superview == nil else { return }
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.frame = parkingView.bounds
        #if canImport(UIKit)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        #elseif canImport(AppKit)
        webView.autoresizingMask = [.width, .height]
        #endif
        parkingView.addSubview(webView)
    }
}

/// The plugin web view where a view shows it: the plugin panel's sheet, or a plugin's
/// options page in Settings. When the view goes away, the web view returns to its parking place.
@MainActor
struct CommunityPluginWebViewContainer {
    let host: CommunityPluginHost

    final class Coordinator {
        let host: CommunityPluginHost
        init(host: CommunityPluginHost) { self.host = host }
    }

    func makeCoordinator() -> Coordinator { Coordinator(host: host) }
}

#if canImport(UIKit)
extension CommunityPluginWebViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        if let webView = host.webView { CommunityPluginWebViewPlacement.show(webView, in: container) }
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if let webView = host.webView { CommunityPluginWebViewPlacement.show(webView, in: container) }
    }

    static func dismantleUIView(_ container: UIView, coordinator: Coordinator) {
        for subview in container.subviews { subview.removeFromSuperview() }
        coordinator.host.parkWebViewIfDetached()
    }
}
#elseif canImport(AppKit)
extension CommunityPluginWebViewContainer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        if let webView = host.webView { CommunityPluginWebViewPlacement.show(webView, in: container) }
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if let webView = host.webView { CommunityPluginWebViewPlacement.show(webView, in: container) }
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        for subview in container.subviews { subview.removeFromSuperview() }
        coordinator.host.parkWebViewIfDetached()
    }
}
#endif

/// Where the plugin web view waits while no panel shows it: in the window, behind
/// everything, invisible and not touchable, so WebKit runs the plugins as a visible page.
@MainActor
struct CommunityPluginWebViewParking {
    let host: CommunityPluginHost
}

#if canImport(UIKit)
extension CommunityPluginWebViewParking: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let parkingView = UIView()
        parkingView.alpha = 0
        parkingView.isUserInteractionEnabled = false
        parkingView.accessibilityElementsHidden = true
        host.parkingView = parkingView
        return parkingView
    }

    func updateUIView(_ parkingView: UIView, context: Context) {
        host.parkingView = parkingView
        // Reading the web view here makes a new one (a restart, another vault) park too.
        CommunityPluginWebViewPlacement.parkIfDetached(host.webView, in: parkingView)
    }
}
#elseif canImport(AppKit)
extension CommunityPluginWebViewParking: NSViewRepresentable {
    /// A view that never takes clicks, so the parked web view cannot either.
    final class ParkingView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView {
        let parkingView = ParkingView()
        parkingView.alphaValue = 0
        parkingView.setAccessibilityElement(false)
        host.parkingView = parkingView
        return parkingView
    }

    func updateNSView(_ parkingView: NSView, context: Context) {
        host.parkingView = parkingView
        CommunityPluginWebViewPlacement.parkIfDetached(host.webView, in: parkingView)
    }
}
#endif

/// A plugin's modal, settings or view, in a sheet over the workspace.
struct CommunityPluginPanel: View {
    let host: CommunityPluginHost

    var body: some View {
        NavigationStack {
            CommunityPluginWebViewContainer(host: host)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(host.panelTitle)
                #if canImport(UIKit)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { host.panelDidClose() } }
                }
        }
        .frame(minWidth: 420, minHeight: 360)
    }
}

/// Plugins' notices, briefly over the workspace.
struct CommunityPluginNoticeStack: View {
    let host: CommunityPluginHost

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(host.notices) { notice in
                VStack(alignment: .leading, spacing: 2) {
                    if let pluginName = notice.pluginName {
                        Text(pluginName).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(notice.message).font(.callout)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: 360, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                .onTapGesture { host.notices.removeAll { candidate in candidate.id == notice.id } }
                .accessibilityAddTraits(.isStaticText)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.snappy(duration: 0.2), value: host.notices)
        .allowsHitTesting(!host.notices.isEmpty)
    }
}

/// Connects the vault's community plugins to the window: their panel, notices and menus,
/// and what they need to know about the focused document and the appearance.
struct CommunityPluginPresentation: ViewModifier {
    @Bindable var workspace: WorkspaceModel
    /// Shows Settings, for a plugin that opens its own options.
    let showSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var host: CommunityPluginHost { workspace.communityPlugins }

    func body(content: Content) -> some View {
        content
            .background { CommunityPluginWebViewParking(host: host) }
            .overlay(alignment: .top) { CommunityPluginNoticeStack(host: host) }
            .sheet(isPresented: Binding(get: { host.isPanelPresented }, set: { isPresented in if !isPresented { host.panelDidClose() } })) {
                CommunityPluginPanel(host: host)
                    .tint(workspace.preferences.accentColor)
            }
            .confirmationDialog("", isPresented: Binding(get: { host.pendingMenu != nil }, set: { isPresented in
                guard !isPresented, let menu = host.pendingMenu else { return }
                host.pendingMenu = nil
                // SwiftUI closes the dialog before a button's action runs; the dismissal's
                // answer waits, so a chosen item answers first.
                Task { menu.finish(choosing: nil) }
            }), presenting: host.pendingMenu) { menu in
                ForEach(menu.items) { item in
                    Button(item.isChecked ? "✓ " + item.title : item.title, role: item.isWarning ? .destructive : nil) {
                        menu.finish(choosing: item.id)
                        host.pendingMenu = nil
                    }
                    .disabled(item.isDisabled)
                }
            }
            .onChange(of: workspace.selection) { host.activeDocumentDidChange() }
            .onChange(of: workspace.markdownSession?.viewMode) { host.activeDocumentDidChange() }
            .onChange(of: host.isRuntimeRunning) { host.activeDocumentDidChange() }
            .onChange(of: colorScheme, initial: true) { _, scheme in host.appearanceDidChange(isDark: scheme == .dark) }
            .onChange(of: host.requestedSettingsPlugin) { _, requestedPlugin in
                if requestedPlugin != nil { showSettings() }
            }
    }
}
