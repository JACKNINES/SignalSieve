// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum HiddenElementRiskLevel: Int, Sendable, CaseIterable {
    case clear = 0
    case suspicious = 1
    case medium = 2
    case high = 3

    public var label: String {
        switch self {
        case .clear: "Clear"
        case .suspicious: "Suspicious"
        case .medium: "Medium risk"
        case .high: "High risk"
        }
    }
}

public enum HiddenElementContext: String, Sendable, Equatable {
    case noFunctionalContext = "No functional Unicode context detected"
    case emojiComposition = "Functional emoji composition"
    case scriptShaping = "Functional script shaping"
    case glyphVariation = "Functional glyph variation"
    case bidirectionalText = "Functional bidirectional text"

    public var isFunctional: Bool { self != .noFunctionalContext }
}

public enum HiddenElementKind: String, Sendable, CaseIterable {
    case zeroWidth = "Zero-width character"
    case bidirectional = "Bidirectional control"
    case variationSelector = "Variation selector"
    case tag = "Unicode tag"
    case control = "Control character"
    case unusualWhitespace = "Unusual whitespace"
    case privateUse = "Private-use character"
    case unassigned = "Unassigned code point"

    public var riskLevel: HiddenElementRiskLevel {
        switch self {
        case .bidirectional, .tag, .control: .high
        case .zeroWidth, .variationSelector, .privateUse: .medium
        case .unusualWhitespace, .unassigned: .suspicious
        }
    }

    public var severity: Int { riskLevel.rawValue }
}

public struct HiddenElement: Identifiable, Sendable, Equatable {
    public let id: Int
    public let scalarPosition: Int
    public let utf16Position: Int
    public let codePoint: String
    public let kind: HiddenElementKind
    public let displayName: String
    public let context: HiddenElementContext
    public let riskLevel: HiddenElementRiskLevel
    public var evidenceConfidence: EvidenceConfidence { .exact }
    public var isActionable: Bool { riskLevel != .clear }

    public init(
        id: Int,
        scalarPosition: Int,
        utf16Position: Int,
        codePoint: String,
        kind: HiddenElementKind,
        displayName: String,
        context: HiddenElementContext = .noFunctionalContext,
        riskLevel: HiddenElementRiskLevel? = nil
    ) {
        self.id = id
        self.scalarPosition = scalarPosition
        self.utf16Position = utf16Position
        self.codePoint = codePoint
        self.kind = kind
        self.displayName = displayName
        self.context = context
        self.riskLevel = riskLevel ?? kind.riskLevel
    }

    /// A focused query that explains the code point without including any of
    /// the user's original text.
    public var researchQuery: String {
        "Unicode \(codePoint) \(displayName) \(kind.rawValue) meaning security implications"
    }

    public var researchURL: URL? {
        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: researchQuery)
        ]
        return components?.url
    }
}

public struct TextInspection: Sendable, Equatable {
    public let scalarCount: Int
    public let utf16Count: Int
    public let findings: [HiddenElement]
    public let changesUnderNFC: Bool
    public let changesUnderNFKC: Bool

    public var actionableFindings: [HiddenElement] { findings.filter(\.isActionable) }
    public var isClean: Bool { actionableFindings.isEmpty }
    public var highestRiskLevel: HiddenElementRiskLevel? {
        actionableFindings.map(\.riskLevel).max { $0.rawValue < $1.rawValue }
    }

    public init(
        scalarCount: Int,
        utf16Count: Int,
        findings: [HiddenElement],
        changesUnderNFC: Bool,
        changesUnderNFKC: Bool
    ) {
        self.scalarCount = scalarCount
        self.utf16Count = utf16Count
        self.findings = findings
        self.changesUnderNFC = changesUnderNFC
        self.changesUnderNFKC = changesUnderNFKC
    }
}

public enum HiddenTextAnalyzer {
    struct ScalarAssessment: Sendable, Equatable {
        let kind: HiddenElementKind
        let context: HiddenElementContext
        let riskLevel: HiddenElementRiskLevel

        var shouldPreserveInSafeCleaning: Bool { context.isFunctional }
    }

    private enum JoiningScript: Equatable {
        case arabic
        case syriac
        case thaana
        case nko
        case devanagari
        case bengali
        case gurmukhi
        case gujarati
        case odia
        case tamil
        case telugu
        case kannada
        case malayalam
        case sinhala
        case myanmar
        case khmer
        case mongolian
    }

