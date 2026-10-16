import XCTest
@testable import GraphiteCore

final class CodeSyntaxHighlightingTests: XCTestCase {
    /// The text of each token of `code`, with its kind.
    private func tokens(_ code: String, _ languageName: String) throws -> [(text: String, kind: CodeTokenKind)] {
        let language = try XCTUnwrap(CodeLanguage.named(languageName), "\(languageName) is highlighted")
        let source = code as NSString
        return CodeSyntaxHighlighter.uncachedTokens(in: code, language: language).map { token in (source.substring(with: token.range), token.kind) }
    }

    private func texts(_ kind: CodeTokenKind, in code: String, _ languageName: String) throws -> [String] {
        try tokens(code, languageName).filter { token in token.kind == kind }.map(\.text)
    }

    private func assertKind(_ kind: CodeTokenKind, of expectedTexts: [String], in code: String, _ languageName: String,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let found = try texts(kind, in: code, languageName)
        for expectedText in expectedTexts {
            XCTAssertTrue(found.contains(expectedText), "\(languageName): \"\(expectedText)\" is \(kind); found \(found)", file: file, line: line)
        }
    }

    private func assertPlain(_ plainTexts: [String], in code: String, _ languageName: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let tokenTexts = try tokens(code, languageName).map(\.text)
        for plainText in plainTexts {
            XCTAssertFalse(tokenTexts.contains(plainText), "\(languageName): \"\(plainText)\" stays plain", file: file, line: line)
        }
    }

    // MARK: Languages and aliases

    func testAliasesNameTheirLanguages() throws {
        let expectedNames = [
            "c": "c", "h": "c", "cpp": "cpp", "c++": "cpp", "C++": "cpp", "cc": "cpp", "hpp": "cpp", "vhdl": "vhdl", "vhd": "vhdl",
            "verilog": "verilog", "sv": "verilog", "systemverilog": "verilog", "py": "python", "js": "javascript", "ts": "typescript",
            "sh": "shell", "zsh": "shell", "bash": "shell", "yml": "yaml", "rs": "rust", "golang": "go", "asm": "assembly",
            "matlab": "matlab", "tex": "latex", "md": "markdown", "json": "json", "sql": "sql", "swift": "swift", "java": "java",
        ]
        for (alias, name) in expectedNames {
            XCTAssertEqual(CodeLanguage.named(alias)?.name, name, alias)
        }
        XCTAssertNil(CodeLanguage.named("dataview"), "An unknown language stays plain.")
        XCTAssertNil(CodeLanguage.named(""))
        XCTAssertEqual(CodeSyntaxHighlighter.language(forFenceInfo: "python title=\"main.py\"")?.name, "python", "The first word of the info names the language.")
    }

    // MARK: C family

    func testC() throws {
        let code = """
            #include <stdio.h>
            #define MAX_SIZE 10 /* limit */
            // entry point
            int main(void) {
                size_t count = 0x1F;
                char letter = 'a';
                printf("%d\\n", count);
                return NULL;
            }
            """
        try assertKind(.preprocessor, of: ["#include", "#define"], in: code, "c")
        try assertKind(.string, of: ["<stdio.h>", "'a'", "\"%d\\n\""], in: code, "c")
        try assertKind(.comment, of: ["/* limit */", "// entry point"], in: code, "c")
        try assertKind(.typeName, of: ["int", "void", "size_t", "char"], in: code, "c")
        try assertKind(.keyword, of: ["return"], in: code, "c")
        try assertKind(.function, of: ["main", "printf"], in: code, "c")
        try assertKind(.number, of: ["10", "0x1F"], in: code, "c")
        try assertKind(.constant, of: ["MAX_SIZE", "NULL"], in: code, "c")
        try assertPlain(["count", "letter"], in: code, "c")
    }

    func testCPlusPlus() throws {
        let code = """
            namespace graphite {
            template <typename T>
            class Buffer final : public Base {
                std::vector<T> items;
                constexpr auto size = 1'000'000;
                auto pointer = nullptr;
            };
            }
            """
        try assertKind(.keyword, of: ["namespace", "template", "typename", "class", "final", "public", "constexpr", "auto"], in: code, "cpp")
        try assertKind(.typeName, of: ["graphite", "Buffer", "Base", "vector", "T"], in: code, "cpp")
        try assertKind(.number, of: ["1'000'000"], in: code, "cpp")
        try assertKind(.constant, of: ["nullptr"], in: code, "cpp")
        try assertPlain(["std", "items"], in: code, "cpp")
        XCTAssertEqual(try texts(.comment, in: "/* one\ntwo */ int x;", "c++"), ["/* one", "two */"], "A block comment continues on the next line.")
    }

