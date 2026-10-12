import Foundation
import JavaScriptCore
import GraphiteCore

/// Owns one offline mathematical interpreter. Mutable JavaScript objects stay
/// inside this actor; only prepared strings and immutable source ranges leave it.
public actor ReadAloudMarkdownPreparation {
    private var mathematicalInterpreter: OfflineMathematicalInterpreter?

    public init() {}

    public func prepare(_ source: String, selectedRange: NSRange? = nil,
                        paletteHexByName: [String: String] = [:],
                        mathematicalStyle: MathematicalSpeechStyle = .concise) throws -> ReadAloudDocument {
        try ReadAloudDocument.markdown(source, selectedRange: selectedRange, paletteHexByName: paletteHexByName) { expression in
            try Task.checkCancellation()
            if mathematicalInterpreter == nil { mathematicalInterpreter = try OfflineMathematicalInterpreter() }
            return mathematicalInterpreter?.speech(for: expression, style: mathematicalStyle)
        }
    }
}

private final class OfflineMathematicalInterpreter {
    private struct Request: Hashable {
        let expression: String
        let style: MathematicalSpeechStyle
    }

    private struct CachedSpeech {
        let description: String?
        let utf16Count: Int
    }

    private let context: JSContext
    private let speechFunction: JSValue
    private var cachedSpeech: [Request: CachedSpeech] = [:]
    private var cachedRequests: [Request] = []
    private var cachedUTF16Count = 0

    init() throws {
        guard let resource = Bundle.module.url(forResource: "math-speech", withExtension: "js", subdirectory: "MathSpeech"),
              let context = JSContext() else {
            throw GraphiteError.unavailable("The offline math reader could not be loaded.")
        }
        let script = try String(contentsOf: resource, encoding: .utf8)
        context.evaluateScript(script)
        guard context.exception == nil,
              let engine = context.objectForKeyedSubscript("GraphiteMathSpeech"),
              engine.objectForKeyedSubscript("isReady")?.toBool() == true,
              let speechFunction = engine.objectForKeyedSubscript("speech"), !speechFunction.isUndefined else {
            throw GraphiteError.unavailable("The offline math reader could not start. Choose the passage again.")
        }
        self.context = context
        self.speechFunction = speechFunction
    }

    func speech(for expression: String, style: MathematicalSpeechStyle) -> String? {
        guard expression.utf16.count <= 8_192, !Task.isCancelled else { return nil }
        let request = Request(expression: expression, style: style)
        if let cached = cachedSpeech[request] { return cached.description }
        context.exception = nil
        let description = speechFunction.call(withArguments: [expression, style == .detailed])
        let spokenText = context.exception == nil && description?.isNull == false && description?.isUndefined == false
            ? description?.toString() : nil
        let utf16Count = expression.utf16.count + (spokenText?.utf16.count ?? 0)
        // Repeated equations are common in course notes. Bound both the number
        // of cached requests and their combined source/speech storage.
        while !cachedRequests.isEmpty && (cachedRequests.count >= 128 || cachedUTF16Count + utf16Count > 262_144) {
            let oldest = cachedRequests.removeFirst()
            if let removed = cachedSpeech.removeValue(forKey: oldest) { cachedUTF16Count -= removed.utf16Count }
        }
        cachedRequests.append(request)
        cachedSpeech[request] = CachedSpeech(description: spokenText, utf16Count: utf16Count)
        cachedUTF16Count += utf16Count
        return spokenText
    }
}
