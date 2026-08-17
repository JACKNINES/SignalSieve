// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum SignatureTechnique: String, Sendable, CaseIterable {
    case unicodeTags = "Unicode Tag payload"
    case variationSelectors = "Variation-selector payload"
    case zeroWidthEncoding = "Zero-width encoded payload"
    case bidirectionalControl = "Bidirectional control signature"
    case hiddenUnicode = "Hidden Unicode signature"
    case sourceCodeRisk = "Source-code Unicode signature"
    case encodedData = "Encoded data signature"
}

public enum SignatureDisposition: String, Sendable, CaseIterable {
    case safeToNeutralize = "Safe to neutralize"
    case reviewOnly = "Review only"
    case protected = "Do not modify"
}

public struct SignatureOccurrence: Identifiable, Sendable, Equatable {
    public let id: String
    public let relativePath: String
    public let line: Int
    public let column: Int
    public let codePoint: String?
    public let fragment: String?
    public let encoding: TextEncodingKind
    public let changePreview: VaccineChangePreview?

    public init(
        id: String,
        relativePath: String,
        line: Int,
        column: Int,
        codePoint: String?,
        fragment: String?,
        encoding: TextEncodingKind,
        changePreview: VaccineChangePreview?
    ) {
        self.id = id
        self.relativePath = relativePath
        self.line = line
        self.column = column
        self.codePoint = codePoint
        self.fragment = fragment
        self.encoding = encoding
        self.changePreview = changePreview
    }
}

public struct SignatureGroup: Identifiable, Sendable, Equatable {
    public let id: String
    public let technique: SignatureTechnique
    public let disposition: SignatureDisposition
    public let confidence: CodeLanguageConfidence
    public let codePoint: String?
    public let revealedFragment: String?
    public let occurrences: [SignatureOccurrence]

    public init(
        id: String,
        technique: SignatureTechnique,
        disposition: SignatureDisposition,
        confidence: CodeLanguageConfidence,
        codePoint: String?,
        revealedFragment: String?,
        occurrences: [SignatureOccurrence]
    ) {
        self.id = id
        self.technique = technique
        self.disposition = disposition
        self.confidence = confidence
        self.codePoint = codePoint
        self.revealedFragment = revealedFragment
        self.occurrences = occurrences
    }

    public var occurrenceCount: Int { occurrences.count }
    public var fileCount: Int { Set(occurrences.map(\.relativePath)).count }
}

public struct SignatureHuntReport: Sendable, Equatable {
    public let vaccineReport: VaccineScanReport
    public let groups: [SignatureGroup]

    public init(vaccineReport: VaccineScanReport, groups: [SignatureGroup]) {
        self.vaccineReport = vaccineReport
        self.groups = groups
    }

    public var safeGroupCount: Int {
        groups.filter { $0.disposition == .safeToNeutralize }.count
    }
    public var totalOccurrenceCount: Int {
        groups.reduce(0) { $0 + $1.occurrenceCount }
    }
}

public struct SignatureNeutralizationResult: Sendable, Equatable {
    public let vaccineResult: VaccineResult
    public let neutralizedGroupIDs: [String]
    public let remainingSafeGroupIDs: [String]
    public let postScanReport: SignatureHuntReport

    public init(
        vaccineResult: VaccineResult,
        neutralizedGroupIDs: [String],
        remainingSafeGroupIDs: [String],
        postScanReport: SignatureHuntReport
    ) {
        self.vaccineResult = vaccineResult
        self.neutralizedGroupIDs = neutralizedGroupIDs
        self.remainingSafeGroupIDs = remainingSafeGroupIDs
        self.postScanReport = postScanReport
    }

    public var verificationPassed: Bool { remainingSafeGroupIDs.isEmpty }
}

public enum SignatureHuntEngine {
    private struct Candidate {
        let key: String
        let technique: SignatureTechnique
        let disposition: SignatureDisposition
        let confidence: CodeLanguageConfidence
        let codePoint: String?
        let revealedFragment: String?
        let occurrence: SignatureOccurrence
    }

    public static func scan(rootURL: URL) throws -> SignatureHuntReport {
        analyze(try VaccineEngine.scan(rootURL: rootURL))
    }

