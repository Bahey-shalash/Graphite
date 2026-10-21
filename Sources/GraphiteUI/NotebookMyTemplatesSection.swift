import SwiftUI
import PhotosUI
import GraphiteCore
import GraphiteApple

/// "My Templates" in the New Notebook sheet, beside the built-in papers: a page of a PDF or a
/// picture the person chose as paper, kept in the vault. A tap chooses one; Edit arranges, renames,
/// hides and deletes them; Add makes one.
struct NotebookMyTemplatesSection: View {
    @Binding var options: NewNotebookOptions
    let model: MyTemplatesModel
    @Environment(\.displayScale) private var displayScale
    @State private var draft: MyTemplateDraft?
    @State private var showsEditor = false
    @State private var showsFileImporter = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var problem: MyTemplateDraftError?

    private static let pictureWidthPoints: CGFloat = 112
    /// The shape of a tile whose picture is not drawn yet: A4.
    private static let defaultPageSize = CGSize(width: 595, height: 842)
    private let columns = [GridItem(.adaptive(minimum: pictureWidthPoints, maximum: 160), spacing: 20, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("My Templates").font(.headline)
                Spacer()
                if !model.templates.isEmpty { Button("Edit") { showsEditor = true } }
                addMenu
            }
            if model.shownTemplates.isEmpty {
                Text(emptyExplanation).font(.subheadline).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(model.shownTemplates) { template in tile(for: template) }
                }
            }
        }
        .sheet(item: $draft) { draft in MyTemplateDraftSheet(draft: draft, model: model) }
        .sheet(isPresented: $showsEditor) { MyTemplatesEditSheet(model: model) }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: false) { result in
            guard case .success(let locations) = result, let location = locations.first else { return } // A cancelled chooser adds nothing.
            Task { await open(location) }
        }
        .onChange(of: pickedPhoto) { _, photo in
            guard let photo else { return }
            pickedPhoto = nil
            Task { await open(photo) }
        }
        .onChange(of: model.shownTemplates) { keepChosenTemplateShown() }
        .modifier(MyTemplatesAlerts(model: model, problem: $problem))
    }

    private var emptyExplanation: String {
        model.templates.isEmpty
            ? "Make paper of a page of a PDF or of a picture. It is kept in your vault."
            : "Every template is hidden. Edit shows them."
    }

    private var addMenu: some View {
        Menu {
            Button("PDF Page or Picture…", systemImage: "doc") { showsFileImporter = true }
            PhotosPicker(selection: $pickedPhoto, matching: .images) { Label("Photo…", systemImage: "photo") }
        } label: {
            Label("Add", systemImage: "plus")
        }
    }

    private func tile(for template: MyPaperTemplateList.Template) -> some View {
        let isChosen = options.myTemplateFileName == template.fileName
        let preview = model.previews[template.fileName]
        return VStack(spacing: 8) {
            Button {
                options.choose(myTemplate: template.fileName)
            } label: {
                NotebookPaperPicture(picture: preview?.image, pageSize: preview?.pageSize ?? Self.defaultPageSize, displayScale: displayScale)
                    .frame(height: Self.pictureWidthPoints * 1.15)
                    .overlay(alignment: .bottom) {
                        if isChosen {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(.bottom, 8)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(template.name)
            .accessibilityAddTraits(isChosen ? .isSelected : [])
            Text(template.name)
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .task { model.requestPreview(of: template.fileName) }
    }

    /// A template that was hidden or deleted while chosen gives the choice back to the built-in paper.
    private func keepChosenTemplateShown() {
        guard let chosenFileName = options.myTemplateFileName else { return }
        guard !model.shownTemplates.contains(where: { template in template.fileName == chosenFileName }) else { return }
        options.choose(options.paperChoice)
    }

    private func open(_ location: URL) async {
        do { draft = try await MyTemplateDraft.read(from: location) } catch { problem = error as? MyTemplateDraftError ?? .unreadable }
    }

    private func open(_ photo: PhotosPickerItem) async {
        do {
            guard let photoData = try await photo.loadTransferable(type: Data.self) else { throw MyTemplateDraftError.unreadable }
            draft = try await MyTemplateDraft.make(from: photoData, sourceName: "Picture")
        } catch {
            problem = error as? MyTemplateDraftError ?? .unreadable
        }
    }
}

/// What the templates and a chosen file report once: a problem with the list, or a file that cannot be used.
private struct MyTemplatesAlerts: ViewModifier {
    let model: MyTemplatesModel
    @Binding var problem: MyTemplateDraftError?

    func body(content: Content) -> some View {
        content
            .alert(model.failure?.title ?? "", isPresented: Binding(get: { model.failure != nil }, set: { isShown in
                if !isShown { model.dismissFailure() }
            })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.failure?.message ?? "")
            }
            .alert("Can't Use This File", isPresented: Binding(get: { problem != nil }, set: { isShown in if !isShown { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem?.message ?? "")
            }
    }
}
