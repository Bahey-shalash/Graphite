import XCTest
import AppKit
import SwiftUI
import Textual
import GraphiteCore
import GraphiteIndex
import GraphiteApple
@testable import GraphiteUI

@MainActor
final class ReadAloudReadingViewTests: XCTestCase {
    func testRenderedWordsRetainExactOccurrencesAcrossMarkdownTransforms() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudReading-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let source = "---\r\nprivate: hidden\r\n---\r\n# Repeat\r\nRepeat **repeat** [[Topic|repeat]] and cafe\u{301} &amp; tea.\r\n%% hidden %%After $x^2$ now.\r\n\r\n- [x] Study `word` today.\r\n\r\n```swift\r\nrepeat hidden\r\n```\r\n\r\n> [!note] Repeat\r\n> Repeat **again**.\r\n> > [!tip] Nested\r\n> > More repeat.\r\n\r\n# Repeat\r\nFinish."
        let build = try await ReadingViewBuilder().build(source: source, note: VaultPath("Note.md"), root: directory,
                                                       index: index, configuration: ReadingConfiguration(mapsReadAloudSourceLocations: true))
        var mappedRanges: [NSRange] = []
        func inspect(_ blocks: [RenderedBlock]) throws {
            for block in blocks {
                let markdown: String
                switch block {
                case .markdown(_, let text), .displayMath(_, let text): markdown = text
                case .heading(_, let level, let text, _): markdown = String(repeating: "#", count: level) + " " + text
                case .callout(_, _, let title, _, let body):
                    let tokens = try XCTUnwrap(build.readingSourceTokensByBlock[block.id])
                    var attributed = try ObsidianMarkdownParser(baseURL: directory, textSize: 17).attributedString(for: title)
                    XCTAssertTrue(ReadingSourceAlignment.apply(tokens, to: &attributed), "Callout \(title)")
                    mappedRanges += attributed.runs.compactMap { run in run[ReadingSourceRangeAttribute.self] }
                    try inspect(body)
                    continue
                default: continue
                }
                let tokens = try XCTUnwrap(build.readingSourceTokensByBlock[block.id])
                var attributed = try ObsidianMarkdownParser(baseURL: directory, textSize: 17).attributedString(for: markdown)
                XCTAssertTrue(ReadingSourceAlignment.apply(tokens, to: &attributed), "Block \(markdown), tokens \(tokens.map(\.text))")
                mappedRanges += attributed.runs.compactMap { run in run[ReadingSourceRangeAttribute.self] }
            }
        }
        try inspect(build.blocks)
        let expected = ReadAloudSourceToken.tokens(in: try ReadAloudDocument.markdown(source))
        XCTAssertEqual(Set(mappedRanges), Set(expected.map(\.sourceRange)))
        let repeatRanges = expected.filter { token in token.text.lowercased() == "repeat" }.map(\.sourceRange)
        XCTAssertGreaterThan(repeatRanges.count, 5)
        XCTAssertEqual(Set(repeatRanges).count, repeatRanges.count)
        for range in repeatRanges { XCTAssertEqual((source as NSString).substring(with: range).lowercased(), "repeat") }
        let equation = try XCTUnwrap(expected.first(where: \.isEquation))
        XCTAssertEqual((source as NSString).substring(with: equation.sourceRange), "$x^2$")
    }

    /// The owner saw no highlight at all in the reading view: one apostrophe, quote or dash
    /// in a paragraph made its words differ from the voice's ("gate’s"), which switched the
    /// whole paragraph's highlight off. Acronyms said differently must not do that either.
    func testTypographicMarksAndRespelledTermsKeepTheirParagraphMapped() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudReading-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let source = "# Shannon's expansion\n\nThe gate's \"full\" level -- while the CMOS and SRAM keep GPUs busy, e.g. at https://example.com/a now."
        let build = try await ReadingViewBuilder().build(source: source, note: VaultPath("Note.md"), root: directory,
                                                       index: index, configuration: ReadingConfiguration(mapsReadAloudSourceLocations: true))
        var mappedBlocks = 0
        for block in build.blocks {
            let markdown: String
            switch block {
            case .markdown(_, let text): markdown = text
            case .heading(_, let level, let text, _): markdown = String(repeating: "#", count: level) + " " + text
            default: continue
            }
            let tokens = try XCTUnwrap(build.readingSourceTokensByBlock[block.id])
            var attributed = try ObsidianMarkdownParser(baseURL: directory, textSize: 17).attributedString(for: markdown)
            XCTAssertTrue(ReadingSourceAlignment.apply(tokens, to: &attributed), "Block \(markdown), tokens \(tokens.map(\.text))")
            mappedBlocks += 1
        }
        XCTAssertEqual(mappedBlocks, 2)
    }

    func testAnyChangedWordDisablesTheCompleteMapping() throws {
        let tokens = ReadAloudSourceToken.tokens(in: try ReadAloudDocument.markdown("same same then 12"))
        for rendered in ["same then 12", "same same then 13", "same same extra then 12"] {
            var attributed = AttributedString(rendered)
            XCTAssertFalse(ReadingSourceAlignment.apply(tokens, to: &attributed))
            XCTAssertTrue(attributed.runs.allSatisfy { run in run[ReadingSourceRangeAttribute.self] == nil })
        }
    }

    func testNativeTextGeometryHighlightsOnlyTheChosenRepeatedWordAndClears() async throws {
        let source = "same same"
        let tokens = ReadAloudSourceToken.tokens(in: try ReadAloudDocument.markdown(source))
        let state = HighlightState()
        let root = HighlightProbe(markdown: source, tokens: tokens, state: state)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 120),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 120)
        defer { window.contentView = nil; window.orderOut(nil) }
        state.range = tokens[0].sourceRange
        try await settle(hosting)
        let first = try XCTUnwrap(state.frames.first)
        XCTAssertEqual(first.sourceRange, tokens[0].sourceRange)
        XCTAssertGreaterThan(first.frame.width, 10)
        XCTAssertGreaterThan(first.frame.height, 10)
        XCTAssertGreaterThan(try yellowPixelCount(in: hosting), 20, "The geometry must produce a visible highlight")
        state.range = tokens[1].sourceRange
        try await settle(hosting)
        let second = try XCTUnwrap(state.frames.first)
        XCTAssertEqual(second.sourceRange, tokens[1].sourceRange)
        XCTAssertGreaterThan(second.frame.minX, first.frame.maxX)
        state.range = nil
        try await settle(hosting)
        XCTAssertTrue(state.frames.isEmpty)
        XCTAssertEqual(try yellowPixelCount(in: hosting), 0, "Stop must remove the drawn highlight")
    }

    func testNativeReadingViewFollowsDistantWordOnlyWhenEnabled() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadAloudFollowing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let index = try VaultIndex(databaseURL: directory.appendingPathComponent("index.sqlite"))
        let source = "# Start\nFirst word.\n\n" + (0..<40).map { number in
            "# Section \(number)\n\nA paragraph that makes this note longer.\n\n"
        }.joined() + "# Last\n\nFinal target."
        let state = HighlightState()
        let position = ReadingPosition()
        let root = FollowingProbe(source: source, root: directory, index: index, state: state, position: position)
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 360, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.frame = CGRect(x: 0, y: 0, width: 360, height: 240)
        window.orderFront(nil)
        defer { window.contentView = nil; window.orderOut(nil) }
        state.range = (source as NSString).range(of: "First")
        let initialDeadline = ContinuousClock.now + .seconds(3)
        while state.frames.isEmpty, ContinuousClock.now < initialDeadline { try await settle(hosting) }
        XCTAssertFalse(state.frames.isEmpty)
        XCTAssertLessThan(position.verticalOffset, 1)
        state.range = (source as NSString).range(of: "target")
        try await settle(hosting)
        XCTAssertLessThan(position.verticalOffset, 1)
        state.followsReading = true
        let deadline = ContinuousClock.now + .seconds(3)
        while (position.verticalOffset < 100 || !state.frames.contains(where: { frame in frame.sourceRange == state.range })), ContinuousClock.now < deadline {
            try await settle(hosting)
        }
        XCTAssertGreaterThan(position.verticalOffset, 100)
        let target = try XCTUnwrap(state.frames.first(where: { frame in frame.sourceRange == state.range }),
                                  "offset \(position.verticalOffset), frames \(state.frames), last \(String(describing: position.blockLocations.last)), active \(String(describing: state.range))")
        XCTAssertGreaterThanOrEqual(target.frame.minY, 0)
        XCTAssertLessThanOrEqual(target.frame.maxY, 240)
    }

    func testLivePreviewTableMathAndOpenCalloutHighlightActualRenderedContent() async throws {
        let path = try VaultPath("Note.md")
        let samples = ["Before.\n\n| Name | Value |\n| --- | --- |\n| repeat | clear |\n", "Before.\n\n$$x^2$$\n", "> [!note]+ Title\n> Read repeat now.\n"]
        // A folded callout's body is no longer read (the owner's rule) nor expanded for
        // reading; an open callout highlights its body.
        for source in samples {
            let speech = ReadingProbeSpeech()
            let preferenceName = "ReadAloudWidget-\(UUID().uuidString)"
            let preferences = try XCTUnwrap(UserDefaults(suiteName: preferenceName))
            defer { preferences.removePersistentDomain(forName: preferenceName) }
            let reader = ReadAloudController(session: ReadAloudSession(speech: speech, preferences: preferences))
            reader.session.chooseVoice("reading-probe")
            reader.readMarkdown(source, path: path)
            let deadline = ContinuousClock.now + .seconds(3)
            while reader.isPreparing, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNil(reader.errorMessage)
            let document = try XCTUnwrap(reader.session.document)
            let targetIndex = try XCTUnwrap(document.passages.firstIndex(where: { passage in passage.text.contains("repeat") || passage.spans.contains(where: \.isEquation) }))
            reader.session.move(to: targetIndex)
            reader.session.play()
            let passage = try XCTUnwrap(reader.session.currentPassage)
            let spokenRange = passage.spans.contains(where: \.isEquation) ? NSRange(location: 0, length: 1) : (passage.text as NSString).range(of: "repeat")
            speech.eventHandler?(.spoken(try XCTUnwrap(speech.requestIdentifier), spokenRange))
            let globalRange = try XCTUnwrap(reader.session.sourceRange)
            let block = try XCTUnwrap(LivePreviewBlockScanner.blocks(in: source as NSString).first(where: { block in NSIntersectionRange(block.range, globalRange).length > 0 }))
            let state = HighlightState()
            let environment = LivePreviewEnvironment(root: FileManager.default.temporaryDirectory, textSize: 17, colorsEnabled: true, paletteHexByName: [:], drawingVersion: 0,
                                                     resolve: { _, _ in nil }, open: { _ in }, follow: { _, _ in }, updateProperties: nil,
                                                     readingContext: LivePreviewReadingContext(controller: reader, path: path))
            let root = LivePreviewWidgetView(block: block, environment: environment, revealSource: {}, reportHeight: { _ in })
                .coordinateSpace(.named(ReadingCoordinateSpace.name))
                .onPreferenceChange(ReadingHighlightGeometryKey.self) { frames in MainActor.assumeIsolated { state.frames = frames } }
                .frame(width: 360, height: 240, alignment: .topLeading)
            let hosting = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 360, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.frame = CGRect(x: 0, y: 0, width: 360, height: 240)
            defer { window.contentView = nil; window.orderOut(nil); reader.clear() }
            let geometryDeadline = ContinuousClock.now + .seconds(3)
            while state.frames.isEmpty, ContinuousClock.now < geometryDeadline { try await settle(hosting) }
            let frame = try XCTUnwrap(state.frames.first, source)
            XCTAssertEqual(frame.sourceRange, NSRange(location: globalRange.location - block.range.location, length: globalRange.length))
            XCTAssertGreaterThan(frame.frame.width, 5)
            XCTAssertGreaterThan(frame.frame.height, 5)
            reader.stop()
            try await settle(hosting)
            XCTAssertTrue(state.frames.isEmpty)
        }
    }

    func testNativeSourceFollowingKeepsSelectionAndSourceText() async throws {
        let scrollView = MarkdownMacTextView.makeScrollableTextView()
        let textView = try XCTUnwrap(scrollView.documentView as? MarkdownMacTextView)
        XCTAssertNotNil(textView.textLayoutManager)
        let source = (0..<200).map { number in "Paragraph \(number).\n" }.joined() + "Final target."
        textView.string = source
        textView.font = .systemFont(ofSize: 17)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 360, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = scrollView
        scrollView.frame = CGRect(x: 0, y: 0, width: 360, height: 240)
        textView.frame.size.width = 360
        window.orderFront(nil)
        defer { window.contentView = nil; window.orderOut(nil) }
        try await settle(scrollView)
        textView.readAloudRange = (source as NSString).range(of: "target")
        textView.followReadingRange()
        try await settle(scrollView)
        XCTAssertGreaterThan(textView.visibleRect.minY, 100)
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertEqual(textView.string, source)
    }

    private func settle(_ view: NSView) async throws {
        for _ in 0..<8 {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func yellowPixelCount(in view: NSView) throws -> Int {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2),
                                                   pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8,
                                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var count = 0
        for verticalPixel in 0..<bitmap.pixelsHigh {
            for horizontalPixel in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: horizontalPixel, y: verticalPixel)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.5, color.redComponent > color.blueComponent + 0.1,
                   color.greenComponent > color.blueComponent + 0.1 { count += 1 }
            }
        }
        return count
    }
}

