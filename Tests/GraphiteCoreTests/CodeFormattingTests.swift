import XCTest
@testable import GraphiteCore

final class CodeFormattingTests: XCTestCase {
    private func formatted(_ code: String, _ languageName: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let language = try XCTUnwrap(CodeLanguage.named(languageName), file: file, line: line)
        return try XCTUnwrap(CodeFormatter.formatted(code, language: language), "\(languageName) is formatted", file: file, line: line)
    }

    func testTheOwnersExample() throws {
        XCTAssertEqual(try formatted("main(){\n\n\n}\n", "c"), "main() {\n}\n")
    }

    func testCIndentsByBracesAndTidiesSpaces() throws {
        let code = """
            #include <stdio.h>
              #define MAX(a,b) ((a)>(b)?(a):(b))
            int main(void){
            int values[] = {1,2,3};
            for(int index=0;index<3;index++){
            if(values[index]>1){
            printf("%d,%d\\n",index,values[index]);
            }else{
            /* a,b stays */
            }
            }


            return 0;
            }
            """
        let expected = """
            #include <stdio.h>
            #define MAX(a, b) ((a)>(b)?(a):(b))
            int main(void) {
                int values[] = {1, 2, 3};
                for (int index=0;index<3;index++) {
                    if (values[index]>1) {
                        printf("%d,%d\\n", index, values[index]);
                    } else {
                        /* a,b stays */
                    }
                }

                return 0;
            }
            """
        XCTAssertEqual(try formatted(code, "c"), expected)
    }

    func testTheCodesOwnIndentationWidthIsKept() throws {
        let code = "int main() {\n  if (x) {\ny();\n  }\n}"
        XCTAssertEqual(try formatted(code, "cpp"), "int main() {\n  if (x) {\n    y();\n  }\n}")
        XCTAssertEqual(try formatted("func main() {\n\tif x {\ny()\n}\n}", "go"), "func main() {\n\tif x {\n\t\ty()\n\t}\n}")
    }

    func testStringsAndCommentsAreNotChangedInside() throws {
        let code = "const a = `line,one\n   keep  {\n`;\nlet b = \"x,y){\"; // c,d){\n"
        XCTAssertEqual(try formatted(code, "js"), "const a = `line,one\n   keep  {\n`;\nlet b = \"x,y){\"; // c,d){\n")
        let comment = "void f() {\n/**\n* Doc.\n*/\nint x;\n}"
        XCTAssertEqual(try formatted(comment, "c"), "void f() {\n    /**\n     * Doc.\n     */\n    int x;\n}")
    }

    func testVHDL() throws {
        let code = """
            library ieee;
            use ieee.std_logic_1164.all;
            entity counter is
            port (
            CLKxCI : in std_logic;
            COUNTxDO : out unsigned(7 downto 0)
            );
            end entity counter;
            architecture rtl of counter is
            signal STATExDP : unsigned(7 downto 0);
            begin
            p_count : process (CLKxCI)
            begin
            if rising_edge(CLKxCI) then
            case MODExS is
            when IDLE =>
            STATExDP <= (others => '0');
            when others =>
            STATExDP <= STATExDP + 1;
            end case;
            elsif ENxS = '1' then
            STATExDP <= x"FF";
            else
            null;
            end if;
            end process p_count;
            u_sub : entity work.sub port map (A => B);
            end architecture rtl;
            """
        let expected = """
            library ieee;
            use ieee.std_logic_1164.all;
            entity counter is
                port (
                    CLKxCI : in std_logic;
                    COUNTxDO : out unsigned(7 downto 0)
                );
            end entity counter;
            architecture rtl of counter is
                signal STATExDP : unsigned(7 downto 0);
            begin
                p_count : process (CLKxCI)
                begin
                    if rising_edge(CLKxCI) then
                        case MODExS is
                            when IDLE =>
                                STATExDP <= (others => '0');
                            when others =>
                                STATExDP <= STATExDP + 1;
                        end case;
                    elsif ENxS = '1' then
                        STATExDP <= x"FF";
                    else
                        null;
                    end if;
                end process p_count;
                u_sub : entity work.sub port map (A => B);
            end architecture rtl;
            """
        XCTAssertEqual(try formatted(code, "vhdl"), expected)
        XCTAssertEqual(try formatted("IF a THEN\nb <= c;\nEND IF;", "vhdl"), "IF a THEN\n    b <= c;\nEND IF;", "Keywords are found in any case.")
    }