    func testJavaAndKotlin() throws {
        let java = """
            @Override
            public static final String NAME = "graphite";
            public void run() { System.out.println(NAME); }
            """
        try assertKind(.attribute, of: ["@Override"], in: java, "java")
        try assertKind(.keyword, of: ["public", "static", "final"], in: java, "java")
        try assertKind(.typeName, of: ["String", "void", "System"], in: java, "java")
        try assertKind(.function, of: ["run", "println"], in: java, "java")
        try assertKind(.constant, of: ["NAME"], in: java, "java")
        try assertKind(.function, of: ["greet"], in: "fun greet(name: String) = println(\"hi\")", "kotlin")
    }

    // MARK: Scripting languages

    func testPython() throws {
        let code = """
            @dataclass
            class Point:
                def norm(self) -> float:
                    \"\"\"Length.
                    Spans lines.\"\"\"
                    return math.sqrt(self.x ** 2)  # Pythagoras
            path = r"C:\\new"
            label = f'{x}'
            print(None, True)
            """
        try assertKind(.attribute, of: ["@dataclass"], in: code, "python")
        try assertKind(.keyword, of: ["class", "def", "return"], in: code, "python")
        try assertKind(.typeName, of: ["Point", "float"], in: code, "python")
        try assertKind(.function, of: ["norm", "sqrt", "print"], in: code, "py")
        try assertKind(.string, of: ["\"\"\"Length.", "        Spans lines.\"\"\"", "r\"C:\\new\"", "f'{x}'"], in: code, "python")
        try assertKind(.comment, of: ["# Pythagoras"], in: code, "python")
        try assertKind(.constant, of: ["None", "True", "self"], in: code, "python")
        try assertPlain(["math", "path"], in: code, "python")
    }

    func testJavaScriptAndTypeScript() throws {
        let code = """
            const greeting = `Hello
            ${name}`; // template
            export function greet($element) { return new Map(); }
            """
        try assertKind(.keyword, of: ["const", "export", "function", "return", "new"], in: code, "js")
        try assertKind(.string, of: ["`Hello", "${name}`"], in: code, "js")
        try assertKind(.function, of: ["greet"], in: code, "js")
        try assertKind(.typeName, of: ["Map"], in: code, "js")
        try assertPlain(["$element"], in: code, "js")
        let typeScript = "interface Shape { area(): number; readonly name: string }\ntype Id = string | undefined"
        try assertKind(.keyword, of: ["interface", "readonly", "type"], in: typeScript, "ts")
        try assertKind(.typeName, of: ["Shape", "number", "string", "Id"], in: typeScript, "ts")
        try assertKind(.constant, of: ["undefined"], in: typeScript, "ts")
    }

    func testShell() throws {
        let code = """
            #!/bin/bash
            for file in "$HOME"/*.md; do
              echo "${file%.md}" # strip
              grep -c x#y "$1" && exit 0
            done
            """
        try assertKind(.comment, of: ["#!/bin/bash", "# strip"], in: code, "sh")
        try assertKind(.keyword, of: ["for", "in", "do", "done", "exit"], in: code, "bash")
        try assertKind(.string, of: ["\"$HOME\"", "\"${file%.md}\"", "\"$1\""], in: code, "zsh")
        try assertKind(.function, of: ["echo"], in: code, "shell")
        try assertPlain(["x#y", "grep"], in: code, "sh")
        try assertKind(.variable, of: ["$PATH", "${HOME}"], in: "export PATH=$PATH:${HOME}/bin", "sh")
    }

    func testMATLAB() throws {
        let code = """
            function y = scaled(x) % helper
            %{
            Block comment.
            %}
            y = x' * 2; s = 'it''s';
            end
            """
        try assertKind(.keyword, of: ["function", "end"], in: code, "matlab")
        try assertKind(.function, of: ["scaled"], in: code, "matlab")
        try assertKind(.comment, of: ["% helper", "%{", "Block comment.", "%}"], in: code, "matlab")
        try assertKind(.string, of: ["'it''s'"], in: code, "matlab")
        XCTAssertFalse(try texts(.string, in: code, "matlab").contains { text in text.hasPrefix("' *") }, "x' transposes; it does not open a string.")
    }

    // MARK: Systems languages

