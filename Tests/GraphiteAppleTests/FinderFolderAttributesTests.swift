import XCTest
import GraphiteCore
import GraphiteTestSupport
@testable import GraphiteApple

final class FinderFolderAttributesTests: XCTestCase {
    /// What Finder wrote on a folder given a color and an emoji is read the same on every platform.
    func testReadsFindersAttributes() throws {
        let vault = try TemporaryVault.make(prefix: "FinderLook", files: ["Lab/Note.md": "x"], for: self)
        let path = vault.location(of: "Lab").path
        try setAttribute(FinderFolderLook.tagsAttributeName, PropertyListSerialization.data(fromPropertyList: ["Green\n2"], format: .binary, options: 0), path)
        try setAttribute(FinderFolderLook.iconAttributeName, Data(#"{"emoji":"🥸"}"#.utf8), path)
        try setAttribute(FinderFolderLook.finderInformationAttributeName, Data([0, 0, 0, 0, 0, 0, 0, 0, 0x04] + [UInt8](repeating: 0, count: 23)), path)

        let look = FinderFolderAttributes(root: vault.root).look(of: try VaultPath("Lab"))

        XCTAssertEqual(look.style, FolderStyle(color: .green, mark: .emoji("🥸")))
        XCTAssertEqual(FinderFolderAttributes(root: vault.root).look(of: try VaultPath("Missing")), .plain)
    }

    #if os(macOS)
    /// The written attributes are the ones the system draws from: the folder's icon changes.
    func testAWrittenLookIsWhatTheSystemDraws() throws {
        let vault = try TemporaryVault.make(prefix: "FinderLook", files: ["Lab/Note.md": "x"], for: self)
        var tagged = vault.location(of: "Lab")
        var tagValues = URLResourceValues()
        tagValues.tagNames = ["Work"]
        try tagged.setResourceValues(tagValues)
        let attributes = FinderFolderAttributes(root: vault.root)
        let lab = try VaultPath("Lab")
        let plainIcon = try XCTUnwrap(attributes.systemIcon(of: lab, pixels: 64))
        let style = FolderStyle(color: .green, mark: .symbol("star.fill"))

        try attributes.write(FinderFolderLookChange.change(for: style, from: attributes.look(of: lab), colorTagNames: FinderFolderAttributes.colorTagNames()), to: lab)

        let look = attributes.look(of: lab)
        XCTAssertEqual(look.style, style)
        XCTAssertEqual(look.tags.first?.name, "Work")
        XCTAssertEqual(ShownFolderLook.resolve(stored: style, finder: look), .drawnByFinder(style))
        let styledIcon = try XCTUnwrap(attributes.systemIcon(of: lab, pixels: 64))
        XCTAssertNotEqual(pixels(of: styledIcon), pixels(of: plainIcon))

        try attributes.write(FinderFolderLookChange.change(for: nil, from: look, colorTagNames: FinderFolderAttributes.colorTagNames()), to: lab)

        let cleared = attributes.look(of: lab)
        XCTAssertFalse(cleared.isCustomized)
        XCTAssertEqual(cleared.tags.map(\.name), ["Work"])
        XCTAssertEqual(pixels(of: try XCTUnwrap(attributes.systemIcon(of: lab, pixels: 64))), pixels(of: plainIcon))
    }

    /// A picture written as Finder's custom icon is the folder's icon, and a symbol chosen
    /// afterwards replaces it.
    func testAPictureIsFindersCustomIcon() async throws {
        let vault = try TemporaryVault.make(prefix: "FinderLook", files: ["Lab/Note.md": "x"], for: self)
        let attributes = FinderFolderAttributes(root: vault.root)
        let lab = try VaultPath("Lab")
        let plainIcon = try XCTUnwrap(attributes.systemIcon(of: lab, pixels: 64))
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let picturePath = try await VaultStore(root: vault.root).saveFolderPicture(FolderIconRenderer.pngData(of: try XCTUnwrap(context.makeImage())))
        let style = FolderStyle(mark: .picture(FolderPicture(path: picturePath, layout: .onFolder)))

        try attributes.write(FinderFolderLookChange.change(for: style, from: attributes.look(of: lab), colorTagNames: [:]), to: lab)

        let look = attributes.look(of: lab)
        XCTAssertTrue(look.showsCustomIconFile)
        XCTAssertEqual(ShownFolderLook.resolve(stored: style, finder: look), .drawnByFinder(style))
        XCTAssertNotEqual(pixels(of: try XCTUnwrap(attributes.systemIcon(of: lab, pixels: 64))), pixels(of: plainIcon))

        try attributes.write(FinderFolderLookChange.change(for: FolderStyle(mark: .symbol("star.fill")), from: look, colorTagNames: [:]), to: lab)
        XCTAssertFalse(attributes.look(of: lab).hasCustomIconFile)
        XCTAssertEqual(attributes.look(of: lab).mark, .symbol("star.fill"))
    }

    private func pixels(of image: CGImage) -> Data {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context?.makeImage()?.dataProvider?.data as Data? ?? Data()
    }
    #endif

    private func setAttribute(_ name: String, _ attributeData: Data, _ path: String) throws {
        let status = attributeData.withUnsafeBytes { buffer in setxattr(path, name, buffer.baseAddress, buffer.count, 0, 0) }
        XCTAssertEqual(status, 0)
    }
}
