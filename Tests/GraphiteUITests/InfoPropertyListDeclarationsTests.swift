import XCTest
import UniformTypeIdentifiers
import GraphiteVoices
@testable import GraphiteUI

/// The identifiers and platform declarations in `App/Info.plist` that the code and the
/// system rely on: renaming one breaks drags, links, background downloads or file sharing
/// without any compile error.
final class InfoPropertyListDeclarationsTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func infoPropertyList() throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("App/Info.plist"))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    // MARK: Identifiers

    func testTheBundleIdentifierIsTakenFromTheProjectsProductIdentifier() throws {
        XCTAssertEqual(try infoPropertyList()["CFBundleIdentifier"] as? String, "$(PRODUCT_BUNDLE_IDENTIFIER)")
        let project = try String(contentsOf: repositoryRoot.appendingPathComponent("Graphite.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertTrue(project.contains("PRODUCT_BUNDLE_IDENTIFIER = com.graphite.study;"))
    }

    func testTheLinkSchemeIsGraphiteUnderTheLinksName() throws {
        let urlTypes = try XCTUnwrap(try infoPropertyList()["CFBundleURLTypes"] as? [[String: Any]])
        XCTAssertEqual(urlTypes.count, 1)
        XCTAssertEqual(urlTypes[0]["CFBundleURLName"] as? String, "com.graphite.study.links")
        XCTAssertEqual(urlTypes[0]["CFBundleURLSchemes"] as? [String], ["graphite"])
    }

    func testTheDragTypesAreDeclaredAsDataTypesAndMatchTheCode() throws {
        let declarations = try XCTUnwrap(try infoPropertyList()["UTExportedTypeDeclarations"] as? [[String: Any]])
        XCTAssertEqual(declarations.compactMap { $0["UTTypeIdentifier"] as? String },
                       ["com.graphite.study.vault-item", "com.graphite.study.tab", "com.graphite.study.pdf-page"])
        for declaration in declarations {
            XCTAssertEqual(declaration["UTTypeConformsTo"] as? [String], ["public.data"], declaration["UTTypeIdentifier"] as? String ?? "")
        }
        XCTAssertEqual(UTType.graphiteVaultItem.identifier, "com.graphite.study.vault-item")
        XCTAssertEqual(UTType.graphiteTab.identifier, "com.graphite.study.tab")
        XCTAssertEqual(UTType.graphitePDFPage.identifier, "com.graphite.study.pdf-page")
    }

    func testTheVoiceDownloadSessionHasItsIdentifier() {
        XCTAssertEqual(NeuralVoiceDownloader.sessionIdentifier, "com.graphite.study.voice-downloads")
        XCTAssertEqual(GraphiteVoiceDownloads.sessionIdentifier, NeuralVoiceDownloader.sessionIdentifier)
    }

    // MARK: Platform declarations

    func testThePlatformDeclarationsAreTheseValues() throws {
        let propertyList = try infoPropertyList()
        let sceneManifest = try XCTUnwrap(propertyList["UIApplicationSceneManifest"] as? [String: Any])
        XCTAssertEqual(sceneManifest["UIApplicationSupportsMultipleScenes"] as? Bool, false)
        XCTAssertEqual(propertyList["UIBackgroundModes"] as? [String], ["audio"])
        XCTAssertEqual(propertyList["UIFileSharingEnabled"] as? Bool, true)
        XCTAssertEqual(propertyList["LSSupportsOpeningDocumentsInPlace"] as? Bool, true)
        XCTAssertEqual(propertyList["UISupportsDocumentBrowser"] as? Bool, true)
    }

    func testTheInfoPropertyListHasExactlyTheseTopLevelKeys() throws {
        XCTAssertEqual(Set(try infoPropertyList().keys), [
            "CFBundleDisplayName", "CFBundleExecutable", "CFBundleIdentifier", "CFBundleName", "CFBundlePackageType",
            "CFBundleShortVersionString", "CFBundleVersion", "CFBundleURLTypes",
            "ITSAppUsesNonExemptEncryption", "LSApplicationCategoryType", "LSSupportsOpeningDocumentsInPlace",
            "NSCameraUsageDescription", "NSMicrophoneUsageDescription", "NSPhotoLibraryAddUsageDescription",
            "UIApplicationSceneManifest", "UIBackgroundModes", "UIFileSharingEnabled", "UILaunchScreen",
            "UISupportedInterfaceOrientations", "UISupportsDocumentBrowser", "UTExportedTypeDeclarations",
        ])
    }

    // MARK: App Store Connect

    /// Each TestFlight upload needs a higher build number, which `scripts/archive-for-testflight.sh` passes as
    /// `CURRENT_PROJECT_VERSION`; a number written into `Info.plist` would ignore it.
    func testTheVersionAndBuildNumberComeFromTheProjectsBuildSettings() throws {
        let propertyList = try infoPropertyList()
        XCTAssertEqual(propertyList["CFBundleShortVersionString"] as? String, "$(MARKETING_VERSION)")
        XCTAssertEqual(propertyList["CFBundleVersion"] as? String, "$(CURRENT_PROJECT_VERSION)")
        let project = try String(contentsOf: repositoryRoot.appendingPathComponent("Graphite.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertEqual(project.components(separatedBy: "MARKETING_VERSION = ").count - 1, 2)
        XCTAssertEqual(project.components(separatedBy: "CURRENT_PROJECT_VERSION = ").count - 1, 2)
    }

    /// App Store Connect refuses a Mac upload without a category; iOS ignores the key.
    func testTheMacAppHasAnAppStoreCategory() throws {
        XCTAssertEqual(try infoPropertyList()["LSApplicationCategoryType"] as? String, "public.app-category.productivity")
    }

    /// Without this answer every uploaded build waits in App Store Connect for the export compliance question.
    func testTheAppDeclaresItUsesNoNonExemptEncryption() throws {
        XCTAssertEqual(try infoPropertyList()["ITSAppUsesNonExemptEncryption"] as? Bool, false)
    }

    func testThePrivacyManifestDeclaresNoTrackingAndIsCopiedIntoTheApp() throws {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("App/PrivacyInfo.xcprivacy"))
        let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.count, 0)
        let accessedTypes = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        XCTAssertEqual(Set(accessedTypes.compactMap { $0["NSPrivacyAccessedAPIType"] as? String }), [
            "NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPICategoryFileTimestamp",
            "NSPrivacyAccessedAPICategorySystemBootTime", "NSPrivacyAccessedAPICategoryDiskSpace",
        ])
        let project = try String(contentsOf: repositoryRoot.appendingPathComponent("Graphite.xcodeproj/project.pbxproj"), encoding: .utf8)
        XCTAssertTrue(project.contains("/* PrivacyInfo.xcprivacy in Resources */,"))
    }
}
