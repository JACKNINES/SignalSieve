// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum RewriteIntegrityAssessment: String, Sendable, Equatable {
    case noCandidate = "No candidate rewrite"
    case identical = "Candidate is identical"
    case reviewRequired = "Manual semantic review required"
    case protectedValuesChanged = "Protected values changed"
    case codeNotSupported = "Rewrite comparison is blocked for source code"
    case inputTooLarge = "Rewrite comparison input is too large"
}

public enum RewriteProtectedValueKind: String, Sendable, Equatable {
    case number = "Number or date"
    case url = "URL"
    case quotation = "Quoted text"
}

public enum RewriteValueChange: String, Sendable, Equatable {
    case removed = "Removed from candidate"
    case added = "Added to candidate"
}

public struct RewriteIntegrityFinding: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: RewriteProtectedValueKind
    public let change: RewriteValueChange
    public let value: String
    public var evidenceConfidence: EvidenceConfidence { .exact }

    public init(id: String, kind: RewriteProtectedValueKind, change: RewriteValueChange, value: String) {
        self.id = id
        self.kind = kind
        self.change = change
        self.value = value
    }
}

public struct RewriteIntegrityReport: Sendable, Equatable {
    public let assessment: RewriteIntegrityAssessment
    public let originalTokenCount: Int
    public let candidateTokenCount: Int
    public let lexicalDivergence: Double
    public let lengthRatio: Double
    public let findings: [RewriteIntegrityFinding]
    public let semanticEquivalenceConfidence: EvidenceConfidence

    public var hasProtectedValueChanges: Bool { !findings.isEmpty }

    public init(
        assessment: RewriteIntegrityAssessment,
        originalTokenCount: Int,
        candidateTokenCount: Int,
        lexicalDivergence: Double,
        lengthRatio: Double,
        findings: [RewriteIntegrityFinding],
        semanticEquivalenceConfidence: EvidenceConfidence
    ) {
        self.assessment = assessment
        self.originalTokenCount = originalTokenCount
        self.candidateTokenCount = candidateTokenCount
        self.lexicalDivergence = lexicalDivergence
        self.lengthRatio = lengthRatio
        self.findings = findings
        self.semanticEquivalenceConfidence = semanticEquivalenceConfidence
    }
}

/// Compares an original text with a user-supplied candidate. It does not
/// generate rewrites and never treats lexical difference as semantic proof.
public enum RewriteIntegrityAnalyzer {
    public static let maximumCharacterCount = 200_000

    private static let wordExpression = try? NSRegularExpression(
        pattern: #"[\p{L}\p{N}]+(?:['’\-][\p{L}\p{N}]+)*"#
    )
    private static let urlExpression = try? NSRegularExpression(
        pattern: #"https?://[^\s<>\"“”]+"#,
        options: [.caseInsensitive]
    )
    private static let numberExpression = try? NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_])[-+]?\d+(?:[.,:/\-]\d+)*(?:%|[\p{L}]{1,4})?"#
    )
    private static let quotationExpression = try? NSRegularExpression(
        pattern: #"\"([^\"\n]+)\"|“([^”\n]+)”|«([^»\n]+)»"#
    )

    public static func analyze(original: String, candidate: String) -> RewriteIntegrityReport {
        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return emptyReport(.noCandidate)
        }
        guard original.count <= maximumCharacterCount,
              candidate.count <= maximumCharacterCount else {
            return emptyReport(.inputTooLarge)
        }
        if CodeGuardAnalyzer.analyze(original).isLikelyCode
            || CodeGuardAnalyzer.analyze(candidate).isLikelyCode {
            return emptyReport(.codeNotSupported)
        }

        let originalTokens = tokens(original)
        let candidateTokens = tokens(candidate)
        let lexicalDivergence = jaccardDivergence(originalTokens, candidateTokens)
        let lengthRatio = originalTokens.isEmpty
            ? 0
            : Double(candidateTokens.count) / Double(originalTokens.count)

        var findings: [RewriteIntegrityFinding] = []
        appendDifferences(
            kind: .url,
            original: values(in: original, expression: urlExpression),
            candidate: values(in: candidate, expression: urlExpression),
            to: &findings
        )
        appendDifferences(
            kind: .number,
            original: values(in: original, expression: numberExpression),
            candidate: values(in: candidate, expression: numberExpression),
            to: &findings
        )
        appendDifferences(
            kind: .quotation,
            original: quotedValues(in: original),
            candidate: quotedValues(in: candidate),
            to: &findings
        )

        let assessment: RewriteIntegrityAssessment
        if original == candidate {
            assessment = .identical
        } else if !findings.isEmpty {
            assessment = .protectedValuesChanged
        } else {
            assessment = .reviewRequired
        }

        return RewriteIntegrityReport(
            assessment: assessment,
            originalTokenCount: originalTokens.count,
            candidateTokenCount: candidateTokens.count,
            lexicalDivergence: lexicalDivergence,
            lengthRatio: lengthRatio,
            findings: findings,
            semanticEquivalenceConfidence: .notTestable
        )
    }

    private static func emptyReport(_ assessment: RewriteIntegrityAssessment) -> RewriteIntegrityReport {
        RewriteIntegrityReport(
            assessment: assessment,
            originalTokenCount: 0,
            candidateTokenCount: 0,
            lexicalDivergence: 0,
            lengthRatio: 0,
            findings: [],
            semanticEquivalenceConfidence: .notTestable
        )
    }

    private static func tokens(_ text: String) -> [String] {
        guard let wordExpression else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return wordExpression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return text[swiftRange].folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
        }
    }

    private static func jaccardDivergence(_ left: [String], _ right: [String]) -> Double {
        let leftSet = Set(left)
        let rightSet = Set(right)
        let unionCount = leftSet.union(rightSet).count
        guard unionCount > 0 else { return 0 }
        let similarity = Double(leftSet.intersection(rightSet).count) / Double(unionCount)
        return 1 - similarity
    }

    private static func values(in text: String, expression: NSRegularExpression?) -> [String] {
        guard let expression else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange].prefix(200))
        }
    }

    private static func quotedValues(in text: String) -> [String] {
        guard let quotationExpression else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return quotationExpression.matches(in: text, range: range).compactMap { match in
            for group in 1..<match.numberOfRanges where match.range(at: group).location != NSNotFound {
                if let swiftRange = Range(match.range(at: group), in: text) {
                    return String(text[swiftRange].prefix(200))
                }
            }
            return nil
        }
    }

    private static func appendDifferences(
        kind: RewriteProtectedValueKind,
        original: [String],
        candidate: [String],
        to findings: inout [RewriteIntegrityFinding]
    ) {
        let originalCounts = counts(original)
        let candidateCounts = counts(candidate)
        for value in Set(originalCounts.keys).union(candidateCounts.keys).sorted() {
            let delta = candidateCounts[value, default: 0] - originalCounts[value, default: 0]
            let change: RewriteValueChange = delta < 0 ? .removed : .added
            for _ in 0..<abs(delta) {
                findings.append(RewriteIntegrityFinding(
                    id: "\(kind.rawValue):\(change.rawValue):\(findings.count)",
                    kind: kind,
                    change: change,
                    value: value
                ))
            }
        }
    }

    private static func counts(_ values: [String]) -> [String: Int] {
        values.reduce(into: [:]) { result, value in
            result[value, default: 0] += 1
        }
    }
}
