import SwiftUI
import ImageIO
import GraphiteCore
import GraphiteApple
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// What a view can do with a row or a value, provided by the base's container.
struct BaseViewActions {
    let openPath: (VaultPath) -> Void
    let openLink: (BaseLink) -> Void
    /// Nil when the cell cannot be edited from the base.
    let editRequest: (VaultPath, BasePropertyIdentifier, BaseCellValue) -> BaseEditRequest?
    let beginEditing: (BaseEditRequest) -> Void
    /// Toggles a checkbox cell from the value it shows.
    let toggleCheckbox: (BaseEditRequest, Bool) -> Void
    /// The value a checkbox tap asked for while its save runs, shown in place of the cell's.
    let requestedCheckboxValue: (BaseEditRequest) -> Bool?
    let thumbnails: BaseThumbnailStore
    let vaultRoot: URL
    /// Changes when vault files change, so images check their files again.
    let contentVersion: Int
}

extension BasePropertyIdentifier {
    /// Whether the property's values are tags, so each `#` string shows as a tag chip.
    var holdsTags: Bool { self == .file("tags") }
}

/// A request to edit one note property from a base.
struct BaseEditRequest: Identifiable {
    let path: VaultPath
    let property: BasePropertyIdentifier
    let displayName: String
    let kind: BasePropertyEditorKind
    let currentValue: BaseValue?
    var id: String { path.rawValue + "\u{0}" + property.rawValue }
}

/// Renders one computed cell. Errors stay visible in the cell with their message.
struct BaseCellView: View {
    let cell: BaseCellValue
    let lineLimit: Int
    let actions: BaseViewActions
    var editRequest: BaseEditRequest?
    /// Whether `#` strings are tags whatever they look like, as in `file.tags`.
    var holdsTags = false

    var body: some View {
        switch cell {
        case .error(let message):
            Label {
                Text(message).lineLimit(lineLimit)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(.red)
            .help(message)
            .accessibilityLabel("Error: \(message)")
        case .value(let value):
            BaseValueView(value: value, lineLimit: lineLimit, actions: actions, editRequest: editRequest, holdsTags: holdsTags)
        }
    }
}

struct BaseValueView: View {
    let value: BaseValue
    let lineLimit: Int
    let actions: BaseViewActions
    var editRequest: BaseEditRequest?
    var holdsTags = false

    var body: some View {
        switch value {
        case .null:
            Text(" ").accessibilityLabel("Empty")
        case .boolean(let storedValue):
            if let editRequest {
                let isOn = actions.requestedCheckboxValue(editRequest) ?? storedValue
                Button {
                    actions.toggleCheckbox(editRequest, isOn)
                } label: {
                    Image(systemName: isOn ? "checkmark.square.fill" : "square")
                        .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isOn ? "Checked" : "Unchecked")
            } else {
                Image(systemName: storedValue ? "checkmark.square.fill" : "square")
                    .foregroundStyle(storedValue ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary))
                    .accessibilityLabel(storedValue ? "Checked" : "Unchecked")
            }
        case .number:
            Text(value.displayText).monospacedDigit().lineLimit(1)
        case .string(let text):
            if Self.isTag(text, isKnownTag: holdsTags) {
                BaseTagChip(text: text)
            } else if let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                Link(text, destination: url).lineLimit(lineLimit)
            } else {
                Text(text).lineLimit(lineLimit)
            }
        case .date(let date):
            Text(Self.formatted(date)).monospacedDigit().lineLimit(1)
        case .link(let link):
            if link.isExternal, let url = URL(string: link.target) {
                Link(link.displayText, destination: url).lineLimit(lineLimit)
            } else {
                Button(link.displayText) { actions.openLink(link) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tint)
                    .lineLimit(lineLimit)
            }
        case .file(let path):
            Button(value.displayText) { actions.openPath(path) }
                .buttonStyle(.borderless)
                .foregroundStyle(.tint)
                .lineLimit(lineLimit)
        case .list(let elements):
            BaseListValueView(elements: elements, actions: actions, holdsTags: holdsTags)
        case .image(let target):
            BaseImageValueView(target: target, actions: actions)
        case .icon(let name):
            if let symbolName = BaseIconMapping.symbolName(forLucideIcon: name) {
                Image(systemName: symbolName).help(name).accessibilityLabel(name)
            } else {
                Text(name).foregroundStyle(.secondary).lineLimit(1)
            }
        case .duration, .object, .regularExpression:
            Text(value.displayText).lineLimit(lineLimit)
        }
    }

    /// Whether a string shows as a tag chip. Obsidian tags need a character other than a
    /// digit and hold no space or second `#`. A `#` and three to eight hex digits is usually
    /// a color, so it shows as text unless the value is known to be a tag.
    static func isTag(_ text: String, isKnownTag: Bool = false) -> Bool {
        guard text.hasPrefix("#") else { return false }
        let name = text.dropFirst()
        guard !name.isEmpty, !name.contains(" "), !name.contains("#"), !name.allSatisfy(\.isNumber) else { return false }
        return isKnownTag || !(name.allSatisfy(\.isHexDigit) && [3, 4, 6, 8].contains(name.count))
    }

    static func formatted(_ date: BaseDate) -> String {
        if date.hasTime { return date.date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute()) }
        return date.date.formatted(.dateTime.year().month(.abbreviated).day())
    }

    /// Summary numbers can be long fractions; three decimals are enough to read.
    static func summaryText(_ value: BaseValue) -> String {
        switch value {
        case .number(let number) where number.rounded() != number:
            return number.formatted(.number.precision(.fractionLength(0...3)))
        case .date(let date):
            return formatted(date)
        default:
            return value.displayText
        }
    }
}

