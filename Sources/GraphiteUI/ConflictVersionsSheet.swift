import SwiftUI
import GraphiteCore
import GraphiteApple

// MARK: Model

/// What the Versions sheet shows and does for one file.
@MainActor @Observable
final class ConflictVersionsModel {
    let path: VaultPath
    private let workspace: WorkspaceModel
    private(set) var listing: ConflictVersionListing?
    private(set) var hasLoaded = false
    /// True while a decision is being carried out, so a second one cannot start.
    private(set) var isWorking = false
    /// Why the last load or decision failed.
    var problem: String?
    /// Versions kept as files of their own since the sheet opened.
    private(set) var keptCopies: [VaultPath] = []

    var versions: [FileConflictVersion] { listing?.versions ?? [] }

    init(path: VaultPath, workspace: WorkspaceModel) {
        self.path = path; self.workspace = workspace
    }

    func load() async {
        do {
            listing = try await workspace.conflictVersionListing(of: path)
        } catch { problem = error.localizedDescription }
        hasLoaded = true
    }

    /// Keeps the current file and removes every version listed.
    func keepCurrentVersion() async {
        await decide { [self] in try await workspace.keepCurrentVersion(of: path, removing: versions) }
    }

    func replaceCurrentVersion(with version: FileConflictVersion) async {
        guard let listing else { return }
        await decide { [self] in
            do {
                try await workspace.replaceCurrentVersion(of: path, with: version, listedIn: listing)
            } catch GraphiteError.conflict {
                throw GraphiteError.unavailable("“\(path.name)” changed after these versions were listed, so it was not replaced. The versions are listed again: compare them once more before deciding.")
            }
        }
    }

    func keepAsSeparateFile(_ version: FileConflictVersion) async {
        await decide { [self] in keptCopies.append(try await workspace.keepAsSeparateFile(version, of: path)) }
    }

    private func decide(_ decision: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await decision()
            problem = nil
        } catch { problem = error.localizedDescription }
        // What is left, and the current file as it is now.
        if let refreshedListing = try? await workspace.conflictVersionListing(of: path) { listing = refreshedListing }
    }
}

// MARK: Sheet

/// The versions a file provider kept beside a file: who saved each and when, what each
/// holds, and the choice between keeping the current one, replacing it, or keeping a
/// version as a separate file.
struct ConflictVersionsSheet: View {
    @Bindable var workspace: WorkspaceModel
    @State private var model: ConflictVersionsModel
    @State private var navigationPath: [FileConflictVersion.ID] = []
    @State private var isConfirmingKeepCurrent = false
    @Environment(\.dismiss) private var dismiss

    init(workspace: WorkspaceModel, request: ConflictVersionsRequest) {
        self.workspace = workspace
        _model = State(initialValue: ConflictVersionsModel(path: request.path, workspace: workspace))
    }

