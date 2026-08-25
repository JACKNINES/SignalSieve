// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum CovertTextChannelKind: String, Sendable, Codable, CaseIterable {
    case zeroWidthBase4 = "Zero-width base-4 channel"
    case mixedSpaceAlphabet = "Mixed-space alphabet"
    case trailingWhitespace = "Trailing-whitespace channel"
    case confusableSubstitution = "Confusable-letter channel"
}

public struct CovertTextChannelFinding: Identifiable, Sendable, Equatable {
    public let id: Int
    public let kind: CovertTextChannelKind
    public let riskLevel: HiddenElementRiskLevel
    public let confidence: EvidenceConfidence
    public let line: Int
    public let column: Int
    public let carrierCount: Int
    public let periodicityPercent: Int?
    public let decodedPayload: String?
    public let evidence: String

    public init(
        id: Int,
        kind: CovertTextChannelKind,
        riskLevel: HiddenElementRiskLevel,
        confidence: EvidenceConfidence,
        line: Int,
        column: Int,
        carrierCount: Int,
        periodicityPercent: Int? = nil,
        decodedPayload: String? = nil,
        evidence: String
    ) {
        self.id = id
        self.kind = kind
        self.riskLevel = riskLevel
        self.confidence = confidence
        self.line = line
        self.column = column
        self.carrierCount = carrierCount
        self.periodicityPercent = periodicityPercent
        self.decodedPayload = decodedPayload
        self.evidence = evidence
    }
}

public struct CovertTextChannelReport: Sendable, Equatable {
    public let findings: [CovertTextChannelFinding]

    public init(findings: [CovertTextChannelFinding]) {
        self.findings = findings
    }

    public var hasSuspiciousChannel: Bool { !findings.isEmpty }
    public var highestRiskLevel: HiddenElementRiskLevel? {
        findings.map(\.riskLevel).max { $0.rawValue < $1.rawValue }
    }
}

/// Detects covert alphabets that are expressed through relationships between
/// otherwise ordinary characters. This complements scalar-by-scalar Unicode
/// inspection; it never attributes a channel to a provider or executes a
/// decoded payload.
public enum CovertTextChannelAnalyzer {
    public static let maximumInputScalars = 1_000_000
    public static let maximumDecodedPayloadBytes = 512

    private struct LocatedScalar {
        let scalar: Unicode.Scalar
        let position: Int
        let line: Int
        let column: Int
    }

    private static let base4Alphabet: [UInt32: UInt8] = [
        0x200B: 0, 0x200C: 1, 0x200D: 2, 0x2060: 3
    ]

    private static let unusualSpaces: Set<UInt32> = [
        0x00A0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004,
        0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x202F,
        0x205F, 0x3000
    ]

    private static let cyrillicConfusables: Set<UInt32> = [
        0x0406, 0x0408, 0x0410, 0x0412, 0x0415, 0x041A, 0x041C,
        0x041D, 0x041E, 0x0420, 0x0421, 0x0422, 0x0425, 0x0430,
        0x0435, 0x043E, 0x0440, 0x0441, 0x0445, 0x0456, 0x0458
    ]

    public static func analyze(_ text: String) -> CovertTextChannelReport {
        guard let located = locatedScalars(in: text) else {
            return CovertTextChannelReport(findings: [])
        }

        var findings: [CovertTextChannelFinding] = []
        appendBase4Findings(in: located, to: &findings)
        appendMixedSpaceFindings(in: located, to: &findings)
        appendTrailingWhitespaceFinding(in: text, to: &findings)
        appendConfusableFinding(in: located, to: &findings)

        return CovertTextChannelReport(
            findings: findings.enumerated().map { index, finding in
                CovertTextChannelFinding(
                    id: index,
                    kind: finding.kind,
                    riskLevel: finding.riskLevel,
                    confidence: finding.confidence,
                    line: finding.line,
                    column: finding.column,
                    carrierCount: finding.carrierCount,
                    periodicityPercent: finding.periodicityPercent,
                    decodedPayload: finding.decodedPayload,
                    evidence: finding.evidence
                )
            }
        )
    }

