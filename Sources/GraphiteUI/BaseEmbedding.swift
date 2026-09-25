import SwiftUI
import GraphiteCore
import GraphiteIndex

/// What a base inside a note needs from the app. Build one per open note and pass it
/// to `BaseCodeBlockView` / `BaseFileEmbedView`, directly or through the environment.
public struct BaseEmbedContext {
    public let store: VaultStore
    public let index: VaultIndex
    /// The note containing the base; `this` in its formulas.
    public let embeddingNote: VaultPath
    /// Change it after vault files or the index change, so the bases run again.
    public let contentVersion: Int
    public let isIndexComplete: Bool
    public let open: (VaultPath) -> Void
    public let filesChanged: ([VaultPath]) -> Void
    /// Opens a base on its own at the named view, for an embed's Open Base; nil opens the
    /// base file with `open`, on its first view.
    public let openBase: ((VaultPath, String?) -> Void)?
    /// Keeps the results of bases scrolled out of sight; see `EmbeddedBaseModelCache`.
    public let modelCache: EmbeddedBaseModelCache?

    public init(store: VaultStore, index: VaultIndex, embeddingNote: VaultPath, contentVersion: Int, isIndexComplete: Bool,
                open: @escaping (VaultPath) -> Void, filesChanged: @escaping ([VaultPath]) -> Void = { _ in },
                openBase: ((VaultPath, String?) -> Void)? = nil, modelCache: EmbeddedBaseModelCache? = nil) {
        self.store = store
        self.index = index
        self.embeddingNote = embeddingNote
        self.contentVersion = contentVersion
        self.isIndexComplete = isIndexComplete
        self.open = open
        self.filesChanged = filesChanged
        self.openBase = openBase
        self.modelCache = modelCache
    }
}

private struct BaseEmbedContextKey: EnvironmentKey {
    /// Computed, so no shared mutable default exists.
    static var defaultValue: BaseEmbedContext? { nil }
}

extension EnvironmentValues {
    /// Set on a reading view so the bases inside it can run. Nil shows base YAML as text.
    public var baseEmbedContext: BaseEmbedContext? {
        get { self[BaseEmbedContextKey.self] }
        set { self[BaseEmbedContextKey.self] = newValue }
    }
}

/// A ```` ```base ```` code block in a note: the live base when a context is available
/// (argument first, then the environment), otherwise its YAML as text, so the block is
/// never blank when Bases are unavailable or turned off.
public struct BaseCodeBlockView: View {
    private let yaml: String
    private let context: BaseEmbedContext?
    @Environment(\.baseEmbedContext) private var environmentContext

    public init(yaml: String, context: BaseEmbedContext? = nil) {
        self.yaml = yaml
        self.context = context
    }

    public var body: some View {
        if let activeContext = context ?? environmentContext {
            EmbeddedBaseView(yaml: yaml, embeddingNote: activeContext.embeddingNote, store: activeContext.store, index: activeContext.index,
                             contentVersion: activeContext.contentVersion, isIndexComplete: activeContext.isIndexComplete,
                             open: activeContext.open, filesChanged: activeContext.filesChanged, modelCache: activeContext.modelCache)
        } else {
            Text(yaml)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// An embedded `.base` file (`![[Books.base#Gallery]]`), starting on the named view.
/// Without a context it shows a button that opens the base file.
public struct BaseFileEmbedView: View {
    private let path: VaultPath
    private let viewName: String?
    private let context: BaseEmbedContext?
    private let openWithoutContext: ((VaultPath) -> Void)?
    @Environment(\.baseEmbedContext) private var environmentContext

    public init(path: VaultPath, viewName: String?, context: BaseEmbedContext? = nil, openWithoutContext: ((VaultPath) -> Void)? = nil) {
        self.path = path
        self.viewName = viewName
        self.context = context
        self.openWithoutContext = openWithoutContext
    }

    public var body: some View {
        if let activeContext = context ?? environmentContext {
            EmbeddedBaseView(basePath: path, viewName: viewName, embeddingNote: activeContext.embeddingNote, store: activeContext.store, index: activeContext.index,
                             contentVersion: activeContext.contentVersion, isIndexComplete: activeContext.isIndexComplete,
                             open: activeContext.open, openBase: activeContext.openBase, filesChanged: activeContext.filesChanged,
                             modelCache: activeContext.modelCache)
        } else if let openWithoutContext {
            Button { openWithoutContext(path) } label: {
                Label(path.name + (viewName.map { name in " › " + name } ?? ""), systemImage: "tablecells")
            }
            .buttonStyle(.borderless)
        } else {
            Label(path.name + (viewName.map { name in " › " + name } ?? ""), systemImage: "tablecells").foregroundStyle(.secondary)
        }
    }
}
