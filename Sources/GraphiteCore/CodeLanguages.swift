import Foundation

/// A programming or markup language's lexical rules: its words, comments, strings and the
/// conventions `CodeLineHighlighter` colors by. Two languages are equal when their names are.
public struct CodeLanguage: Hashable, Sendable {
    /// The canonical name, such as `cpp` for ```` ```c++ ````.
    public let name: String
    let syntax: Syntax
    let features: Features
    let ignoresCase: Bool
    let keywords: Set<String>
    let typeNames: Set<String>
    let constants: Set<String>
    let builtinFunctions: Set<String>
    /// Registers in assembly.
    let variableNames: Set<String>
    /// Keywords after which the next name is declared as a function: `def`, `fn`, `func`.
    let functionDeclarationKeywords: Set<String>
    /// Keywords after which the next name is declared as a type: `class`, `struct`, `entity`.
    let typeDeclarationKeywords: Set<String>
    /// Lowercased letters written right before a string's quote: `r`, `f`, `b`, `u8`.
    let stringPrefixes: Set<String>
    let lineCommentPrefixes: [[UInt16]]
    let blockComments: [BlockCommentRule]
    /// Tried in order, so `"""` comes before `"`.
    let strings: [StringRule]
    /// Characters besides letters, digits and `_` that names may contain: `$` in JavaScript.
    let identifierExtraUnits: Set<UInt16>