    func testSwift() throws {
        let code = """
            @MainActor
            struct Editor: View {
                #if os(iOS)
                let text = \"\"\"
                    Multi
                    \"\"\"
                #endif
                /* outer /* nested */ still comment */
                func render() -> Int? { nil }
            }
            """
        try assertKind(.attribute, of: ["@MainActor"], in: code, "swift")
        try assertKind(.preprocessor, of: ["#if", "#endif"], in: code, "swift")
        try assertKind(.keyword, of: ["struct", "let", "func"], in: code, "swift")
        try assertKind(.typeName, of: ["Editor", "View", "Int"], in: code, "swift")
        try assertKind(.function, of: ["render", "os"], in: code, "swift")
        try assertKind(.comment, of: ["/* outer /* nested */ still comment */"], in: code, "swift")
        try assertKind(.constant, of: ["nil"], in: code, "swift")
        XCTAssertTrue(try texts(.string, in: code, "swift").contains("        Multi"), "A multi-line string spans its lines.")
    }

    func testRust() throws {
        let code = """
            #[derive(Debug, Clone)]
            pub struct Point<'a> { name: &'a str, letter: char }
            fn main() { let c = 'x'; println!("{}", c); let raw = r"\\d+"; }
            """
        try assertKind(.attribute, of: ["#[derive(Debug, Clone)]", "'a"], in: code, "rust")
        try assertKind(.keyword, of: ["pub", "struct", "fn", "let"], in: code, "rs")
        try assertKind(.typeName, of: ["Point", "str", "char"], in: code, "rust")
        try assertKind(.function, of: ["main", "println!"], in: code, "rust")
        try assertKind(.string, of: ["'x'", "\"{}\"", "r\"\\d+\""], in: code, "rust")
    }

    func testGo() throws {
        let code = """
            package main
            func (s *Server) Start(port int) error {
                path := `raw
            string`
                return fmt.Errorf("port %d", len(path))
            }
            """
        try assertKind(.keyword, of: ["package", "func", "return"], in: code, "go")
        try assertKind(.typeName, of: ["int", "error"], in: code, "go")
        try assertKind(.function, of: ["Start", "Errorf", "len"], in: code, "golang")
        try assertKind(.string, of: ["`raw", "string`", "\"port %d\""], in: code, "go")
        try assertPlain(["Server", "fmt"], in: code, "go")
    }

    // MARK: Hardware description languages

    func testVHDL() throws {
        let code = """
            library IEEE;
            use IEEE.STD_LOGIC_1164.ALL;
            entity Counter is
              port (CLKxCI : in std_logic; COUNTxDO : out unsigned(7 downto 0));
            end entity Counter; -- the counter
            architecture rtl of Counter is
              signal STATE : std_logic_vector(3 downto 0) := x"F";
            begin
              process (CLKxCI) begin
                if rising_edge(CLKxCI) and CLKxCI'event then
                  STATE <= "0000"; COUNTxDO <= to_unsigned(16#FF#, 8); EN <= '1';
                end if;
              end process;
            end architecture;
            """
        try assertKind(.keyword, of: ["library", "use", "entity", "is", "port", "in", "out", "downto", "end", "architecture", "of", "signal", "begin", "process", "if", "then", "and"], in: code, "vhdl")
        try assertKind(.typeName, of: ["Counter", "rtl", "std_logic", "unsigned", "std_logic_vector"], in: code, "vhdl")
        try assertKind(.function, of: ["rising_edge", "to_unsigned"], in: code, "vhd")
        try assertKind(.attribute, of: ["'event"], in: code, "vhdl")
        try assertKind(.number, of: ["x\"F\"", "16#FF#", "7", "0", "8"], in: code, "vhdl")
        try assertKind(.string, of: ["\"0000\"", "'1'"], in: code, "vhdl")
        try assertKind(.comment, of: ["-- the counter"], in: code, "vhdl")
        try assertKind(.keyword, of: ["ENTITY", "Begin"], in: "ENTITY x IS\nBegin", "vhdl")
        try assertPlain(["CLKxCI", "STATE"], in: code, "vhdl")
    }

    func testVerilogAndSystemVerilog() throws {
        let code = """
            `timescale 1ns/1ps
            module counter #(parameter WIDTH = 8) (input logic clk, output reg [WIDTH-1:0] count);
              always_ff @(posedge clk) begin
                count <= count + 8'hFF + 'b1 + 4'd10; // step
                $display("count=%d", count);
              end
            endmodule
            """
        try assertKind(.preprocessor, of: ["`timescale"], in: code, "verilog")
        try assertKind(.keyword, of: ["module", "parameter", "input", "output", "always_ff", "posedge", "begin", "end", "endmodule"], in: code, "sv")
        try assertKind(.typeName, of: ["counter", "logic", "reg"], in: code, "systemverilog")
        try assertKind(.number, of: ["8'hFF", "'b1", "4'd10", "8"], in: code, "verilog")
        try assertKind(.function, of: ["$display"], in: code, "verilog")
        try assertKind(.constant, of: ["WIDTH"], in: code, "verilog")
        try assertKind(.comment, of: ["// step"], in: code, "verilog")
        try assertKind(.string, of: ["\"count=%d\""], in: code, "verilog")
    }

