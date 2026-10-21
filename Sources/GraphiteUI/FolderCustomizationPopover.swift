import SwiftUI
import PhotosUI
import GraphiteCore
import GraphiteApple

/// What the popover's Picture menu needs from the library.
struct FolderPictureActions {
    /// Pictures of the vault whose name matches; recent ones for an empty query.
    let findVaultPictures: (String) async -> [VaultPath]
    let readVaultPicture: (VaultPath) async throws -> Data
    /// Saves a framed picture in the vault and makes it the folder's look with the color given;
    /// returns the new look, or nil when it failed (the library reports why).
    let applyPicture: (CGImage, FolderPictureLayout, FolderColor?) async -> FolderStyle?
    /// Draws a look with Apple's folder art, for the previews.
    let drawPreview: (FolderStyle) async -> FolderTileImage?
    /// Apple's folder art in a color, the back layer of the icon maker's folder templates.
    let drawFolderArt: (FolderColor?) async -> CGImage?
}

/// A folder's look, chosen as in Finder's folder popover: a large preview with the folder's
/// name, one row of colors, the symbols in sections, then Clear and Emoji. Each choice is
/// applied at once, as Finder applies it.
struct FolderCustomizationPopover: View {
    let folderName: String
    let pictureActions: FolderPictureActions
    let apply: (FolderStyle?) -> Void
    @State private var draft: FolderStyle
    /// The draft as Apple's art draws it, redrawn after each choice.
    @State private var previewImage: FolderTileImage?
    @State private var pictureSource: FolderPictureSource?
    @State private var pickedPicture: PickedFolderPicture?
    @State private var pictureFailure: FolderPictureProblem?

    static let width: CGFloat = 330
    private static let previewSymbolPoints: CGFloat = 84
    private static let symbolGridHeight: CGFloat = 250
    private static let symbolCellPoints: CGFloat = 38

    init(folderName: String, style: FolderStyle?, previewImage: FolderTileImage?, pictureActions: FolderPictureActions,
         apply: @escaping (FolderStyle?) -> Void) {
        self.folderName = folderName
        self.pictureActions = pictureActions
        self.apply = apply
        _draft = State(initialValue: style ?? FolderStyle())
        _previewImage = State(initialValue: previewImage)
    }

