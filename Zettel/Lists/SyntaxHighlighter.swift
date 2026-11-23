import Foundation

/// A small, dependency-free highlighter for `code` notes: keywords, strings,
/// numbers and comments for common languages. Good enough for scratch code.
enum SyntaxHighlighter {
    enum Token: Equatable, Sendable {
        case keyword, string, number, comment
    }

    struct Language: Equatable, Sendable {
        var name: String
        var keywords: Set<String>
        var lineComment: String?
        var blockComment: (open: String, close: String)?

        static func == (lhs: Language, rhs: Language) -> Bool { lhs.name == rhs.name }

        /// Prefix used by ⌘/ in code notes.
        var commentPrefix: String { lineComment ?? "//" }
    }

    /// State carried from one line to the next (inside a block comment).
    struct State: Equatable, Sendable {
        var inBlockComment = false
    }

    /// `code: py`, `code: swift` … → language; unknown names get a generic one.
    static func language(named name: String?) -> Language {
        let key = (name ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        for language in languages where language.aliases.contains(key) {
            return language.language
        }
        return generic
    }

    static func tokens(in line: String, language: Language, state: inout State) -> [(NSRange, Token)] {
        let characters = Array(line.utf16)
        let text = line as NSString
        var result: [(NSRange, Token)] = []
        var index = 0

        func starts(with marker: String, at position: Int) -> Bool {
            let length = (marker as NSString).length
            return position + length <= characters.count
                && text.substring(with: NSRange(location: position, length: length)) == marker
        }

        while index < characters.count {
            if state.inBlockComment, let block = language.blockComment {
                let rest = NSRange(location: index, length: characters.count - index)
                let end = text.range(of: block.close, range: rest)
                let stop = end.location == NSNotFound ? characters.count : NSMaxRange(end)
                result.append((NSRange(location: index, length: stop - index), .comment))
                state.inBlockComment = end.location == NSNotFound
                index = stop
                continue
            }
            if let block = language.blockComment, starts(with: block.open, at: index) {
                state.inBlockComment = true
                continue
            }
            if let lineComment = language.lineComment, starts(with: lineComment, at: index) {
                result.append((NSRange(location: index, length: characters.count - index), .comment))
                break
            }

            let character = characters[index]
            // Strings: "…", '…' and `…` on one line, with backslash escapes.
            if character == 0x22 || character == 0x27 || character == 0x60 {
                var end = index + 1
                while end < characters.count, characters[end] != character {
                    end += characters[end] == 0x5C ? 2 : 1
                }
                end = min(end + 1, characters.count)
                result.append((NSRange(location: index, length: end - index), .string))
                index = end
                continue
            }
            // Identifiers and keywords.
            if isIdentifierStart(character) {
                var end = index + 1
                while end < characters.count, isIdentifierPart(characters[end]) { end += 1 }
                let word = text.substring(with: NSRange(location: index, length: end - index))
                if language.keywords.contains(word) {
                    result.append((NSRange(location: index, length: end - index), .keyword))
                }
                index = end
                continue
            }
            // Numbers: 42, 3.14, 0xFF, 1_000.
            if character >= 0x30, character <= 0x39 {
                var end = index + 1
                while end < characters.count, isIdentifierPart(characters[end]) || characters[end] == 0x2E { end += 1 }
                result.append((NSRange(location: index, length: end - index), .number))
                index = end
                continue
            }
            index += 1
        }
        return result
    }

    private static func isIdentifierStart(_ c: UInt16) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c == 0x24 || c == 0x40
    }

    private static func isIdentifierPart(_ c: UInt16) -> Bool {
        isIdentifierStart(c) || (c >= 0x30 && c <= 0x39)
    }

    // MARK: Languages

    private static let generic = Language(
        name: "text",
        keywords: ["if", "else", "for", "while", "return", "function", "def", "class", "import", "true", "false", "null", "nil", "None"],
        lineComment: "//",
        blockComment: ("/*", "*/")
    )

    private static let cLike: Set<String> = [
        "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return",
        "class", "struct", "enum", "interface", "public", "private", "protected", "static", "final",
        "const", "void", "int", "float", "double", "char", "bool", "boolean", "long", "new", "this",
        "true", "false", "null", "try", "catch", "throw", "throws", "import", "package", "extends",
        "implements", "fn", "let", "mut", "impl", "pub", "use", "func", "go", "defer", "var", "type",
    ]

    private static let languages: [(aliases: Set<String>, language: Language)] = [
        (["py", "python"], Language(
            name: "python",
            keywords: ["def", "class", "if", "elif", "else", "for", "while", "return", "import", "from", "as",
                       "with", "try", "except", "finally", "raise", "lambda", "yield", "in", "is", "not",
                       "and", "or", "pass", "break", "continue", "None", "True", "False", "global", "async", "await"],
            lineComment: "#", blockComment: nil
        )),
        (["js", "javascript", "ts", "typescript", "jsx", "tsx"], Language(
            name: "javascript",
            keywords: ["function", "const", "let", "var", "if", "else", "for", "while", "return", "class",
                       "import", "export", "from", "default", "new", "this", "true", "false", "null",
                       "undefined", "async", "await", "try", "catch", "throw", "typeof", "interface", "type", "of", "in"],
            lineComment: "//", blockComment: ("/*", "*/")
        )),
        (["swift"], Language(
            name: "swift",
            keywords: ["func", "let", "var", "if", "else", "guard", "for", "while", "return", "class", "struct",
                       "enum", "protocol", "extension", "import", "self", "Self", "true", "false", "nil",
                       "switch", "case", "default", "try", "throw", "throws", "async", "await", "in", "private",
                       "public", "static", "init", "some", "any", "where"],
            lineComment: "//", blockComment: ("/*", "*/")
        )),
        (["sh", "bash", "zsh", "shell"], Language(
            name: "shell",
            keywords: ["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "case", "esac",
                       "function", "return", "export", "local", "echo"],
            lineComment: "#", blockComment: nil
        )),
        (["rb", "ruby"], Language(
            name: "ruby",
            keywords: ["def", "end", "class", "module", "if", "elsif", "else", "unless", "do", "while", "return",
                       "require", "true", "false", "nil", "self", "yield"],
            lineComment: "#", blockComment: nil
        )),
        (["sql"], Language(
            name: "sql",
            keywords: ["select", "from", "where", "and", "or", "insert", "into", "values", "update", "set",
                       "delete", "create", "table", "join", "left", "on", "group", "by", "order", "limit",
                       "SELECT", "FROM", "WHERE", "AND", "OR", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
                       "DELETE", "CREATE", "TABLE", "JOIN", "LEFT", "ON", "GROUP", "BY", "ORDER", "LIMIT", "NULL"],
            lineComment: "--", blockComment: ("/*", "*/")
        )),
        (["json"], Language(name: "json", keywords: ["true", "false", "null"], lineComment: nil, blockComment: nil)),
        (["c", "cpp", "c++", "java", "kotlin", "kt", "cs", "go", "rust", "rs", "php", "dart"], Language(
            name: "c", keywords: cLike, lineComment: "//", blockComment: ("/*", "*/")
        )),
    ]
}
