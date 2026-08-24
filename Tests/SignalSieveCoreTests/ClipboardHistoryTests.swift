// SPDX-License-Identifier: MPL-2.0
import Foundation
import SignalSieveCore
import Testing

@Test("Clipboard history is newest-first and bounded")
func boundsClipboardHistory() {
    var entries: [ClipboardHistoryEntry] = []
    for index in 0..<(ClipboardHistory.maximumEntries + 8) {
        let entry = ClipboardHistory.makeEntry(
            text: "copy \(index)",
            capturedAt: Date(timeIntervalSince1970: TimeInterval(index)),
            sourceApplicationName: "Test App",
            sourceBundleIdentifier: "test.app",
            hiddenUnicodeCount: 0,
            codeRiskCount: 0,
            trackedLinkCount: 0,
            binaryKind: nil,
            wasAutomaticallyCleaned: false
        )
        entries = ClipboardHistory.appending(entry, to: entries)
    }

    #expect(entries.count == ClipboardHistory.maximumEntries)
    #expect(entries.first?.text == "copy 57")
    #expect(entries.last?.text == "copy 8")
}

@Test("Clipboard history truncates stored content and reveals invisible preview characters")
func protectsClipboardHistoryMemoryAndPreview() {
    let text = String(repeating: "a", count: ClipboardHistory.maximumStoredCharacters)
        + "\u{200B}tail"
    let entry = ClipboardHistory.makeEntry(
        text: text,
        sourceApplicationName: "Editor",
        sourceBundleIdentifier: "test.editor",
        hiddenUnicodeCount: 1,
        codeRiskCount: 0,
        trackedLinkCount: 0,
        binaryKind: nil,
        wasAutomaticallyCleaned: false
    )

    #expect(entry.isTruncated)
    #expect(entry.text.count == ClipboardHistory.maximumStoredCharacters)
    #expect(entry.originalCharacterCount == text.count)

    let preview = ClipboardHistory.visiblePreview("alpha\u{200B}beta")
    #expect(preview == "alpha⟦U+200B⟧beta")
    #expect(!preview.contains("\u{200B}"))
}

@Test("Clipboard history retains automatic cleaning reanalysis evidence")
func retainsAutomaticCleaningAudit() throws {
    let audit = ClipboardAutomaticCleaningAudit(
        mode: .strict,
        didWriteCleanedText: true,
        removedElementCount: 1,
        replacedElementCount: 0,
        originalAlertCount: 1,
        remainingAlertCount: 0,
        originalPriority: .high,
        remainingPriority: .standard
    )
    let entry = ClipboardHistory.makeEntry(
        text: "original\u{202E}",
        sourceApplicationName: "Browser",
        sourceBundleIdentifier: "test.browser",
        hiddenUnicodeCount: 1,
        codeRiskCount: 0,
        trackedLinkCount: 0,
        binaryKind: nil,
        wasAutomaticallyCleaned: true,
        automaticCleaningAudit: audit
    )

    let retained = try #require(entry.automaticCleaningAudit)
    #expect(retained.mode == .strict)
    #expect(retained.outcome == .cleanedAllDetectedAlerts)
    #expect(retained.redRiskWasRemoved)
}

@Test("Clipboard history treats scam signals as known risk")
func retainsScamRiskInHistory() {
    let entry = ClipboardHistory.makeEntry(
        text: "Review this suspicious link",
        sourceApplicationName: "Messages",
        sourceBundleIdentifier: "test.messages",
        hiddenUnicodeCount: 0,
        codeRiskCount: 0,
        trackedLinkCount: 0,
        binaryKind: nil,
        scamSignalCount: 4,
        scamThreatLevel: .high,
        wasAutomaticallyCleaned: false
    )

    #expect(entry.hasKnownRisk)
    #expect(entry.scamSignalCount == 4)
    #expect(entry.scamThreatLevel == .high)
}