    var body: some View {
        VStack(spacing: 12) {
            preview
            FolderColorSwatches(color: draft.color) { color in change { style in style.color = color } }
            Divider()
            symbolGrid
            Divider()
            // Finder's buttons: equal widths across the bottom, Clear first and Emoji last.
            HStack(spacing: 8) {
                Button { change { style in style = FolderStyle() } } label: {
                    // The plain button style does not dim a disabled button by itself.
                    Text("Clear").foregroundStyle(draft.isPlain ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary)).bottomButtonLabel()
                }
                    .disabled(draft.isPlain)
                pictureMenu
                EmojiInputButton(currentEmoji: currentEmoji) { emoji in change { style in style.mark = .emoji(emoji) } }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: Self.width)
        .modifier(FolderPicturePicking(source: $pictureSource, findVaultPictures: pictureActions.findVaultPictures,
                                       readVaultPicture: pictureActions.readVaultPicture,
                                       pick: { image in pickedPicture = PickedFolderPicture(image: image) },
                                       fail: { message in pictureFailure = message }))
        .sheet(item: $pickedPicture) { picked in
            let color = draft.color
            let drawFolderArt = pictureActions.drawFolderArt
            FolderIconMaker(picture: picked.image, folderName: folderName, drawFolderArt: { await drawFolderArt(color) }) { keptPicture, layout in
                applyPicture(keptPicture, layout: layout)
            }
            // A page-sized sheet gives the iPad room for the template column beside the preview.
            .presentationSizing(.page)
        }
        .alert("Picture Not Used", isPresented: Binding(get: { pictureFailure != nil }, set: { isShown in if !isShown { pictureFailure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(pictureFailure?.message ?? "")
        }
    }

    /// Photos, Files or a picture of the vault, as Finder takes a picture pasted on a folder.
    private var pictureMenu: some View {
        Menu {
            Button("Photos…", systemImage: "photo.on.rectangle") { pictureSource = .photos }
            Button("Files…", systemImage: "folder") { pictureSource = .files }
            Button("From Vault…", systemImage: "books.vertical") { pictureSource = .vault }
        } label: {
            Label("Picture", systemImage: "photo").bottomButtonLabel()
        }
        .menuIndicator(.hidden)
    }

    private func applyPicture(_ framedPicture: CGImage, layout: FolderPictureLayout) {
        let color = draft.color
        Task {
            guard let style = await pictureActions.applyPicture(framedPicture, layout, color) else { return }
            draft = style
        }
    }

    private var currentEmoji: String? {
        if case .emoji(let emojiText) = draft.mark { emojiText } else { nil }
    }

    private var preview: some View {
        VStack(spacing: 4) {
            FolderArtView(style: draft, image: previewImage, symbolPointSize: Self.previewSymbolPoints)
                .frame(height: Self.previewSymbolPoints * 1.25)
                .task(id: draft) { previewImage = await pictureActions.drawPreview(draft) }
            Text(folderName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(draft.isPlain ? "\(folderName), plain folder" : "\(folderName), \(draft.spokenDescription)")
    }

    private var symbolGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(FolderSymbolCatalog.sections) { section in
                    Section {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.symbolCellPoints), spacing: 4)], spacing: 4) {
                            ForEach(section.symbolNames, id: \.self) { symbolName in symbolButton(symbolName) }
                        }
                    } header: {
                        Text(section.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
        }
        .frame(height: Self.symbolGridHeight)
    }

    private func symbolButton(_ symbolName: String) -> some View {
        let isChosen = draft.mark == .symbol(symbolName)
        return Button {
            // Choosing the chosen symbol again takes it off, as in Finder.
            change { style in style.mark = isChosen ? nil : .symbol(symbolName) }
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 17))
                .frame(width: Self.symbolCellPoints, height: Self.symbolCellPoints)
                .foregroundStyle(isChosen ? Color.white : Color.secondary)
                .background {
                    if isChosen { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(FolderSymbolCatalog.spokenName(of: symbolName))
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func change(_ edit: (inout FolderStyle) -> Void) {
        edit(&draft)
        apply(draft.isPlain ? nil : draft)
    }
}

/// Finder's row of colors: no color (a crossed-out tag) and the seven tag colors, the colors
/// Finder and the Files app can show. The chosen one is ringed; a color an older build stored
/// rings the tag color it is written as.
private struct FolderColorSwatches: View {
    let color: FolderColor?
    let choose: (FolderColor?) -> Void

    /// Finder's swatch size, at the touch minimum of 28 points on the iPad and the iPhone.
    #if os(macOS)
    private static let swatchPoints: CGFloat = 24
    #else
    private static let swatchPoints: CGFloat = 28
    #endif
    /// Each swatch takes touches over a wider square than it draws, as close to the 44-point
    /// default as the popover's width allows for eight swatches.
    private static let swatchTouchPoints: CGFloat = 36

    var body: some View {
        HStack(spacing: 0) {
            swatch(for: nil) {
                Circle().fill(.background)
                    .overlay(Circle().strokeBorder(.tertiary, lineWidth: 1))
                    .overlay(CrossedOutLine().stroke(.secondary, lineWidth: 1.5))
            }
            ForEach(FolderColor.tagColors, id: \.self) { tagColor in
                swatch(for: tagColor) { Circle().fill(tagColor.tileColor) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The color as written on the folder.
    private var writtenColor: FolderColor? { color.flatMap(FinderTagColor.init(nearestTo:))?.folderColor }

    private func swatch(for swatchColor: FolderColor?, @ViewBuilder fill: () -> some View) -> some View {
        let isChosen = swatchColor == writtenColor
        return Button { choose(swatchColor) } label: {
            fill()
                .frame(width: Self.swatchPoints, height: Self.swatchPoints)
                .overlay { if isChosen { ring } }
                .frame(width: Self.swatchTouchPoints, height: Self.swatchTouchPoints)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(swatchColor?.title ?? "No Color")
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private var ring: some View {
        Circle().strokeBorder(.primary.opacity(0.55), lineWidth: 2).padding(-4)
    }
}

/// The line through the no-color swatch, from its lower left to its upper right.
private struct CrossedOutLine: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.2
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
        return path
    }
}

/// Where a folder's picture is chosen from.
enum FolderPictureSource: Identifiable {
    case photos, files, vault
    var id: Self { self }
}

/// The pickers of the Picture menu: the photo library, Files, or the vault. A chosen picture
/// is read and decoded off the main actor, at a bounded size, before it is handed over.
private struct FolderPicturePicking: ViewModifier {
    @Binding var source: FolderPictureSource?
    let findVaultPictures: (String) async -> [VaultPath]
    let readVaultPicture: (VaultPath) async throws -> Data
    let pick: (CGImage) -> Void
    let fail: (FolderPictureProblem) -> Void
    @State private var pickedPhoto: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: isPresenting(.photos), selection: $pickedPhoto, matching: .images)
            .fileImporter(isPresented: isPresenting(.files), allowedContentTypes: [.image]) { pickedFile in
                guard case .success(let location) = pickedFile else { return }
                decode { try await Task.detached(priority: .userInitiated) { try PickedImageFiles.imageData(at: location) }.value }
            }
            .sheet(isPresented: isPresenting(.vault)) {
                VaultPicturePicker(findPictures: findVaultPictures) { path in decode { try await readVaultPicture(path) } }
            }
            .onChange(of: pickedPhoto) { _, photo in
                guard let photo else { return }
                pickedPhoto = nil
                decode {
                    guard let imageData = try await photo.loadTransferable(type: Data.self) else { throw FolderPictureProblem.unreadable }
                    return imageData
                }
            }
    }

    private func isPresenting(_ presentedSource: FolderPictureSource) -> Binding<Bool> {
        Binding(get: { source == presentedSource }, set: { isPresented in if !isPresented, source == presentedSource { source = nil } })
    }

    private func decode(_ load: @escaping () async throws -> Data) {
        Task {
            do {
                let imageData = try await load()
                let image = await Task.detached(priority: .userInitiated) { FolderIconRenderer.decodedPicture(from: imageData) }.value
                guard let image else { return fail(.notAPicture) }
                pick(image)
            } catch is CancellationError {
                return
            } catch GraphiteError.oversized(_) {
                fail(.tooLarge)
            } catch {
                fail(.unreadable)
            }
        }
    }
}

/// Why a chosen picture was not used, worded for the alert.
enum FolderPictureProblem: Error {
    case unreadable, notAPicture, tooLarge

    var message: String {
        switch self {
        case .unreadable: "Graphite could not read this picture."
        case .notAPicture: "This file is not a picture Graphite can read."
        case .tooLarge: "This picture is too large to use."
        }
    }
}

extension View {
    /// A label of the popover's bottom buttons, which share its width equally as Finder's do.
    func bottomButtonLabel() -> some View {
        font(.callout)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