    private static let explicitZeroWidth: Set<UInt32> = [
        0x00AD, // soft hyphen
        0x034F, // combining grapheme joiner
        0x180E, // Mongolian vowel separator
        0x200B, // zero width space
        0x200C, // zero width non-joiner
        0x200D, // zero width joiner
        0x2060, // word joiner
        0xFEFF  // zero width no-break space / BOM
    ]

    private static let knownNames: [UInt32: String] = [
        0x00A0: "NO-BREAK SPACE",
        0x00AD: "SOFT HYPHEN",
        0x034F: "COMBINING GRAPHEME JOINER",
        0x061C: "ARABIC LETTER MARK",
        0x180B: "MONGOLIAN FREE VARIATION SELECTOR ONE",
        0x180C: "MONGOLIAN FREE VARIATION SELECTOR TWO",
        0x180D: "MONGOLIAN FREE VARIATION SELECTOR THREE",
        0x180E: "MONGOLIAN VOWEL SEPARATOR",
        0x200B: "ZERO WIDTH SPACE",
        0x200C: "ZERO WIDTH NON-JOINER",
        0x200D: "ZERO WIDTH JOINER",
        0x200E: "LEFT-TO-RIGHT MARK",
        0x200F: "RIGHT-TO-LEFT MARK",
        0x202A: "LEFT-TO-RIGHT EMBEDDING",
        0x202B: "RIGHT-TO-LEFT EMBEDDING",
        0x202C: "POP DIRECTIONAL FORMATTING",
        0x202D: "LEFT-TO-RIGHT OVERRIDE",
        0x202E: "RIGHT-TO-LEFT OVERRIDE",
        0x202F: "NARROW NO-BREAK SPACE",
        0x2060: "WORD JOINER",
        0x2066: "LEFT-TO-RIGHT ISOLATE",
        0x2067: "RIGHT-TO-LEFT ISOLATE",
        0x2068: "FIRST STRONG ISOLATE",
        0x2069: "POP DIRECTIONAL ISOLATE",
        0xFEFF: "ZERO WIDTH NO-BREAK SPACE / BOM"
    ]

    public static func inspect(_ text: String) -> TextInspection {
        var findings: [HiddenElement] = []
        var utf16Position = 0
        let scalars = Array(text.unicodeScalars)

        for (index, scalar) in scalars.enumerated() {
            if let assessment = assess(scalars, at: index) {
                findings.append(
                    HiddenElement(
                        id: findings.count,
                        scalarPosition: index + 1,
                        utf16Position: utf16Position + 1,
                        codePoint: codePoint(for: scalar.value),
                        kind: assessment.kind,
                        displayName: name(for: scalar),
                        context: assessment.context,
                        riskLevel: assessment.riskLevel
                    )
                )
            }
            utf16Position += scalar.utf16.count
        }

        return TextInspection(
            scalarCount: scalars.count,
            utf16Count: text.utf16.count,
            findings: findings,
            changesUnderNFC: text != text.precomposedStringWithCanonicalMapping,
            changesUnderNFKC: text != text.precomposedStringWithCompatibilityMapping
        )
    }

    public static func classify(_ scalar: Unicode.Scalar) -> HiddenElementKind? {
        let value = scalar.value

        if value == 0x061C
            || value == 0x200E
            || value == 0x200F
            || (0x202A...0x202E).contains(value)
            || (0x2066...0x2069).contains(value) {
            return .bidirectional
        }
        if (0x180B...0x180D).contains(value)
            || (0xFE00...0xFE0F).contains(value)
            || (0xE0100...0xE01EF).contains(value) {
            return .variationSelector
        }
        if (0xE0000...0xE007F).contains(value) {
            return .tag
        }
        if explicitZeroWidth.contains(value) {
            return .zeroWidth
        }

        let category = scalar.properties.generalCategory
        if category == .control {
            // New lines and tabs are visible structural characters, not findings.
            if value == 0x09 || value == 0x0A || value == 0x0D {
                return nil
            }
            return .control
        }
        if category == .format {
            return .zeroWidth
        }
        if category == .privateUse {
            return .privateUse
        }
        if category == .unassigned {
            return .unassigned
        }
        if scalar.properties.isWhitespace,
           value != 0x20,
           value != 0x09,
           value != 0x0A,
           value != 0x0D {
            return .unusualWhitespace
        }

        return nil
    }

