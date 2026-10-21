import SwiftUI
import GraphiteCore
import GraphiteApple

/// One thing the New menu creates.
enum CreatableItem: Hashable, Identifiable {
    case document(CreationKind)
    case dailyNote
    case scanDocuments
    case pictureFromPhotos
    case takePhoto
    case importFiles
    case folder

    var id: Self { self }

    var title: String {
        switch self {
        case .document(.notebook): "Notebook"
        case .document(.note): "Note"
        case .document(.canvas): "Canvas"
        case .document(.base): "Base"
        case .dailyNote: "Today's Daily Note"
        case .scanDocuments: "Scan Documents"
        case .pictureFromPhotos: "Image from Photos"
        case .takePhoto: "Take Photo"
        case .importFiles: "Import"
        case .folder: "Folder"
        }
    }

    /// What the item makes, under its title in the large choices.
    var subtitle: String {
        switch self {
        case .document(.notebook): "PDF pages for Apple Pencil"
        case .document(.note): "Markdown text"
        case .document(.canvas): "Cards on a board"
        case .document(.base): "A table of notes"
        case .dailyNote: "Opens or creates it"
        case .scanDocuments: "Paper pages into a PDF notebook"
        case .pictureFromPhotos: "A picture from your photo library, as a file here"
        case .takePhoto: "With the camera, as a file here"
        case .importFiles: "PDFs, images and other files"
        case .folder: "In this folder"
        }
    }

    var systemImage: String {
        switch self {
        case .document(.notebook): "book.closed"
        case .document(.note): "doc.text"
        case .document(.canvas): "rectangle.3.group"
        case .document(.base): "tablecells"
        case .dailyNote: "calendar"
        case .scanDocuments: "doc.viewfinder"
        case .pictureFromPhotos: "photo"
        case .takePhoto: "camera"
        case .importFiles: "square.and.arrow.down"
        case .folder: "folder.badge.plus"
        }
    }

    /// The core plugin an item needs, or nil when it is always offered.
    var requiredPlugin: CorePlugin? {
        switch self {
        case .document(.canvas): .canvas
        case .document(.base): .bases
        case .dailyNote: .dailyNotes
        case .document(.notebook), .document(.note), .scanDocuments, .pictureFromPhotos, .takePhoto, .importFiles, .folder: nil
        }
    }

    /// The two large choices first, in the order the person's note-taking asks for, then the
    /// rest; items whose plugin is off are left out, and Scan Documents and Take Photo are left out
    /// where the device has no camera for them.
    static func offered(firstKind: CreationKind, isEnabled: (CorePlugin) -> Bool, canScanDocuments: Bool,
                        canTakePhoto: Bool) -> (large: [CreatableItem], others: [CreatableItem]) {
        let large: [CreatableItem] = firstKind == .note ? [.document(.note), .document(.notebook)] : [.document(.notebook), .document(.note)]
        let others: [CreatableItem] = [.document(.canvas), .document(.base), .dailyNote, .scanDocuments, .pictureFromPhotos, .takePhoto, .importFiles, .folder]
        return (large, others.filter { item in
            switch item {
            case .scanDocuments: canScanDocuments
            case .takePhoto: canTakePhoto
            case .document, .dailyNote, .pictureFromPhotos, .importFiles, .folder: item.requiredPlugin.map(isEnabled) ?? true
            }
        })
    }
}

/// The New menu, after Goodnotes': a notebook and a note as large choices, the other kinds
/// below. A popover on the iPad and the Mac, a sheet on the iPhone.
struct NewItemPicker: View {
    let firstKind: CreationKind
    let isEnabled: (CorePlugin) -> Bool
    let canScanDocuments: Bool
    let canTakePhoto: Bool
    let choose: (CreatableItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let offered = CreatableItem.offered(firstKind: firstKind, isEnabled: isEnabled, canScanDocuments: canScanDocuments, canTakePhoto: canTakePhoto)
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ForEach(offered.large) { item in largeChoice(item) }
            }
            VStack(spacing: 0) {
                ForEach(Array(offered.others.enumerated()), id: \.element) { position, item in
                    if position > 0 { Divider().padding(.leading, 52) }
                    row(item)
                }
            }
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(16)
        .frame(idealWidth: 380)
        .presentationDetents([.medium, .large])
    }

    private func largeChoice(_ item: CreatableItem) -> some View {
        Button {
            pick(item)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.title)
                Text(item.title)
                    .font(.headline)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .padding(.horizontal, 8)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: CreatableItem) -> some View {
        Button {
            pick(item)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: item.systemImage)
                    .frame(width: 24)
                    .foregroundStyle(.tint)
                Text(item.title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(item.subtitle)
    }

    private func pick(_ item: CreatableItem) {
        dismiss()
        choose(item)
    }
}