    private static func appendBase4Findings(
        in located: [LocatedScalar],
        to findings: inout [CovertTextChannelFinding]
    ) {
        var index = 0
        while index < located.count {
            guard base4Alphabet[located[index].scalar.value] != nil else {
                index += 1
                continue
            }
            let start = index
            while index < located.count, base4Alphabet[located[index].scalar.value] != nil {
                index += 1
            }
            let run = Array(located[start..<index])
            guard run.count >= 8, Set(run.map(\.scalar.value)).count >= 3,
                  let first = run.first else { continue }
            let digits = run.compactMap { base4Alphabet[$0.scalar.value] }
            let bytes = base4Bytes(from: digits)
            let decoded = displayableText(from: bytes)
            findings.append(CovertTextChannelFinding(
                id: findings.count,
                kind: .zeroWidthBase4,
                riskLevel: decoded == nil ? .medium : .high,
                confidence: decoded == nil ? .probable : .exact,
                line: first.line,
                column: first.column,
                carrierCount: run.count,
                decodedPayload: decoded,
                evidence: "U+200B/U+200C/U+200D/U+2060 form a four-symbol alphabet"
            ))
        }
    }

    private static func appendMixedSpaceFindings(
        in located: [LocatedScalar],
        to findings: inout [CovertTextChannelFinding]
    ) {
        let asciiLetterCount = located.filter { item in
            (0x41...0x5A).contains(item.scalar.value) || (0x61...0x7A).contains(item.scalar.value)
        }.count
        let visibleLetterCount = located.filter { $0.scalar.properties.isAlphabetic }.count

        for unusual in unusualSpaces.sorted() {
            let alphabet = located.filter { $0.scalar.value == 0x20 || $0.scalar.value == unusual }
            let unusualItems = alphabet.filter { $0.scalar.value == unusual }
            guard alphabet.count >= 16, unusualItems.count >= 4,
                  alphabet.count - unusualItems.count >= 4,
                  let first = unusualItems.first else { continue }
            if unusual == 0x3000, visibleLetterCount > 0,
               Double(asciiLetterCount) / Double(visibleLetterCount) < 0.60 {
                continue
            }

            let bits = alphabet.map { $0.scalar.value == 0x20 ? "0" : "1" }.joined()
            let decoded = displayableText(from: binaryBytes(from: bits))
            let periodicity = periodicityPercent(of: unusualItems.map(\.position))
            guard decoded != nil || periodicity >= 70 else { continue }
            findings.append(CovertTextChannelFinding(
                id: findings.count,
                kind: .mixedSpaceAlphabet,
                riskLevel: decoded == nil ? .suspicious : .high,
                confidence: decoded == nil ? .heuristic : .probable,
                line: first.line,
                column: first.column,
                carrierCount: alphabet.count,
                periodicityPercent: periodicity,
                decodedPayload: decoded,
                evidence: "ASCII SPACE alternates with \(codePoint(unusual)) across word boundaries"
            ))
        }
    }