    static func assess(
        _ scalars: [Unicode.Scalar],
        at index: Int
    ) -> ScalarAssessment? {
        guard scalars.indices.contains(index),
              let kind = classify(scalars[index]) else {
            return nil
        }

        let context = functionalContext(for: kind, in: scalars, at: index)
        return ScalarAssessment(
            kind: kind,
            context: context,
            riskLevel: context.isFunctional ? .clear : kind.riskLevel
        )
    }

    private static func functionalContext(
        for kind: HiddenElementKind,
        in scalars: [Unicode.Scalar],
        at index: Int
    ) -> HiddenElementContext {
        let value = scalars[index].value

        switch kind {
        case .variationSelector:
            if isEmojiVariationSelector(value),
               index > 0,
               isEmojiBase(scalars[index - 1]) {
                return .emojiComposition
            }
            if isSingleGlyphVariation(in: scalars, at: index) {
                return .glyphVariation
            }

        case .zeroWidth:
            if value == 0x200D, isEmojiJoiner(in: scalars, at: index) {
                return .emojiComposition
            }
            if (value == 0x200C || value == 0x200D),
               isScriptJoiner(in: scalars, at: index) {
                return .scriptShaping
            }

        case .bidirectional:
            if [0x061C, 0x200E, 0x200F].contains(value),
               isFunctionalDirectionalMark(in: scalars, at: index) {
                return .bidirectionalText
            }

        case .tag:
            if isStandardEmojiTagSequence(in: scalars, containing: index) {
                return .emojiComposition
            }

        case .control, .unusualWhitespace, .privateUse, .unassigned:
            break
        }

        return .noFunctionalContext
    }

    private static func isEmojiVariationSelector(_ value: UInt32) -> Bool {
        value == 0xFE0E || value == 0xFE0F
    }

    private static func isEmojiBase(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isEmoji
    }

    private static func isEmojiJoiner(
        in scalars: [Unicode.Scalar],
        at index: Int
    ) -> Bool {
        guard let previous = emojiNeighbor(in: scalars, from: index, step: -1),
              let next = emojiNeighbor(in: scalars, from: index, step: 1) else {
            return false
        }
        return isEmojiBase(previous) && isEmojiBase(next)
    }

    private static func emojiNeighbor(
        in scalars: [Unicode.Scalar],
        from index: Int,
        step: Int
    ) -> Unicode.Scalar? {
        var cursor = index + step
        while scalars.indices.contains(cursor) {
            let value = scalars[cursor].value
            if isEmojiVariationSelector(value) || (0x1F3FB...0x1F3FF).contains(value) {
                cursor += step
                continue
            }
            return scalars[cursor]
        }
        return nil
    }

    private static func isSingleGlyphVariation(
        in scalars: [Unicode.Scalar],
        at index: Int
    ) -> Bool {
        guard index > 0 else { return false }
        let value = scalars[index].value
        let previous = scalars[index - 1]
        let hasAdjacentSelector = (index > 1 && classify(scalars[index - 1]) == .variationSelector)
            || (index + 1 < scalars.count && classify(scalars[index + 1]) == .variationSelector)
        guard !hasAdjacentSelector else { return false }

        if (0x180B...0x180D).contains(value) {
            return joiningScript(for: previous.value) == .mongolian
        }
        if (0xE0100...0xE01EF).contains(value) {
            return isIdeographicBase(previous.value)
        }
        if (0xFE00...0xFE0F).contains(value) {
            return previous.value > 0x7F
                && !previous.properties.isWhitespace
                && previous.properties.generalCategory != .control
                && previous.properties.generalCategory != .format
        }
        return false
    }

    private static func isIdeographicBase(_ value: UInt32) -> Bool {
        (0x3400...0x4DBF).contains(value)
            || (0x4E00...0x9FFF).contains(value)
            || (0xF900...0xFAFF).contains(value)
            || (0x20000...0x323AF).contains(value)
    }

    private static func isScriptJoiner(
        in scalars: [Unicode.Scalar],
        at index: Int
    ) -> Bool {
        guard index > 0, index + 1 < scalars.count,
              let previousScript = joiningScript(for: scalars[index - 1].value),
              let nextScript = joiningScript(for: scalars[index + 1].value) else {
            return false
        }
        return previousScript == nextScript
    }