struct BaseTagChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(.tint)
            .background(.tint.opacity(0.12), in: Capsule())
    }
}

/// Lists render as chips, like Obsidian's multi-value properties.
struct BaseListValueView: View {
    private static let maximumVisibleElements = 8
    let elements: [BaseValue]
    let actions: BaseViewActions
    var holdsTags = false

    var body: some View {
        NaturalWidthRow {
            listContent
        }
        .clipped()
    }

    private var listContent: some View {
        HStack(spacing: 4) {
            ForEach(Array(elements.prefix(Self.maximumVisibleElements).enumerated()), id: \.offset) { _, element in
                switch element {
                case .link, .file, .image, .icon, .boolean:
                    BaseValueView(value: element, lineLimit: 1, actions: actions)
                        .font(.callout)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                case .string(let text) where BaseValueView.isTag(text, isKnownTag: holdsTags):
                    BaseTagChip(text: text)
                default:
                    Text(BaseValueView.summaryText(element))
                        .font(.callout)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                }
            }
            if elements.count > Self.maximumVisibleElements {
                Text("+\(elements.count - Self.maximumVisibleElements)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Shows its content at its natural width within whatever width it is offered, so chips
/// that do not fit are cut off, as in Obsidian, instead of each being squeezed unreadable.
private struct NaturalWidthRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let naturalSize = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: min(proposal.width ?? naturalSize.width, naturalSize.width), height: naturalSize.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
    }
}

/// `image()` values in a cell: a small thumbnail of a vault image or URL.
struct BaseImageValueView: View {
    let target: String
    let actions: BaseViewActions
    @State private var resolvedReference: BaseImageReference?

    var body: some View {
        Group {
            if let resolvedReference {
                BaseCoverImageView(reference: resolvedReference, fit: .contain, thumbnails: actions.thumbnails, vaultRoot: actions.vaultRoot,
                                   contentVersion: actions.contentVersion)
                    .frame(width: 44, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Label(target, systemImage: "photo").labelStyle(.titleAndIcon).lineLimit(1).foregroundStyle(.secondary)
            }
        }
        .task(id: target) { resolvedReference = Self.reference(for: target) }
    }

    /// Links in `image()` were resolved to vault paths by the query when possible.
    static func reference(for target: String) -> BaseImageReference? {
        if target.hasPrefix("#"), BaseColorParsing.color(from: target) != nil { return .color(target) }
        if let url = URL(string: target), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return .remote(url) }
        if let path = try? VaultPath(target), !path.rawValue.isEmpty, DocumentKind(path: path) == .image { return .vaultFile(path) }
        return nil
    }
}

/// A card cover or inline image from a vault file, a URL, or a solid color. Images from
/// files and URLs go through the thumbnail store, so none is decoded at full size, and the
/// decoded image is kept rather than decoded again whenever the view redraws.
struct BaseCoverImageView: View {
    let reference: BaseImageReference
    let fit: BaseImageFit
    let thumbnails: BaseThumbnailStore
    let vaultRoot: URL
    /// A change makes the image check its file again, so an edited or newly downloaded
    /// image replaces the old picture or the error.
    let contentVersion: Int
    @Environment(\.accent) private var accent
    @State private var loadedCover: LoadedCover?

    /// The image shown for `reference`; a nil image means it could not be loaded.
    private struct LoadedCover {
        let reference: BaseImageReference
        /// The store's decoded thumbnail, shared by every card showing the same cover.
        let thumbnail: CGImage?
        let image: Image?
    }

    private struct CoverRequest: Hashable {
        let reference: BaseImageReference
        let contentVersion: Int
    }

    var body: some View {
        switch reference {
        case .color(let text):
            Rectangle().fill(BaseMarkerStyle.color(for: text, accent: accent) ?? Color.secondary.opacity(0.15))
        case .remote, .vaultFile:
            ZStack {
                if let loadedCover, loadedCover.reference == reference {
                    if let image = loadedCover.image {
                        fitted(image.resizable())
                    } else {
                        placeholder(systemImage: "photo.badge.exclamationmark")
                    }
                } else if case .remote = reference {
                    ProgressView()
                } else {
                    placeholder(systemImage: "photo")
                }
            }
            .task(id: CoverRequest(reference: reference, contentVersion: contentVersion)) { await loadCover() }
        }
    }

    private func loadCover() async {
        let requestedReference = reference
        do {
            let location: URL
            switch requestedReference {
            case .color: return
            case .remote(let url): location = url
            case .vaultFile(let path): location = try path.url(in: vaultRoot)
            }
            let thumbnail = try await thumbnails.thumbnail(at: location)
            if let loadedCover, loadedCover.reference == requestedReference, loadedCover.thumbnail === thumbnail { return }
            guard !Task.isCancelled else { return }
            loadedCover = LoadedCover(reference: requestedReference, thumbnail: thumbnail, image: Image(decorative: thumbnail, scale: 1))
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled else { return }
            loadedCover = LoadedCover(reference: requestedReference, thumbnail: nil, image: nil)
        }
    }

    @ViewBuilder private func fitted(_ image: Image) -> some View {
        switch fit {
        case .cover: image.scaledToFill()
        case .contain: image.scaledToFit()
        }
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            Rectangle().fill(Color.secondary.opacity(0.08))
            Image(systemName: systemImage).foregroundStyle(.secondary)
        }
    }
}

/// Decoded thumbnails for one base view, bounded by a byte budget. Decoding happens on
/// `ImageFileService`'s actor or, for images on the web, on a background thread, never on
/// the main actor. The pixels are kept decoded, not as PNG data, so cards showing the same
/// cover share one bitmap and none decodes it again when drawn.
///
/// Invariants: each location appears at most once in `insertionOrder`, `totalBytes` is the
/// sum of the cached thumbnails' pixel bytes, and at most one decode runs per location, since
/// many cards often share one cover and appear together. A cached thumbnail is used only
/// while its file's modification date and size are unchanged, so the cache can outlive
/// the index changes that re-run the base.
actor BaseThumbnailStore {
    typealias ThumbnailDecoder = @Sendable (URL, Int) async throws -> CGImage
    private static let maximumBytes = 32 * 1_048_576
    private static let maximumDimension = 640
    /// Larger downloads are refused before they are decoded.
    static let maximumRemoteImageBytes = 32 * 1_048_576

    private struct FileVersion: Equatable {
        let modificationDate: Date?
        let size: Int?
    }

    private struct CachedThumbnail {
        let image: CGImage
        let fileVersion: FileVersion
        var byteCount: Int { BaseThumbnailStore.byteCount(of: image) }
    }

    private struct PendingDecode {
        let identifier: UUID
        let fileVersion: FileVersion
        let task: Task<CGImage, any Error>
    }

    private let decodeThumbnail: ThumbnailDecoder
    private var cachedThumbnails: [URL: CachedThumbnail] = [:]
    private var pendingDecodes: [URL: PendingDecode] = [:]
    private var insertionOrder: [URL] = []
    private var totalBytes = 0

    init(decodeThumbnail: @escaping ThumbnailDecoder = BaseThumbnailStore.decodeWithImageService) {
        self.decodeThumbnail = decodeThumbnail
    }

    private static func decodeWithImageService(at location: URL, maximumDimension: Int) async throws -> CGImage {
        guard location.isFileURL else { return try await downloadedThumbnail(at: location, maximumDimension: maximumDimension) }
        return try await ImageFileService().displayImage(at: location, maximumPixelDimension: maximumDimension)
    }

    static func byteCount(of image: CGImage) -> Int { image.bytesPerRow * image.height }

    /// Downloads an image, refusing one larger than `maximumRemoteImageBytes`, and
    /// downsamples it like a vault image.
    static func downloadedThumbnail(at location: URL, maximumDimension: Int) async throws -> CGImage {
        let tooLargeError = GraphiteError.oversized("This image is larger than \(maximumRemoteImageBytes / 1_048_576) MB.")
        let (bytes, response) = try await URLSession.shared.bytes(from: location)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw GraphiteError.unavailable("The image could not be downloaded (HTTP \(httpResponse.statusCode)).")
        }
        guard response.expectedContentLength <= Int64(maximumRemoteImageBytes) else { throw tooLargeError }
        var imageData = Data()
        if response.expectedContentLength > 0 { imageData.reserveCapacity(Int(response.expectedContentLength)) }
        for try await byte in bytes {
            imageData.append(byte)
            guard imageData.count <= maximumRemoteImageBytes else { throw tooLargeError }
        }
        return try downsampledImage(from: imageData, maximumDimension: maximumDimension)
    }

    static func downsampledImage(from imageData: Data, maximumDimension: Int) throws -> CGImage {
        // Decoding immediately keeps the work on this background thread, not at first draw.
        guard let source = CGImageSourceCreateWithData(imageData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw GraphiteError.invalidFile("Cannot preview this image.") }
        return image
    }

    /// Bytes held by cached thumbnails, for tests of the budget.
    var cachedByteCount: Int { totalBytes }
    var cachedThumbnailCount: Int { cachedThumbnails.count }

    func thumbnail(at location: URL) async throws -> CGImage {
        let fileVersion = Self.fileVersion(at: location)
        if let cached = cachedThumbnails[location], cached.fileVersion == fileVersion { return cached.image }
        if let pending = pendingDecodes[location], pending.fileVersion == fileVersion { return try await pending.task.value }
        let decodeThumbnail = decodeThumbnail
        let pending = PendingDecode(identifier: UUID(), fileVersion: fileVersion,
                                    task: Task { try await decodeThumbnail(location, Self.maximumDimension) })
        pendingDecodes[location] = pending
        do {
            let image = try await pending.task.value
            // A newer decode of a changed file replaces this one and caches its own result.
            if pendingDecodes[location]?.identifier == pending.identifier {
                pendingDecodes[location] = nil
                insert(image, fileVersion: fileVersion, at: location)
            }
            return image
        } catch {
            if pendingDecodes[location]?.identifier == pending.identifier { pendingDecodes[location] = nil }
            throw error
        }
    }

    private func insert(_ image: CGImage, fileVersion: FileVersion, at location: URL) {
        if let replaced = cachedThumbnails.removeValue(forKey: location) {
            totalBytes -= replaced.byteCount
            insertionOrder.removeAll { cachedLocation in cachedLocation == location }
        }
        let thumbnail = CachedThumbnail(image: image, fileVersion: fileVersion)
        cachedThumbnails[location] = thumbnail
        insertionOrder.append(location)
        totalBytes += thumbnail.byteCount
        while totalBytes > Self.maximumBytes, !insertionOrder.isEmpty {
            let evicted = insertionOrder.removeFirst()
            totalBytes -= cachedThumbnails.removeValue(forKey: evicted)?.byteCount ?? 0
        }
    }

    private static func fileVersion(at location: URL) -> FileVersion {
        // An image on the web keeps its thumbnail until the budget evicts it.
        guard location.isFileURL else { return FileVersion(modificationDate: nil, size: nil) }
        // A file that cannot be examined gets an unknown version; decoding it reports why.
        let attributes = try? FileManager.default.attributesOfItem(atPath: location.path)
        return FileVersion(modificationDate: attributes?[.modificationDate] as? Date, size: (attributes?[.size] as? NSNumber)?.intValue)
    }
}

/// Maps Lucide icon names (used by Obsidian and the Maps plugin) to SF Symbols.
enum BaseIconMapping {
    private static let symbolsByLucideName: [String: String] = [
        "map-pin": "mappin", "pin": "pin.fill", "map": "map.fill", "landmark": "building.columns.fill", "building": "building.fill",
        "building-2": "building.2.fill", "castle": "building.columns", "church": "building.columns", "home": "house.fill",
        "house": "house.fill", "hotel": "bed.double.fill", "bed": "bed.double.fill", "star": "star.fill", "heart": "heart.fill",
        "coffee": "cup.and.saucer.fill", "utensils": "fork.knife", "utensils-crossed": "fork.knife", "pizza": "fork.knife",
        "beer": "mug.fill", "wine": "wineglass.fill", "book": "book.fill", "book-open": "book.fill", "library": "books.vertical.fill",
        "school": "graduationcap.fill", "graduation-cap": "graduationcap.fill", "tree": "tree.fill", "trees": "tree.fill",
        "tree-pine": "tree.fill", "mountain": "mountain.2.fill", "mountain-snow": "mountain.2.fill", "tent": "tent.fill",
        "waves": "water.waves", "sun": "sun.max.fill", "moon": "moon.fill", "plane": "airplane", "train": "tram.fill",
        "train-front": "tram.fill", "tram-front": "tram.fill", "bus": "bus.fill", "car": "car.fill", "bike": "bicycle",
        "ship": "ferry.fill", "sailboat": "sailboat.fill", "fuel": "fuelpump.fill", "shopping-cart": "cart.fill",
        "shopping-bag": "bag.fill", "store": "storefront.fill", "camera": "camera.fill", "music": "music.note",
        "film": "film", "clapperboard": "film", "theater": "theatermasks.fill", "drama": "theatermasks.fill",
        "palette": "paintpalette.fill", "flag": "flag.fill", "user": "person.fill", "users": "person.2.fill",
        "briefcase": "briefcase.fill", "hospital": "cross.case.fill", "stethoscope": "stethoscope", "dumbbell": "dumbbell.fill",
        "globe": "globe", "compass": "safari.fill", "anchor": "ferry.fill", "gift": "gift.fill", "bookmark": "bookmark.fill",
        "lightbulb": "lightbulb.fill", "info": "info.circle.fill", "circle": "circle.fill", "square": "square.fill",
        "triangle": "triangle.fill", "check": "checkmark", "x": "xmark", "alert-triangle": "exclamationmark.triangle.fill",
        "triangle-alert": "exclamationmark.triangle.fill", "flower": "leaf.fill", "leaf": "leaf.fill", "dog": "dog.fill",
        "cat": "cat.fill", "fish": "fish.fill", "bird": "bird.fill", "trophy": "trophy.fill", "medal": "medal.fill",
        "microscope": "microscope", "flask-conical": "flask.fill", "cpu": "cpu", "laptop": "laptopcomputer",
        "phone": "phone.fill", "mail": "envelope.fill", "calendar": "calendar", "clock": "clock.fill", "zap": "bolt.fill",
        "parking-circle": "parkingsign.circle.fill", "square-parking": "parkingsign", "tower-control": "antenna.radiowaves.left.and.right",
        "university": "building.columns.fill", "museum": "building.columns.fill", "bridge": "road.lanes",
        // Food and drink, common on restaurant maps. Symbols the system lacks fall back to a dot.
        "ice-cream-cone": "birthday.cake.fill", "ice-cream-bowl": "birthday.cake.fill", "ice-cream": "birthday.cake.fill",
        "cake": "birthday.cake.fill", "cake-slice": "birthday.cake.fill", "croissant": "birthday.cake.fill", "cookie": "birthday.cake.fill",
        "dessert": "birthday.cake.fill", "candy": "birthday.cake.fill", "cup-soda": "takeoutbag.and.cup.and.straw.fill",
        "sandwich": "takeoutbag.and.cup.and.straw.fill", "soup": "takeoutbag.and.cup.and.straw.fill", "salad": "leaf.fill",
        "carrot": "carrot.fill", "martini": "wineglass.fill", "glass-water": "waterbottle.fill", "chef-hat": "fork.knife",
    ]

