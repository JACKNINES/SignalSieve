// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum ClipboardAlertPriority: Sendable, Equatable {
    case standard
    case elevated
    case high
}

public struct ClipboardProtectionAnalysis: Sendable, Equatable {
    public let limitation: TextAnalysisLimitation?
    public let inspection: TextInspection
    public let covertChannelReport: CovertTextChannelReport
    public let codeAnalysis: CodeGuardAnalysis
    public let binaryAnalysis: BinaryContentAnalysis
    public let linkCleaning: URLCleaningResult
    public let identifierAnalysis: OpaqueIdentifierAnalysis
    public let scamAnalysis: ScamAttemptAnalysis
    public let recentPatternReport: PatternReport
    public let updatedPatternTexts: [String]
    public let addedPatternSample: Bool

    public init(
        limitation: TextAnalysisLimitation? = nil,
        inspection: TextInspection,
        covertChannelReport: CovertTextChannelReport,
        codeAnalysis: CodeGuardAnalysis,
        binaryAnalysis: BinaryContentAnalysis,
        linkCleaning: URLCleaningResult,
        identifierAnalysis: OpaqueIdentifierAnalysis,
        scamAnalysis: ScamAttemptAnalysis,
        recentPatternReport: PatternReport,
        updatedPatternTexts: [String],
        addedPatternSample: Bool
    ) {
        self.limitation = limitation
        self.inspection = inspection
        self.covertChannelReport = covertChannelReport
        self.codeAnalysis = codeAnalysis
        self.binaryAnalysis = binaryAnalysis
        self.linkCleaning = linkCleaning
        self.identifierAnalysis = identifierAnalysis
        self.scamAnalysis = scamAnalysis
        self.recentPatternReport = recentPatternReport
        self.updatedPatternTexts = updatedPatternTexts
        self.addedPatternSample = addedPatternSample
    }

    public var containsHiddenUnicode: Bool {
        !inspection.isClean || covertChannelReport.hasSuspiciousChannel
    }
    public var hiddenTextFindingCount: Int {
        inspection.totalActionableFindingCount + covertChannelReport.findings.count
    }
    public var hiddenTextRiskLevel: HiddenElementRiskLevel? {
        [inspection.highestRiskLevel, covertChannelReport.highestRiskLevel]
            .compactMap { $0 }
            .max { $0.rawValue < $1.rawValue }
    }
    public var containsCodeRisk: Bool { codeAnalysis.hasRisks }
    public var containsBinaryContent: Bool { binaryAnalysis.isDetected }
    public var containsTrackedLinks: Bool { linkCleaning.hasTrackingRisk }
    public var containsOpaqueIdentifiers: Bool { identifierAnalysis.containsIdentifiers }
    public var containsPotentialScam: Bool { scamAnalysis.isPotentialScam }
    public var containsRecentPattern: Bool {
        addedPatternSample
            && recentPatternReport.sampleCount == 3
            && recentPatternReport.hasSuspiciousRepetition
    }

    public var cleanReceiptAlertCount: Int {
        (limitation == nil ? 0 : 1)
            + hiddenTextFindingCount
            + codeAnalysis.findings.count
            + (binaryAnalysis.isDetected ? 1 : 0)
            + linkCleaning.linksFlagged
            + identifierAnalysis.findings.count
            + (scamAnalysis.isPotentialScam ? scamAnalysis.signals.count : 0)
    }

    public var cleanReceiptPriority: ClipboardAlertPriority {
        if limitation != nil { return .elevated }
        return ClipboardProtectionAnalyzer.alertPriority(
            hiddenUnicodeRisk: hiddenTextRiskLevel,
            codeRisk: codeAnalysis.highestRiskLevel,
            scamThreat: scamAnalysis.isPotentialScam ? scamAnalysis.threatLevel : nil,
            hasElevatedSignal: linkCleaning.hasTrackingRisk
        )
    }
}

public enum PatternSampleRejectionReason: Sendable, Equatable {
    case emptyOrTooShort
    case duplicate
    case inputTooLarge
}

public struct PatternSampleAppendResult: Sendable, Equatable {
    public let texts: [String]
    public let added: Bool
    public let rejectionReason: PatternSampleRejectionReason?

    public init(
        texts: [String],
        added: Bool,
        rejectionReason: PatternSampleRejectionReason?
    ) {
        self.texts = texts
        self.added = added
        self.rejectionReason = rejectionReason
    }
}

public enum ClipboardProtectionAnalyzer {
    public static let minimumPatternSampleLength = 30
    public static let maximumPatternSamples = 10
    public static let alertPatternWindow = 3