    public static func analyze(_ vaccineReport: VaccineScanReport) -> SignatureHuntReport {
        var candidates: [Candidate] = []
        for file in vaccineReport.findings {
            let isCode = file.detectedLanguage != nil
            let coveredPositions = Set(file.revealedFragments.flatMap(\.scalarPositions))

            for fragment in file.revealedFragments {
                let technique = technique(for: fragment.codePoint, decoded: fragment.presentation == .decodedPayload)
                let disposition = disposition(
                    for: technique,
                    codePoint: fragment.codePoint,
                    isCode: isCode
                )
                let key = fragment.presentation == .decodedPayload
                    ? "payload|\(technique.rawValue)|\(fragment.text)"
                    : "unicode|\(technique.rawValue)|\(fragment.codePoint)"
                candidates.append(Candidate(
                    key: key,
                    technique: technique,
                    disposition: disposition,
                    confidence: fragment.presentation == .decodedPayload ? .high : .medium,
                    codePoint: fragment.codePoint,
                    revealedFragment: fragment.text,
                    occurrence: occurrence(
                        file: file,
                        suffix: "fragment-\(fragment.id)",
                        line: fragment.line,
                        column: fragment.column,
                        codePoint: fragment.codePoint,
                        fragment: fragment.text
                    )
                ))
            }

            if isCode {
                for finding in file.codeFindings where !coveredPositions.contains(finding.scalarPosition) {
                    let technique = technique(for: finding)
                    let disposition: SignatureDisposition
                    switch finding.kind {
                    case .confusableIdentifier, .mixedScriptIdentifier, .unsupportedUnicode:
                        disposition = .reviewOnly
                    default:
                        disposition = .safeToNeutralize
                    }
                    let key = "code|\(technique.rawValue)|\(finding.kind.rawValue)|\(finding.codePoint)"
                    candidates.append(Candidate(
                        key: key,
                        technique: technique,
                        disposition: disposition,
                        confidence: .high,
                        codePoint: finding.codePoint,
                        revealedFragment: nil,
                        occurrence: occurrence(
                            file: file,
                            suffix: "code-\(finding.id)",
                            line: finding.line,
                            column: finding.column,
                            codePoint: finding.codePoint,
                            fragment: nil
                        )
                    ))
                }
            } else {
                for finding in file.hiddenFindings where !coveredPositions.contains(finding.scalarPosition) {
                    let technique: SignatureTechnique = finding.kind == .bidirectional
                        ? .bidirectionalControl
                        : .hiddenUnicode
                    let safe = isSafelyNeutralized(finding.kind, codePoint: finding.codePoint, isCode: false)
                    let key = "text|\(technique.rawValue)|\(finding.kind.rawValue)|\(finding.codePoint)"
                    candidates.append(Candidate(
                        key: key,
                        technique: technique,
                        disposition: safe ? .safeToNeutralize : .reviewOnly,
                        confidence: .high,
                        codePoint: finding.codePoint,
                        revealedFragment: nil,
                        occurrence: occurrence(
                            file: file,
                            suffix: "text-\(finding.id)",
                            line: 0,
                            column: 0,
                            codePoint: finding.codePoint,
                            fragment: nil
                        )
                    ))
                }
            }

            if let encoded = file.encodedDataKind {
                let key = "encoded|\(encoded.rawValue)"
                candidates.append(Candidate(
                    key: key,
                    technique: .encodedData,
                    disposition: .reviewOnly,
                    confidence: .medium,
                    codePoint: nil,
                    revealedFragment: encoded.rawValue,
                    occurrence: occurrence(
                        file: file,
                        suffix: "encoded",
                        line: 0,
                        column: 0,
                        codePoint: nil,
                        fragment: encoded.rawValue
                    )
                ))
            }
        }

        let grouped = Dictionary(grouping: candidates, by: \.key)
        let groups = grouped.map { key, values -> SignatureGroup in
            let first = values[0]
            let disposition: SignatureDisposition
            if values.contains(where: { $0.disposition == .protected }) {
                disposition = .protected
            } else if values.contains(where: { $0.disposition == .reviewOnly }) {
                disposition = .reviewOnly
            } else {
                disposition = .safeToNeutralize
            }
            return SignatureGroup(
                id: signatureID(for: key),
                technique: first.technique,
                disposition: disposition,
                confidence: values.map(\.confidence).min(by: { confidenceRank($0) < confidenceRank($1) }) ?? .low,
                codePoint: first.codePoint,
                revealedFragment: first.revealedFragment,
                occurrences: values.map(\.occurrence).sorted {
                    $0.relativePath == $1.relativePath
                        ? $0.line < $1.line
                        : $0.relativePath < $1.relativePath
                }
            )
        }.sorted {
            let leftRank = dispositionRank($0.disposition)
            let rightRank = dispositionRank($1.disposition)
            if leftRank != rightRank { return leftRank < rightRank }
            if $0.occurrenceCount != $1.occurrenceCount {
                return $0.occurrenceCount > $1.occurrenceCount
            }
            return $0.id < $1.id
        }

        return SignatureHuntReport(vaccineReport: vaccineReport, groups: groups)
    }

