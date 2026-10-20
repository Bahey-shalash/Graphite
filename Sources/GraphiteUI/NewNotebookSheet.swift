import SwiftUI
import GraphiteCore
import GraphiteApple

/// Creating a notebook, after Goodnotes' New Notebook sheet: the first page large, the
/// name, size and paper color beside it, and every paper below as a picture to choose.
struct NewNotebookSheet<PlacementContent: View>: View {
    /// Where the new notebook goes, as the sheet describes it.
    let folderDescription: String
    let initialOptions: NewNotebookOptions
    /// Choices about where the notebook lives, shown above the paper when creating from a note.
    @ViewBuilder let placementContent: () -> PlacementContent
    let create: (String, NewNotebookOptions) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var name = ""
    @State private var options: NewNotebookOptions
    @State private var pictures = NotebookPaperPictures()

    init(folderDescription: String, initialOptions: NewNotebookOptions, @ViewBuilder placementContent: @escaping () -> PlacementContent,
         create: @escaping (String, NewNotebookOptions) -> Void) {
        self.folderDescription = folderDescription
        self.initialOptions = initialOptions
        self.placementContent = placementContent
        self.create = create
        _options = State(initialValue: initialOptions)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    summary
                    placementContent()
                    NotebookPaperGalleryView(options: $options, pictures: pictures)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle("New Notebook")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", systemImage: "checkmark", action: createIfValid)
                        .disabled(nameProblem != nil || options.problem != nil)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 560)
        #else
        // As large as Goodnotes' sheet, so the page sits beside its settings above the papers.
        .presentationSizing(.page)
        #endif
        .onAppear { pictures.draw(for: options) }
        .onChange(of: options) { _, changedOptions in pictures.draw(for: changedOptions) }
        .onDisappear { pictures.stop() }
    }

    /// The chosen first page beside its settings; one above the other on a narrow screen.
    @ViewBuilder private var summary: some View {
        if horizontalSizeClass == .compact {
            VStack(spacing: 20) {
                NotebookFirstPagePreview(picture: pictures.chosenPicture, pageSize: options.pageSize.pointSize, title: options.paperChoice.title)
                settings
            }
        } else {
            HStack(alignment: .top, spacing: 28) {
                NotebookFirstPagePreview(picture: pictures.chosenPicture, pageSize: options.pageSize.pointSize, title: options.paperChoice.title)
                    .frame(width: 240)
                settings
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 6) {
            NotebookSettingsCard {
                TextField("Untitled Notebook", text: $name)
                    .submitLabel(.done)
                    .onSubmit(createIfValid)
                    .accessibilityLabel("Name")
                    .padding(.vertical, 12)
                Divider()
                NotebookPageSizeMenu(pageSize: $options.pageSize)
                Divider()
                NotebookPaperColorMenu(paperColorHex: $options.paperStyle.paperColorHex)
                Divider()
                Stepper(value: $options.pageCount, in: NewNotebookOptions.pageCountRange) {
                    LabeledContent("Pages", value: options.pageCount.formatted())
                }
                .padding(.vertical, 8)
            }
            Text(footnote)
                .font(.footnote)
                .foregroundStyle(problemText == nil ? Color.secondary : Color.red)
                .padding(.horizontal, 4)
            NotebookCustomSizeFields(pageSize: $options.pageSize)
            NotebookPaperStyleSettings(paperStyle: $options.paperStyle, showsLineSettings: options.paperChoice != .blank)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footnote: String {
        problemText ?? "In “\(folderDescription)”"
    }

    private var problemText: String? {
        if let nameProblem, !name.isEmpty { return nameProblem }
        switch options.problem {
        case .pageSizeOutOfRange: return "Width and height must be from 72 to 2,880 points (1 to 40 inches)."
        case .pageCountOutOfRange: return "A notebook can have 1 to 1,000 pages."
        case nil: return nil
        }
    }

    /// An empty name is allowed: the notebook is then called "Untitled Notebook".
    private var nameProblem: String? {
        FileNameRules.problem(with: chosenName, isNote: false)
    }

    private var chosenName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Untitled Notebook" : trimmedName
    }

    private func createIfValid() {
        guard nameProblem == nil, options.problem == nil else { return }
        create(chosenName, options)
        dismiss()
    }
}

extension NewNotebookSheet where PlacementContent == EmptyView {
    init(folderDescription: String, initialOptions: NewNotebookOptions, create: @escaping (String, NewNotebookOptions) -> Void) {
        self.init(folderDescription: folderDescription, initialOptions: initialOptions, placementContent: { EmptyView() }, create: create)
    }
}

/// Rows on one rounded background, as the sheet's settings and Goodnotes' are grouped.
struct NotebookSettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(.horizontal, 16)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