    public static func alertPriority(
        hiddenUnicodeRisk: HiddenElementRiskLevel?,
        codeRisk: HiddenElementRiskLevel?,
        scamThreat: ScamThreatLevel? = nil,
        hasElevatedSignal: Bool = false
    ) -> ClipboardAlertPriority {
        if hiddenUnicodeRisk == .high || codeRisk == .high || scamThreat == .high {
            return .high
        }
        if hiddenUnicodeRisk == .medium
            || codeRisk == .medium
            || scamThreat == .suspicious
            || hasElevatedSignal {
            return .elevated
        }
        return .standard
    }

    /// Performs the deterministic part of active clipboard protection. The
    /// caller remains responsible for reading or replacing the pasteboard.
    public static func analyze(
        _ text: String,
        recentPatternTexts: [String],
        customRules: [CustomURLRule] = []
    ) -> ClipboardProtectionAnalysis {
        if let limitation = TextAnalysisBudget.limitation(for: text) {
            let boundedTexts = boundedPatternTexts(recentPatternTexts)
            return ClipboardProtectionAnalysis(
                limitation: limitation,
                inspection: HiddenTextAnalyzer.inspect(""),
                covertChannelReport: CovertTextChannelAnalyzer.analyze(""),
                codeAnalysis: CodeGuardAnalyzer.analyze(""),
                binaryAnalysis: BinaryContentDetector.analyze(""),
                linkCleaning: URLTrackerCleaner.cleanLinks(in: "", customRules: customRules),
                identifierAnalysis: OpaqueIdentifierAnalyzer.analyze(""),
                scamAnalysis: ScamAttemptDetector.analyze(""),
                recentPatternReport: PatternAnalyzer.analyze(
                    Array(boundedTexts.suffix(alertPatternWindow))
                ),
                updatedPatternTexts: boundedTexts,
                addedPatternSample: false
            )
        }
        let sampleUpdate = appendingPatternSample(text, to: recentPatternTexts)
        let recentWindow = Array(sampleUpdate.texts.suffix(alertPatternWindow))
        let safelyCleanedText = TextCleaner.clean(text, mode: .safe).text

        return ClipboardProtectionAnalysis(
            inspection: HiddenTextAnalyzer.inspect(text),
            covertChannelReport: CovertTextChannelAnalyzer.analyze(text),
            codeAnalysis: CodeGuardAnalyzer.analyze(text),
            binaryAnalysis: BinaryContentDetector.analyze(text),
            linkCleaning: URLTrackerCleaner.cleanLinks(
                in: safelyCleanedText,
                customRules: customRules
            ),
            identifierAnalysis: OpaqueIdentifierAnalyzer.analyze(text),
            scamAnalysis: ScamAttemptDetector.analyze(text),
            recentPatternReport: PatternAnalyzer.analyze(recentWindow),
            updatedPatternTexts: sampleUpdate.texts,
            addedPatternSample: sampleUpdate.added
        )
    }

    public static func appendingPatternSample(
        _ text: String,
        to existingTexts: [String]
    ) -> PatternSampleAppendResult {
        var texts = boundedPatternTexts(existingTexts)
        guard TextAnalysisBudget.limitation(
            for: text,
            maximumUTF8Bytes: TextAnalysisBudget.maximumPatternSampleUTF8Bytes
        ) == nil else {
            return PatternSampleAppendResult(
                texts: texts,
                added: false,
                rejectionReason: .inputTooLarge
            )
        }
        let sample = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sample.count >= minimumPatternSampleLength else {
            return PatternSampleAppendResult(
                texts: texts,
                added: false,
                rejectionReason: .emptyOrTooShort
            )
        }
        guard texts.last != sample else {
            return PatternSampleAppendResult(
                texts: texts,
                added: false,
                rejectionReason: .duplicate
            )
        }

        texts.append(sample)
        texts = boundedPatternTexts(texts)
        return PatternSampleAppendResult(
            texts: texts,
            added: true,
            rejectionReason: nil
        )
    }

    private static func boundedPatternTexts(_ existingTexts: [String]) -> [String] {
        var texts = Array(existingTexts.suffix(maximumPatternSamples)).filter {
            TextAnalysisBudget.limitation(
                for: $0,
                maximumUTF8Bytes: TextAnalysisBudget.maximumPatternSampleUTF8Bytes
            ) == nil
        }
        var totalBytes = texts.reduce(0) { partial, text in
            partial + text.utf8.count
        }
        while totalBytes > TextAnalysisBudget.maximumPatternMemoryUTF8Bytes,
              let first = texts.first {
            totalBytes -= first.utf8.count
            texts.removeFirst()
        }
        return texts
    }
}