    public static func neutralizeSafeSignatures(
        in report: SignatureHuntReport,
        backupBaseURL: URL
    ) throws -> SignatureNeutralizationResult {
        let safeBefore = Set(report.groups.filter {
            $0.disposition == .safeToNeutralize
        }.map(\.id))
        let vaccineResult = try VaccineEngine.vaccinate(
            report.vaccineReport,
            backupBaseURL: backupBaseURL
        )
        let after = try scan(rootURL: report.vaccineReport.rootURL)
        let safeAfter = Set(after.groups.filter {
            $0.disposition == .safeToNeutralize
        }.map(\.id))
        return SignatureNeutralizationResult(
            vaccineResult: vaccineResult,
            neutralizedGroupIDs: Array(safeBefore.subtracting(safeAfter)).sorted(),
            remainingSafeGroupIDs: Array(safeBefore.intersection(safeAfter)).sorted(),
            postScanReport: after
        )
    }

    private static func occurrence(
        file: VaccineFileFinding,
        suffix: String,
        line: Int,
        column: Int,
        codePoint: String?,
        fragment: String?
    ) -> SignatureOccurrence {
        SignatureOccurrence(
            id: "\(file.relativePath)|\(suffix)",
            relativePath: file.relativePath,
            line: line,
            column: column,
            codePoint: codePoint,
            fragment: fragment,
            encoding: file.textEncoding,
            changePreview: file.changePreview
        )
    }

    private static func technique(for finding: CodeGuardFinding) -> SignatureTechnique {
        switch finding.kind {
        case .bidirectionalControl: .bidirectionalControl
        default: .sourceCodeRisk
        }
    }

    private static func technique(for codePoint: String, decoded: Bool) -> SignatureTechnique {
        guard let value = scalarValue(from: codePoint) else { return .hiddenUnicode }
        if (0xE0000...0xE007F).contains(value) { return .unicodeTags }
        if (0xFE00...0xFE0F).contains(value) || (0xE0100...0xE01EF).contains(value) {
            return decoded ? .variationSelectors : .hiddenUnicode
        }
        if [0x200B, 0x200C, 0x200D].contains(value), decoded {
            return .zeroWidthEncoding
        }
        if (0x202A...0x202E).contains(value) || (0x2066...0x2069).contains(value) {
            return .bidirectionalControl
        }
        return .hiddenUnicode
    }

    private static func disposition(
        for technique: SignatureTechnique,
        codePoint: String,
        isCode: Bool
    ) -> SignatureDisposition {
        switch technique {
        case .unicodeTags, .bidirectionalControl:
            return .safeToNeutralize
        case .variationSelectors, .zeroWidthEncoding:
            return isCode ? .safeToNeutralize : .reviewOnly
        case .hiddenUnicode:
            guard let value = scalarValue(from: codePoint),
                  let scalar = Unicode.Scalar(value),
                  let kind = HiddenTextAnalyzer.classify(scalar) else {
                return .reviewOnly
            }
            return isSafelyNeutralized(kind, codePoint: codePoint, isCode: isCode)
                ? .safeToNeutralize
                : .reviewOnly
        case .sourceCodeRisk:
            return .safeToNeutralize
        case .encodedData:
            return .reviewOnly
        }
    }

    private static func isSafelyNeutralized(
        _ kind: HiddenElementKind,
        codePoint: String,
        isCode: Bool
    ) -> Bool {
        if isCode {
            return ![.privateUse, .unassigned].contains(kind)
        }
        return switch kind {
        case .bidirectional, .tag, .control, .unusualWhitespace: true
        case .zeroWidth: codePoint != "U+200C" && codePoint != "U+200D"
        case .variationSelector, .privateUse, .unassigned: false
        }
    }

    private static func scalarValue(from codePoint: String) -> UInt32? {
        guard codePoint.hasPrefix("U+") else { return nil }
        return UInt32(codePoint.dropFirst(2), radix: 16)
    }

    private static func signatureID(for key: String) -> String {
        let hash = key.utf8.reduce(UInt64(1_469_598_103_934_665_603)) { value, byte in
            (value ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(format: "SIG-%08X", UInt32(truncatingIfNeeded: hash))
    }

    private static func dispositionRank(_ disposition: SignatureDisposition) -> Int {
        switch disposition {
        case .safeToNeutralize: 0
        case .reviewOnly: 1
        case .protected: 2
        }
    }

    private static func confidenceRank(_ confidence: CodeLanguageConfidence) -> Int {
        switch confidence {
        case .none: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }
}
