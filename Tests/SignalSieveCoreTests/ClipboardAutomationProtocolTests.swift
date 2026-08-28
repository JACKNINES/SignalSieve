// SPDX-License-Identifier: MPL-2.0
import AppKit
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
    #expect(ClipboardAutomationProtocol.persistedOrReviewAll("visual-transfer") == .visualTransfer)
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

@Test("Clean Receipt quarantines a residual red candidate instead of treating cleaning as success")
func cleanReceiptQuarantinesResidualRedCandidate() {
    let original = "AppIe. El lPhone 15 Plus en modo perdido fue ubicado hoy a las 11:47 Hrs. Ver ubicación: https://securityios.us/tvDb\u{200B}"
    let transform = ClipboardAutomationPolicy.transform(
        original,
        using: .safeClean,
        isLikelyCode: false,
        hasNonTextRepresentation: false,
        isPrivacySensitive: false
    )
    let originalAnalysis = ClipboardProtectionAnalyzer.analyze(
        original,
        recentPatternTexts: []
    )
    let candidateAnalysis = ClipboardProtectionAnalyzer.analyze(
        transform.text,
        recentPatternTexts: []
    )
    let audit = ClipboardAutomaticCleaningAudit(
        mode: .safe,
        didWriteCleanedText: false,
        removedElementCount: transform.removedCount,
        replacedElementCount: transform.replacedCount,
        originalAlertCount: originalAnalysis.cleanReceiptAlertCount,
        remainingAlertCount: candidateAnalysis.cleanReceiptAlertCount,
        originalPriority: originalAnalysis.cleanReceiptPriority,
        remainingPriority: candidateAnalysis.cleanReceiptPriority
    )

    #expect(transform.didChange)
    #expect(originalAnalysis.cleanReceiptPriority == .high)
    #expect(candidateAnalysis.cleanReceiptPriority == .high)
    #expect(ClipboardAutomationPolicy.shouldQuarantineAutomaticReplacement(
        candidatePriority: candidateAnalysis.cleanReceiptPriority,
        skipReason: transform.skipReason
    ))
    #expect(audit.receipt.verdict == .riskRemainsDoNotShare)
    #expect(!audit.receipt.wasAutomaticCleaningSkipped)
}

@Test("Clean Receipt allows successfully removed red text risks but keeps source review warning")
func cleanReceiptKeepsSourceWarningForSuccessfulRedCleaning() {
    let original = "invoice total\u{202E}cod.exe"
    let transform = ClipboardAutomationPolicy.transform(
        original,
        using: .safeClean,
        isLikelyCode: false,
        hasNonTextRepresentation: false,
        isPrivacySensitive: false
    )
    let originalAnalysis = ClipboardProtectionAnalyzer.analyze(
        original,
        recentPatternTexts: []
    )
    let candidateAnalysis = ClipboardProtectionAnalyzer.analyze(
        transform.text,
        recentPatternTexts: []
    )
    let audit = ClipboardAutomaticCleaningAudit(
        mode: .safe,
        didWriteCleanedText: true,
        removedElementCount: transform.removedCount,
        replacedElementCount: transform.replacedCount,
        originalAlertCount: originalAnalysis.cleanReceiptAlertCount,
        remainingAlertCount: candidateAnalysis.cleanReceiptAlertCount,
        originalPriority: originalAnalysis.cleanReceiptPriority,
        remainingPriority: candidateAnalysis.cleanReceiptPriority
    )

    #expect(transform.didChange)
    #expect(originalAnalysis.cleanReceiptPriority == .high)
    #expect(candidateAnalysis.cleanReceiptPriority != .high)
    #expect(!ClipboardAutomationPolicy.shouldQuarantineAutomaticReplacement(
        candidatePriority: candidateAnalysis.cleanReceiptPriority,
        skipReason: transform.skipReason
    ))
    #expect(audit.redRiskWasRemoved)
    #expect(audit.receipt.verdict == .cleanedSourceNeedsReview)
}

@Test("Clean Receipt records skipped cleaning without copied content")
func cleanReceiptRecordsSkippedCleaningWithoutContent() {
    let result = ClipboardAutomationPolicy.transform(
        "let value = \"payload\u{200B}\"",
        using: .strictClean,
        isLikelyCode: true,
        hasNonTextRepresentation: false,
        isPrivacySensitive: false
    )
    let audit = ClipboardAutomaticCleaningAudit(
        mode: .strict,
        didWriteCleanedText: false,
        removedElementCount: result.removedCount,
        replacedElementCount: result.replacedCount,
        originalAlertCount: 1,
        remainingAlertCount: 1,
        originalPriority: .high,
        remainingPriority: .high,
        skipReason: result.skipReason
    )

    #expect(result.skipReason == .sourceCode)
    #expect(audit.receipt.wasAutomaticCleaningSkipped)
    #expect(audit.receipt.verdict == .riskRemainsDoNotShare)
    #expect(!audit.receipt.reason.contains("payload"))
}

