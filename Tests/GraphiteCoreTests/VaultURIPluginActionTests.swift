import XCTest
@testable import GraphiteCore

/// The links a community plugin's protocol handler (`registerObsidianProtocolHandler`) gets:
/// the action name lowercased, the parameters with the names the link wrote.
final class VaultURIPluginActionTests: XCTestCase {
    private func uri(_ text: String) -> VaultURI? {
        URL(string: text).flatMap { VaultURI(url: $0) }
    }

    func testAPluginActionKeepsEveryParameterNameAsWrittenIncludingTheVaultsAndLowercasesTheAction() {
        XCTAssertEqual(uri("graphite://advanced-uri?vault=V&Key=1"),
                       VaultURI(vault: "V", action: .plugin(action: "advanced-uri", parameters: ["vault": "V", "Key": "1"])))
        XCTAssertEqual(uri("graphite://Advanced-URI?Vault=V&FilePath=A%20b.md&mode=append"),
                       VaultURI(vault: "V", action: .plugin(action: "advanced-uri", parameters: ["Vault": "V", "FilePath": "A b.md", "mode": "append"])))
    }

    func testAPluginActionWithASlashIsNamedByItsHostAndPath() {
        XCTAssertEqual(uri("obsidian://Smart-Plugins/Callback?Code=1"),
                       VaultURI(vault: nil, action: .plugin(action: "smart-plugins/callback", parameters: ["Code": "1"])))
    }

    func testAParameterWithoutAValueIsAnEmptyString() {
        XCTAssertEqual(uri("graphite://my-action?Flag&Other="), VaultURI(vault: nil, action: .plugin(action: "my-action", parameters: ["Flag": "", "Other": ""])))
    }

    func testAnActionNameWithOtherCharactersIsNotAPluginAction() {
        XCTAssertNil(uri("graphite://my%20action?x=1"))
    }
}
