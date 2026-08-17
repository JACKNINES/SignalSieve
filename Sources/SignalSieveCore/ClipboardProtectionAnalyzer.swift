// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum ClipboardAlertPriority: Sendable, Equatable {
    case standard
    case high
}

public struct ClipboardProtectionAnalysis: Sendable, Equatable {
    public let inspection: TextInspection
    public let codeAnalysis: CodeGuardAnalysis
    public let binaryAnalysis: BinaryContentAnalysis
    public let linkCleaning: URLCleaningResult
    public let recentPatternReport: PatternReport
    public let updatedPatternTexts: [String]
    public let addedPatternSample: Bool

    public init(
        inspection: TextInspection,
        codeAnalysis: CodeGuardAnalysis,
        binaryAnalysis: BinaryContentAnalysis,
        linkCleaning: URLCleaningResult,
        recentPatternReport: PatternReport,
        updatedPatternTexts: [String],
        addedPatternSample: Bool
    ) {
        self.inspection = inspection
        self.codeAnalysis = codeAnalysis
        self.binaryAnalysis = binaryAnalysis
        self.linkCleaning = linkCleaning
        self.recentPatternReport = recentPatternReport
        self.updatedPatternTexts = updatedPatternTexts
        self.addedPatternSample = addedPatternSample
    }

    public var containsHiddenUnicode: Bool { !inspection.isClean }
    public var containsCodeRisk: Bool { codeAnalysis.hasRisks }
    public var containsBinaryContent: Bool { binaryAnalysis.isDetected }
    public var containsTrackedLinks: Bool { linkCleaning.linksChanged > 0 }
    public var containsRecentPattern: Bool {
        addedPatternSample
            && recentPatternReport.sampleCount == 3
            && recentPatternReport.hasSuspiciousRepetition
    }
}

public enum ClipboardProtectionAnalyzer {
    public static let minimumPatternSampleLength = 30
    public static let maximumPatternSamples = 10
    public static let alertPatternWindow = 3

    public static func alertPriority(
        hiddenUnicodeRisk: HiddenElementRiskLevel?,
        codeRisk: HiddenElementRiskLevel?
    ) -> ClipboardAlertPriority {
        hiddenUnicodeRisk == .high || codeRisk == .high ? .high : .standard
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

        return ClipboardProtectionAnalysis(
            inspection: HiddenTextAnalyzer.inspect(text),
            codeAnalysis: CodeGuardAnalyzer.analyze(text),
            binaryAnalysis: BinaryContentDetector.analyze(text),
            linkCleaning: URLTrackerCleaner.cleanLinks(in: text, customRules: customRules),
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