    func testVerilog() throws {
        let code = """
            module counter(input clk, output reg [7:0] count);
            always @(posedge clk) begin
            if (reset) begin
            count <= 8'h00;
            end else begin
            case (mode)
            2'b00: count <= count + 1;
            default: count <= count;
            endcase
            end
            end
            endmodule
            """
        let expected = """
            module counter(input clk, output reg [7:0] count);
                always @(posedge clk) begin
                    if (reset) begin
                        count <= 8'h00;
                    end else begin
                        case (mode)
                            2'b00: count <= count + 1;
                            default: count <= count;
                        endcase
                    end
                end
            endmodule
            """
        XCTAssertEqual(try formatted(code, "sv"), expected)
    }

    func testPythonKeepsItsIndentation() throws {
        let code = "def f(a,b):  \n    return a\n\n\n\n\nprint(f(1,2))\n"
        XCTAssertEqual(try formatted(code, "py"), "def f(a, b):\n    return a\n\n\nprint(f(1, 2))\n")
    }

    func testShell() throws {
        let code = "for file in *.md; do\nif [ -f \"$file\" ]; then\necho \"$file\"\nelse\nexit 1\nfi\ncase \"$file\" in\na|b)\necho one\n;;\n*)\necho other\n;;\nesac\ndone"
        let expected = "for file in *.md; do\n    if [ -f \"$file\" ]; then\n        echo \"$file\"\n    else\n        exit 1\n    fi\n    case \"$file\" in\n        a|b)\n            echo one\n            ;;\n        *)\n            echo other\n            ;;\n    esac\ndone"
        XCTAssertEqual(try formatted(code, "sh"), expected)
    }

    func testMATLABLuaAndLaTeX() throws {
        XCTAssertEqual(try formatted("function y = f(x)\nif x(end) > 0\ny = 1;\nelse\ny = 2;\nend\nend", "matlab"),
                       "function y = f(x)\n    if x(end) > 0\n        y = 1;\n    else\n        y = 2;\n    end\nend")
        XCTAssertEqual(try formatted("local function f(x)\nif x then\nreturn 1\nelseif y then\nreturn 2\nend\nend", "lua"),
                       "local function f(x)\n  if x then\n    return 1\n  elseif y then\n    return 2\n  end\nend")
        XCTAssertEqual(try formatted("\\begin{document}\n\\begin{itemize}\n\\item One\n\\end{itemize}\n\\end{document}", "latex"),
                       "\\begin{document}\n\\begin{itemize}\n  \\item One\n\\end{itemize}\n\\end{document}")
    }

    func testJSONAndWindowsLineEndings() throws {
        XCTAssertEqual(try formatted("{\r\n\"a\": [1,2],\r\n\"b\": {\"c\": true}\r\n}\r\n", "json"),
                       "{\r\n  \"a\": [1, 2],\r\n  \"b\": {\"c\": true}\r\n}\r\n")
    }

    func testFormattingIsStable() throws {
        for (code, language) in [("int main(){\nif(x){y();}\n}", "c"), ("entity e is\nend entity;", "vhdl"), ("def f():\n  pass", "python")] {
            let once = try formatted(code, language)
            XCTAssertEqual(try formatted(once, language), once, language)
        }
    }

    func testMarkdownIsNotFormatted() throws {
        XCTAssertNil(CodeFormatter.formatted("a  \nb", language: try XCTUnwrap(CodeLanguage.named("md"))))
    }

    func testFencedCodeBlockFindsItsCodeAndContainsLocations() {
        let text = "Intro\n```c\nint a;\n````\nint b;\n```\nAfter\n" as NSString
        let codeStart = text.range(of: "int a").location
        let block = FencedCodeBlock(language: "c", codeStart: codeStart, quoteDepth: 0, fence: "```")
        XCTAssertEqual(text.substring(with: block.codeRange(in: text)), "int a;\n", "A longer fence closes the block too.")
        XCTAssertFalse(block.contains(text.range(of: "int b").location, in: text))
        XCTAssertTrue(block.contains(codeStart + 2, in: text))
        XCTAssertFalse(block.contains(text.range(of: "After").location, in: text))
        XCTAssertFalse(block.contains(0, in: text))
    }
}
