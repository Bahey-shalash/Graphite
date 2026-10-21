import SwiftUI
import GraphiteCore

/// Settings › General › Add-ons: each pack Graphite can download, its size, and whether it is
/// on this device, with Download or Remove.
struct AddOnsSettingsSection: View {
    @Environment(AddOnLibrary.self) private var addOns: AddOnLibrary?

    var body: some View {
        if let addOns, !addOns.packs.isEmpty {
            Section {
                ForEach(addOns.packs) { pack in AddOnPackRow(pack: pack, state: addOns.state(of: pack), library: addOns) }
            } header: {
                Text("Add-ons")
            } footer: {
                Text("Extras Graphite downloads the first time a feature needs them, rather than carrying them in the app. "
                     + "They are kept on this device, outside your vaults. Removing one frees its space; it downloads again when needed.")
                    .formFooterAlignment()
            }
            .onAppear { addOns.refresh() }
        }
    }
}

private struct AddOnPackRow: View {
    let pack: AddOnPack
    let state: AddOnPackState
    let library: AddOnLibrary

    private var size: String { ByteCountFormatter.string(fromByteCount: pack.byteCount, countStyle: .file) }

    var body: some View {
        LabeledContent {
            switch state {
            case .notDownloaded, .failed:
                Button("Download") { library.download(pack) }
            case .downloading:
                ProgressView().controlSize(.small)
            case .downloaded:
                Button("Remove", role: .destructive) { library.remove(pack) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var detail: String {
        switch state {
        case .notDownloaded: "\(size), not downloaded"
        case .downloading: "Downloading \(size)…"
        case .downloaded: "\(size) on this device"
        case .failed(let reason): reason.explanation
        }
    }
}
