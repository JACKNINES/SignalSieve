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

@Test("Application icon follows explicit and automatic themes")
func mapsThemesToApplicationIcons() {
    #expect(AppTheme.light.iconVariant(systemIsDark: true) == .light)
    #expect(AppTheme.dark.iconVariant(systemIsDark: false) == .dark)
    #expect(AppTheme.iridescentPink.iconVariant(systemIsDark: true) == .iridescentPink)
    #expect(AppTheme.system.iconVariant(systemIsDark: false) == .light)
    #expect(AppTheme.system.iconVariant(systemIsDark: true) == .dark)
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
        "Compares Input and Result or creates an optional local rewrite without claiming semantic equivalence.",
        "Theme",
        "Automatic",
        "Light",
        "Dark",
        "Toolbar section",
        "Inspect pasted text and control clipboard monitoring.",
        "Local forensic tools for files, images, and the current text.",
        "Produces reviewable output. Code is never modified automatically.",
        "Expand Input to full width",
        "Expand Result to full width",
        "Restore both panels",
        "Privacy & Threat Insights",
        "Possible scam attempt detected",
        "Warn About Opaque Identifiers",
        "Warn About Possible Scam Attempts",
        "Learn Personal Baseline Locally",
        "Reset Personal Baseline",
        "Don't show opaque-identifier warnings again",
        "Don't show possible-scam warnings again",
        "Turn off Personal Baseline learning and warnings",
        "Clipboard Protocol",
        "Don't show standard warnings again",
        "Automatically Safe Clean copied text",
        "Automatically Strict Clean copied text",
        "These choices are mutually exclusive. Uncheck the selected option to restore all enabled warnings without automatic text cleaning.",
        "Automatic text cleaning skips source code, files, images, and privacy-sensitive clipboard types.",
        "Select one protocol. Leave all three unchecked to show every enabled warning without automatic text cleaning.",
        "Red high-risk alerts always remain visible.",
        "Review all enabled warnings",
        "High-risk alerts only",
        "Automatic Safe Clean",
        "Automatic Strict Clean",
        "Copying Settings",
        "Automatically prepare Result from Input using the selected protocol",
        "When enabled, Input prepares Result with the selected Safe Clean, Strict Clean, or Visual Transfer protocol. With automatic cleaning off, Result remains unchanged.",
        "Automatic Visual Transfer did not prepare Result because OCR changed a URL, number, quotation, or produced an unsafe result.",
        "Automatic Visual Transfer prepared Result with local OCR: %d characters recognized. Review it before use.",
        "Automatic Visual Transfer could not prepare Result: %@",
        "Stop showing green and yellow alerts",
        "Stop showing green through orange alerts",
        "Red alerts always appear, even when their warning category is turned off.",
        "Orange and red alerts remain visible. Red alerts cannot be disabled.",
        "Only red alerts remain visible. Red alerts cannot be disabled.",
        "Alert visibility choices are mutually exclusive.",
        "Automatic cleaning: %@",
        "Off",
        "Safe Clean and Strict Clean are mutually exclusive. Alert visibility is a separate setting.",
        "Eligible future text copies are Safe Cleaned. Alert visibility is controlled separately.",
        "Eligible future text copies are Strict Cleaned. Emoji and some writing systems may change. Alert visibility is controlled separately.",
        "Green and yellow alerts are hidden. Orange and red alerts remain mandatory.",
        "Green and yellow alerts are visible again. Orange and red alerts remain mandatory.",
        "Green through orange alerts are visible. Red alerts remain mandatory.",
        "Green through orange alerts are hidden. Only mandatory red alerts will appear.",
        "Automatic text cleaning is off. Alert visibility is unchanged.",
        "Safe Clean is now automatic for eligible future text copies. Alert visibility is unchanged.",
        "Strict Clean is now automatic for eligible future text copies. Alert visibility is unchanged.",
        "%@ removed the detected red text risk from the current clipboard",
        "%@ did not remove every red finding",
        "The clipboard text was reanalyzed after cleaning and no red text finding remained. Still use caution: the original source may have malicious intent.",
        "A red finding remains or automatic cleaning was skipped. Do not trust the content solely because cleaning is enabled; its source may have malicious intent.",
        "%@ · alerts cleaned successfully",
        "%@ · some alerts cleaned",
        "%@ · alerts remain",
        "%@ · cleaning skipped",
        "Possible scam · %d signal(s)",
        "%@ reanalysis: %d original alert(s), none remaining after automatic cleaning.",
        "%@ reanalysis: %d original alert(s), %d remaining after automatic cleaning.",
        "Automatically use Safe Clean for copied text",
        "Automatically use Strict Clean for copied text",
        "Automatically use Visual Transfer (OCR) for copied text",
        "Automatically prepare a Safe Clean Result from Input",
        "When enabled, pasting or typing in Input immediately prepares reviewable Safe Clean output. Disable it to keep Result unchanged until you choose a cleaning action.",
        "Automatic Visual Transfer",
        "Safe Clean, Strict Clean, and Automatic Visual Transfer are mutually exclusive. Alert visibility is a separate setting.",
        "Automatic processing skips source code, files, images, privacy-sensitive clipboard types, and oversized OCR input.",
        "Automatic Visual Transfer uses local OCR and may change words or punctuation. It refuses to overwrite detected changes to URLs, numbers, or quotations.",
        "Strict Clean converted this copy to plain text and removed its HTML or rich-text formatting.",
        "My Usual Copy Patterns",
        "Learn my usual copy patterns on this Mac",
        "Learning usual patterns · %d/%d+ copies",
        "Forget learned copy patterns",
        "This copy looks different from your usual copies",
        "Glossary",
        "Plain-language explanations of SignalSieve terms.",
        "Search terms",
        "Red alert",
        "Tracking parameter",
        "Metadata",
        "Link Coverage",
        "Link Tracking Coverage",
        "Coverage matrix",
        "Removed",
        "Detected but not resolvable offline",
        "Preserved because it may be functional",
        "Outside clipboard scope",
        "Copy Link Report",
        "Opaque redirect or short link detected",
        "Review Link Report"
    ]
    for key in popupKeys {
        #expect(AppLocalization.hasTranslation(key, language: .spanish))
        #expect(AppLocalization.hasTranslation(key, language: .norwegianBokmal))
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

@Test("A fresh installation follows the system appearance")
func defaultsToSystemThemeWithoutAStoredChoice() {
    #expect(AppTheme.persistedOrSystem(nil) == .system)
    #expect(AppTheme.persistedOrSystem("") == .system)
    #expect(AppTheme.persistedOrSystem("unsupported") == .system)
}

@Test("An explicitly selected theme is restored")
func restoresStoredThemeSelection() {
    #expect(AppTheme.persistedOrSystem("system") == .system)
    #expect(AppTheme.persistedOrSystem("light") == .light)
    #expect(AppTheme.persistedOrSystem("dark") == .dark)
    #expect(AppTheme.persistedOrSystem("iridescentPink") == .iridescentPink)
}

@Test("Automatic appearance clears any forced window theme")
func mapsThemeToWindowAppearanceOverride() {
    #expect(AppTheme.system.appearanceOverride == .followSystem)
    #expect(AppTheme.light.appearanceOverride == .light)
    #expect(AppTheme.dark.appearanceOverride == .dark)
    #expect(AppTheme.iridescentPink.appearanceOverride == .light)
}

@Test("Every theme carries a translated label")
func localizesThemeLabels() {
    #expect(AppLocalization.text(AppTheme.system.label, language: .spanish) == "Automático")
    #expect(AppLocalization.text(AppTheme.light.label, language: .spanish) == "Claro")
    #expect(AppLocalization.text(AppTheme.dark.label, language: .spanish) == "Oscuro")
    #expect(
        AppLocalization.text(AppTheme.iridescentPink.label, language: .spanish)
            == "Rosa iridiscente"
    )
    #expect(AppLocalization.text(AppTheme.system.label, language: .norwegianBokmal) == "Automatisk")
    #expect(
        AppLocalization.text(AppTheme.iridescentPink.label, language: .norwegianBokmal)
            == "Iriserende rosa"
    )
    #expect(AppLocalization.text(AppTheme.dark.label, language: .english) == "Dark")
}
