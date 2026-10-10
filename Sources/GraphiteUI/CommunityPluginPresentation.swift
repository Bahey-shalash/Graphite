import SwiftUI
import WebKit
import GraphiteCore

/// The plugin web view where a view shows it: the plugin panel's sheet, or a plugin's
/// options page in Settings. There is one web view per vault, so showing it here takes it
/// from wherever it was.
struct CommunityPluginWebViewContainer {
    let webView: WKWebView?
}

#if canImport(UIKit)
extension CommunityPluginWebViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        attachWebView(to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        attachWebView(to: container)
    }

    static func dismantleUIView(_ container: UIView, coordinator: ()) {
        for subview in container.subviews { subview.removeFromSuperview() }
    }

    private func attachWebView(to container: UIView) {
        guard let webView, webView.superview !== container else { return }
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
}
#elseif canImport(AppKit)
extension CommunityPluginWebViewContainer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attachWebView(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        attachWebView(to: container)
    }

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        for subview in container.subviews { subview.removeFromSuperview() }
    }

    private func attachWebView(to container: NSView) {
        guard let webView, webView.superview !== container else { return }
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
}
#endif

/// A plugin's modal, settings or view, in a sheet over the workspace.
struct CommunityPluginPanel: View {
    let host: CommunityPluginHost

    var body: some View {
        NavigationStack {
            CommunityPluginWebViewContainer(webView: host.webView)
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
            .overlay(alignment: .top) { CommunityPluginNoticeStack(host: host) }
            .sheet(isPresented: Binding(get: { host.isPanelPresented }, set: { isPresented in if !isPresented { host.panelDidClose() } })) {
                CommunityPluginPanel(host: host)
                    .tint(workspace.preferences.accentColor)
            }
            .confirmationDialog("", isPresented: Binding(get: { host.pendingMenu != nil }, set: { isPresented in
                if !isPresented {
                    host.pendingMenu?.finish(choosing: nil)
                    host.pendingMenu = nil
                }
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
