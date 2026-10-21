import SwiftUI
import GraphiteCore
import GraphiteApple

/// Choosing the page of a PDF (or checking a picture) and naming the template, before it is kept.
struct MyTemplateDraftSheet: View {
    let draft: MyTemplateDraft
    let model: MyTemplatesModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    private var nameProblem: String? {
        FileNameRules.problem(with: draft.name.trimmingCharacters(in: .whitespacesAndNewlines), isNote: false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    NotebookPaperPicture(picture: draft.pagePreviews[draft.selectedPageIndex], pageSize: pageSize, displayScale: displayScale)
                        .frame(maxHeight: 340)
                        .task(id: draft.selectedPageIndex) { await draft.drawPagePreview(of: draft.selectedPageIndex) }
                    if draft.pageCount > 1 { pagePicker }
                    nameField
                }
                .padding(20)
            }
            .navigationTitle("New Template")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: add).disabled(nameProblem != nil) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #else
        .presentationSizing(.page)
        #endif
    }

    /// The page's shape, which the small picture shows once drawn.
    private var pageSize: CGSize {
        guard let picture = draft.pagePreviews[draft.selectedPageIndex] else { return CGSize(width: 595, height: 842) }
        return CGSize(width: picture.width, height: picture.height)
    }

    private var pagePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper("Page \(draft.selectedPageIndex + 1) of \(draft.pageCount)", value: Binding(get: { draft.selectedPageIndex + 1 }, set: { number in
                draft.selectPage(number - 1)
            }), in: 1...draft.pageCount)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(0..<draft.pageCount, id: \.self) { pageIndex in pageTile(pageIndex) }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func pageTile(_ pageIndex: Int) -> some View {
        let isChosen = pageIndex == draft.selectedPageIndex
        return Button {
            draft.selectPage(pageIndex)
        } label: {
            VStack(spacing: 4) {
                NotebookPaperPicture(picture: draft.pagePreviews[pageIndex], pageSize: CGSize(width: 595, height: 842), displayScale: displayScale)
                    .frame(width: 72, height: 102)
                    .overlay { if isChosen { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2) } }
                Text("\(pageIndex + 1)").font(.caption).foregroundStyle(isChosen ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(pageIndex + 1)")
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .task { await draft.drawPagePreview(of: pageIndex) }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            NotebookSettingsCard {
                TextField("Name", text: Binding(get: { draft.name }, set: { draft.rename(to: $0) }))
                    .submitLabel(.done)
                    .onSubmit(add)
                    .padding(.vertical, 12)
            }
            Text(nameProblem.flatMap { _ in draft.name.isEmpty ? nil : nameProblem } ?? "Kept in the vault, so it is there on your other devices.")
                .font(.footnote)
                .foregroundStyle(draft.name.isEmpty || nameProblem == nil ? Color.secondary : Color.red)
        }
    }

    private func add() {
        guard nameProblem == nil else { return }
        model.add(draft, named: draft.name.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}
