// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum CodeGuardFindingKind: String, Sendable, CaseIterable {
    case bidirectionalControl = "Bidirectional control in code"
    case invisibleCharacter = "Invisible character in code"
    case nonASCIIWhitespace = "Non-ASCII whitespace in code"
    case typographicPunctuation = "Typographic punctuation in code"
    case mixedScriptIdentifier = "Mixed-script identifier"
    case confusableIdentifier = "Confusable identifier character"
    case unsupportedUnicode = "Unsupported Unicode in code"

    public var riskLevel: HiddenElementRiskLevel {
        switch self {
        case .bidirectionalControl, .invisibleCharacter, .confusableIdentifier:
            .high
        case .nonASCIIWhitespace, .typographicPunctuation, .unsupportedUnicode:
            .medium
        case .mixedScriptIdentifier:
            .suspicious
        }
    }

    public var detail: String {
        switch self {
        case .bidirectionalControl:
            "This control can make source code display in a different order than it is interpreted."
        case .invisibleCharacter:
            "This invisible character can change an identifier or token without being visible."
        case .nonASCIIWhitespace:
            "This whitespace can be rejected or interpreted differently by tools and compilers."
        case .typographicPunctuation:
            "Rich-text punctuation can look correct while breaking source code or shell commands."
        case .mixedScriptIdentifier:
            "This identifier mixes writing systems. That can be legitimate, but it deserves review."
        case .confusableIdentifier:
            "This identifier contains a non-Latin character that resembles a common Latin letter."
        case .unsupportedUnicode:
            "This private-use or unassigned character may behave differently across tools."
        }
    }
}

public struct CodeGuardFinding: Identifiable, Sendable, Equatable {
    public let id: Int
    public let scalarPosition: Int
    public let line: Int
    public let column: Int
    public let codePoint: String
    public let kind: CodeGuardFindingKind
    public let displayName: String
    public var evidenceConfidence: EvidenceConfidence { .exact }

    public init(
        id: Int,
        scalarPosition: Int,
        line: Int,
        column: Int,
        codePoint: String,
        kind: CodeGuardFindingKind,
        displayName: String
    ) {
        self.id = id
        self.scalarPosition = scalarPosition
        self.line = line
        self.column = column
        self.codePoint = codePoint
        self.kind = kind
        self.displayName = displayName
    }

    /// The copied source and identifier are deliberately excluded.
    public var researchQuery: String {
        "Unicode \(codePoint) \(displayName) \(kind.rawValue) source code security"
    }

    public var researchURL: URL? {
        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [URLQueryItem(name: "q", value: researchQuery)]
        return components?.url
    }
}

public struct CodeGuardAnalysis: Sendable, Equatable {
    public let languageDetection: CodeLanguageDetection
    public let findings: [CodeGuardFinding]

    public init(
        languageDetection: CodeLanguageDetection,
        findings: [CodeGuardFinding]
    ) {
        self.languageDetection = languageDetection
        self.findings = findings
    }

    public var isLikelyCode: Bool { languageDetection.isLikelyCode }
    public var detectedLanguage: String { languageDetection.displayName }
    public var languageConfidence: CodeLanguageConfidence { languageDetection.confidence }
    public var hasRisks: Bool { isLikelyCode && !findings.isEmpty }
    public var highestRiskLevel: HiddenElementRiskLevel? {
        findings.map(\.kind.riskLevel).max { $0.rawValue < $1.rawValue }
    }

    public var sanitizableFindingCount: Int {
        findings.filter { finding in
            switch finding.kind {
            case .bidirectionalControl, .invisibleCharacter,
                    .nonASCIIWhitespace, .typographicPunctuation:
                true
            case .mixedScriptIdentifier, .confusableIdentifier, .unsupportedUnicode:
                false
            }
        }.count
    }
}

public struct CodeSanitizationResult: Sendable, Equatable {
    public let text: String
    public let removedCount: Int
    public let replacedCount: Int

    public init(text: String, removedCount: Int, replacedCount: Int) {
        self.text = text
        self.removedCount = removedCount
        self.replacedCount = replacedCount
    }
}

