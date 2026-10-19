import XCTest
import SwiftUI
import GraphiteCore
@testable import GraphiteUI

/// Which colour a callout takes when the vault's theme sets callout colours, and which icon
/// it keeps: Graphite's, whatever the theme says.
@MainActor
final class CalloutAppearanceThemeLookupTests: XCTestCase {
    private let themedRed = ThemeColor(red: 0.8, green: 0.1, blue: 0.1)
    private let themedGreen = ThemeColor(red: 0.1, green: 0.7, blue: 0.2)

    private func theme(calloutColors: [String: ThemeColor]) -> NoteThemeStyle {
        var light = ThemeModeTokens(), dark = ThemeModeTokens()
        light.calloutColors = calloutColors
        dark.calloutColors = calloutColors
        return NoteThemeStyle(tokens: VaultThemeTokens(fingerprint: "test", themeName: "Test", light: light, dark: dark))
    }

    private func themedTint(_ type: String, in style: NoteThemeStyle) throws -> Color {
        Color(try XCTUnwrap(style.calloutColors[type]).tint)
    }

    func testAnUnknownTypeTakesTheThemesNoteColourAndGraphitesPencilIcon() throws {
        let style = theme(calloutColors: ["note": themedRed])
        let unknown = CalloutAppearance(type: "my-own-type", theme: style)
        XCTAssertEqual(unknown.color, try themedTint("note", in: style))
        XCTAssertEqual(unknown.systemImage, "pencil")
        XCTAssertEqual(CalloutAppearance(type: "note", theme: style).color, try themedTint("note", in: style))
    }

    func testAnUnknownTypeWithoutAThemedNoteColourKeepsGraphitesOwn() {
        let style = theme(calloutColors: ["warning": themedRed])
        XCTAssertEqual(CalloutAppearance(type: "my-own-type", theme: style).color, CalloutAppearance(type: "note").color)
    }

    /// The theme's colour is looked up by the lowercased type; Graphite's icon table is matched
    /// on the type as given, so a type must already be lowercase to have its own icon.
    func testTheThemesColourIsFoundByTheLowercasedTypeAndTheIconByTheTypeAsGiven() throws {
        let style = theme(calloutColors: ["warning": themedRed])
        let uppercase = CalloutAppearance(type: "WARNING", theme: style)
        XCTAssertEqual(uppercase.color, try themedTint("warning", in: style))
        XCTAssertEqual(uppercase.systemImage, "pencil")
        XCTAssertEqual(CalloutAppearance(type: "warning", theme: style).systemImage, "exclamationmark.triangle")
    }

    /// The theme's colour for an alias is the one measured for that alias (the probe reads
    /// every type). A colour set only for `warning` does not reach `caution` here.
    func testAnAliasTakesTheColourMeasuredForItAndNotItsMainTypes() throws {
        let style = theme(calloutColors: ["warning": themedRed, "caution": themedGreen])
        XCTAssertEqual(CalloutAppearance(type: "warning", theme: style).color, try themedTint("warning", in: style))
        XCTAssertEqual(CalloutAppearance(type: "caution", theme: style).color, try themedTint("caution", in: style))
        XCTAssertNotEqual(try themedTint("warning", in: style), try themedTint("caution", in: style))
        let onlyWarning = theme(calloutColors: ["warning": themedRed])
        XCTAssertEqual(CalloutAppearance(type: "caution", theme: onlyWarning).color, CalloutAppearance(type: "caution").color)
    }

    func testEveryTypeOfTheCoreTableIsKnownToItsCanonicalTypeAndHasAnIconOfItsOwnExceptNote() {
        for type in ObsidianCalloutTypes.variableNamesByType.keys {
            XCTAssertEqual(ObsidianCalloutTypes.canonicalType(type), type, type)
            XCTAssertEqual(ObsidianCalloutTypes.canonicalType(type.uppercased()), type, type)
            if type != "note" { XCTAssertNotEqual(CalloutAppearance(type: type).systemImage, "pencil", "\(type) has an icon of its own.") }
        }
        XCTAssertEqual(ObsidianCalloutTypes.variableNamesByType.count, 27)
        XCTAssertEqual(ObsidianCalloutTypes.canonicalType("something-else"), "note")
        XCTAssertEqual(CalloutAppearance(type: "note").systemImage, "pencil")
    }
}
