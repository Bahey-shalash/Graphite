import Foundation

/// Writes a `JSONValue` as JavaScript's `JSON.stringify(value, null, 2)` lays it out, which
/// is how Obsidian writes its settings files: two spaces per level, `"name": value`, and `[]`
/// or `{}` for an empty list or object. Object members are written in name order.
enum JSONStringifyLayout {
    static func data(_ value: JSONValue) -> Data {
        var output: [UInt8] = []
        append(value, indentation: 0, to: &output)
        return Data(output)
    }

    private static let indentationStep = 2

    private static func append(_ value: JSONValue, indentation: Int, to output: inout [UInt8]) {
        switch value {
        case .null: output += Array("null".utf8)
        case .bool(let flag): output += Array((flag ? "true" : "false").utf8)
        case .integer(let number): output += Array(String(number).utf8)
        case .number(let number): output += Array(numberText(number).utf8)
        case .string(let text): output += CanvasJSONWriter.string(text)
        case .array(let elements): appendArray(elements, indentation: indentation, to: &output)
        case .object(let members): appendObject(members, indentation: indentation, to: &output)
        }
    }

    private static func appendArray(_ elements: [JSONValue], indentation: Int, to output: inout [UInt8]) {
        guard !elements.isEmpty else { output += Array("[]".utf8); return }
        output += Array("[\n".utf8)
        for (position, element) in elements.enumerated() {
            output += spaces(indentation + indentationStep)
            append(element, indentation: indentation + indentationStep, to: &output)
            output += Array((position == elements.count - 1 ? "\n" : ",\n").utf8)
        }
        output += spaces(indentation) + Array("]".utf8)
    }

    private static func appendObject(_ members: [String: JSONValue], indentation: Int, to output: inout [UInt8]) {
        guard !members.isEmpty else { output += Array("{}".utf8); return }
        output += Array("{\n".utf8)
        let names = members.keys.sorted()
        for (position, name) in names.enumerated() {
            output += spaces(indentation + indentationStep) + CanvasJSONWriter.string(name) + Array(": ".utf8)
            if let member = members[name] { append(member, indentation: indentation + indentationStep, to: &output) }
            output += Array((position == names.count - 1 ? "\n" : ",\n").utf8)
        }
        output += spaces(indentation) + Array("}".utf8)
    }

    private static func spaces(_ count: Int) -> [UInt8] { Array(repeating: UInt8(ascii: " "), count: count) }

    /// A number as JavaScript writes it: whole numbers without a fraction.
    private static func numberText(_ number: Double) -> String {
        guard number.isFinite else { return "null" }
        if number.rounded() == number, abs(number) < 1e15 { return String(Int64(number)) }
        return String(number)
    }
}
