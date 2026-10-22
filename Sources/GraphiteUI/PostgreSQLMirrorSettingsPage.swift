import SwiftUI
import GraphitePostgreSQLMirror

/// Settings › PostgreSQL Mirror: the server, a connection test, Copy Now, and what the last
/// copy did. Edits apply when saved, so a half-typed address never reaches the network.
struct PostgreSQLMirrorSettingsPage: View {
    let mirror: PostgreSQLMirrorController
    @Bindable var preferences: GraphitePreferences
    /// Copies the open vault now, with the settings just saved.
    let copyNow: () -> Void
    @State private var draft = PostgreSQLMirrorConfiguration()
    @State private var password = ""
    @State private var savedPassword = ""
    @State private var connectionTest = ConnectionTest.notRun
    @State private var saveError: String?

    private enum ConnectionTest: Equatable {
        case notRun
        case running
        case succeeded(PostgreSQLServerDescription)
        case failed(String)
    }

    private var hasUnsavedChanges: Bool { draft != preferences.postgreSQLMirrorConfiguration || password != savedPassword }

    var body: some View {
        Form {
            Section {
                field("Address", prompt: "localhost or db.example.org", text: $draft.host)
                LabeledContent("Port") {
                    TextField("Port", value: $draft.port, format: .number.grouping(.never), prompt: Text(String(PostgreSQLMirrorConfiguration.defaultPort)))
                        .multilineTextAlignment(.trailing)
                        #if canImport(UIKit)
                        .keyboardType(.numberPad)
                        #endif
                }
                field("Database", prompt: "notes", text: $draft.databaseName)
                field("User", prompt: "postgres", text: $draft.userName)
                LabeledContent("Password") {
                    SecureField("Password", text: $password, prompt: Text("Optional"))
                        .multilineTextAlignment(.trailing)
                }
                Picker("Encryption", selection: $draft.transportSecurity) {
                    Text("When the Server Offers It").tag(PostgreSQLMirrorConfiguration.TransportSecurity.preferred)
                    Text("Required, Verified Certificate").tag(PostgreSQLMirrorConfiguration.TransportSecurity.verified)
                    Text("Off").tag(PostgreSQLMirrorConfiguration.TransportSecurity.off)
                }
            } header: {
                Text("Server")
            } footer: {
                Text("The password stays in this device's keychain. Off suits a server on this device or a network you trust.")
                    .formFooterAlignment()
            }
            Section {
                field("Schema", prompt: PostgreSQLMirrorConfiguration.defaultSchemaName, text: $draft.schemaName)
            } footer: {
                (Text("Graphite creates the schema if it is missing and keeps its tables there: notes, links, and the views notes_with_properties ")
                    + Text("(one column per property) and, with PostGIS, links_on_map. ")
                    + Text("Notes are copied a few seconds after they change; nothing is ever copied back into the vault."))
                    .formFooterAlignment()
            }
            Section {
                Button("Save and Copy Now", systemImage: "arrow.triangle.2.circlepath") { saveAndCopy() }
                    .disabled(draft.missingSetting != nil)
                Button("Test Connection", systemImage: "bolt.horizontal") { testConnection() }
                    .disabled(draft.missingSetting != nil || connectionTest == .running)
            } footer: {
                if let missingSetting = draft.missingSetting {
                    Text("Fill in \(missingSetting) to start copying.").formFooterAlignment()
                } else if let saveError {
                    Text(saveError).foregroundStyle(.red).formFooterAlignment()
                } else {
                    connectionTestText.formFooterAlignment()
                }
            }
            Section("Last Copy") {
                statusContent
            }
        }
        .navigationTitle("PostgreSQL Mirror")
        .onAppear {
            draft = preferences.postgreSQLMirrorConfiguration
            savedPassword = mirror.readPassword()
            password = savedPassword
        }
        .onChange(of: draft) { connectionTest = .notRun }
        .onChange(of: password) { connectionTest = .notRun }
    }

    private func field(_ title: String, prompt: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                #endif
                .onSubmit { if hasUnsavedChanges, draft.missingSetting == nil { saveAndCopy() } }
        }
    }

    @ViewBuilder private var connectionTestText: some View {
        switch connectionTest {
        case .notRun:
            Text(hasUnsavedChanges ? "Changes apply once saved." : "Copies follow the vault while this plugin is on.")
        case .running:
            Text("Connecting…")
        case .succeeded(let server):
            if let postGISVersion = server.postGISVersion {
                Text("Connected to PostgreSQL \(server.version) with PostGIS \(postGISVersion).")
            } else {
                Text("Connected to PostgreSQL \(server.version). ")
                    + Text("PostGIS is not installed in this database: notes get a latitude and a longitude, without a geometry for map apps.")
            }
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }

    @ViewBuilder private var statusContent: some View {
        switch mirror.status {
        case .idle:
            Text(preferences.postgreSQLMirrorConfiguration.missingSetting == nil ? "No copy yet since Graphite opened this vault." : "Not set up yet.")
                .foregroundStyle(.secondary)
        case .copying:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Copying…")
            }
        case .copied(let report, let finishedAt):
            VStack(alignment: .leading, spacing: 4) {
                Text("\(report.copiedNoteCount.formatted()) notes in the database")
                Text(Self.changes(in: report) + " · " + finishedAt.formatted(.relative(presentation: .named)))
                    .font(.caption).foregroundStyle(.secondary)
                if !report.hasGeometry {
                    (Text("Without PostGIS, notes have a latitude and a longitude but no geometry. ")
                        + Text("Install it in the database (CREATE EXTENSION postgis) and the next copy adds one."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        case .failed(let message, let finishedAt):
            VStack(alignment: .leading, spacing: 4) {
                Text(message).foregroundStyle(.red)
                Text("Failed " + finishedAt.formatted(.relative(presentation: .named)) + ". Graphite tries again after the next change, or with Copy Now.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private static func changes(in report: PostgreSQLMirrorReport) -> String {
        guard report.writtenNoteCount > 0 || report.deletedNoteCount > 0 else { return "Nothing had changed" }
        var parts: [String] = []
        if report.writtenNoteCount > 0 {
            parts.append(report.writtenNoteCount == 1 ? "1 note written" : "\(report.writtenNoteCount.formatted()) notes written")
        }
        if report.deletedNoteCount > 0 { parts.append(report.deletedNoteCount == 1 ? "1 removed" : "\(report.deletedNoteCount.formatted()) removed") }
        return parts.joined(separator: ", ")
    }

    private func saveAndCopy() {
        do {
            try mirror.savePassword(password)
        } catch {
            saveError = PostgreSQLMirrorController.message(for: error)
            return
        }
        saveError = nil
        savedPassword = password
        preferences.postgreSQLMirrorConfiguration = draft
        copyNow()
    }

    private func testConnection() {
        connectionTest = .running
        let configuration = draft
        let password = password
        Task {
            do {
                let server = try await mirror.describeServer(configuration: configuration, password: password)
                connectionTest = .succeeded(server)
            } catch {
                connectionTest = .failed(PostgreSQLMirrorController.message(for: error))
            }
        }
    }
}