/// What the New menu's choices do, for one folder.
struct NewItemActions {
    /// The folder new items go to; nil for the vault's location for new files.
    let directory: VaultPath?
    let create: (CreationKind, VaultPath?) -> Void
    let openDailyNote: () -> Void
    let newFolder: (VaultPath?) -> Void
    let importFiles: ([URL], VaultPath?) -> Void
    /// Saves a finished document scan as a new PDF notebook in the folder, and opens it. Nil
    /// where the device cannot scan documents, which leaves Scan Documents out of the menu.
    let saveScannedNotebook: (@MainActor (ScannedDocumentPDF, Date, VaultPath?) async -> Void)?
    /// Tells the person why a scan could not be used.
    let reportProblem: @MainActor (String) -> Void
    /// Saves a picture (its data, when it was taken) as a file in the folder and opens it.
    let savePicture: @MainActor (Data, Date, VaultPath?) async -> Void
    /// Whether this device has a camera, which Take Photo needs.
    let canTakePhoto: Bool
}

/// A New button that opens `NewItemPicker`, and the file chooser its Import asks for.
struct NewItemButton<Label: View>: View {
    let firstKind: CreationKind
    let isEnabled: (CorePlugin) -> Bool
    let actions: NewItemActions
    @ViewBuilder let label: () -> Label
    @State private var showsPicker = false
    @State private var showsImporter = false
    @State private var showsScanner = false
    @State private var showsPhotoPicker = false
    @State private var showsCamera = false
    @State private var scanProcessing = DocumentScanProcessing(wordRecognizer: .onDevice)

    var body: some View {
        Button(action: openPickerOrCancelScan) {
            // A scan takes a few seconds to become a PDF; the button shows it, and a tap cancels it.
            if scanProcessing.isProcessing { ProgressView().frame(width: 44, height: 44) } else { label() }
        }
            .accessibilityHint(scanProcessing.isProcessing ? "Preparing a scan. Cancels it." : "")
            .popover(isPresented: $showsPicker) {
                NewItemPicker(firstKind: firstKind, isEnabled: isEnabled, canScanDocuments: actions.saveScannedNotebook != nil,
                              canTakePhoto: actions.canTakePhoto, choose: perform)
            }
            .modifier(scanPresentation)
            .modifier(NewItemPicturePresentation(showsPhotoPicker: $showsPhotoPicker, showsCamera: $showsCamera,
                                                 directory: actions.directory, save: actions.savePicture))
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                // A cancelled chooser imports nothing; there is nothing to report.
                guard case .success(let sources) = result, !sources.isEmpty else { return }
                actions.importFiles(sources, actions.directory)
            }
    }

    private func openPickerOrCancelScan() {
        if scanProcessing.isProcessing { scanProcessing.cancel() } else { showsPicker = true }
    }

    /// The scanner Scan Documents opens; its PDF becomes a notebook in this button's folder.
    private var scanPresentation: DocumentScanPresentation {
        let directory = actions.directory
        let saveScannedNotebook = actions.saveScannedNotebook
        return DocumentScanPresentation(isPresented: $showsScanner, processing: scanProcessing,
                                        save: { scan, scannedAt in await saveScannedNotebook?(scan, scannedAt, directory) },
                                        report: actions.reportProblem)
    }

    private func perform(_ item: CreatableItem) {
        switch item {
        case .document(let kind): actions.create(kind, actions.directory)
        case .dailyNote: actions.openDailyNote()
        case .scanDocuments: showsScanner = true
        case .pictureFromPhotos: showsPhotoPicker = true
        case .takePhoto: showsCamera = true
        case .importFiles: showsImporter = true
        case .folder: actions.newFolder(actions.directory)
        }
    }
}
