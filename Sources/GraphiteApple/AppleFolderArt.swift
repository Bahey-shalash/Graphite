import Foundation
import CoreGraphics
import GraphiteCore

/// Draws a folder look with Apple's own folder art, as `AppleFolderArtPlan` says: Finder
/// draws a stand-in folder in Graphite's temporary items, then a picture is placed on it.
/// iOS gives no folder art (see `FinderFolderAttributes.systemIcon(at:pixels:)`), so there
/// no stand-in is made and the caller draws the folder.
public struct AppleFolderArt: Sendable {
    /// Where the stand-in folders are kept: one empty folder per look, in the temporary items.
    public let standInDirectory: URL

    public init(standInDirectory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("Graphite Folder Looks", isDirectory: true)) {
        self.standInDirectory = standInDirectory
    }

    /// The look drawn `pixels` wide; nil when the system gives no folder art, and the caller
    /// draws the folder itself.
    public func art(for style: FolderStyle, picture: CGImage?, pixels: Int) async -> CGImage? {
        let plan = AppleFolderArtPlan.plan(for: style)
        if plan.picture?.layout == .wholeIcon { return picture }
        guard var art = await standInArt(plan, pixels: pixels) else { return nil }
        if let picture, let pictureLayout = plan.picture?.layout {
            art = FolderIconRenderer.finderIcon(picture: picture, layout: pictureLayout, folderIcon: art) ?? art
        }
        return art
    }

    private func standInArt(_ plan: AppleFolderArtPlan, pixels: Int) async -> CGImage? {
        #if os(macOS)
        guard let standIn = preparedStandIn(plan) else { return nil }
        return await FinderFolderAttributes.systemIcon(at: standIn, pixels: pixels)
        #else
        return nil
        #endif
    }

    /// The stand-in folder carrying the plan's look, made the first time it is needed; nil
    /// when it cannot be made, and there is then no Apple art for the look.
    private func preparedStandIn(_ plan: AppleFolderArtPlan) -> URL? {
        let name = plan.standInName
        let standIn = standInDirectory.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: standIn.path) else { return standIn }
        do {
            try FileManager.default.createDirectory(at: standIn, withIntermediateDirectories: true)
            try FinderFolderAttributes(root: standInDirectory).write(plan.standIn, to: VaultPath(name))
            return standIn
        } catch {
            return nil
        }
    }

    #if os(macOS)
    /// Apple's folder art in a color, drawn at once, as the Mac draws icons without waiting:
    /// the folder a picture is placed on for Finder's custom icon.
    public func folderArtNow(color: FolderColor?, pixels: Int) -> CGImage? {
        guard let standIn = preparedStandIn(AppleFolderArtPlan.plan(for: FolderStyle(color: color))) else { return nil }
        return FinderFolderAttributes.systemIconNow(at: standIn, pixels: pixels)
    }
    #endif
}