public enum CodeGuardAnalyzer {
    private enum Script: Hashable {
        case latin
        case cyrillic
        case greek
    }

    private struct PositionedScalar {
        let scalar: Unicode.Scalar
        let scalarPosition: Int
        let line: Int
        let column: Int
    }

    private static let typographicReplacements: [UInt32: String] = [
        0x2018: "'", 0x2019: "'",
        0x201C: "\"", 0x201D: "\"",
        0x2013: "-", 0x2014: "-", 0x2212: "-",
        0x2026: "..."
    ]

    private static let commonConfusables: [UInt32: String] = [
        0x0391: "A", 0x0392: "B", 0x0395: "E", 0x0396: "Z",
        0x0397: "H", 0x0399: "I", 0x039A: "K", 0x039C: "M",
        0x039D: "N", 0x039F: "O", 0x03A1: "P", 0x03A4: "T",
        0x03A5: "Y", 0x03A7: "X", 0x03B1: "a", 0x03B5: "e",
        0x03B9: "i", 0x03BA: "k", 0x03BD: "v", 0x03BF: "o",
        0x03C1: "p", 0x03C4: "t", 0x03C5: "u", 0x03C7: "x",
        0x0405: "S", 0x0406: "I", 0x0408: "J", 0x0410: "A",
        0x0412: "B", 0x0415: "E", 0x041A: "K", 0x041C: "M",
        0x041D: "H", 0x041E: "O", 0x0420: "P", 0x0421: "C",
        0x0422: "T", 0x0425: "X", 0x0430: "a", 0x0435: "e",
        0x043E: "o", 0x0440: "p", 0x0441: "c", 0x0445: "x",
        0x0455: "s", 0x0456: "i", 0x0458: "j"
    ]

    public static func analyze(_ text: String) -> CodeGuardAnalysis {
        let languageDetection = CodeLanguageDetector.detect(text)
        guard languageDetection.isLikelyCode else {
            return CodeGuardAnalysis(
                languageDetection: languageDetection,
                findings: []
            )
        }

        let positioned = positionedScalars(in: text)
        var findings: [CodeGuardFinding] = []

        for item in positioned {
            if let hiddenKind = HiddenTextAnalyzer.classify(item.scalar) {
                let codeKind: CodeGuardFindingKind
                switch hiddenKind {
                case .bidirectional:
                    codeKind = .bidirectionalControl
                case .zeroWidth, .variationSelector, .tag, .control,
                     .invisibleFiller, .layoutControl:
                    codeKind = .invisibleCharacter
                case .unusualWhitespace:
                    codeKind = .nonASCIIWhitespace
                case .privateUse, .unassigned, .reservedIgnorable, .noncharacter:
                    codeKind = .unsupportedUnicode
                }
                appendFinding(for: item, kind: codeKind, to: &findings)
            } else if typographicReplacements[item.scalar.value] != nil {
                appendFinding(for: item, kind: .typographicPunctuation, to: &findings)
            }
        }

        appendIdentifierFindings(from: positioned, to: &findings)

        let ordered = findings
            .sorted {
                $0.scalarPosition == $1.scalarPosition
                    ? $0.kind.rawValue < $1.kind.rawValue
                    : $0.scalarPosition < $1.scalarPosition
            }
            .enumerated()
            .map { index, finding in
                CodeGuardFinding(
                    id: index,
                    scalarPosition: finding.scalarPosition,
                    line: finding.line,
                    column: finding.column,
                    codePoint: finding.codePoint,
                    kind: finding.kind,
                    displayName: finding.displayName
                )
            }

        return CodeGuardAnalysis(
            languageDetection: languageDetection,
            findings: ordered
        )
    }