    public static func == (leftLanguage: CodeLanguage, rightLanguage: CodeLanguage) -> Bool { leftLanguage.name == rightLanguage.name }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }

    enum Syntax: Sendable {
        case general, markdown, markup
    }

    struct Features: OptionSet, Sendable {
        let rawValue: Int
        static let marksFunctionCalls = Features(rawValue: 1 << 0)
        static let capitalizedIdentifiersAreTypes = Features(rawValue: 1 << 1)
        static let uppercaseIdentifiersAreConstants = Features(rawValue: 1 << 2)
        /// `size_t`, `pthread_t`: C's names ending in `_t` are types.
        static let underscoreTypeSuffix = Features(rawValue: 1 << 3)
        /// `#include` at the start of a line.
        static let lineStartHashDirectives = Features(rawValue: 1 << 4)
        /// `#if`, `#available` anywhere, as in Swift.
        static let hashDirectives = Features(rawValue: 1 << 5)
        static let atAttributes = Features(rawValue: 1 << 6)
        /// Rust's `#[derive(Debug)]`.
        static let bracketAttributes = Features(rawValue: 1 << 7)
        static let dollarVariables = Features(rawValue: 1 << 8)
        /// Verilog's system tasks, `$display`.
        static let dollarFunctions = Features(rawValue: 1 << 9)
        /// Verilog's `` `define `` and `` `timescale ``.
        static let backtickDirectives = Features(rawValue: 1 << 10)
        /// A single quote is a character (`'a'`) or something else, never a long string.
        static let characterLiteralsOnly = Features(rawValue: 1 << 11)
        /// VHDL's `16#FF#`, `x"FF"` and `clk'event`.
        static let vhdlNumbers = Features(rawValue: 1 << 12)
        /// Verilog's `8'hFF` and `'0`.
        static let verilogNumbers = Features(rawValue: 1 << 13)
        /// MATLAB's `a'`, which transposes rather than quotes.
        static let transposeQuote = Features(rawValue: 1 << 14)
        /// LaTeX's `\section`.
        static let backslashCommands = Features(rawValue: 1 << 15)
        /// Mnemonics, labels, registers, directives and immediates.
        static let assemblyLines = Features(rawValue: 1 << 16)
        /// JSON's `"key":`.
        static let keysBeforeColon = Features(rawValue: 1 << 17)
        static let yamlKeys = Features(rawValue: 1 << 18)
        /// YAML's plain values stay plain, with its anchors, aliases, tags and `---`.
        static let yamlValues = Features(rawValue: 1 << 19)
        /// Rust's `println!` and lifetimes.
        static let macroBang = Features(rawValue: 1 << 20)
        /// `#` starts a comment only after a space or at the start of a line.
        static let hashCommentsAfterSpace = Features(rawValue: 1 << 21)
        /// C#'s `@"…"` and `$"…"`, Objective-C's `@"…"`.
        static let sigilStringPrefixes = Features(rawValue: 1 << 22)
        /// Ruby's `@name`.
        static let atVariables = Features(rawValue: 1 << 23)
        /// C++'s `1'000'000`.
        static let digitSeparatorQuotes = Features(rawValue: 1 << 24)
        /// CSS's properties, selectors, hex colors and custom properties.
        static let cssRules = Features(rawValue: 1 << 25)
        /// Names that are nothing else, and operators, are tokens of their own.
        static let identifiersAndOperators = Features(rawValue: 1 << 26)
        /// `Point(1, 2)` makes a value of the type `Point`: functions are written in lower case.
        static let capitalizedCallsMakeTypes = Features(rawValue: 1 << 27)
    }

    struct BlockCommentRule: Sendable {
        let opening: [UInt16]
        let closing: [UInt16]
        var nests = false
        /// MATLAB's `%{` and Ruby's `=begin`, which open and close alone on their lines.
        var opensOnlyAloneOnLine = false

        init(_ opening: String, _ closing: String, nests: Bool = false, opensOnlyAloneOnLine: Bool = false) {
            self.opening = Array(opening.utf16)
            self.closing = Array(closing.utf16)
            self.nests = nests
            self.opensOnlyAloneOnLine = opensOnlyAloneOnLine
        }
    }

    struct StringRule: Sendable {
        let opening: [UInt16]
        let closing: [UInt16]
        var usesBackslashEscapes = false
        /// `''` inside `'…'` is a quote, as in SQL, VHDL and MATLAB.
        var doubledClosingEscapes = false
        var spansLines = false
        var kind = CodeTokenKind.string

        init(opening: String, closing: String, usesBackslashEscapes: Bool = false, doubledClosingEscapes: Bool = false,
             spansLines: Bool = false, kind: CodeTokenKind = .string) {
            self.opening = Array(opening.utf16)
            self.closing = Array(closing.utf16)
            self.usesBackslashEscapes = usesBackslashEscapes
            self.doubledClosingEscapes = doubledClosingEscapes
            self.spansLines = spansLines
            self.kind = kind
        }

        static func escaped(_ quote: String, spansLines: Bool = false) -> StringRule {
            StringRule(opening: quote, closing: quote, usesBackslashEscapes: true, spansLines: spansLines)
        }
    }

    init(name: String, syntax: Syntax = .general, features: Features = [], ignoresCase: Bool = false,
         keywords: String = "", typeNames: String = "", constants: String = "", builtinFunctions: String = "",
         variableNames: Set<String> = [], functionDeclarationKeywords: String = "", typeDeclarationKeywords: String = "",
         stringPrefixes: String = "", lineComments: [String] = [], blockComments: [BlockCommentRule] = [], strings: [StringRule] = [],
         identifierExtraCharacters: String = "") {
        func words(_ list: String) -> Set<String> {
            Set(list.split(whereSeparator: \.isWhitespace).map { word in ignoresCase ? word.lowercased() : String(word) })
        }
        self.name = name
        self.syntax = syntax
        self.features = features
        self.ignoresCase = ignoresCase
        self.keywords = words(keywords)
        self.typeNames = words(typeNames)
        self.constants = words(constants)
        self.builtinFunctions = words(builtinFunctions)
        self.variableNames = variableNames
        self.functionDeclarationKeywords = words(functionDeclarationKeywords)
        self.typeDeclarationKeywords = words(typeDeclarationKeywords)
        self.stringPrefixes = Set(stringPrefixes.split(whereSeparator: \.isWhitespace).map { prefix in prefix.lowercased() })
        self.lineCommentPrefixes = lineComments.map { prefix in Array(prefix.utf16) }
        self.blockComments = blockComments
        self.strings = strings
        self.identifierExtraUnits = Set(identifierExtraCharacters.utf16)
    }

    /// The language a code block's first info word names, ignoring case: `cpp`, `C++`,
    /// `vhd`, `sh`. Nil for a language Graphite does not highlight.
    public static func named(_ name: String) -> CodeLanguage? {
        languagesByAlias[name.lowercased()]
    }

    /// Every language Graphite highlights.
    public static let all: [CodeLanguage] = [
        .c, .cpp, .objectiveC, .csharp, .java, .kotlin, .javaScript, .typeScript, .python, .swift, .rust, .go,
        .shell, .json, .yaml, .sql, .vhdl, .verilog, .assembly, .matlab, .latex, .markdown, .markup, .css, .ruby, .lua,
    ]

    private static let aliases: [String: [String]] = [
        "c": ["c", "h"],
        "cpp": ["cpp", "c++", "cc", "cxx", "hpp", "hh", "hxx", "h++", "ino", "cuda", "cu"],
        "objectivec": ["objectivec", "objective-c", "objc", "mm"],
        "csharp": ["csharp", "c#", "cs"],
        "java": ["java"],
        "kotlin": ["kotlin", "kt", "kts"],
        "javascript": ["javascript", "js", "jsx", "mjs", "cjs", "node"],
        "typescript": ["typescript", "ts", "tsx", "mts", "cts"],
        "python": ["python", "py", "python3", "py3", "gyp", "sage"],
        "swift": ["swift"],
        "rust": ["rust", "rs"],
        "go": ["go", "golang"],
        "shell": ["bash", "sh", "shell", "zsh", "ksh", "shellscript", "console", "terminal", "command"],
        "json": ["json", "jsonc", "json5", "geojson", "webmanifest"],
        "yaml": ["yaml", "yml"],
        "sql": ["sql", "mysql", "postgresql", "postgres", "psql", "sqlite", "plsql", "tsql"],
        "vhdl": ["vhdl", "vhd"],
        "verilog": ["verilog", "v", "systemverilog", "sv", "svh", "vh"],
        "assembly": ["asm", "assembly", "nasm", "masm", "gas", "x86asm", "x86", "armasm", "arm", "aarch64", "riscv", "mips", "s"],
        "matlab": ["matlab", "octave"],
        "latex": ["latex", "tex", "context"],
        "markdown": ["markdown", "md", "mdx"],
        "markup": ["html", "htm", "xhtml", "xml", "svg", "plist", "xaml", "vue", "markup"],
        "css": ["css", "scss", "less", "sass"],
        "ruby": ["ruby", "rb", "gemspec", "rake"],
        "lua": ["lua"],
    ]

    private static let languagesByAlias: [String: CodeLanguage] = {
        var languagesByAlias: [String: CodeLanguage] = [:]
        for language in all {
            for alias in aliases[language.name] ?? [language.name] { languagesByAlias[alias] = language }
        }
        return languagesByAlias
    }()

    // MARK: Shared rules

    private static let cStyleComments = [BlockCommentRule("/*", "*/")]
    private static let doubleAndSingleQuotes: [StringRule] = [.escaped("\""), .escaped("'")]
    private static let cStyleFeatures: Features = [.marksFunctionCalls, .uppercaseIdentifiersAreConstants, .identifiersAndOperators]

    private static let cKeywords = """
        auto break case const continue default do else enum extern for goto if inline register restrict return sizeof static struct switch \
        typedef union volatile while _Alignas _Alignof _Atomic _Generic _Noreturn _Static_assert _Thread_local alignas alignof static_assert \
        thread_local typeof
        """
    private static let cTypes = """
        char double float int long short signed unsigned void _Bool bool _Complex size_t ssize_t ptrdiff_t intptr_t uintptr_t wchar_t \
        int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t FILE va_list
        """

    // MARK: Languages

    static let c = CodeLanguage(
        name: "c", features: cStyleFeatures.union([.lineStartHashDirectives, .underscoreTypeSuffix]),
        keywords: cKeywords, typeNames: cTypes, constants: "NULL true false EOF stdin stdout stderr",
        typeDeclarationKeywords: "struct enum union", stringPrefixes: "L u U u8",
        lineComments: ["//"], blockComments: cStyleComments, strings: doubleAndSingleQuotes)

    static let cpp = CodeLanguage(
        name: "cpp", features: cStyleFeatures.union([.lineStartHashDirectives, .underscoreTypeSuffix, .capitalizedIdentifiersAreTypes, .digitSeparatorQuotes]),
        keywords: cKeywords + """
             and and_eq asm bitand bitor catch class compl concept consteval constexpr constinit const_cast co_await co_return co_yield \
            decltype delete dynamic_cast explicit export friend mutable namespace new noexcept not not_eq operator or or_eq private \
            protected public reinterpret_cast requires static_cast template this throw try typeid typename using virtual xor xor_eq \
            override final import module
            """,
        typeNames: cTypes + """
             char8_t char16_t char32_t string string_view wstring vector map unordered_map set unordered_set multimap multiset array \
            deque list forward_list queue priority_queue stack optional variant any unique_ptr shared_ptr weak_ptr pair tuple function \
            ostream istream iostream fstream ifstream ofstream stringstream span thread mutex atomic
            """,
        constants: "nullptr NULL true false", typeDeclarationKeywords: "class struct enum union namespace concept",
        stringPrefixes: "L u U u8 R LR uR UR u8R", lineComments: ["//"], blockComments: cStyleComments, strings: doubleAndSingleQuotes)

    static let objectiveC = CodeLanguage(
        name: "objectivec",
        features: cStyleFeatures.union([.lineStartHashDirectives, .underscoreTypeSuffix, .capitalizedIdentifiersAreTypes, .atAttributes, .sigilStringPrefixes]),
        keywords: cKeywords
            + " self super in out inout bycopy byref oneway nonatomic atomic strong weak copy assign readonly readwrite retain nullable nonnull",
        typeNames: cTypes + " id instancetype BOOL SEL IMP Class NSInteger NSUInteger CGFloat",
        constants: "nil Nil NULL YES NO true false", typeDeclarationKeywords: "struct enum union",
        lineComments: ["//"], blockComments: cStyleComments, strings: doubleAndSingleQuotes)

    static let csharp = CodeLanguage(
        name: "csharp", features: cStyleFeatures.union([.lineStartHashDirectives, .capitalizedIdentifiersAreTypes, .sigilStringPrefixes]),
        keywords: """
            abstract as base break case catch checked class const continue default delegate do else enum event explicit extern finally \
            fixed for foreach goto if implicit in interface internal is lock namespace new operator out override params private protected \
            public readonly ref return sealed sizeof stackalloc static struct switch this throw try typeof unchecked unsafe using virtual \
            volatile while add alias ascending async await by descending equals from get global group into join let nameof on orderby \
            partial remove select set value var when where yield record init required with not and or
            """,
        typeNames: "bool byte char decimal double float int long object sbyte short string uint ulong ushort void dynamic nint nuint",
        constants: "true false null", typeDeclarationKeywords: "class struct enum interface record namespace",
        lineComments: ["//"], blockComments: cStyleComments,
        strings: [StringRule(opening: "\"\"\"", closing: "\"\"\"", spansLines: true), .escaped("\""), .escaped("'")])

    static let java = CodeLanguage(
        name: "java", features: cStyleFeatures.union([.capitalizedIdentifiersAreTypes, .capitalizedCallsMakeTypes, .atAttributes]),
        keywords: """
            abstract assert break case catch class continue default do else enum extends final finally for if implements import instanceof \
            interface native new package private protected public return static strictfp super switch synchronized this throw throws \
            transient try volatile while var record sealed permits yield module requires exports opens
            """,
        typeNames: "boolean byte char double float int long short void", constants: "true false null",
        typeDeclarationKeywords: "class interface enum record", lineComments: ["//"], blockComments: cStyleComments,
        strings: [StringRule(opening: "\"\"\"", closing: "\"\"\"", usesBackslashEscapes: true, spansLines: true), .escaped("\""), .escaped("'")],
        identifierExtraCharacters: "$")

    static let kotlin = CodeLanguage(
        name: "kotlin", features: cStyleFeatures.union([.capitalizedIdentifiersAreTypes, .capitalizedCallsMakeTypes, .atAttributes]),
        keywords: """
            as break class continue do else for fun if in interface is object package return super this throw try typealias val var when \
            while by catch constructor delegate dynamic field file finally get import init param property receiver set setparam where \
            actual abstract annotation companion const crossinline data enum expect external final infix inline inner internal lateinit \
            noinline open operator out override private protected public reified sealed suspend tailrec vararg value
            """,
        constants: "true false null", functionDeclarationKeywords: "fun", typeDeclarationKeywords: "class interface object typealias",
        lineComments: ["//"], blockComments: [BlockCommentRule("/*", "*/", nests: true)],
        strings: [StringRule(opening: "\"\"\"", closing: "\"\"\"", spansLines: true), .escaped("\""), .escaped("'")])

    private static let javaScriptKeywords = """
        break case catch class const continue debugger default delete do else export extends finally for function if import in \
        instanceof let new return super switch this throw try typeof var void while with yield async await of static get set from as
        """

    static let javaScript = CodeLanguage(
        name: "javascript", features: cStyleFeatures.union([.capitalizedIdentifiersAreTypes, .capitalizedCallsMakeTypes, .atAttributes]),
        keywords: javaScriptKeywords, constants: "true false null undefined NaN Infinity",
        functionDeclarationKeywords: "function", typeDeclarationKeywords: "class", lineComments: ["//"], blockComments: cStyleComments,
        strings: [.escaped("\""), .escaped("'"), .escaped("`", spansLines: true)], identifierExtraCharacters: "$")

    static let typeScript = CodeLanguage(
        name: "typescript", features: cStyleFeatures.union([.capitalizedIdentifiersAreTypes, .capitalizedCallsMakeTypes, .atAttributes]),
        keywords: javaScriptKeywords + """
             type interface enum namespace declare abstract implements private protected public readonly keyof infer is asserts \
            satisfies module override unique
            """,
        typeNames: "any boolean number string symbol bigint never unknown object void",
        constants: "true false null undefined NaN Infinity", functionDeclarationKeywords: "function",
        typeDeclarationKeywords: "class interface enum type namespace", lineComments: ["//"], blockComments: cStyleComments,
        strings: [.escaped("\""), .escaped("'"), .escaped("`", spansLines: true)], identifierExtraCharacters: "$")

    static let python = CodeLanguage(
        name: "python", features: cStyleFeatures.union([.capitalizedIdentifiersAreTypes, .capitalizedCallsMakeTypes, .atAttributes]),
        keywords: """
            and as assert async await break class continue def del elif else except finally for from global if import in is lambda \
            nonlocal not or pass raise return try while with yield match case
            """,
        typeNames: "int str float list dict set tuple bool bytes bytearray object type complex frozenset memoryview range",
        constants: "True False None NotImplemented Ellipsis self cls",
        builtinFunctions: """
            print len open isinstance issubclass enumerate zip map filter sorted reversed sum min max abs any all input super property \
            staticmethod classmethod iter next repr hash id format getattr setattr hasattr delattr callable round divmod pow chr ord bin \
            hex oct vars dir globals locals exec eval compile help slice
            """,
        functionDeclarationKeywords: "def", typeDeclarationKeywords: "class", stringPrefixes: "r u b f rb br fr rf",
        lineComments: ["#"],
        strings: [StringRule(opening: "\"\"\"", closing: "\"\"\"", usesBackslashEscapes: true, spansLines: true),
                  StringRule(opening: "'''", closing: "'''", usesBackslashEscapes: true, spansLines: true), .escaped("\""), .escaped("'")])

    static let swift = CodeLanguage(
        name: "swift",
        features: [.marksFunctionCalls, .capitalizedIdentifiersAreTypes, .capitalizedCallsMakeTypes, .hashDirectives, .atAttributes, .identifiersAndOperators],
        keywords: """
            associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private \
            precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do \
            else fallthrough for guard if in repeat return throw switch where while as is try throws await async actor any some \
            nonisolated isolated consume borrowing consuming discard each macro package super self Self get set willSet didSet lazy \
            mutating nonmutating optional override required convenience dynamic final indirect weak unowned sending
            """,
        constants: "true false nil", functionDeclarationKeywords: "func", typeDeclarationKeywords: "class struct enum protocol extension actor typealias",
        lineComments: ["//"], blockComments: [BlockCommentRule("/*", "*/", nests: true)],
        strings: [StringRule(opening: "\"\"\"", closing: "\"\"\"", usesBackslashEscapes: true, spansLines: true), .escaped("\"")])

    static let rust = CodeLanguage(
        name: "rust",
        features: cStyleFeatures.union([.capitalizedIdentifiersAreTypes, .capitalizedCallsMakeTypes, .bracketAttributes, .macroBang, .characterLiteralsOnly]),
        keywords: """
            as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return \
            self Self static struct super trait type union unsafe use where while yield macro_rules
            """,
        typeNames: "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str",
        constants: "true false", functionDeclarationKeywords: "fn", typeDeclarationKeywords: "struct enum trait type union mod",
        stringPrefixes: "b r br c cr", lineComments: ["//"], blockComments: [BlockCommentRule("/*", "*/", nests: true)],
        strings: [.escaped("\"", spansLines: true)])

    static let go = CodeLanguage(
        name: "go", features: [.marksFunctionCalls, .identifiersAndOperators],
        keywords: """
            break case chan const continue default defer else fallthrough for func go goto if import interface map package range return \
            select struct switch type var
            """,
        typeNames: """
            bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 \
            uintptr any comparable
            """,
        constants: "true false nil iota",
        builtinFunctions: "append cap clear close complex copy delete imag len make max min new panic print println real recover",
        functionDeclarationKeywords: "func", typeDeclarationKeywords: "type", lineComments: ["//"], blockComments: cStyleComments,
        strings: [.escaped("\""), .escaped("'"), StringRule(opening: "`", closing: "`", spansLines: true)])

    static let shell = CodeLanguage(
        name: "shell", features: [.dollarVariables, .hashCommentsAfterSpace],
        keywords: """
            if then else elif fi case esac for select while until do done in function time coproc return break continue exit local \
            declare readonly export typeset unset shift source alias eval exec set trap wait let
            """,
        constants: "true false",
        builtinFunctions: """
            echo printf read cd pwd pushd popd test kill jobs bg fg getopts mapfile readarray umask ulimit type hash command builtin \
            enable logout dirs disown history sudo
            """,
        functionDeclarationKeywords: "function", lineComments: ["#"],
        strings: [.escaped("\"", spansLines: true), StringRule(opening: "'", closing: "'", spansLines: true)])

    static let json = CodeLanguage(
        name: "json", features: [.keysBeforeColon], constants: "true false null",
        lineComments: ["//"], blockComments: cStyleComments, strings: [.escaped("\""), .escaped("'")])

    static let yaml = CodeLanguage(
        name: "yaml", features: [.yamlKeys, .yamlValues, .hashCommentsAfterSpace, .keysBeforeColon],
        constants: "true false null yes no on off True False TRUE FALSE Null NULL Yes No ~", lineComments: ["#"],
        strings: [.escaped("\""), StringRule(opening: "'", closing: "'", doubledClosingEscapes: true)])

    static let sql = CodeLanguage(
        name: "sql", features: [.marksFunctionCalls, .identifiersAndOperators], ignoresCase: true,
        keywords: """
            select from where insert into values update set delete create table drop alter add column index view primary key foreign \
            references not unique default check constraint join inner left right outer full cross on as and or in is like ilike between \
            exists distinct order by group having limit offset union all case when then else end begin commit rollback transaction \
            grant revoke with recursive returning if replace truncate database schema use desc asc procedure function trigger declare \
            cast natural using over partition window lateral fetch first next rows only top any some intersect except returns language \
            auto_increment autoincrement collate escape materialized temporary temp vacuum explain analyze
            """,
        typeNames: """
            int integer smallint bigint tinyint decimal numeric float real double precision varchar char character text date time \
            timestamp timestamptz interval boolean bool blob clob json jsonb uuid serial bigserial bytea money nvarchar datetime
            """,
        constants: "null true false", lineComments: ["--"], blockComments: cStyleComments,
        strings: [StringRule(opening: "'", closing: "'", doubledClosingEscapes: true, spansLines: true),
                  StringRule(opening: "\"", closing: "\"", doubledClosingEscapes: true, kind: .property),
                  StringRule(opening: "`", closing: "`", kind: .property)])

    static let vhdl = CodeLanguage(
        name: "vhdl", features: [.vhdlNumbers, .characterLiteralsOnly, .identifiersAndOperators], ignoresCase: true,
        keywords: """
            abs access after alias all and architecture array assert attribute begin block body buffer bus case component configuration \
            constant context disconnect downto else elsif end entity exit file for force function generate generic group guarded if impure \
            in inertial inout is label library linkage literal loop map mod nand new next nor not null of on open or others out package \
            parameter port postponed procedure process protected pure range record register reject release rem report return rol ror \
            select severity signal shared sla sll sra srl subtype then to transport type unaffected units until use variable wait when \
            while with xnor xor default
            """,
        typeNames: """
            std_logic std_logic_vector std_ulogic std_ulogic_vector signed unsigned integer natural positive boolean bit bit_vector real \
            time string character line text severity_level unresolved_signed unresolved_unsigned u_signed u_unsigned sfixed ufixed \
            float32 float64 integer_vector boolean_vector real_vector time_vector
            """,
        constants: "true false note warning error failure ieee std work",
        builtinFunctions: """
            rising_edge falling_edge to_unsigned to_signed to_integer to_stdlogicvector to_stdulogicvector to_bit to_bitvector \
            to_slv resize shift_left shift_right rotate_left rotate_right std_match conv_integer conv_std_logic_vector conv_unsigned \
            conv_signed now readline writeline read write hread hwrite oread owrite to_string to_hstring to_ostring minimum maximum \
            finish stop
            """,
        functionDeclarationKeywords: "function procedure", typeDeclarationKeywords: "entity architecture package component configuration type subtype",
        lineComments: ["--"], blockComments: cStyleComments,
        strings: [StringRule(opening: "\"", closing: "\"", doubledClosingEscapes: true)])

    static let verilog = CodeLanguage(
        name: "verilog", features: [.dollarFunctions, .backtickDirectives, .verilogNumbers, .uppercaseIdentifiersAreConstants, .identifiersAndOperators],
        keywords: """
            always always_comb always_ff always_latch and assign automatic begin buf bufif0 bufif1 case casex casez cell cmos config \
            deassign default defparam design disable edge else end endcase endconfig endfunction endgenerate endmodule endprimitive \
            endspecify endtable endtask event for force forever fork function generate genvar highz0 highz1 if ifnone incdir include \
            initial inout input instance join large liblist library localparam macromodule medium module nand negedge nmos nor \
            noshowcancelled not notif0 notif1 or output parameter pmos posedge primitive pull0 pull1 pulldown pullup pulsestyle_ondetect \
            pulsestyle_onevent rcmos release repeat rnmos rpmos rtran rtranif0 rtranif1 scalared showcancelled signed small specify \
            specparam strong0 strong1 supply0 supply1 table task tran tranif0 tranif1 triand trior trireg unsigned use vectored wait \
            weak0 weak1 while xnor xor alias assert assume before bind bins binsof break class clocking const constraint context \
            continue cover covergroup coverpoint cross dist do endclass endclocking endgroup endinterface endpackage endprogram \
            endproperty endsequence enum expect export extends extern final first_match foreach forkjoin iff ignore_bins illegal_bins \
            import inside interface intersect join_any join_none local modport new null package packed priority program property \
            protected pure rand randc randcase randsequence ref return sequence solve static struct super tagged this throughout \
            timeprecision timeunit type typedef union unique unique0 var virtual void wait_order wildcard with within
            """,
        typeNames: "wire reg logic bit byte int integer shortint longint real realtime time string shortreal tri tri0 tri1 wand wor chandle",
        functionDeclarationKeywords: "function task", typeDeclarationKeywords: "module interface class package program macromodule primitive",
        lineComments: ["//"], blockComments: cStyleComments, strings: [.escaped("\"")])

    static let assembly = CodeLanguage(
        name: "assembly", features: [.assemblyLines], ignoresCase: true, variableNames: assemblyRegisters,
        lineComments: [";", "#", "//"], blockComments: cStyleComments, strings: doubleAndSingleQuotes)

    /// Registers of x86-64, ARM, AArch64 and RISC-V, lowercased.
    private static let assemblyRegisters: Set<String> = {
        var registers: Set<String> = [
            "rax", "rbx", "rcx", "rdx", "rsi", "rdi", "rbp", "rsp", "rip", "eax", "ebx", "ecx", "edx", "esi", "edi", "ebp", "esp", "eip",
            "ax", "bx", "cx", "dx", "si", "di", "bp", "sp", "ip", "al", "bl", "cl", "dl", "ah", "bh", "ch", "dh", "sil", "dil", "bpl", "spl",
            "cs", "ds", "es", "fs", "gs", "ss", "lr", "pc", "fp", "xzr", "wzr", "zero", "ra", "gp", "tp", "cpsr", "apsr", "eflags", "rflags",
        ]
        for number in 0...31 {
            registers.formUnion(["x\(number)", "w\(number)", "v\(number)", "q\(number)", "d\(number)", "s\(number)", "f\(number)",
                                 "xmm\(number)", "ymm\(number)", "zmm\(number)"])
        }
        for number in 0...15 { registers.insert("r\(number)") }
        for number in 8...15 { registers.formUnion(["r\(number)d", "r\(number)w", "r\(number)b"]) }
        for number in 0...7 { registers.formUnion(["a\(number)", "cr\(number)", "dr\(number)", "st\(number)"]) }
        for number in 0...6 { registers.insert("t\(number)") }
        return registers
    }()

    static let matlab = CodeLanguage(
        name: "matlab", features: [.transposeQuote, .identifiersAndOperators],
        keywords: """
            break case catch classdef continue else elseif end for function global if otherwise parfor persistent return spmd switch try \
            while properties methods events enumeration arguments
            """,
        constants: "true false pi Inf inf NaN nan eps",
        builtinFunctions: """
            disp fprintf sprintf zeros ones eye rand randn size length numel plot figure hold xlabel ylabel title legend grid subplot \
            linspace sum mean max min abs sqrt exp log sin cos tan floor ceil round mod rem find any all isempty error warning num2str \
            str2num strcat cell struct fieldnames isfield fft ifft conv filter
            """,
        functionDeclarationKeywords: "function", typeDeclarationKeywords: "classdef", lineComments: ["%"],
        blockComments: [BlockCommentRule("%{", "%}", opensOnlyAloneOnLine: true)],
        strings: [StringRule(opening: "\"", closing: "\"", doubledClosingEscapes: true), StringRule(opening: "'", closing: "'", doubledClosingEscapes: true)])

    static let latex = CodeLanguage(
        name: "latex", features: [.backslashCommands], lineComments: ["%"],
        strings: [StringRule(opening: "$$", closing: "$$", spansLines: true), StringRule(opening: "$", closing: "$")])

    static let markdown = CodeLanguage(name: "markdown", syntax: .markdown)

    static let markup = CodeLanguage(name: "markup", syntax: .markup, blockComments: [BlockCommentRule("<!--", "-->")])

    static let css = CodeLanguage(
        name: "css", features: [.cssRules, .atAttributes, .marksFunctionCalls],
        keywords: "important and not only", constants: "inherit initial unset revert none auto transparent currentColor",
        lineComments: ["//"], blockComments: cStyleComments, strings: doubleAndSingleQuotes, identifierExtraCharacters: "-")

    static let ruby = CodeLanguage(
        name: "ruby",
        features: [.capitalizedIdentifiersAreTypes, .capitalizedCallsMakeTypes, .atVariables, .dollarVariables, .uppercaseIdentifiersAreConstants,
                   .identifiersAndOperators],
        keywords: """
            alias and begin break case class def defined do else elsif end ensure for if in module next not or redo rescue retry return \
            super then undef unless until when while yield require require_relative include extend attr_accessor attr_reader \
            attr_writer private protected public lambda proc raise
            """,
        constants: "true false nil self", builtinFunctions: "puts print p pp gets format sprintf loop",
        functionDeclarationKeywords: "def", typeDeclarationKeywords: "class module", lineComments: ["#"],
        blockComments: [BlockCommentRule("=begin", "=end", opensOnlyAloneOnLine: true)],
        strings: [.escaped("\"", spansLines: true), .escaped("'", spansLines: true)])

    static let lua = CodeLanguage(
        name: "lua", features: [.marksFunctionCalls, .identifiersAndOperators],
        keywords: "and break do else elseif end for function goto if in local not or repeat return then until while",
        constants: "true false nil", builtinFunctions: "print pairs ipairs require type tostring tonumber setmetatable getmetatable error assert pcall select",
        functionDeclarationKeywords: "function", lineComments: ["--"],
        blockComments: [BlockCommentRule("--[[", "]]")],
        strings: [.escaped("\""), .escaped("'"), StringRule(opening: "[[", closing: "]]", spansLines: true)])
}
