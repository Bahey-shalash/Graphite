import XCTest
@testable import GraphiteCore

final class HTMLToMarkdownTests: XCTestCase {
    func testCommonWebMarkupBecomesMarkdown() {
        let html = """
        <html><head><style>p { color: red }</style></head><body>
        <h2>Fourier <em>series</em></h2>
        <p>A <strong>periodic</strong> signal &amp; its <a href="https://example.org/wiki">harmonics</a>.<br>Next line</p>
        <ul><li>one</li><li>two<ol><li>nested</li></ol></li></ul>
        <blockquote><p>Quoted</p></blockquote>
        <pre><code>let x = 1
        let y = 2</code></pre>
        <p>Inline <code>code</code> and <img src="https://example.org/a.png" alt="Plot"></p>
        <table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>
        <!-- a comment --><script>alert(1)</script>
        </body></html>
        """
        let expected = """
        ## Fourier *series*

        A **periodic** signal & its [harmonics](https://example.org/wiki).  
        Next line

        - one
        - two
        \t1. nested

        > Quoted

        ```
        let x = 1
        let y = 2
        ```

        Inline `code` and ![Plot](https://example.org/a.png)

        | A | B |
        | --- | --- |
        | 1 | 2 |
        """
        XCTAssertEqual(HTMLToMarkdown.markdown(from: html), expected)
    }

    func testEntitiesAndBrokenMarkup() {
        XCTAssertEqual(HTMLToMarkdown.markdown(from: "&lt;tag&gt; &#8594; &#x2192; &nbsp;x"), "<tag> → → x")
        XCTAssertEqual(HTMLToMarkdown.markdown(from: "<b>unclosed <i>tags"), "**unclosed *tags")
        XCTAssertEqual(HTMLToMarkdown.markdown(from: "a < b and c > d"), "a < b and c > d")
    }
}
