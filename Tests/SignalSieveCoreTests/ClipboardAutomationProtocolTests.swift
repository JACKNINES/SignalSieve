// SPDX-License-Identifier: MPL-2.0
import SignalSieveCore
import Testing

@Test("Clipboard Protocol restores persisted values and fails closed to review-all")
func restoresClipboardAutomationProtocol() {
    #expect(ClipboardAutomationProtocol.persistedOrReviewAll(nil) == .reviewAll)
    #expect(ClipboardAutomationProtocol.persistedOrReviewAll("") == .reviewAll)
    #expect(ClipboardAutomationProtocol.persistedOrReviewAll("unknown") == .reviewAll)
    #expect(ClipboardAutomationProtocol.persistedOrReviewAll("high-risk-only") == .reviewAll)
    #expect(ClipboardAutomationProtocol.persistedOrReviewAll("safe-clean") == .safeClean)
    #expect(ClipboardAutomationProtocol.persistedOrReviewAll("strict-clean") == .strictClean)
}

@Test("Alert visibility supports all, orange-and-red, and mandatory-red tiers")
func limitsClipboardAlertVisibilityPreference() {
    #expect(ClipboardAlertVisibility.persistedOrShowAll(nil) == .showAll)
    #expect(ClipboardAlertVisibility.persistedOrShowAll("unknown") == .showAll)
    #expect(ClipboardAlertVisibility.persistedOrShowAll(
        nil,
        legacyHidesGreenAndYellow: true
    ) == .hideGreenAndYellow)
    #expect(ClipboardAlertVisibility.persistedOrShowAll("red-only") == .redOnly)

    #expect(ClipboardAlertVisibilityPolicy.shouldPresent(.standard, visibility: .showAll))
    #expect(ClipboardAlertVisibilityPolicy.shouldPresent(.elevated, visibility: .showAll))
    #expect(ClipboardAlertVisibilityPolicy.shouldPresent(.high, visibility: .showAll))

    #expect(!ClipboardAlertVisibilityPolicy.shouldPresent(
        .standard,
        visibility: .hideGreenAndYellow
    ))
    #expect(ClipboardAlertVisibilityPolicy.shouldPresent(
        .elevated,
        visibility: .hideGreenAndYellow
    ))
    #expect(ClipboardAlertVisibilityPolicy.shouldPresent(
        .high,
        visibility: .hideGreenAndYellow
    ))

    #expect(!ClipboardAlertVisibilityPolicy.shouldPresent(.standard, visibility: .redOnly))
    #expect(!ClipboardAlertVisibilityPolicy.shouldPresent(.elevated, visibility: .redOnly))
    #expect(ClipboardAlertVisibilityPolicy.shouldPresent(.high, visibility: .redOnly))
}

@Test("Red findings override disabled warning categories")
func keepsRedFindingsMandatoryAcrossCategoryPreferences() {
    #expect(!ClipboardAlertVisibilityPolicy.shouldIncludeCategory(
        isEnabled: false,
        highestRisk: .medium
    ))
    #expect(ClipboardAlertVisibilityPolicy.shouldIncludeCategory(
        isEnabled: false,
        highestRisk: .high
    ))
    #expect(!ClipboardAlertVisibilityPolicy.shouldIncludeScamCategory(
        isEnabled: false,
        threatLevel: .suspicious
    ))
    #expect(ClipboardAlertVisibilityPolicy.shouldIncludeScamCategory(
        isEnabled: false,
        threatLevel: .high
    ))
}

@Test("Automatic cleaning audit distinguishes removed and remaining alerts")
func auditsAutomaticCleaningOutcomes() {
    let cleaned = ClipboardAutomaticCleaningAudit(
        mode: .safe,
        didWriteCleanedText: true,
        removedElementCount: 2,
        replacedElementCount: 0,
        originalAlertCount: 2,
        remainingAlertCount: 0,
        originalPriority: .high,
        remainingPriority: .standard
    )
    #expect(cleaned.outcome == .cleanedAllDetectedAlerts)
    #expect(cleaned.redRiskWasRemoved)
    #expect(!cleaned.redRiskRemains)

    let partial = ClipboardAutomaticCleaningAudit(
        mode: .strict,
        didWriteCleanedText: true,
        removedElementCount: 1,
        replacedElementCount: 0,
        originalAlertCount: 3,
        remainingAlertCount: 2,
        originalPriority: .high,
        remainingPriority: .high
    )
    #expect(partial.outcome == .cleanedSomeDetectedAlerts)
    #expect(!partial.redRiskWasRemoved)
    #expect(partial.redRiskRemains)

    let skipped = ClipboardAutomaticCleaningAudit(
        mode: .safe,
        didWriteCleanedText: false,
        removedElementCount: 0,
        replacedElementCount: 0,
        originalAlertCount: 1,
        remainingAlertCount: 1,
        originalPriority: .high,
        remainingPriority: .high,
        skipReason: .sourceCode
    )
    #expect(skipped.outcome == .skipped)
    #expect(skipped.redRiskRemains)
}

@Test("Automatic Safe Clean preserves contextual Unicode and removes standalone carriers")
func safeClipboardAutomationIsContextual() {
    let family = "👨\u{200D}👩\u{200D}👧"
    let source = "Family: \(family) hidden\u{200B}payload"
    let result = ClipboardAutomationPolicy.transform(
        source,
        using: .safeClean,
        isLikelyCode: false,
        hasNonTextRepresentation: false,
        isPrivacySensitive: false
    )

    #expect(result.didChange)
    #expect(result.text == "Family: \(family) hiddenpayload")
    #expect(result.skipReason == nil)
}

@Test("Automatic Strict Clean applies compatibility normalization")
func strictClipboardAutomationNormalizesCompatibilityText() {
    let result = ClipboardAutomationPolicy.transform(
        "Ｆｕｌｌｗｉｄｔｈ",
        using: .strictClean,
        isLikelyCode: false,
        hasNonTextRepresentation: false,
        isPrivacySensitive: false
    )

    #expect(result.didChange)
    #expect(result.text == "Fullwidth")
}

@Test("Automatic cleaning refuses code, non-text, and privacy-sensitive copies")
func automaticClipboardCleaningHonorsSafetyBoundaries() {
    let cases: [(Bool, Bool, Bool, ClipboardAutomationSkipReason)] = [
        (true, false, false, .sourceCode),
        (false, true, false, .nonTextRepresentation),
        (false, false, true, .privacySensitiveClipboard)
    ]

    for (isCode, hasNonText, isPrivate, expectedReason) in cases {
        let result = ClipboardAutomationPolicy.transform(
            "secret\u{200B}text",
            using: .strictClean,
            isLikelyCode: isCode,
            hasNonTextRepresentation: hasNonText,
            isPrivacySensitive: isPrivate
        )
        #expect(!result.didChange)
        #expect(result.text == "secret\u{200B}text")
        #expect(result.skipReason == expectedReason)
    }
}

@Test("Non-automatic protocols never rewrite clipboard text")
func reviewProtocolsDoNotRewriteText() {
    let result = ClipboardAutomationPolicy.transform(
        "hidden\u{200B}text",
        using: .reviewAll,
        isLikelyCode: false,
        hasNonTextRepresentation: false,
        isPrivacySensitive: false
    )
    #expect(!result.didChange)
    #expect(result.text == "hidden\u{200B}text")
    #expect(result.skipReason == nil)
}
