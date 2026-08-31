// SPDX-License-Identifier: MPL-2.0
import Foundation

public struct ManualInputInspectionAnalysis: Sendable, Equatable {
    public let limitation: TextAnalysisLimitation?
    public let inspection: TextInspection
    public let covertChannelReport: CovertTextChannelReport
    public let codeAnalysis: CodeGuardAnalysis
    public let binaryAnalysis: BinaryContentAnalysis
    public let identifierAnalysis: OpaqueIdentifierAnalysis
    public let scamAnalysis: ScamAttemptAnalysis
    public let adaptiveAnalysis: AdaptiveCopyAnalysis
    public let linkCleaningReport: URLCleaningResult
    public let revealedFragments: [RevealedInvisibleFragment]

    public init(
        limitation: TextAnalysisLimitation? = nil,
        inspection: TextInspection,
        covertChannelReport: CovertTextChannelReport,
        codeAnalysis: CodeGuardAnalysis,
        binaryAnalysis: BinaryContentAnalysis,
        identifierAnalysis: OpaqueIdentifierAnalysis,
        scamAnalysis: ScamAttemptAnalysis,
        adaptiveAnalysis: AdaptiveCopyAnalysis,
        linkCleaningReport: URLCleaningResult,
        revealedFragments: [RevealedInvisibleFragment]
    ) {
        self.limitation = limitation
        self.inspection = inspection
        self.covertChannelReport = covertChannelReport
        self.codeAnalysis = codeAnalysis
        self.binaryAnalysis = binaryAnalysis
        self.identifierAnalysis = identifierAnalysis
        self.scamAnalysis = scamAnalysis
        self.adaptiveAnalysis = adaptiveAnalysis
        self.linkCleaningReport = linkCleaningReport
        self.revealedFragments = revealedFragments
    }
}

public enum ManualInputInspectionAnalyzer {
    public static func analyze(
        _ text: String,
        customRules: [CustomURLRule] = [],
        adaptiveModel: AdaptiveCopyModel,
        isAdaptiveModelEnabled: Bool
    ) -> ManualInputInspectionAnalysis {
        if let limitation = TextAnalysisBudget.limitation(for: text) {
            return limitedAnalysis(
                limitation,
                customRules: customRules,
                adaptiveSampleCount: adaptiveModel.sampleCount
            )
        }

        return ManualInputInspectionAnalysis(
            inspection: HiddenTextAnalyzer.inspect(text),
            covertChannelReport: CovertTextChannelAnalyzer.analyze(text),
            codeAnalysis: CodeGuardAnalyzer.analyze(text),
            binaryAnalysis: BinaryContentDetector.analyze(text),
            identifierAnalysis: OpaqueIdentifierAnalyzer.analyze(text),
            scamAnalysis: ScamAttemptDetector.analyze(text),
            adaptiveAnalysis: isAdaptiveModelEnabled
                ? adaptiveModel.assess(text)
                : disabledAdaptiveAnalysis(sampleCount: adaptiveModel.sampleCount),
            linkCleaningReport: URLTrackerCleaner.cleanLinks(in: text, customRules: customRules),
            revealedFragments: InvisibleFragmentRevealer.reveal(in: text)
        )
    }

    public static func limitedAnalysis(
        _ limitation: TextAnalysisLimitation,
        customRules: [CustomURLRule] = [],
        adaptiveSampleCount: Int
    ) -> ManualInputInspectionAnalysis {
        ManualInputInspectionAnalysis(
            limitation: limitation,
            inspection: emptyInspection,
            covertChannelReport: CovertTextChannelReport(findings: []),
            codeAnalysis: emptyCodeAnalysis,
            binaryAnalysis: BinaryContentAnalysis(kind: nil),
            identifierAnalysis: OpaqueIdentifierAnalysis(findings: []),
            scamAnalysis: ScamAttemptAnalysis(score: 0, threatLevel: .review, signals: [], inspectedHosts: []),
            adaptiveAnalysis: disabledAdaptiveAnalysis(sampleCount: adaptiveSampleCount),
            linkCleaningReport: URLTrackerCleaner.cleanLinks(in: "", customRules: customRules),
            revealedFragments: []
        )
    }

    public static func disabledAdaptiveAnalysis(sampleCount: Int) -> AdaptiveCopyAnalysis {
        AdaptiveCopyAnalysis(
            sampleCountBeforeLearning: sampleCount,
            anomalyScore: 0,
            deviations: [],
            wasEligibleForLearning: false
        )
    }

    private static var emptyInspection: TextInspection {
        TextInspection(
            scalarCount: 0,
            utf16Count: 0,
            findings: [],
            changesUnderNFC: false,
            changesUnderNFKC: false
        )
    }

    private static var emptyCodeAnalysis: CodeGuardAnalysis {
        CodeGuardAnalysis(
            languageDetection: CodeLanguageDetection(
                isLikelyCode: false,
                primary: nil,
                alternatives: [],
                confidence: .none,
                evidenceScore: 0
            ),
            findings: []
        )
    }
}
