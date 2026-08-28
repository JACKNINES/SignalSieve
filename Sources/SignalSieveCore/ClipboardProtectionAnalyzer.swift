// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum ClipboardAlertPriority: Sendable, Equatable {
    case standard
    case elevated
    case high
}

public struct ClipboardProtectionAnalysis: Sendable, Equatable {
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
        hiddenTextFindingCount
            + codeAnalysis.findings.count
            + (binaryAnalysis.isDetected ? 1 : 0)
            + linkCleaning.linksFlagged
            + identifierAnalysis.findings.count
            + (scamAnalysis.isPotentialScam ? scamAnalysis.signals.count : 0)
    }

    public var cleanReceiptPriority: ClipboardAlertPriority {
        ClipboardProtectionAnalyzer.alertPriority(
            hiddenUnicodeRisk: hiddenTextRiskLevel,
            codeRisk: codeAnalysis.highestRiskLevel,
            scamThreat: scamAnalysis.isPotentialScam ? scamAnalysis.threatLevel : nil,
            hasElevatedSignal: linkCleaning.hasTrackingRisk
        )
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
    ) -> (texts: [String], added: Bool) {
        let sample = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sample.count >= minimumPatternSampleLength, existingTexts.last != sample else {
            return (existingTexts, false)
        }

        var texts = existingTexts
        texts.append(sample)
        if texts.count > maximumPatternSamples {
            texts.removeFirst(texts.count - maximumPatternSamples)
        }
        return (texts, true)
    }
}