@Test("Clean Receipt never labels unresolved binary content as cleared")
func cleanReceiptKeepsBinaryContentInReview() {
    let analysis = ClipboardProtectionAnalyzer.analyze(
        "SGVsbG8sIFNpZ25hbCBTaWV2ZSE=",
        recentPatternTexts: []
    )
    let audit = ClipboardAutomaticCleaningAudit(
        mode: .safe,
        didWriteCleanedText: false,
        removedElementCount: 0,
        replacedElementCount: 0,
        originalAlertCount: analysis.cleanReceiptAlertCount,
        remainingAlertCount: analysis.cleanReceiptAlertCount,
        originalPriority: analysis.cleanReceiptPriority,
        remainingPriority: analysis.cleanReceiptPriority
    )

    #expect(analysis.binaryAnalysis.isDetected)
    #expect(analysis.cleanReceiptAlertCount > 0)
    #expect(audit.receipt.verdict == .cleanedSourceNeedsReview)
}

@Test("A skipped clean without red risk remains review-only")
func cleanReceiptDoesNotPromoteEverySkipToRed() {
    let audit = ClipboardAutomaticCleaningAudit(
        selectedProtocol: .visualTransfer,
        didWriteCleanedText: false,
        removedElementCount: 0,
        replacedElementCount: 0,
        originalAlertCount: 0,
        remainingAlertCount: 0,
        originalPriority: .standard,
        remainingPriority: .standard,
        skipReason: .visualTransferFailed
    )

    #expect(audit.mode == nil)
    #expect(audit.receipt.selectedProtocol == .visualTransfer)
    #expect(audit.receipt.verdict == .cleanedSourceNeedsReview)
    #expect(!audit.redRiskRemains)
}

@Test("A high-risk OCR candidate keeps mandatory red receipt priority")
func cleanReceiptTreatsIntroducedHighRiskAsRed() {
    let audit = ClipboardAutomaticCleaningAudit(
        selectedProtocol: .visualTransfer,
        didWriteCleanedText: false,
        removedElementCount: 0,
        replacedElementCount: 0,
        originalAlertCount: 0,
        remainingAlertCount: 1,
        originalPriority: .standard,
        remainingPriority: .high
    )

    #expect(audit.redRiskRemains)
    #expect(audit.receipt.verdict == .riskRemainsDoNotShare)
}

@MainActor
@Test("Stale pasteboard state blocks restoration writes")
func stalePasteboardStateBlocksRestorationWrites() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }

    ClipboardPlainTextWriter.write("clean result", to: pasteboard)
    let cleanChangeCount = pasteboard.changeCount
    ClipboardPlainTextWriter.write("new user copy", to: pasteboard)

    #expect(!ClipboardPlainTextWriter.replace(
        on: pasteboard,
        expectedChangeCount: cleanChangeCount,
        expectedText: "clean result",
        replacement: "original text"
    ))
    #expect(pasteboard.string(forType: .string) == "new user copy")
}

@MainActor
@Test("Matching pasteboard snapshot permits one guarded replacement")
func matchingPasteboardSnapshotPermitsGuardedReplacement() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }

    ClipboardPlainTextWriter.write("clean result", to: pasteboard)
    let snapshot = try #require(ClipboardPlainTextWriter.snapshot(on: pasteboard))

    #expect(ClipboardPlainTextWriter.matches(snapshot, on: pasteboard))
    #expect(ClipboardPlainTextWriter.replace(
        on: pasteboard,
        matching: snapshot,
        replacement: "original text"
    ))
    #expect(pasteboard.string(forType: .string) == "original text")
    #expect(!ClipboardPlainTextWriter.matches(snapshot, on: pasteboard))
}