    private var fileName: String { workspace.preferences.displayName(for: model.path) }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                if let problem = model.problem {
                    Section { Label(problem, systemImage: "exclamationmark.circle").foregroundStyle(.secondary) }
                }
                if !model.keptCopies.isEmpty { keptCopiesSection }
                if model.hasLoaded && model.versions.isEmpty {
                    ContentUnavailableView("No Other Versions", systemImage: "checkmark.circle",
                                           description: Text("Only the current version of “\(fileName)” is left."))
                } else if model.hasLoaded {
                    versionSections
                }
            }
            .overlay { if !model.hasLoaded || model.isWorking { ProgressView() } }
            .navigationTitle("Versions of “\(fileName)”")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationDestination(for: FileConflictVersion.ID.self) { versionIdentifier in
                if let version = model.versions.first(where: { version in version.id == versionIdentifier }) {
                    ConflictVersionPreview(workspace: workspace, model: model, version: version) { navigationPath = [] }
                }
            }
            .confirmationDialog(ConflictVersionsText.keepCurrentQuestion(versionCount: model.versions.count), isPresented: $isConfirmingKeepCurrent, titleVisibility: .visible) {
                Button(ConflictVersionsText.removeButtonTitle(versionCount: model.versions.count), role: .destructive) { Task { await model.keepCurrentVersion() } }
            } message: {
                Text("“\(fileName)” stays as it is. The other versions are removed for good, on every device that syncs this folder.")
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .task { await model.load() }
        .disabled(model.isWorking)
    }

    @ViewBuilder private var versionSections: some View {
        Section {
            ConflictVersionRow(title: "Current version", detail: ConflictVersionsText.detail(modified: model.listing?.currentStamp.modified, byteCount: model.listing?.currentStamp.byteCount, savedBy: nil))
        } header: {
            Text("In the vault now")
        } footer: {
            Text("“\(fileName)” was changed in two places before the changes could sync, so more than one version exists. Nothing is removed until you decide.")
        }
        Section("Kept beside it") {
            ForEach(model.versions) { version in
                NavigationLink(value: version.id) {
                    ConflictVersionRow(title: ConflictVersionsText.title(of: version),
                                       detail: ConflictVersionsText.detail(modified: version.modified, byteCount: version.byteCount, savedBy: version.savedBy))
                }
                .accessibilityIdentifier("conflictVersion")
            }
        }
        Section {
            Button("Keep Current Version…", systemImage: "checkmark.circle") { isConfirmingKeepCurrent = true }
                .accessibilityIdentifier("keepCurrentVersion")
        } footer: {
            Text("Open a version to see what it holds, to replace the current version with it, or to keep it as a separate file.")
        }
    }

    private var keptCopiesSection: some View {
        Section("Kept as separate files") {
            ForEach(model.keptCopies) { copyPath in
                Button {
                    dismiss()
                    Task { await workspace.open(copyPath) }
                } label: {
                    Label(workspace.preferences.displayName(for: copyPath), systemImage: DocumentKind(path: copyPath).systemImage)
                }
            }
        }
    }
}

private struct ConflictVersionRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

/// The wording of the Versions sheet, kept apart from its views.
enum ConflictVersionsText {
    /// The device a version was saved on, when the provider recorded it.
    static func title(of version: FileConflictVersion) -> String {
        guard let deviceName = version.deviceName, !deviceName.isEmpty else { return "Version from another device" }
        return "Version from \(deviceName)"
    }

    /// "30 Sep 2026 at 12:15 · 4 KB · saved by Anna", leaving out what is unknown.
    static func detail(modified: Date?, byteCount: Int?, savedBy: String?) -> String {
        var parts: [String] = []
        if let modified { parts.append(modified.formatted(date: .abbreviated, time: .shortened)) }
        if let byteCount { parts.append(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)) }
        if let savedBy, !savedBy.isEmpty { parts.append("saved by \(savedBy)") }
        return parts.joined(separator: " · ")
    }

    static func keepCurrentQuestion(versionCount: Int) -> String {
        versionCount == 1 ? "Keep the current version and remove the other one?" : "Keep the current version and remove the \(versionCount) others?"
    }

    static func removeButtonTitle(versionCount: Int) -> String {
        versionCount == 1 ? "Remove the Other Version" : "Remove \(versionCount) Other Versions"
    }

    /// What the banner over an open document and the sidebar's mark say.
    static let bannerText = "Another version of this file was kept when it was changed in two places."
    static let markerDescription = "Has another version to review"
}

// MARK: Preview of one version

/// What a version holds, as far as Graphite can show it.
enum ConflictVersionContent: Equatable {
    /// A note: the version's text, and its comparison with the current note unless the
    /// two differ over too many lines.
    case note(text: String, comparison: TextVersionComparison?)
    /// Any other file, shown by the preview of its kind.
    case file(URL)
    case unavailable(String)

