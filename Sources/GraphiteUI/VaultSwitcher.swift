import SwiftUI
import UniformTypeIdentifiers
import GraphiteCore
#if canImport(UIKit)
import UIKit
#endif

/// The vault name at the bottom of the sidebar. Like Obsidian's vault switcher, it lists
/// every known vault for a one-tap switch and leads to the vault manager.
struct VaultSwitcherBar: View {
    @Bindable var workspace: WorkspaceModel
    let manageVaults: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Menu {
                if !workspace.vaultLibrary.vaults.isEmpty {
                    Picker("Vaults", selection: Binding(get: { workspace.currentVaultIdentifier }, set: { identifier in
                        guard let identifier, let vault = workspace.vaultLibrary.vault(withIdentifier: identifier) else { return }
                        Task {
                            do { try await workspace.openVault(vault) }
                            catch { workspace.errorMessage = error.localizedDescription }
                        }
                    })) {
                        ForEach(workspace.vaultLibrary.vaults) { vault in
                            Text(vault.name).tag(Optional(vault.id))
                        }
                    }
                    .pickerStyle(.inline)
                }
                Button("Manage Vaults…", systemImage: "folder.badge.gearshape") { manageVaults() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "books.vertical").foregroundStyle(.tint)
                    // Concrete colors: a menu label's hierarchical styles would take the tint.
                    Text(workspace.store == nil ? "Choose a Vault" : workspace.title).font(.headline).foregroundStyle(Color.primary).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Color.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel(workspace.store == nil ? "Choose a vault" : "Vault \(workspace.title)")
            .accessibilityHint("Switches to another vault")
            if workspace.store != nil && (workspace.isIndexing || !workspace.indexingMessage.isEmpty) {
                HStack(spacing: 6) {
                    if workspace.isIndexing { ProgressView().controlSize(.mini) }
                    Text(workspace.indexingMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.leading, 30)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// Obsidian's vault manager: every known vault, plus creating a vault or opening a folder
/// as one. Shown as a sheet, and as the welcome screen when no vault is open.
struct VaultManagerView: View {
    @Bindable var workspace: WorkspaceModel
    /// A sheet closes once a vault opens; the welcome screen is replaced by the vault.
    var isPresentedAsSheet = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var showsFolderPicker = false
    @State private var showsNewVaultForm = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !isPresentedAsSheet {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "pencil.and.scribble").font(.system(size: 52, weight: .light)).foregroundStyle(.tint)
                        Text("Welcome to Graphite").font(.largeTitle.weight(.semibold))
                        Text("Notes, handwriting, PDFs, and lectures, kept in ordinary files you own. A vault is a folder, and it can be an existing Obsidian vault.")
                            .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .listRowBackground(Color.clear)
                }
            }
            if !workspace.vaultLibrary.vaults.isEmpty {
                Section {
                    ForEach(workspace.vaultLibrary.vaults) { vault in
                        KnownVaultRow(vault: vault, location: workspace.vaultLibrary.readableLocation(of: vault), isOpen: vault.id == workspace.currentVaultIdentifier) {
                            Task { await open { try await workspace.openVault(vault) } }
                        } remove: {
                            workspace.removeFromVaultList(vault)
                        }
                    }
                } header: {
                    // The sheet's title already says "Vaults".
                    if !isPresentedAsSheet { Text("Your vaults") }
                }
            }
            Section {
                Button { showsNewVaultForm = true } label: {
                    VaultActionLabel(title: "Create New Vault", detail: "Start a vault in a new, empty folder.", systemImage: "plus.rectangle.on.folder")
                }
                Button { showsFolderPicker = true } label: {
                    VaultActionLabel(title: "Open Folder as Vault", detail: "Choose an existing folder, such as an Obsidian vault in iCloud Drive.", systemImage: "folder")
                }
            } footer: {
                if !workspace.vaultLibrary.vaults.isEmpty {
                    Text("Removing a vault from this list forgets it and deletes its File recovery snapshots on this device. The folder and its files stay where they are.")
                }
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .navigationTitle(isPresentedAsSheet ? "Vaults" : "")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if isPresentedAsSheet { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .fileImporter(isPresented: $showsFolderPicker, allowedContentTypes: [.folder]) { pickedFolder in
            switch pickedFolder {
            case .success(let folder): Task { await open { try await workspace.openFolderAsVault(folder) } }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showsNewVaultForm) {
            NewVaultForm(workspace: workspace) { if isPresentedAsSheet { dismiss() } }
                .tint(accent)
        }
        .errorAlert($errorMessage)
    }

    /// Runs an opening action and closes the sheet once the vault is open.
    private func open(_ opening: () async throws -> Void) async {
        do {
            try await opening()
            if isPresentedAsSheet { dismiss() }
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct KnownVaultRow: View {
    let vault: KnownVault
    let location: String
    let isOpen: Bool
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: isOpen ? "folder.fill" : "folder").font(.title2).foregroundStyle(.tint).frame(width: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(vault.name).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
                    Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if isOpen { Text("Open").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOpen ? .isSelected : [])
        .contextMenu {
            if !isOpen { Button("Remove from List", systemImage: "minus.circle", role: .destructive, action: remove) }
        }
        .swipeActions {
            // Red like other destructive swipes, rather than the app's accent tint.
            if !isOpen { Button("Remove", systemImage: "minus.circle", role: .destructive, action: remove).tint(.red) }
        }
    }

    private var details: String {
        isOpen ? location : "\(location) · opened \(vault.lastOpenedDate.formatted(.relative(presentation: .named)))"
    }
}

private struct VaultActionLabel: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage).font(.title2).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                // A concrete color, so the button's tint does not wash out the description.
                Text(detail).font(.caption).foregroundStyle(Color.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Names a new vault and chooses where its folder goes.
private struct NewVaultForm: View {
    @Bindable var workspace: WorkspaceModel
    let didCreate: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    /// The folder that will contain the vault; nil means Graphite's own folder in Files.
    @State private var parentFolder: URL?
    @State private var showsParentFolderPicker = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Vault name", text: $name)
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.words)
                        #endif
                        .onSubmit(create)
                } footer: {
                    Text("A vault is an ordinary folder. Graphite creates an empty folder with this name.")
                }
                Section {
                    LabeledContent("Location") {
                        Text(locationDescription).foregroundStyle(parentFolder == nil && !Self.canUseGraphiteFolder ? .secondary : .primary)
                    }
                    Button("Choose Folder…", systemImage: "folder") { showsParentFolderPicker = true }
                    if Self.canUseGraphiteFolder && parentFolder != nil {
                        Button("Use Graphite's Folder", systemImage: "arrow.uturn.backward") { parentFolder = nil }
                    }
                } footer: {
                    Text(Self.canUseGraphiteFolder
                         ? "Graphite's folder appears in the Files app. To sync with your other devices, choose a folder in iCloud Drive. To use the vault in Obsidian on this device too, choose iCloud Drive › Obsidian."
                         : "To use the vault in Obsidian too, choose the folder where you keep your Obsidian vaults.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Vault")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create).disabled(!canCreate)
                }
            }
            .fileImporter(isPresented: $showsParentFolderPicker, allowedContentTypes: [.folder]) { pickedFolder in
                switch pickedFolder {
                case .success(let folder): parentFolder = folder
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
            .errorAlert($errorMessage)
        }
        .frame(minWidth: 360, minHeight: 320)
    }

    /// Only iOS shows an app's own Documents folder in Files; on the Mac it is hidden.
    private static var canUseGraphiteFolder: Bool {
        #if os(macOS)
        false
        #else
        true
        #endif
    }

    private var locationDescription: String {
        if let parentFolder { return parentFolder.lastPathComponent }
        #if canImport(UIKit)
        return "On My \(UIDevice.current.model) › Graphite"
        #else
        return "Choose a folder"
        #endif
    }

    private var canCreate: Bool {
        !isCreating && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (parentFolder != nil || Self.canUseGraphiteFolder)
    }

    private func create() {
        guard canCreate else { return }
        isCreating = true
        Task {
            defer { isCreating = false }
            do {
                try await workspace.createVault(named: name, in: parentFolder)
                dismiss(); didCreate()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

extension View {
    /// An alert for an error that belongs to this view, such as one inside a sheet.
    func errorAlert(_ errorMessage: Binding<String?>) -> some View {
        alert("Graphite", isPresented: Binding(get: { errorMessage.wrappedValue != nil }, set: { isPresented in if !isPresented { errorMessage.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage.wrappedValue ?? "") }
    }
}