@Test("Privacy-sensitive automatic cleaning is excluded from clean-result retention")
func privacySensitiveCleaningIsExcludedFromCleanResultRetention() throws {
    let result = ClipboardAutomationPolicy.transform(
        "private\u{200B}memo",
        using: .safeClean,
        isLikelyCode: false,
        hasNonTextRepresentation: false,
        isPrivacySensitive: true
    )
    let audit = ClipboardAutomaticCleaningAudit(
        mode: .safe,
        didWriteCleanedText: false,
        removedElementCount: result.removedCount,
        replacedElementCount: result.replacedCount,
        originalAlertCount: 1,
        remainingAlertCount: 1,
        originalPriority: .high,
        remainingPriority: .high,
        skipReason: result.skipReason
    )
    let entry = ClipboardHistory.makeEntry(
        text: "private\u{200B}memo",
        sourceApplicationName: "Synthetic Test App",
        sourceBundleIdentifier: "test.synthetic",
        hiddenUnicodeCount: 1,
        codeRiskCount: 0,
        trackedLinkCount: 0,
        binaryKind: nil,
        wasAutomaticallyCleaned: false,
        automaticCleaningAudit: audit,
        cleanedText: nil,
        cleanedPasteboardChangeCount: nil
    )

    let retainedAudit = try #require(entry.automaticCleaningAudit)
    #expect(result.skipReason == .privacySensitiveClipboard)
    #expect(result.text == "private\u{200B}memo")
    #expect(retainedAudit.receipt.wasAutomaticCleaningSkipped)
    #expect(entry.cleanedText == nil)
    #expect(entry.cleanedPasteboardChangeCount == nil)
}

@Test("Clean Receipt keeps reason text bounded and single-line")
func cleanReceiptBoundsReasonText() {
    let receipt = ClipboardCleanReceipt(
        selectedProtocol: .strictClean,
        verdict: .riskRemainsDoNotShare,
        originalAlertCount: 3,
        originalPriority: .high,
        removedElementCount: 1,
        replacedElementCount: 0,
        remainingAlertCount: 2,
        remainingPriority: .high,
        wasAutomaticCleaningSkipped: false,
        reason: String(repeating: "residual\n", count: 40)
    )

    #expect(receipt.reason.count <= ClipboardCleanReceipt.maximumReasonCharacters)
    #expect(!receipt.reason.contains("\n"))
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

@Test("Strict Clean flattens rich clipboard representations even when visible text is unchanged")
func strictClipboardAutomationFlattensRichText() {
    let result = ClipboardAutomationPolicy.transform(
        "Guarda .build/vendor entre corridas",
        using: .strictClean,
        isLikelyCode: false,
        hasNonTextRepresentation: false,
        isPrivacySensitive: false
    )

    #expect(!result.didChange)
    #expect(ClipboardAutomationPolicy.shouldFlattenRichText(
        using: .strictClean,
        hasRichTextRepresentation: true,
        skipReason: result.skipReason
    ))
    #expect(!ClipboardAutomationPolicy.shouldFlattenRichText(
        using: .safeClean,
        hasRichTextRepresentation: true,
        skipReason: nil
    ))
    #expect(!ClipboardAutomationPolicy.shouldFlattenRichText(
        using: .strictClean,
        hasRichTextRepresentation: true,
        skipReason: .privacySensitiveClipboard
    ))
}

@Test("Automatic Visual Transfer uses bounded eligibility and protected-value validation")
func automaticVisualTransferUsesSafetyGates() {
    let eligible = ClipboardAutomationPolicy.transform(
        "Ordinary prose for local OCR.",
        using: .visualTransfer,
        isLikelyCode: false,
        hasNonTextRepresentation: false,
        isPrivacySensitive: false
    )
    #expect(eligible.skipReason == nil)
    #expect(!eligible.didChange)

    let oversized = String(
        repeating: "a",
        count: ClipboardAutomationPolicy.maximumAutomaticVisualTransferCharacterCount + 1
    )
    #expect(ClipboardAutomationPolicy.skipReason(
        for: .visualTransfer,
        text: oversized,
        isLikelyCode: false,
        hasNonTextRepresentation: false,
        isPrivacySensitive: false
    ) == .inputTooLarge)
    #expect(ClipboardAutomationPolicy.skipReason(
        for: .visualTransfer,
        text: "let value = 1",
        isLikelyCode: true,
        hasNonTextRepresentation: false,
        isPrivacySensitive: false
    ) == .sourceCode)

    #expect(ClipboardAutomationPolicy.acceptsAutomaticVisualTransfer(
        original: "Meet me tomorrow.",
        candidate: "Meet me tomorrow."
    ))
    #expect(!ClipboardAutomationPolicy.acceptsAutomaticVisualTransfer(
        original: "Open https://example.com at 11:47.",
        candidate: "Open https://examp1e.com at 11:47."
    ))
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