    /// Reads a version for its preview. Notes are compared off the main thread.
    @MainActor
    static func load(_ version: FileConflictVersion, of path: VaultPath, workspace: WorkspaceModel) async -> ConflictVersionContent {
        do {
            let location = try await workspace.contentsLocation(of: version, ofFileAt: path)
            guard DocumentKind(path: path) == .markdown, let store = workspace.store else { return .file(location) }
            let maximumBytes = MarkdownSession.maximumEditableBytes
            // A note too large for the editor is left to the system's preview as well.
            guard let currentData = try? await store.read(path, maximumBytes: maximumBytes).data else { return .file(location) }
            return try await Task.detached(priority: .userInitiated) {
                let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                // A version too large for the editor, or not text, is left to the system's preview.
                guard size <= maximumBytes,
                      let versionText = NoteTextEncoding.decode(try Data(contentsOf: location))?.text,
                      let currentText = NoteTextEncoding.decode(currentData)?.text else { return ConflictVersionContent.file(location) }
                return .note(text: versionText, comparison: TextVersionComparison.compare(current: currentText, otherVersion: versionText))
            }.value
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }
}

struct ConflictVersionPreview: View {
    @Bindable var workspace: WorkspaceModel
    let model: ConflictVersionsModel
    let version: FileConflictVersion
    /// Returns to the list of versions.
    let close: () -> Void
    @State private var content: ConflictVersionContent?
    @State private var showsWholeText = false
    @State private var isConfirmingReplacement = false

    private var fileName: String { workspace.preferences.displayName(for: model.path) }

    var body: some View {
        Group {
            switch content {
            case nil: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .note(let text, let comparison): notePreview(text: text, comparison: comparison)
            case .file(let location): ConflictVersionFilePreview(location: location, path: model.path)
            case .unavailable(let reason):
                ContentUnavailableView("This Version Can't Be Shown", systemImage: "exclamationmark.triangle", description: Text(reason))
            }
        }
        .navigationTitle(ConflictVersionsText.title(of: version))
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .confirmationDialog("Replace “\(fileName)” with this version?", isPresented: $isConfirmingReplacement, titleVisibility: .visible) {
            Button("Replace Current Version", role: .destructive) {
                close()
                Task { await model.replaceCurrentVersion(with: version) }
            }
        } message: {
            Text("The current version is not kept. To keep both, choose Keep as Separate File instead.")
        }
        .task(id: version.id) { content = await ConflictVersionContent.load(version, of: model.path, workspace: workspace) }
    }

    @ViewBuilder private func notePreview(text: String, comparison: TextVersionComparison?) -> some View {
        VStack(spacing: 0) {
            if let comparison {
                Picker("Show", selection: $showsWholeText) {
                    Text("Differences").tag(false)
                    Text("Whole Version").tag(true)
                }
                .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)
                Text(TextComparisonRows.summary(of: comparison)).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 6)
                Divider()
            } else {
                Text("The versions differ over too many lines to compare, so this version is shown whole.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.vertical, 8)
                Divider()
            }
            if let comparison, !showsWholeText {
                TextComparisonView(rows: TextComparisonRows.rows(for: comparison))
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("Keep as Separate File", systemImage: "plus.square.on.square") {
                close()
                Task { await model.keepAsSeparateFile(version) }
            }
            .accessibilityIdentifier("keepVersionAsSeparateFile")
            Button("Replace Current Version…", systemImage: "arrow.triangle.2.circlepath") { isConfirmingReplacement = true }
                .accessibilityIdentifier("replaceCurrentVersion")
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
        .disabled(content == nil || model.isWorking)
    }
}

/// A version of a file that is not a note, through the preview its kind has elsewhere.
private struct ConflictVersionFilePreview: View {
    let location: URL
    let path: VaultPath
    @State private var image: CGImage?
    @State private var hasLoadedImage = false

    var body: some View {
        switch DocumentKind(path: path) {
        case .image:
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFit().padding(16)
                } else if hasLoadedImage {
                    FilePreviewPane(location: location)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: location) {
                image = await ImagePaneContent.load(from: location, fileExtension: path.fileExtension).image
                hasLoadedImage = true
            }
        case .media:
            Group {
                if MediaFileKind.audioExtensions.contains(path.fileExtension) {
                    EmbeddedAudioPlayer(location: location, name: path.name)
                } else {
                    EmbeddedMediaPlayer(location: location)
                }
            }
            .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            FilePreviewPane(location: location)
        }
    }
}

// MARK: Comparison of two notes

/// The rows of a comparison as it is shown: changed lines with a few unchanged ones
/// around them, and the long unchanged stretches between folded into one row each.
enum TextComparisonRows {
    enum Row: Equatable, Identifiable {
        case line(index: Int, TextVersionComparison.Line)
        /// Unchanged lines left out, and how many.
        case unchangedLines(index: Int, count: Int)

