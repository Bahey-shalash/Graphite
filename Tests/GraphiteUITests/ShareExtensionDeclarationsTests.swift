import XCTest
import GraphiteFixtures
@testable import GraphiteUI

/// The declarations that let the share extension hand shared items to the app: one App
/// Group in both entitlements and both `Info.plist` files, the share services extension
/// point, and the version the extension must share with the app it is embedded in. A
/// mismatch builds without error and fails only on a device or at upload.
final class ShareExtensionDeclarationsTests: XCTestCase {
    private static let applicationGroup = "group.com.graphite.study"

    private var repositoryRoot: URL { FixtureFolders.repositoryRoot }

    private func propertyList(at relativePath: String) throws -> [String: Any] {
        let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(relativePath))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], relativePath)
    }

    private func project() throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent("Graphite.xcodeproj/project.pbxproj"), encoding: .utf8)
    }

    func testTheAppAndItsExtensionNameOneApplicationGroupInTheirEntitlementsAndInformation() throws {
        for entitlementsPath in ["App/Graphite-iOS.entitlements", "ShareExtension/ShareExtension.entitlements"] {
            let entitlements = try propertyList(at: entitlementsPath)
            XCTAssertEqual(Set(entitlements.keys), ["com.apple.security.application-groups"], entitlementsPath)
            XCTAssertEqual(entitlements["com.apple.security.application-groups"] as? [String], [Self.applicationGroup], entitlementsPath)
        }
        for informationPath in ["App/Info.plist", "ShareExtension/Info.plist"] {
            XCTAssertEqual(try propertyList(at: informationPath)[WorkspaceDeviceServices.applicationGroupInformationKey] as? String, Self.applicationGroup,
                           informationPath)
        }
    }

    func testOnlyTheIOSAppIsSignedWithTheApplicationGroup() throws {
        let project = try project()
        XCTAssertEqual(project.components(separatedBy: #""CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]" = "App/Graphite-iOS.entitlements";"#).count - 1, 2)
        XCTAssertEqual(project.components(separatedBy: #""CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]" = "App/Graphite-iOS.entitlements";"#).count - 1, 2)
        XCTAssertEqual(project.components(separatedBy: #""CODE_SIGN_ENTITLEMENTS[sdk=macosx*]" = App/Graphite.entitlements;"#).count - 1, 2)
        XCTAssertEqual(project.components(separatedBy: "CODE_SIGN_ENTITLEMENTS = ShareExtension/ShareExtension.entitlements;").count - 1, 2)
    }

    func testTheExtensionIsAShareServicesExtensionForTextLinksImagesMoviesAndFiles() throws {
        let information = try propertyList(at: "ShareExtension/Info.plist")
        let extensionDeclaration = try XCTUnwrap(information["NSExtension"] as? [String: Any])
        XCTAssertEqual(extensionDeclaration["NSExtensionPointIdentifier"] as? String, "com.apple.share-services")
        XCTAssertEqual(extensionDeclaration["NSExtensionPrincipalClass"] as? String, "$(PRODUCT_MODULE_NAME).ShareViewController")
        let attributes = try XCTUnwrap(extensionDeclaration["NSExtensionAttributes"] as? [String: Any])
        let activationRule = try XCTUnwrap(attributes["NSExtensionActivationRule"] as? [String: Any])
        XCTAssertEqual(Set(activationRule.keys), [
            "NSExtensionActivationSupportsText", "NSExtensionActivationSupportsWebURLWithMaxCount", "NSExtensionActivationSupportsImageWithMaxCount",
            "NSExtensionActivationSupportsMovieWithMaxCount", "NSExtensionActivationSupportsFileWithMaxCount",
        ])
    }

    func testTheExtensionHasTheAppsVersionAndItsOwnIdentifier() throws {
        let information = try propertyList(at: "ShareExtension/Info.plist")
        XCTAssertEqual(information["CFBundleShortVersionString"] as? String, "$(MARKETING_VERSION)")
        XCTAssertEqual(information["CFBundleVersion"] as? String, "$(CURRENT_PROJECT_VERSION)")
        XCTAssertEqual(information["CFBundlePackageType"] as? String, "XPC!")
        let project = try project()
        XCTAssertEqual(project.components(separatedBy: "PRODUCT_BUNDLE_IDENTIFIER = com.graphite.study.share;").count - 1, 2)
        XCTAssertTrue(project.contains("platformFilter = ios;"), "The Mac app builds and embeds no share extension.")
    }

    func testTheExtensionsPrivacyManifestDeclaresOnlyFileTimestampsInItsContainers() throws {
        let manifest = try propertyList(at: "ShareExtension/PrivacyInfo.xcprivacy")
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        let accessedTypes = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        XCTAssertEqual(accessedTypes.count, 1)
        XCTAssertEqual(accessedTypes.first?["NSPrivacyAccessedAPIType"] as? String, "NSPrivacyAccessedAPICategoryFileTimestamp")
        XCTAssertEqual(accessedTypes.first?["NSPrivacyAccessedAPITypeReasons"] as? [String], ["C617.1"])
    }
}