@MainActor @Observable
private final class HighlightState {
    var range: NSRange?
    var frames: [ReadingHighlightGeometry] = []
    var followsReading = false
}

private struct FollowingProbe: View {
    let source: String
    let root: URL
    let index: VaultIndex
    let state: HighlightState
    let position: ReadingPosition

    var body: some View {
        MarkdownPreview(source: source, path: VaultPath.root, root: root, index: index,
                        configuration: ReadingConfiguration(mapsReadAloudSourceLocations: true),
                        headingScrollRequest: .constant(nil), handledScrollToken: .constant(nil),
                        navigate: { _, _ in }, openPDF: { _, _ in }, updateProperties: nil,
                        savedPosition: position, readAloudRange: state.range, followsReading: state.followsReading)
            .onPreferenceChange(ReadingHighlightGeometryKey.self) { frames in
                MainActor.assumeIsolated { state.frames = frames }
            }
            .frame(width: 360, height: 240)
    }
}

private struct HighlightProbe: View {
    let markdown: String
    let tokens: [ReadAloudSourceToken]
    let state: HighlightState

    var body: some View {
        StructuredText(markdown, parser: ObsidianMarkdownParser(baseURL: nil, textSize: 20, sourceTokens: tokens))
            .font(.system(size: 20))
            .textual.textSelection(.enabled)
            .textual.readingHighlight(state.range, coordinateSpace: "ReadingProbe")
            .coordinateSpace(.named("ReadingProbe"))
            .onPreferenceChange(ReadingHighlightGeometryKey.self) { frames in
                MainActor.assumeIsolated { state.frames = frames }
            }
            .frame(width: 360, height: 120, alignment: .topLeading)
            .foregroundStyle(.black)
            .background(.white)
    }
}

@MainActor
private final class ReadingProbeSpeech: ReadAloudSpeaking {
    var eventHandler: (@MainActor (ReadAloudSpeechEvent) -> Void)?
    var requestIdentifier: UUID?
    let voices = [ReadAloudVoice(id: "reading-probe", name: "Test", language: "en-US", quality: 1)]
    func speak(_ text: String, voiceIdentifier: String, speed: Double, requestIdentifier: UUID) throws { self.requestIdentifier = requestIdentifier }
    func pause() -> Bool { true }
    func resume() -> Bool { true }
    func stop() { requestIdentifier = nil }
}