        var id: Int {
            switch self {
            case .line(let index, _), .unchangedLines(let index, _): index
            }
        }
    }

    /// Unchanged lines shown before and after a change.
    static let contextLineCount = 3

    static func rows(for comparison: TextVersionComparison) -> [Row] {
        let lines = comparison.lines
        var rows: [Row] = []
        var index = 0
        while index < lines.count {
            guard case .unchanged = lines[index] else {
                rows.append(.line(index: index, lines[index])); index += 1
                continue
            }
            var runEnd = index
            while runEnd < lines.count, case .unchanged = lines[runEnd] { runEnd += 1 }
            // Context follows a change above and precedes a change below; the beginning
            // and the end of the note have a change on one side only.
            let leadingContext = index == 0 ? 0 : contextLineCount
            let trailingContext = runEnd == lines.count ? 0 : contextLineCount
            let runLength = runEnd - index
            if runLength <= leadingContext + trailingContext + 1 {
                for lineIndex in index..<runEnd { rows.append(.line(index: lineIndex, lines[lineIndex])) }
            } else {
                for lineIndex in index..<(index + leadingContext) { rows.append(.line(index: lineIndex, lines[lineIndex])) }
                rows.append(.unchangedLines(index: index + leadingContext, count: runLength - leadingContext - trailingContext))
                for lineIndex in (runEnd - trailingContext)..<runEnd { rows.append(.line(index: lineIndex, lines[lineIndex])) }
            }
            index = runEnd
        }
        return rows
    }

    static func summary(of comparison: TextVersionComparison) -> String {
        guard !comparison.isIdentical else { return "This version has the same text as the current one." }
        func lineCount(_ count: Int) -> String { count == 1 ? "1 line" : "\(count) lines" }
        return "Green: \(lineCount(comparison.linesOnlyInOtherVersion)) only in this version. Red: \(lineCount(comparison.linesOnlyInCurrent)) only in the current version."
    }
}

private struct TextComparisonView: View {
    let rows: [TextComparisonRows.Row]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    switch row {
                    case .line(_, let line): lineRow(line)
                    case .unchangedLines(_, let count):
                        Text(count == 1 ? "1 unchanged line" : "\(count) unchanged lines")
                            .font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 6)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder private func lineRow(_ line: TextVersionComparison.Line) -> some View {
        switch line {
        case .unchanged(let text): comparedLine(text, marker: " ", tint: nil, description: nil)
        case .onlyInOtherVersion(let text): comparedLine(text, marker: "+", tint: .green, description: "Only in this version")
        case .onlyInCurrent(let text): comparedLine(text, marker: "−", tint: .red, description: "Only in the current version")
        }
    }

    private func comparedLine(_ text: String, marker: String, tint: Color?, description: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker).foregroundStyle(tint ?? .clear).accessibilityHidden(true)
            // An empty line keeps its height.
            Text(text.isEmpty ? " " : text).textSelection(.enabled)
        }
        .font(.system(.callout, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 1)
        .background(tint?.opacity(0.14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(description.map { description in "\(description): \(text)" } ?? text)
    }
}

// MARK: Marks outside the sheet

/// A line over an open document that has other versions, with the way to them.
struct ConflictVersionsBanner: View {
    @Bindable var workspace: WorkspaceModel
    let path: VaultPath?

    var body: some View {
        if let path, workspace.conflictedPaths.contains(path) {
            HStack(spacing: 10) {
                Label(ConflictVersionsText.bannerText, systemImage: "square.on.square").font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Review Versions") { workspace.conflictVersionsRequest = ConflictVersionsRequest(path: path) }
                    .font(.callout).buttonStyle(.bordered)
                    .accessibilityIdentifier("reviewConflictVersions")
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(.quaternary.opacity(0.4))
            .accessibilityIdentifier("conflictVersionsBanner")
            Divider()
        }
    }
}

/// The small mark beside a file in the sidebar that has other versions.
struct ConflictVersionsMarker: View {
    var body: some View {
        Image(systemName: "square.on.square")
            .font(.caption).foregroundStyle(.orange)
            .accessibilityLabel(ConflictVersionsText.markerDescription)
    }
}
