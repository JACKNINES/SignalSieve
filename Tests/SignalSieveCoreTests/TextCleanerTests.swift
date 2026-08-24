// SPDX-License-Identifier: MPL-2.0
import Testing
@testable import SignalSieveCore

@Test("Safe cleaning removes controls and normalizes unusual whitespace")
func safeCleaning() {
    let text = "hola\u{200B}mundo\u{202E}\u{00A0}!"
    let result = TextCleaner.clean(text, mode: .safe)

    #expect(result.text == "holamundo !")
    #expect(result.removedCount == 2)
    #expect(result.replacedCount == 1)
}

@Test("Both cleaning modes remove bidirectional marks")
func removesDirectionalMarks() {
    let text = "A\u{061C}B\u{200E}C\u{200F}D"

    for mode in [CleaningMode.safe, .strict] {
        let result = TextCleaner.clean(text, mode: mode)
        #expect(result.text == "ABCD")
        #expect(result.removedCount == 3)
        #expect(result.replacedCount == 0)
    }
}

@Test("Safe cleaning preserves emoji composition while strict cleaning flattens it")
func cleaningModesDiffer() {
    let family = "👨\u{200D}👩\u{200D}👧"
    let safe = TextCleaner.clean(family, mode: .safe)
    let strict = TextCleaner.clean(family, mode: .strict)

    #expect(safe.text == family)
    #expect(strict.text != family)
    #expect(HiddenTextAnalyzer.inspect(strict.text).isClean)
}

@Test("Strict cleaning removes selectors and Unicode tags")
func strictCleaning() {
    let text = "A\u{FE0F}\u{E0061}B"
    let result = TextCleaner.clean(text, mode: .strict)

    #expect(result.text == "AB")
    #expect(result.removedCount == 2)
}

@Test("Cleaning normalizes all newline styles")
func normalizesNewlines() {
    let result = TextCleaner.clean("one\r\ntwo\rthree\nfour", mode: .safe)

    #expect(result.text == "one\ntwo\nthree\nfour")
    #expect(result.removedCount == 0)
    #expect(result.replacedCount == 0)
}

@Test("Safe mode retains private-use characters and strict mode removes them")
func handlesPrivateUseByMode() {
    let text = "A\u{E000}B"

    #expect(TextCleaner.clean(text, mode: .safe).text == text)
    #expect(TextCleaner.clean(text, mode: .strict).text == "AB")
}

@Test("Strict mode performs compatibility normalization")
func strictCompatibilityNormalization() {
    #expect(TextCleaner.clean("ＡＢＣ", mode: .strict).text == "ABC")
}

@Test("Safe mode removes payload carriers while preserving contextual Unicode")
func contextualSafeCleaning() {
    let malicious = "A\u{FE0F}B\u{200D}C\u{200C}D"
    let family = "👨\u{200D}👩\u{200D}👧"
    let persian = "نامه\u{200C}ای"
    let devanagari = "क्\u{200D}ष"
    let mixedDirection = "العربية\u{200F} English"
    let ideographic = "邊\u{E0100}"

    let maliciousResult = TextCleaner.clean(malicious, mode: .safe)
    #expect(maliciousResult.text == "ABCD")
    #expect(maliciousResult.removedCount == 3)
    for functional in [family, persian, devanagari, mixedDirection, ideographic] {
        let result = TextCleaner.clean(functional, mode: .safe)
        #expect(result.text == functional)
        #expect(result.removedCount == 0)
    }
}

@Test("Safe mode preserves standardized emoji tags and removes arbitrary tag payloads")
func contextualTagCleaning() {
    let wales = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0077}\u{E006C}\u{E0073}\u{E007F}"
    let payload = "\u{1F3F4}\u{E0068}\u{E0065}\u{E006C}\u{E006C}\u{E006F}\u{E007F}"

    #expect(TextCleaner.clean(wales, mode: .safe).text == wales)
    let cleanedPayload = TextCleaner.clean(payload, mode: .safe)
    #expect(cleanedPayload.text == "\u{1F3F4}")
    #expect(cleanedPayload.removedCount == 6)
}

@Test("Safe cleaning preserves contextual fillers while removing floating carriers")
func cleansExtendedUnicodeContextually() {
    let functional = "\u{1100}\u{3164} · \u{1780}\u{17B4} · \u{13000}\u{13430}\u{13001}"
    #expect(TextCleaner.clean(functional, mode: .safe).text == functional)
    guard let noncharacter = Unicode.Scalar(0xFDD0) else { return }
    let floating = "A\u{3164}B\u{2065}C" + String(noncharacter) + "D"
    #expect(TextCleaner.clean(floating, mode: .safe).text == "ABCD")
}

@Test("Safe cleaning closes carrier gaps without breaking contextual scripts")
func cleansUnicodeCarrierGap() {
    let suspicious = "A\u{2061}B\u{206A}C\u{FFF9}D\u{E0001}EЖ\u{FE00}"
    let cleaned = TextCleaner.clean(suspicious, mode: .safe)
    #expect(cleaned.text == "ABCDEЖ")
    #expect(cleaned.removedCount == 5)

    let functional = "\u{0600}\u{0661} · \u{1100}\u{115F} · \u{0F40}\u{200D}\u{0F42} · 邊\u{FE00}"
    #expect(TextCleaner.clean(functional, mode: .safe).text == functional)
}
