# Offline mathematical speech

Graphite uses MathJax to parse original LaTeX into MathML, then Speech Rule Engine to generate English descriptions. This bundle changes mathematical speech preparation, not Graphite's native equation renderer or the voice that speaks the prepared text.

## Pinned dependencies

| Dependency | Version | License | Purpose |
| --- | --- | --- | --- |
| `@mathjax/src` | 4.1.3 | Apache-2.0 | LaTeX parsing and MathML serialization, using base, AMS, boldsymbol and color packages |
| `speech-rule-engine` | 4.1.4 | Apache-2.0 | ClearSpeak concise and MathSpeak detailed English descriptions |
| `@xmldom/xmldom` | 0.9.12 | MIT | XML DOM used by Speech Rule Engine; explicitly overrides its older parser dependency |
| `wicked-good-xpath` | 1.3.0 | MIT | XPath evaluation over the in-memory XML DOM |
| `esbuild` | 0.28.2 | MIT | Build-time bundling only; not an application runtime |

MathJax 4 is the current major line at integration time (2026-10-11). Speech Rule Engine 4.1.4 is the stable line selected instead of the published 5.0 release candidate. The lock file records all build dependencies and integrity hashes; `bundle-inputs.json` records the modules included in the runtime resource. Installation and audit reported zero known vulnerabilities on 2026-10-11. That is a dated check, not a continuing security guarantee.

Full runtime dependency licenses are copied into the application resource directory. Generated code retains third-party legal comments. Upstream documentation: [MathJax direct conversion](https://docs.mathjax.org/en/v4.0/server/direct.html), [Speech Rule Engine](https://github.com/Speech-Rule-Engine/speech-rule-engine).

## Rebuilding

Run in this directory:

```sh
npm ci --ignore-scripts
node build.mjs
```

The script writes `Sources/GraphiteApple/Resources/MathSpeech/math-speech.js`, its licenses, and the module inventory. SwiftPM copies the resources into GraphiteApple's bundle. The app uses Apple's JavaScriptCore framework; it does not install or launch Node, load a web page, or download a script at runtime.

`system-external.js` replaces Speech Rule Engine's environment adapter at bundle time. It supplies the bundled XML parser and XPath implementation, with no filesystem, network, browser script loader, or native bridge. Only base and English rule maps are included. TeX is passed as a function argument, never concatenated into executable JavaScript. A fresh MathJax parser per expression isolates equation state; user macro-definition packages, URL/HTML extensions and external file inclusion are not enabled.

## Bounds and ownership

`ReadAloudMarkdownPreparation` owns the mutable interpreter on a Swift actor, initializes it lazily for the first equation, and returns immutable prepared speech/source ranges. Core retains its conservative pure Swift interpreter for callers that do not supply the Apple adapter; the production document reader supplies the bundled engine. Preview-only source alignment can use Core's equation spans without generating the same spoken wording.

The actor serializes context use even if its executor changes threads. Apple's [JavaScriptCore threading contract](https://developer.apple.com/documentation/javascriptcore/jsvirtualmachine) permits calls from different threads and serializes access to a virtual machine; no JavaScript values leave this actor or cross into another context.

Each expression is limited to 8,192 UTF-16 units, 32 nested source groups/delimiters, 256 macro substitutions, 4,096 MathML nodes, 64 tree levels, 65,536 serialized MathML units and 32,768 spoken units. A FIFO cache is bounded to 128 requests and 262,144 combined source/spoken UTF-16 units. Whole-note budgets and cancellation checks remain in Core. A canceled request cannot install a document in the UI. Cancellation is observed between bounded expressions; it does not interrupt JavaScript in the middle of an expression.

Unknown commands, malformed expressions and exceeded bounds are announced as unsupported. Engine startup/resource failures are reported as preparation errors rather than silently falling back to different mathematics. Concise/detailed mode changes prepare the chosen source range again and wait for Play. This does not recognize equations from a PDF, infer missing notation, support arbitrary TeX documents/macros, or establish term-level highlight geometry. Source formulas still highlight as complete expressions.