    private static func appendTrailingWhitespaceFinding(
        in text: String,
        to findings: inout [CovertTextChannelFinding]
    ) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var bits = ""
        var carrierCount = 0
        var affectedLines: [Int] = []
        for (lineIndex, rawLine) in lines.enumerated() {
            let scalars = Array(rawLine.unicodeScalars)
            var suffix: [Unicode.Scalar] = []
            for scalar in scalars.reversed() {
                guard scalar.value == 0x20 || scalar.value == 0x09 else { break }
                suffix.append(scalar)
            }
            guard !suffix.isEmpty else { continue }
            affectedLines.append(lineIndex + 1)
            for scalar in suffix.reversed() {
                bits.append(scalar.value == 0x20 ? "0" : "1")
                carrierCount += 1
            }
        }
        guard affectedLines.count >= 2, carrierCount >= 8,
              bits.contains("0"), bits.contains("1") else { return }
        let decoded = displayableText(from: binaryBytes(from: bits))
        findings.append(CovertTextChannelFinding(
            id: findings.count,
            kind: .trailingWhitespace,
            riskLevel: decoded == nil ? .suspicious : .medium,
            confidence: decoded == nil ? .heuristic : .probable,
            line: affectedLines[0],
            column: 1,
            carrierCount: carrierCount,
            decodedPayload: decoded,
            evidence: "Spaces and tabs form a binary alphabet at the ends of \(affectedLines.count) lines"
        ))
    }

    private static func appendConfusableFinding(
        in located: [LocatedScalar],
        to findings: inout [CovertTextChannelFinding]
    ) {
        let carriers = located.filter { cyrillicConfusables.contains($0.scalar.value) }
        let latinCount = located.filter { item in
            (0x41...0x5A).contains(item.scalar.value) || (0x61...0x7A).contains(item.scalar.value)
        }.count
        guard carriers.count >= 3, latinCount >= 12, let first = carriers.first else { return }
        let periodicity = periodicityPercent(of: carriers.map(\.position))
        guard periodicity >= 60 || carriers.count >= 6 else { return }
        findings.append(CovertTextChannelFinding(
            id: findings.count,
            kind: .confusableSubstitution,
            riskLevel: .medium,
            confidence: .heuristic,
            line: first.line,
            column: first.column,
            carrierCount: carriers.count,
            periodicityPercent: periodicity,
            evidence: "Cyrillic look-alikes recur inside predominantly Latin text"
        ))
    }

    private static func base4Bytes(from digits: [UInt8]) -> [UInt8] {
        var bytes: [UInt8] = []
        for start in stride(from: 0, through: max(0, digits.count - 4), by: 4) {
            guard start + 3 < digits.count, bytes.count < maximumDecodedPayloadBytes else { break }
            bytes.append((digits[start] << 6) | (digits[start + 1] << 4) | (digits[start + 2] << 2) | digits[start + 3])
        }
        return bytes
    }

    private static func binaryBytes(from bits: String) -> [UInt8] {
        let values = Array(bits)
        var bytes: [UInt8] = []
        for start in stride(from: 0, through: max(0, values.count - 8), by: 8) {
            guard start + 7 < values.count, bytes.count < maximumDecodedPayloadBytes else { break }
            var byte: UInt8 = 0
            for offset in 0..<8 {
                byte <<= 1
                if values[start + offset] == "1" { byte |= 1 }
            }
            bytes.append(byte)
        }
        return bytes
    }

    private static func displayableText(from bytes: [UInt8]) -> String? {
        guard bytes.count >= 2,
              let text = String(data: Data(bytes), encoding: .utf8),
              !text.isEmpty,
              text.unicodeScalars.allSatisfy({ scalar in
                  scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D
                      || ![Unicode.GeneralCategory.control, .format, .privateUse, .unassigned]
                          .contains(scalar.properties.generalCategory)
              }),
              text.contains(where: { !$0.isWhitespace }) else { return nil }
        return text.count <= 180 ? text : String(text.prefix(180)) + "…"
    }

    private static func periodicityPercent(of positions: [Int]) -> Int {
        guard positions.count >= 3 else { return 0 }
        let gaps = zip(positions.dropFirst(), positions).map { later, earlier in
            later - earlier
        }
        guard !gaps.isEmpty else { return 0 }
        let counts = Dictionary(grouping: gaps, by: { $0 }).mapValues(\.count)
        let dominant = counts.values.max() ?? 0
        return Int((Double(dominant) / Double(gaps.count) * 100).rounded())
    }

    private static func locatedScalars(in text: String) -> [LocatedScalar]? {
        var result: [LocatedScalar] = []
        result.reserveCapacity(min(maximumInputScalars, text.unicodeScalars.count))
        var line = 1
        var column = 1
        for (position, scalar) in text.unicodeScalars.enumerated() {
            guard position < maximumInputScalars else { return nil }
            result.append(LocatedScalar(scalar: scalar, position: position + 1, line: line, column: column))
            if scalar.value == 0x0A {
                line += 1
                column = 1
            } else {
                column += 1
            }
        }
        return result
    }

    private static func codePoint(_ value: UInt32) -> String {
        value <= 0xFFFF ? String(format: "U+%04X", value) : String(format: "U+%06X", value)
    }
}