    /// Produces reviewable output. Confusable identifiers are never guessed or
    /// rewritten because the intended character cannot be known safely.
    public static func sanitize(_ text: String) -> CodeSanitizationResult {
        var output = ""
        var removed = 0
        var replaced = 0

        for scalar in text.unicodeScalars {
            if let hiddenKind = HiddenTextAnalyzer.classify(scalar) {
                switch hiddenKind {
                case .bidirectional, .zeroWidth, .variationSelector, .tag, .control,
                     .invisibleFiller, .reservedIgnorable, .noncharacter, .layoutControl:
                    removed += 1
                case .unusualWhitespace:
                    output.append(" ")
                    replaced += 1
                case .privateUse, .unassigned:
                    output.unicodeScalars.append(scalar)
                }
                continue
            }

            if let replacement = typographicReplacements[scalar.value] {
                output.append(replacement)
                replaced += 1
            } else {
                output.unicodeScalars.append(scalar)
            }
        }

        return CodeSanitizationResult(
            text: output,
            removedCount: removed,
            replacedCount: replaced
        )
    }

    private static func appendIdentifierFindings(
        from positioned: [PositionedScalar],
        to findings: inout [CodeGuardFinding]
    ) {
        var index = 0
        while index < positioned.count {
            guard isIdentifierStart(positioned[index].scalar) else {
                index += 1
                continue
            }

            let start = index
            index += 1
            while index < positioned.count, isIdentifierContinue(positioned[index].scalar) {
                index += 1
            }
            let token = positioned[start..<index]
            let scripts = Set(token.compactMap { script(of: $0.scalar.value) })
            guard scripts.count > 1 else { continue }

            if let confusable = token.first(where: { commonConfusables[$0.scalar.value] != nil }) {
                appendFinding(for: confusable, kind: .confusableIdentifier, to: &findings)
            } else if let mixed = token.first(where: { script(of: $0.scalar.value) != .latin }) {
                appendFinding(for: mixed, kind: .mixedScriptIdentifier, to: &findings)
            }
        }
    }

    private static func positionedScalars(in text: String) -> [PositionedScalar] {
        var result: [PositionedScalar] = []
        var scalarPosition = 1
        var line = 1
        var column = 1
        var previousWasCarriageReturn = false

        for scalar in text.unicodeScalars {
            result.append(
                PositionedScalar(
                    scalar: scalar,
                    scalarPosition: scalarPosition,
                    line: line,
                    column: column
                )
            )
            scalarPosition += 1
            if scalar.value == 0x0D {
                line += 1
                column = 1
                previousWasCarriageReturn = true
            } else if scalar.value == 0x0A {
                if !previousWasCarriageReturn {
                    line += 1
                }
                column = 1
                previousWasCarriageReturn = false
            } else {
                column += 1
                previousWasCarriageReturn = false
            }
        }
        return result
    }

    private static func appendFinding(
        for item: PositionedScalar,
        kind: CodeGuardFindingKind,
        to findings: inout [CodeGuardFinding]
    ) {
        findings.append(
            CodeGuardFinding(
                id: findings.count,
                scalarPosition: item.scalarPosition,
                line: item.line,
                column: item.column,
                codePoint: codePoint(for: item.scalar.value),
                kind: kind,
                displayName: displayName(for: item.scalar, kind: kind)
            )
        )
    }

    private static func displayName(
        for scalar: Unicode.Scalar,
        kind: CodeGuardFindingKind
    ) -> String {
        if let latin = commonConfusables[scalar.value], kind == .confusableIdentifier {
            return "LOOK-ALIKE FOR LATIN \(latin)"
        }
        return "Unicode \(codePoint(for: scalar.value))"
    }

    private static func isIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x5F || CharacterSet.letters.contains(scalar)
    }

    private static func isIdentifierContinue(_ scalar: Unicode.Scalar) -> Bool {
        isIdentifierStart(scalar) || CharacterSet.decimalDigits.contains(scalar)
    }

    private static func script(of value: UInt32) -> Script? {
        switch value {
        case 0x0041...0x005A, 0x0061...0x007A, 0x00C0...0x024F,
                0x1E00...0x1EFF, 0xAB30...0xAB6F:
            .latin
        case 0x0370...0x03FF, 0x1F00...0x1FFF:
            .greek
        case 0x0400...0x052F, 0x2DE0...0x2DFF, 0xA640...0xA69F:
            .cyrillic
        default:
            nil
        }
    }

    private static func codePoint(for value: UInt32) -> String {
        value <= 0xFFFF
            ? String(format: "U+%04X", value)
            : String(format: "U+%06X", value)
    }
}
