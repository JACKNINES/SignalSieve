// SPDX-License-Identifier: MPL-2.0
import SignalSieveCore
import Testing

@Test("A fresh installation starts in English")
func defaultsToEnglishWithoutAStoredLanguage() {
    #expect(AppLanguage.persistedOrEnglish(nil) == .english)
    #expect(AppLanguage.persistedOrEnglish("") == .english)
    #expect(AppLanguage.persistedOrEnglish("unsupported") == .english)
}

@Test("An explicitly selected language is restored")
func restoresStoredLanguageSelection() {
    #expect(AppLanguage.persistedOrEnglish("en") == .english)
    #expect(AppLanguage.persistedOrEnglish("es") == .spanish)
    #expect(AppLanguage.persistedOrEnglish("nb") == .norwegianBokmal)
}

@Test("Spanish and Norwegian interface translations are available")
func translatesPrimaryInterfaceText() {
    #expect(
        AppLocalization.text("Active Guard", language: .spanish)
            == "Protección activa"
    )
    #expect(
        AppLocalization.text("Active Guard", language: .norwegianBokmal)
            == "Aktiv beskyttelse"
    )
    #expect(AppLocalization.text("Active Guard", language: .english) == "Active Guard")

    let popupKeys = [
        "Multiple clipboard warnings",
        "High-priority finding · this alert stays in front until you close it",
        "Don't show hidden Unicode warnings again",
        "Don't show source-code warnings again",
        "Clean Link Once",
        "Turn On Automatic Link Cleaning",
        "Code Guard",
        "Confusable identifier character",
        "%@ code detected",
        "Source code detected",
        "%@ code contains suspicious Unicode",
        "Binary Guard",
        "Vaccine",
        "Don't show binary-data warnings again",
        "Don't show file-or-image metadata warnings again",
        "Warn About File or Image Metadata",
        "Open File Inspector",
        "Decoded hidden fragment",
        "Opaque binary payload",
        "Incomplete hidden payload",
        "Visible source fragment",
        "Reveal",
        "Reveal Hidden Content",
        "Probable detected equivalence",
        "Approximate local catalog match; this is not an exact byte-for-byte decode.",
        "Copy Reveal",
        "Signature Hunt",
        "Safe to neutralize",
        "Review only",
        "Copy Findings",
        "Copy Finding",
        "Copy Signatures",
        "Copy Signature",
        "History",
        "Copy History",
        "Probable source application",
        "Clear History",
        "Copied",
        "Review",
        "Analyze",
        "Clean",
        "A local rewrite can replace one statistical pattern with the local model's own token and style bias. The result is not statistically neutral, and watermark removal is never guaranteed.",
        "Installed model",
        "Refresh Installed Models",
        "Ollama is available, but no local models were found. Signal Sieve will not download one automatically.",
        "Ollama is installed, but its local service is not available on 127.0.0.1.",
        "Compares Input and Result or creates an optional local rewrite without claiming semantic equivalence."
    ]
    for key in popupKeys {
        #expect(AppLocalization.text(key, language: .spanish) != key)
        #expect(AppLocalization.text(key, language: .norwegianBokmal) != key)
    }
}

@Test("Binary Guard and Vaccine have localized names")
func localizesBinaryAndVaccineNames() {
    #expect(AppLocalization.text("Binary Guard", language: .spanish) == "Protección binaria")
    #expect(AppLocalization.text("Vaccine", language: .spanish) == "Vacuna")
    #expect(AppLocalization.text("Binary Guard", language: .norwegianBokmal) == "Binærbeskyttelse")
    #expect(AppLocalization.text("Vaccine", language: .norwegianBokmal) == "Vaksine")
}

@Test("Localized messages retain dynamic values")
func formatsLocalizedValues() {
    #expect(
        AppLocalization.format("Found %d elements to review.", language: .spanish, 4)
            == "Se encontraron 4 elementos para revisar."
    )
    #expect(
        AppLocalization.format("%d samples", language: .norwegianBokmal, 3)
            == "3 prøver"
    )
}

@Test("Pattern reports localize labels without translating copied phrases")
func localizesPatternReportSafely() {
    let phrase = PatternFinding(
        kind: .repeatedPhrase,
        pattern: "privacy remains local",
        detail: "",
        matchingSampleCount: 3,
        confidence: 0.8
    )
    let structure = PatternFinding(
        kind: .repeatedListStructure,
        pattern: "Three or more list items",
        detail: "",
        matchingSampleCount: 2,
        confidence: 0.7
    )

    #expect(AppLocalization.patternValue(phrase, language: .spanish) == phrase.pattern)
    #expect(
        AppLocalization.patternValue(structure, language: .norwegianBokmal)
            == "Tre eller flere listeelementer"
    )
}
