// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum CodeLanguage: String, CaseIterable, Sendable {
    case swift = "Swift"
    case typescript = "TypeScript"
    case javascript = "JavaScript"
    case rust = "Rust"
    case python = "Python"
    case c = "C"
    case cpp = "C++"
    case objectiveC = "Objective-C"
    case go = "Go"
    case java = "Java"
    case kotlin = "Kotlin"
    case cSharp = "C#"
    case shell = "Shell"
    case sql = "SQL"
    case solidity = "Solidity"
    case move = "Move"
    case ruby = "Ruby"
    case php = "PHP"
    case dart = "Dart"
    case lua = "Lua"
    case html = "HTML"
    case css = "CSS"
    case json = "JSON"
    case yaml = "YAML"
    case toml = "TOML"
}

public enum CodeLanguageConfidence: String, Sendable {
    case none = "Language unknown"
    case low = "Low confidence"
    case medium = "Medium confidence"
    case high = "High confidence"
}

public struct CodeLanguageDetection: Sendable, Equatable {
    public let isLikelyCode: Bool
    public let primary: CodeLanguage?
    public let alternatives: [CodeLanguage]
    public let confidence: CodeLanguageConfidence
    public let evidenceScore: Int

    public init(
        isLikelyCode: Bool,
        primary: CodeLanguage?,
        alternatives: [CodeLanguage],
        confidence: CodeLanguageConfidence,
        evidenceScore: Int
    ) {
        self.isLikelyCode = isLikelyCode
        self.primary = primary
        self.alternatives = alternatives
        self.confidence = confidence
        self.evidenceScore = evidenceScore
    }

    public var displayName: String {
        guard let primary else { return isLikelyCode ? "Source code" : "" }
        guard confidence == .low, let alternative = alternatives.first else {
            return primary.rawValue
        }
        return "\(primary.rawValue) / \(alternative.rawValue)"
    }
}

public enum CodeLanguageDetector {
    private struct Rule {
        let language: CodeLanguage
        let pattern: String
        let points: Int
    }

