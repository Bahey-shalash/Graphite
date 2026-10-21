import SwiftUI
import GraphiteCore
import GraphiteApple

/// Edit for My Templates: drag to reorder, rename, hide from or show in the New Notebook sheet,
/// and delete. Hiding keeps the template's file; Delete removes it after a question.
struct MyTemplatesEditSheet: View {
    let model: MyTemplatesModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var renaming: MyPaperTemplateList.Template?
    @State private var newName = ""
    @State private var deleting: MyPaperTemplateList.Template?

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.templates) { template in row(template) }
                    .onMove { offsets, destination in model.move(fromOffsets: offsets, toOffset: destination) }
            }
            .navigationTitle("My Templates")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .overlay {
                if model.templates.isEmpty {
                    ContentUnavailableView("No Templates", systemImage: "doc.on.doc", description: Text("Add one with Add in the New Notebook sheet."))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 440)
        #endif
        .alert("Rename Template", isPresented: isRenaming, presenting: renaming) { template in
            TextField("Name", text: $newName)
            Button("Rename") { rename(template) }.disabled(FileNameRules.problem(with: trimmedNewName, isNote: false) != nil)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?", isPresented: isDeleting, titleVisibility: .visible, presenting: deleting) { template in
            Button("Delete", role: .destructive) { model.delete(template) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The template is deleted for good. Notebooks made from it are not changed, and neither is the file it was made from.")
        }
    }

    private func row(_ template: MyPaperTemplateList.Template) -> some View {
        let preview = model.previews[template.fileName]
        return HStack(spacing: 12) {
            NotebookPaperPicture(picture: preview?.image, pageSize: preview?.pageSize ?? CGSize(width: 595, height: 842), displayScale: displayScale)
                .frame(width: 44, height: 62)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).lineLimit(2)
                if template.isHidden { Text("Hidden").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            Button(template.isHidden ? "Show" : "Hide", systemImage: template.isHidden ? "eye" : "eye.slash") {
                model.setHidden(!template.isHidden, template: template)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            Menu {
                Button("Rename…", systemImage: "pencil") {
                    newName = template.name
                    renaming = template
                }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = template }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .labelStyle(.iconOnly)
        }
        .task { model.requestPreview(of: template.fileName) }
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            Button("Rename") {
                newName = template.name
                renaming = template
            }
            Button(template.isHidden ? "Show" : "Hide") { model.setHidden(!template.isHidden, template: template) }
            Button("Delete") { deleting = template }
        }
    }

    private var trimmedNewName: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { isShown in if !isShown { renaming = nil } })
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { isShown in if !isShown { deleting = nil } })
    }

    private func rename(_ template: MyPaperTemplateList.Template) {
        model.rename(template, to: trimmedNewName)
    }
}