    private static func joiningScript(for value: UInt32) -> JoiningScript? {
        switch value {
        case 0x0600...0x06FF, 0x0750...0x077F, 0x0870...0x089F,
             0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
            .arabic
        case 0x0700...0x074F: .syriac
        case 0x0780...0x07BF: .thaana
        case 0x07C0...0x07FF: .nko
        case 0x0900...0x097F: .devanagari
        case 0x0980...0x09FF: .bengali
        case 0x0A00...0x0A7F: .gurmukhi
        case 0x0A80...0x0AFF: .gujarati
        case 0x0B00...0x0B7F: .odia
        case 0x0B80...0x0BFF: .tamil
        case 0x0C00...0x0C7F: .telugu
        case 0x0C80...0x0CFF: .kannada
        case 0x0D00...0x0D7F: .malayalam
        case 0x0D80...0x0DFF: .sinhala
        case 0x1000...0x109F, 0xAA60...0xAA7F, 0xA9E0...0xA9FF: .myanmar
        case 0x1780...0x17FF: .khmer
        case 0x1800...0x18AF: .mongolian
        default: nil
        }
    }

    private static func isFunctionalDirectionalMark(
        in scalars: [Unicode.Scalar],
        at index: Int
    ) -> Bool {
        let bounds = paragraphBounds(in: scalars, around: index)
        let paragraph = scalars[bounds]
        let implicitMarkCount = paragraph.filter {
            [0x061C, 0x200E, 0x200F].contains($0.value)
        }.count
        guard implicitMarkCount <= 2 else { return false }

        let hasRTL = paragraph.contains(where: isStrongRTL)
        let hasLTR = paragraph.contains(where: isStrongLTR)
        switch scalars[index].value {
        case 0x061C, 0x200F:
            return hasRTL
        case 0x200E:
            return hasRTL && hasLTR
        default:
            return false
        }
    }

    private static func paragraphBounds(
        in scalars: [Unicode.Scalar],
        around index: Int
    ) -> Range<Int> {
        var lower = index
        var upper = index + 1
        while lower > 0, !isParagraphBreak(scalars[lower - 1].value) {
            lower -= 1
        }
        while upper < scalars.count, !isParagraphBreak(scalars[upper].value) {
            upper += 1
        }
        return lower..<upper
    }

    private static func isParagraphBreak(_ value: UInt32) -> Bool {
        value == 0x0A || value == 0x0D || value == 0x2028 || value == 0x2029
    }

    private static func isStrongRTL(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.properties.isAlphabetic else { return false }
        let value = scalar.value
        return (0x0590...0x08FF).contains(value)
            || (0xFB1D...0xFDFF).contains(value)
            || (0xFE70...0xFEFF).contains(value)
            || (0x10800...0x10FFF).contains(value)
            || (0x1E800...0x1EEFF).contains(value)
    }

    private static func isStrongLTR(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.properties.isAlphabetic && !isStrongRTL(scalar))
            || scalar.properties.numericType != nil
    }

    private static func isStandardEmojiTagSequence(
        in scalars: [Unicode.Scalar],
        containing index: Int
    ) -> Bool {
        var start = index
        while start > 0, (0xE0020...0xE007F).contains(scalars[start - 1].value) {
            start -= 1
        }
        var end = index + 1
        while end < scalars.count, (0xE0020...0xE007F).contains(scalars[end].value) {
            end += 1
        }
        guard start > 0,
              scalars[start - 1].value == 0x1F3F4,
              scalars[end - 1].value == 0xE007F else {
            return false
        }

        let tag = scalars[start..<(end - 1)].compactMap { scalar -> Unicode.Scalar? in
            let value = scalar.value
            guard (0xE0061...0xE007A).contains(value) else { return nil }
            return Unicode.Scalar(value - 0xE0000)
        }
        guard tag.count == end - start - 1 else { return false }
        return ["gbeng", "gbsct", "gbwls"].contains(String(String.UnicodeScalarView(tag)))
    }

    private static func codePoint(for value: UInt32) -> String {
        value <= 0xFFFF
            ? String(format: "U+%04X", value)
            : String(format: "U+%06X", value)
    }

    private static func name(for scalar: Unicode.Scalar) -> String {
        if let known = knownNames[scalar.value] {
            return known
        }
        return "Unicode \(codePoint(for: scalar.value))"
    }
}