    private static let rules: [Rule] = [
        // Swift
        Rule(language: .swift, pattern: #"(?m)^\s*import\s+(Foundation|SwiftUI|AppKit|UIKit|Combine)\b"#, points: 6),
        Rule(language: .swift, pattern: #"(?m)^\s*(actor|protocol|extension)\s+[A-Za-z_]"#, points: 4),
        Rule(language: .swift, pattern: #"(?m)^\s*(func\s+\w+\s*\(|guard\s+(let|var)\b|if\s+(let|var)\b)"#, points: 4),
        Rule(language: .swift, pattern: #"@(MainActor|State|Binding|Published|ObservableObject)\b|\b(some\s+View|throws\s*->|async\s+throws)\b"#, points: 5),
        Rule(language: .swift, pattern: #"\b(let|var)\s+\w+\s*:\s*[A-Z][A-Za-z0-9_<>,.? ]*\s*="#, points: 2),

        // TypeScript and JavaScript
        Rule(language: .typescript, pattern: #"(?m)^\s*(interface|type)\s+[A-Za-z_$][\w$]*(\s*<[^>]+>)?\s*(=|\{)"#, points: 7),
        Rule(language: .typescript, pattern: #"\b(import|export)\s+type\b|\bimplements\s+\w+|\bas\s+const\b"#, points: 6),
        Rule(language: .typescript, pattern: #"\b(const|let|var)\s+\w+\s*:\s*(string|number|boolean|unknown|never|any|Record<|Array<)"#, points: 5),
        Rule(language: .typescript, pattern: #"\([^)]*\w+\s*:\s*[A-Za-z_$][\w$<>, |\[\]?]*\)\s*(=>|:)"#, points: 4),
        Rule(language: .javascript, pattern: #"\b(console\.(log|error|warn)|document\.(querySelector|getElementById)|require\s*\()"#, points: 6),
        Rule(language: .javascript, pattern: #"(?m)^\s*(const|let|var)\s+[A-Za-z_$][\w$]*\s*=.*(=>|require\s*\(|Promise\b)"#, points: 4),
        Rule(language: .javascript, pattern: #"\b(async\s+function|function\s+[A-Za-z_$][\w$]*\s*\(|module\.exports|exports\.)"#, points: 5),

        // Rust
        Rule(language: .rust, pattern: #"(?m)^\s*(pub\s+)?(async\s+)?fn\s+\w+\s*(<[^>]+>)?\s*\("#, points: 7),
        Rule(language: .rust, pattern: #"(?m)^\s*(use\s+(std|crate|super)::|impl(<[^>]+>)?\s+|trait\s+\w+)"#, points: 6),
        Rule(language: .rust, pattern: #"\b(let\s+mut|Option<|Result<|Box<|Vec<|&mut\s+|match\s+[^{}\n]+\s*\{)"#, points: 4),
        Rule(language: .rust, pattern: #"\b(println|format|vec|panic|assert)!\s*\("#, points: 5),
        Rule(language: .rust, pattern: #"->\s*(Self|Result<|Option<|impl\s+\w+)"#, points: 3),

        // Python
        Rule(language: .python, pattern: #"(?m)^\s*(async\s+)?def\s+\w+\s*\([^)]*\)\s*(->\s*[^:]+)?\s*:"#, points: 7),
        Rule(language: .python, pattern: #"(?m)^\s*(from\s+[\w.]+\s+import|import\s+[\w.]+(\s+as\s+\w+)?)\s*$"#, points: 5),
        Rule(language: .python, pattern: #"\b(None|True|False|self|__name__|__init__)\b"#, points: 4),
        Rule(language: .python, pattern: #"(?m)^\s*(for|if|elif|while|with|class)\b[^\n]*:\s*$"#, points: 3),
        Rule(language: .python, pattern: #"\b(print|len|range|enumerate|zip)\s*\("#, points: 2),

        // C family
        Rule(language: .c, pattern: #"(?m)^\s*#include\s*<(stdio|stdlib|string|stdint|stdbool)\.h>"#, points: 7),
        Rule(language: .c, pattern: #"\b(printf|scanf|malloc|calloc|realloc|free)\s*\("#, points: 5),
        Rule(language: .c, pattern: #"\btypedef\s+struct\b|\bint\s+main\s*\(\s*(void|int\s+\w+\s*,)"#, points: 5),
        Rule(language: .cpp, pattern: #"(?m)^\s*#include\s*<(iostream|vector|string|memory|algorithm|map)>"#, points: 7),
        Rule(language: .cpp, pattern: #"\b(std::|cout\s*<<|cin\s*>>|nullptr|unique_ptr<|shared_ptr<)"#, points: 6),
        Rule(language: .cpp, pattern: #"\b(template\s*<|namespace\s+\w+|class\s+\w+\s*:\s*public)"#, points: 5),
        Rule(language: .objectiveC, pattern: #"(?m)^\s*#import\s+[<\"](Foundation|UIKit|AppKit)/"#, points: 8),
        Rule(language: .objectiveC, pattern: #"@(interface|implementation|property|autoreleasepool|selector)\b"#, points: 7),
        Rule(language: .objectiveC, pattern: #"\[[A-Za-z_]\w*\s+[A-Za-z_]\w*(:[^\]]*)?\]"#, points: 3),

        // Go
        Rule(language: .go, pattern: #"(?m)^\s*package\s+\w+\s*$"#, points: 7),
        Rule(language: .go, pattern: #"(?m)^\s*func\s+(\([^)]*\)\s*)?\w+\s*\([^)]*\)"#, points: 6),
        Rule(language: .go, pattern: #"\b(fmt\.(Print|Printf|Println)|go\s+\w+\s*\(|defer\s+\w+\s*\(|chan\s+\w+)"#, points: 5),
        Rule(language: .go, pattern: #"\w+\s*:=\s*[^=]"#, points: 4),

        // Java, Kotlin, and C#
        Rule(language: .java, pattern: #"(?m)^\s*(package\s+[\w.]+;|import\s+java\.[\w.*]+;)"#, points: 6),
        Rule(language: .java, pattern: #"\bpublic\s+static\s+void\s+main\s*\(|System\.(out|err)\.print"#, points: 8),
        Rule(language: .java, pattern: #"\b(public|private|protected)\s+(class|interface|enum)\s+\w+"#, points: 4),
        Rule(language: .kotlin, pattern: #"(?m)^\s*(fun\s+\w+\s*\(|data\s+class\s+|object\s+\w+|sealed\s+class\s+)"#, points: 7),
        Rule(language: .kotlin, pattern: #"\b(val|var)\s+\w+\s*:\s*[A-Z]\w*\??|\bcompanion\s+object\b"#, points: 5),
        Rule(language: .kotlin, pattern: #"\b(println|mutableListOf|listOf|when)\s*(\(|\{)"#, points: 3),
        Rule(language: .cSharp, pattern: #"(?m)^\s*using\s+(System|Microsoft)\b[^;]*;"#, points: 7),
        Rule(language: .cSharp, pattern: #"\b(Console\.Write(Line)?|async\s+Task|IEnumerable<|namespace\s+[\w.]+)"#, points: 6),
        Rule(language: .cSharp, pattern: #"\b(public|private|protected|internal)\s+(sealed\s+)?(class|record|interface|struct)\s+\w+"#, points: 4),

        // Shell and SQL
        Rule(language: .shell, pattern: #"(?m)^#!\s*/(usr/bin/env\s+)?(ba|z|fi)?sh\b"#, points: 10),
        Rule(language: .shell, pattern: #"(?m)^\s*(export\s+\w+=|if\s+\[\[?|for\s+\w+\s+in\b|function\s+\w+|case\s+.+\s+in)"#, points: 5),
        Rule(language: .shell, pattern: #"\$\([^)]+\)|\$\{[A-Za-z_]\w*([}:][^}]*)?\}|(?m)^\s*(curl|wget|sudo|chmod|grep|sed|awk)\b"#, points: 4),
        Rule(language: .shell, pattern: #"(?m)^\s*(fi|done|esac)\s*$"#, points: 4),
        Rule(language: .sql, pattern: #"(?im)^\s*(SELECT\s+.+\s+FROM|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM|CREATE\s+(TABLE|VIEW|INDEX))\b"#, points: 8),
        Rule(language: .sql, pattern: #"(?i)\b(INNER|LEFT|RIGHT|FULL)\s+JOIN\b|\bGROUP\s+BY\b|\bORDER\s+BY\b"#, points: 5),
        Rule(language: .sql, pattern: #"(?i)\bPRIMARY\s+KEY\b|\bFOREIGN\s+KEY\b|\bVARCHAR\s*\("#, points: 4),

        // Smart-contract languages
        Rule(language: .solidity, pattern: #"(?m)^\s*pragma\s+solidity\s+[\^<>=0-9.]+\s*;"#, points: 10),
        Rule(language: .solidity, pattern: #"\b(contract|library)\s+\w+|\bmapping\s*\([^)]*=>[^)]*\)"#, points: 6),
        Rule(language: .solidity, pattern: #"\b(msg\.(sender|value)|address\s+payable|uint(8|16|32|64|128|256)?|modifier\s+\w+)"#, points: 5),
        Rule(language: .move, pattern: #"(?m)^\s*module\s+(0x[0-9a-fA-F]+|[A-Za-z_]\w*)::[A-Za-z_]\w*\s*\{"#, points: 10),
        Rule(language: .move, pattern: #"\b(public\s+entry\s+fun|public\s+fun|fun\s+\w+\s*\([^)]*:\s*&?(mut\s+)?signer)"#, points: 7),
        Rule(language: .move, pattern: #"\b(has\s+(key|store|copy|drop)|acquires\s+\w+|move_(to|from)|borrow_global(_mut)?|vector<)"#, points: 6),
        Rule(language: .move, pattern: #"\buse\s+(0x[0-9a-fA-F]+|[A-Za-z_]\w*)::[A-Za-z_]\w*"#, points: 4),

        // Additional common languages
        Rule(language: .ruby, pattern: #"(?m)^\s*(def\s+\w+[!?=]?|class\s+\w+(\s*<\s*\w+)?|module\s+\w+)\s*$"#, points: 6),
        Rule(language: .ruby, pattern: #"\b(puts|attr_(reader|writer|accessor)|require_relative)\b|\.each\s+do\s*\|"#, points: 5),
        Rule(language: .php, pattern: #"<\?php\b"#, points: 10),
        Rule(language: .php, pattern: #"\$[A-Za-z_]\w*\s*=|->\w+\s*\(|\becho\s+"#, points: 4),
        Rule(language: .dart, pattern: #"(?m)^\s*import\s+['\"]package:[^'\"]+['\"]\s*;"#, points: 8),
        Rule(language: .dart, pattern: #"\b(Future<|Widget\s+build\s*\(|StatelessWidget|StatefulWidget|void\s+main\s*\(\)\s*=>)"#, points: 6),
        Rule(language: .lua, pattern: #"(?m)^\s*(local\s+function\s+\w+|function\s+[\w.:]+\s*\(|local\s+\w+\s*=)"#, points: 6),
        Rule(language: .lua, pattern: #"(?m)^\s*(end|then|elseif)\s*$|\bipairs\s*\(|\bpairs\s*\("#, points: 3),

        // Web and structured data
        Rule(language: .html, pattern: #"(?is)<!DOCTYPE\s+html\b|<html\b|<(div|span|main|section|script|body)\b[^>]*>"#, points: 8),
        Rule(language: .html, pattern: #"(?s)</[A-Za-z][A-Za-z0-9-]*>"#, points: 3),
        Rule(language: .css, pattern: #"(?m)^\s*(@media|@supports|:root|[.#][A-Za-z_-][\w-]*)[^\n{]*\{"#, points: 6),
        Rule(language: .css, pattern: #"(?m)^\s*(display|position|color|background|margin|padding|font-[\w-]+)\s*:\s*[^;]+;"#, points: 4),
        Rule(language: .yaml, pattern: #"(?m)^---\s*$|^\s*[A-Za-z_][\w.-]*:\s*[^{};]+$"#, points: 2),
        Rule(language: .yaml, pattern: #"(?m)^\s*-\s+[A-Za-z_][\w.-]*:\s+|^\s*[A-Za-z_][\w.-]*:\s*$"#, points: 3),
        Rule(language: .toml, pattern: #"(?m)^\s*\[\[?[A-Za-z_][\w.-]*\]?\]\s*$"#, points: 5),
        Rule(language: .toml, pattern: #"(?m)^\s*[A-Za-z_][\w.-]*\s*=\s*(\"[^\"]*\"|'[^']*'|\d+|true|false|\[)"#, points: 2)
    ]

    private static let fenceAliases: [String: CodeLanguage] = [
        "swift": .swift, "ts": .typescript, "typescript": .typescript,
        "tsx": .typescript, "js": .javascript, "javascript": .javascript,
        "jsx": .javascript, "rust": .rust, "rs": .rust,
        "python": .python, "py": .python, "c": .c, "h": .c,
        "cpp": .cpp, "c++": .cpp, "cc": .cpp, "hpp": .cpp,
        "objective-c": .objectiveC, "objc": .objectiveC, "m": .objectiveC,
        "go": .go, "java": .java, "kotlin": .kotlin, "kt": .kotlin,
        "csharp": .cSharp, "cs": .cSharp, "c#": .cSharp,
        "sh": .shell, "bash": .shell, "zsh": .shell, "shell": .shell,
        "sql": .sql, "solidity": .solidity, "sol": .solidity,
        "move": .move, "ruby": .ruby, "rb": .ruby, "php": .php,
        "dart": .dart, "lua": .lua, "html": .html, "css": .css,
        "json": .json, "yaml": .yaml, "yml": .yaml, "toml": .toml
    ]

    public static func language(forFileExtension fileExtension: String) -> CodeLanguage? {
        switch fileExtension.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
        case "swift": .swift
        case "ts", "tsx": .typescript
        case "js", "jsx", "mjs", "cjs": .javascript
        case "rs": .rust
        case "py": .python
        case "c", "h": .c
        case "cc", "cpp", "cxx", "hpp": .cpp
        case "m", "mm": .objectiveC
        case "go": .go
        case "java": .java
        case "kt", "kts": .kotlin
        case "cs": .cSharp
        case "sh", "bash", "zsh": .shell
        case "sql": .sql
        case "sol": .solidity
        case "move": .move
        case "rb": .ruby
        case "php": .php
        case "dart": .dart
        case "lua": .lua
        case "html", "htm": .html
        case "css": .css
        case "json": .json
        case "yaml", "yml": .yaml
        case "toml": .toml
        default: nil
        }
    }

    public static func detect(_ text: String) -> CodeLanguageDetection {
        let sample = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else {
            return CodeLanguageDetection(
                isLikelyCode: false,
                primary: nil,
                alternatives: [],
                confidence: .none,
                evidenceScore: 0
            )
        }

        var scores: [CodeLanguage: Int] = [:]
        if let fencedLanguage = fencedLanguage(in: sample) {
            scores[fencedLanguage, default: 0] += 14
        }

        for rule in rules where matches(sample, pattern: rule.pattern) {
            scores[rule.language, default: 0] += rule.points
        }

        if isJSON(sample) {
            scores[.json, default: 0] += 12
        }
        let yamlKeys = matchCount(sample, pattern: #"(?m)^\s*[A-Za-z_][\w.-]*:\s*([^{};]|$)"#)
        if yamlKeys >= 2 {
            scores[.yaml, default: 0] += min(7, yamlKeys + 2)
        }
        let tomlAssignments = matchCount(sample, pattern: #"(?m)^\s*[A-Za-z_][\w.-]*\s*=\s*[^=]+$"#)
        if tomlAssignments >= 2, matches(sample, pattern: #"(?m)^\s*\[\[?[A-Za-z_]"#) {
            scores[.toml, default: 0] += min(7, tomlAssignments + 2)
        }

        let genericScore = genericCodeScore(sample)
        let ranked = scores
            .filter { $0.value > 0 }
            .sorted {
                $0.value == $1.value
                    ? $0.key.rawValue < $1.key.rawValue
                    : $0.value > $1.value
            }
        let topScore = ranked.first?.value ?? 0
        let secondScore = ranked.dropFirst().first?.value ?? 0
        let isLikelyCode = topScore >= 4 || genericScore >= 3 || fencedLanguage(in: sample) != nil

        guard isLikelyCode else {
            return CodeLanguageDetection(
                isLikelyCode: false,
                primary: nil,
                alternatives: [],
                confidence: .none,
                evidenceScore: max(topScore, genericScore)
            )
        }

        guard let top = ranked.first, topScore >= 4 else {
            return CodeLanguageDetection(
                isLikelyCode: true,
                primary: nil,
                alternatives: [],
                confidence: .none,
                evidenceScore: genericScore
            )
        }

        let lead = topScore - secondScore
        let confidence: CodeLanguageConfidence
        if topScore >= 10, lead >= 3 {
            confidence = .high
        } else if topScore >= 6, lead >= 2 {
            confidence = .medium
        } else {
            confidence = .low
        }
        let alternatives = ranked.dropFirst().prefix(2).compactMap { candidate in
            candidate.value >= max(4, topScore - 2) ? candidate.key : nil
        }

        return CodeLanguageDetection(
            isLikelyCode: true,
            primary: top.key,
            alternatives: alternatives,
            confidence: confidence,
            evidenceScore: topScore
        )
    }

    private static func genericCodeScore(_ text: String) -> Int {
        var score = 0
        if text.contains("```") { score += 4 }
        if text.hasPrefix("#!") { score += 4 }
        if matches(text, pattern: #"(?m)^\s*(import|from|class|struct|enum|protocol|func|fn|def|function|const|let|var|return|if|for|while|switch|module|contract|SELECT|INSERT|UPDATE|DELETE|CREATE)\b"#) {
            score += 2
        }
        if matches(text, pattern: #"(?m)^\s*(curl|wget|sudo|git|npm|pnpm|yarn|pip|python|swift|cargo|docker|kubectl)\b"#) {
            score += 2
        }
        if matches(text, pattern: #"(?m)^\s*[A-Za-z_$][A-Za-z0-9_$.]*\s*\([^\n]*\)\s*;?\s*$"#) {
            score += 2
        }
        if matches(text, pattern: #"(?m)^\s*[A-Za-z_$][A-Za-z0-9_$]*\s*=|=>|::|\$\("#) {
            score += 2
        }
        if text.contains("{") && text.contains("}") { score += 1 }
        if text.contains(";") { score += 1 }
        if matches(text, pattern: #"(?m)^\s*(//|/\*|# |-- )"#) { score += 1 }
        return score
    }

    private static func fencedLanguage(in text: String) -> CodeLanguage? {
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)```[ \t]*([A-Za-z+#-]+)"#
        ),
        let match = expression.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ),
        match.numberOfRanges > 1,
        let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return fenceAliases[String(text[range]).lowercased()]
    }

    private static func isJSON(_ text: String) -> Bool {
        guard text.hasPrefix("{") || text.hasPrefix("[") else { return false }
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func matches(_ text: String, pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func matchCount(_ text: String, pattern: String) -> Int {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return expression.numberOfMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
    }
}