    static func symbolName(forLucideIcon name: String) -> String? {
        let normalizedName = name.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "lucide-", with: "")
        guard let symbolName = symbolsByLucideName[normalizedName], isAvailable(symbolName) else { return nil }
        return symbolName
    }

    private static func isAvailable(_ symbolName: String) -> Bool {
        #if canImport(UIKit)
        UIImage(systemName: symbolName) != nil
        #else
        NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) != nil
        #endif
    }
}

enum BaseMarkerStyle {
    static func color(for text: String, accent: Color) -> Color? {
        switch BaseColorParsing.color(from: text) {
        case .rgba(let red, let green, let blue, let alpha)?: return Color(red: red, green: green, blue: blue, opacity: alpha)
        case .accent?: return accent
        case .theme(let name)?:
            switch name {
            case "red": return .red
            case "orange": return .orange
            case "yellow": return .yellow
            case "green": return .green
            case "cyan": return .cyan
            case "blue": return .blue
            case "purple": return .purple
            case "pink": return .pink
            default: return accent
            }
        case nil: return nil
        }
    }
}

extension BaseViewType {
    var systemImage: String {
        switch self {
        case .table: "tablecells"
        case .cards: "square.grid.2x2"
        case .list: "list.bullet"
        case .map: "map"
        case .unsupported: "questionmark.square.dashed"
        }
    }
}