    func testAssembly() throws {
        let code = """
            .globl main
            main:
                movq $42, %rax      # answer
                add x0, x1, #4      ; arm
                ret
            """
        try assertKind(.preprocessor, of: [".globl"], in: code, "asm")
        try assertKind(.function, of: ["main:".replacingOccurrences(of: ":", with: "")], in: code, "asm")
        try assertKind(.keyword, of: ["movq", "add", "ret"], in: code, "asm")
        try assertKind(.number, of: ["$42", "#4"], in: code, "asm")
        try assertKind(.variable, of: ["%rax", "x0", "x1"], in: code, "assembly")
        try assertKind(.comment, of: ["# answer", "; arm"], in: code, "asm")
    }

    // MARK: Data and query languages

    func testJSON() throws {
        let code = "{\n  \"name\": \"Graphite\",\n  \"version\": 1.5e3,\n  \"ready\": true, \"none\": null\n}"
        try assertKind(.property, of: ["\"name\"", "\"version\"", "\"ready\"", "\"none\""], in: code, "json")
        try assertKind(.string, of: ["\"Graphite\""], in: code, "json")
        try assertKind(.number, of: ["1.5e3"], in: code, "json")
        try assertKind(.constant, of: ["true", "null"], in: code, "json")
    }

    func testYAML() throws {
        let code = """
            ---
            title: Lecture notes # about
            tags:
              - vlsi
              - name: "quoted"
            enabled: yes
            base: &defaults
              size: 12
            """
        try assertKind(.property, of: ["title", "tags", "name", "enabled", "base", "size"], in: code, "yml")
        try assertKind(.comment, of: ["# about"], in: code, "yaml")
        try assertKind(.string, of: ["\"quoted\""], in: code, "yaml")
        try assertKind(.constant, of: ["yes"], in: code, "yaml")
        try assertKind(.number, of: ["12"], in: code, "yaml")
        try assertKind(.variable, of: ["&defaults"], in: code, "yaml")
        try assertKind(.preprocessor, of: ["---"], in: code, "yaml")
        try assertPlain(["Lecture", "notes", "vlsi"], in: code, "yaml")
    }

    func testSQL() throws {
        let code = """
            SELECT name, COUNT(*) AS total -- per author
            FROM "notes" WHERE created > '2026-01-01' AND body LIKE 'it''s%'
            group by name;
            """
        try assertKind(.keyword, of: ["SELECT", "AS", "FROM", "WHERE", "AND", "LIKE", "group", "by"], in: code, "sql")
        try assertKind(.function, of: ["COUNT"], in: code, "sql")
        try assertKind(.property, of: ["\"notes\""], in: code, "sql")
        try assertKind(.string, of: ["'2026-01-01'", "'it''s%'"], in: code, "sql")
        try assertKind(.comment, of: ["-- per author"], in: code, "sql")
    }

    // MARK: Markup

    func testMarkdown() throws {
        let code = """
            # Title
            - [ ] task with `code` and [[Note]]
            > quoted
            ```c
            int x;
            ```
            [site](https://example.com)
            """
        try assertKind(.keyword, of: ["# Title", "-", "[ ]"], in: code, "md")
        try assertKind(.string, of: ["`code`", "```c", "int x;", "```", "(https://example.com)"], in: code, "markdown")
        try assertKind(.property, of: ["[[Note]]", "[site]"], in: code, "md")
        try assertKind(.comment, of: ["> quoted"], in: code, "md")
    }

    func testLaTeX() throws {
        let code = "\\begin{equation} % Euler\n  e^{i\\pi} + 1 = 0\n\\end{equation}\nCost is \\$5 and $x^2$."
        try assertKind(.keyword, of: ["\\begin", "\\pi", "\\end"], in: code, "latex")
        try assertKind(.typeName, of: ["equation"], in: code, "tex")
        try assertKind(.comment, of: ["% Euler"], in: code, "latex")
        try assertKind(.string, of: ["$x^2$"], in: code, "latex")
        try assertKind(.number, of: ["1", "0"], in: code, "latex")
    }

