// SPDX-License-Identifier: MPL-2.0
import Testing
@testable import SignalSieveCore

@Test("Cleans the exact Instagram share-link example")
func cleansInstagramShareLink() {
    let input = "https://www.instagram.com/reel/DbyPgivF8qU/?utm_source=ig_web_copy_link&igsh=NTc4MTIwNjQ2YQ=="
    let result = URLTrackerCleaner.cleanLinks(in: input)

    #expect(result.text == "https://www.instagram.com/reel/DbyPgivF8qU")
    #expect(result.linksFound == 1)
    #expect(result.linksChanged == 1)
    #expect(result.removedParameterCount == 2)
}

@Test("Preserves functional parameters while removing trackers")
func preservesFunctionalParameters() {
    let input = "Read https://example.com/search?q=swift&page=2&utm_source=newsletter&gclid=abc now."
    let result = URLTrackerCleaner.cleanLinks(in: input)

    #expect(result.text == "Read https://example.com/search?q=swift&page=2 now.")
    #expect(result.removedParameterCount == 2)
}

@Test("Leaves unknown signatures and fragments untouched")
func preservesUnknownSignatures() {
    let input = "https://files.example.com/download?signature=required&expires=123#section"
    let result = URLTrackerCleaner.cleanLinks(in: input)

    #expect(result.text == input)
    #expect(result.linksChanged == 0)
}

@Test("Cleans multiple links embedded in prose")
func cleansMultipleLinks() {
    let input = "One https://example.com/a?utm_medium=email and two https://youtu.be/abc?si=share123."
    let result = URLTrackerCleaner.cleanLinks(in: input)

    #expect(result.text == "One https://example.com/a and two https://youtu.be/abc.")
    #expect(result.linksFound == 2)
    #expect(result.linksChanged == 2)
    #expect(result.removedParameterCount == 2)
}

@Test("Applies YouTube-specific rules without removing the video identifier")
func cleansYouTubeLink() {
    let input = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=abc&feature=shared&pp=tracking"
    let result = URLTrackerCleaner.cleanLinks(in: input)

    #expect(result.text == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    #expect(result.removedParameterCount == 3)
}

@Test("Applies TikTok and X-specific share rules")
func cleansTikTokAndXLinks() {
    let input = "https://www.tiktok.com/@user/video/123?_t=abc&_r=1&is_from_webapp=1 and https://x.com/user/status/456?s=20&t=token"
    let result = URLTrackerCleaner.cleanLinks(in: input)

    #expect(result.text == "https://www.tiktok.com/@user/video/123 and https://x.com/user/status/456")
    #expect(result.removedParameterCount == 5)
}

@Test("Unwraps Facebook outbound redirect links")
func unwrapsFacebookRedirect() {
    let destination = "https%3A%2F%2Fexample.com%2Farticle%3Fq%3Dprivacy%26utm_source%3Dfacebook"
    let input = "https://l.facebook.com/l.php?u=\(destination)&h=tracking-signature"
    let result = URLTrackerCleaner.cleanLinks(in: input)

    #expect(result.text == "https://example.com/article?q=privacy")
    #expect(result.linksChanged == 1)
}

@Test("Returns an unchanged result when text has no web links")
func handlesTextWithoutLinks() {
    let input = "This paragraph has no URL at all."
    let result = URLTrackerCleaner.cleanLinks(in: input)

    #expect(result.text == input)
    #expect(result.linksFound == 0)
    #expect(result.linksChanged == 0)
    #expect(result.removedParameterCount == 0)
}

@Test("Ignores non-HTTP URL schemes")
func ignoresNonHTTPLinks() {
    let input = "ftp://example.com/file?utm_source=test"
    let result = URLTrackerCleaner.cleanLinks(in: input)

    #expect(result.text == input)
    #expect(result.linksFound == 0)
}

@Test("Direct cleaning leaves malformed and relative URLs unchanged")
func preservesInvalidDirectInputs() {
    #expect(URLTrackerCleaner.cleanURLString("not a URL?utm_source=x").url == "not a URL?utm_source=x")
    #expect(URLTrackerCleaner.cleanURLString("/page?utm_source=x").url == "/page?utm_source=x")
}

@Test("Matches tracker parameter names without case sensitivity")
func cleansCaseInsensitiveParameters() {
    let result = URLTrackerCleaner.cleanURLString(
        "https://example.com/article?UTM_Source=test&Q=keep#details"
    )

    #expect(result.url == "https://example.com/article?Q=keep#details")
    #expect(result.removedParameterCount == 1)
}

@Test("A private rule applies to subdomains but not lookalike domains")
func scopesPrivateRulesToDomainBoundary() throws {
    let rule = try CustomURLRule(domain: "example.com", parameter: "share_code")
    let input = "https://news.example.com/a?share_code=x&q=1 https://notexample.com/a?share_code=keep"
    let result = URLTrackerCleaner.cleanLinks(in: input, customRules: [rule])

    #expect(result.text == "https://news.example.com/a?q=1 https://notexample.com/a?share_code=keep")
}

@Test("Keeps prose punctuation outside a cleaned URL")
func preservesTrailingPunctuation() {
    let input = "See (https://example.com/article?utm_campaign=test), then continue."
    let result = URLTrackerCleaner.cleanLinks(in: input)

    #expect(result.text == "See (https://example.com/article), then continue.")
}