    func testHTML() throws {
        let code = "<!-- top -->\n<a href=\"/x\" class='link'>Don't &amp; go</a>"
        try assertKind(.comment, of: ["<!-- top -->"], in: code, "html")
        try assertKind(.keyword, of: ["a"], in: code, "html")
        try assertKind(.attribute, of: ["href", "class"], in: code, "xml")
        try assertKind(.string, of: ["\"/x\"", "'link'"], in: code, "html")
        try assertKind(.constant, of: ["&amp;"], in: code, "html")
        XCTAssertFalse(try texts(.string, in: code, "html").contains { text in text.hasPrefix("'t") }, "An apostrophe in text opens no string.")
    }

    func testCSS() throws {
        let code = ".theme-dark a:hover {\n  --accent: #1e1e2e;\n  margin: -4px 0 var(--accent);\n}\n@media print { body { color: red; } }"
        try assertKind(.typeName, of: [".theme-dark"], in: code, "css")
        try assertKind(.property, of: ["--accent", "margin"], in: code, "css")
        try assertKind(.number, of: ["#1e1e2e", "-4px", "0"], in: code, "css")
        try assertKind(.variable, of: ["--accent"], in: code, "css")
        try assertKind(.keyword, of: ["@media"], in: code, "css")
        try assertKind(.function, of: ["var"], in: code, "css")
    }

    // MARK: Line states

    func testLineStatesRoundTripThroughStoredValues() {
        let states: [CodeLineState] = [.normal, .markupTag, .string(ruleIndex: 0), .string(ruleIndex: 3), .blockComment(ruleIndex: 0, depth: 1), .blockComment(ruleIndex: 2, depth: 5)]
        for state in states { XCTAssertEqual(CodeLineState(storedValue: state.storedValue), state) }
    }

    func testLineByLineMatchesWholeCode() throws {
        let language = try XCTUnwrap(CodeLanguage.named("c"))
        let code = "int a; /* open\nstill */ int b;\nchar *s = \"x\";"
        let units = Array(code.utf16)
        var highlighter = CodeLineHighlighter(language: language)
        let lines = CodeSyntaxHighlighter.lineRanges(in: units)
        // Following the state past the first line without tokens gives the same second line.
        highlighter.advance(pastLine: lines[0], of: units)
        XCTAssertEqual(highlighter.state, .blockComment(ruleIndex: 0, depth: 1))
        let secondLine = highlighter.tokens(inLine: lines[1], of: units)
        let whole = CodeSyntaxHighlighter.uncachedTokens(in: code, language: language)
        XCTAssertEqual(secondLine, whole.filter { token in token.range.location >= lines[1].lowerBound && token.range.location < lines[1].upperBound })
        XCTAssertEqual(highlighter.state, .normal)
    }

    func testWindowsLineEndingsSplitLines() {
        XCTAssertEqual(CodeSyntaxHighlighter.lineRanges(in: Array("a\r\nbc\rd\n".utf16)), [0..<1, 3..<5, 6..<7, 8..<8])
    }

    func testUnknownCharactersDoNotStopTheScan() throws {
        try assertKind(.keyword, of: ["return"], in: "π = \"ü\" 🎉; return", "c")
        XCTAssertTrue(try tokens("", "c").isEmpty)
        XCTAssertNotNil(try tokens("\"unterminated\n'x", "c"))
    }

    /// A 2,000-line block is tokenized well within a frame in an optimized build; this debug
    /// test allows far more and catches a pass that is quadratic in the block's length.
    func testLongBlockIsTokenizedQuickly() throws {
        let language = try XCTUnwrap(CodeLanguage.named("cpp"))
        let line = "    for (int index = 0; index < count; ++index) { total += values[index] * 0x1F; } // sum\n"
        let code = String(repeating: line, count: 2_000)
        let start = Date()
        let tokens = CodeSyntaxHighlighter.uncachedTokens(in: code, language: language)
        let elapsedSeconds = Date().timeIntervalSince(start)
        XCTAssertEqual(tokens.filter { token in token.kind == .comment }.count, 2_000)
        XCTAssertLessThan(elapsedSeconds, 2.0, "2,000 lines took \(elapsedSeconds) s")
    }

    func testCachedTokensMatchUncached() throws {
        let language = try XCTUnwrap(CodeLanguage.named("python"))
        let code = "def f():\n    return 1  # one"
        XCTAssertEqual(CodeSyntaxHighlighter.tokens(in: code, language: language), CodeSyntaxHighlighter.uncachedTokens(in: code, language: language))
        XCTAssertEqual(CodeSyntaxHighlighter.tokens(in: code, language: language), CodeSyntaxHighlighter.uncachedTokens(in: code, language: language))
    }
}
