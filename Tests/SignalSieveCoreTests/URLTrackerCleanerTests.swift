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

@Test("Cleans Snapchat click IDs using the documented ScCid shape")
func cleansSnapchatClickID() {
    let input = "https://www.mywebsite.com/landing-page?utm_source=snapchat&ScCid=7b3a7917-a82a-47e8-9728-e1b3b045abb2"
    let result = URLTrackerCleaner.cleanLinks(in: input)

    #expect(result.text == "https://www.mywebsite.com/landing-page")
    #expect(result.removedParameterCount == 2)
    #expect(result.findings.contains {
        $0.platform == .snapchat && Set($0.parameterNames.map { $0.lowercased() }) == ["utm_source", "sccid"]
    })
}

@Test("Cleans Reddit attribution while preserving a functional destination parameter")
func cleansRedditAttribution() {
    let input = "https://example.com/article?rdt_cid=abc123&q=privacy"
    let result = URLTrackerCleaner.cleanLinks(in: input)

    #expect(result.text == "https://example.com/article?q=privacy")
    #expect(result.findings.contains { $0.platform == .reddit && $0.treatment == .removed })
    #expect(result.findings.contains {
        $0.treatment == .preservedFunctional && $0.parameterNames == ["q"]
    })
}

@Test("Reports Reddit share redirects without resolving them")
func reportsOpaqueRedditShareLink() {
    let input = "https://www.reddit.com/r/privacy/s/AbCdEf1234"
    let result = URLTrackerCleaner.cleanLinks(in: input)

    #expect(result.text == input)
    #expect(result.linksChanged == 0)
    #expect(result.linksFlagged == 1)
    #expect(result.unresolvedRedirectCount == 1)
    #expect(result.findings.contains {
        $0.platform == .reddit && $0.treatment == .detectedOfflineUnresolvable
    })
}

@Test("Scopes Threads share identifiers to Threads domains")
func cleansThreadsShareIdentifier() {
    let threads = URLTrackerCleaner.cleanLinks(
        in: "https://www.threads.com/@signal/post/DH123?xmt=AQG-share-token&view=compact"
    )
    let unrelated = URLTrackerCleaner.cleanLinks(
        in: "https://example.com/article?xmt=must-stay"
    )

    #expect(threads.text == "https://www.threads.com/@signal/post/DH123?view=compact")
    #expect(threads.removedParameterCount == 1)
    #expect(unrelated.text == "https://example.com/article?xmt=must-stay")
}

@Test("Cleans Pinterest epik attribution and flags pin.it offline")
func cleansPinterestAndReportsShortLink() {
    let destination = URLTrackerCleaner.cleanLinks(
        in: "https://www.myshop.org/checkout?epik=123abc456def789ghi&sku=42"
    )
    let shortLink = "https://pin.it/4AbCdEf"
    let opaque = URLTrackerCleaner.cleanLinks(in: shortLink)

    #expect(destination.text == "https://www.myshop.org/checkout?sku=42")
    #expect(destination.findings.contains { $0.platform == .pinterest && $0.treatment == .removed })
    #expect(opaque.text == shortLink)
    #expect(opaque.unresolvedRedirectCount == 1)
}

@Test("Cleans LinkedIn share attribution and flags lnkd.in offline")
func cleansLinkedInAndReportsShortLink() {
    let input = "https://www.linkedin.com/posts/richardhurtley_startupjourney-founderstories-universityofexeter-activity-7384124628631457792-Mk9s?utm_source=share&utm_medium=member_desktop&rcm=ACoAA-example"
    let result = URLTrackerCleaner.cleanLinks(in: input)
    let opaque = URLTrackerCleaner.cleanLinks(in: "https://lnkd.in/eAbCdEf")

    #expect(result.text == "https://www.linkedin.com/posts/richardhurtley_startupjourney-founderstories-universityofexeter-activity-7384124628631457792-Mk9s")
    #expect(result.removedParameterCount == 3)
    #expect(result.findings.contains { $0.platform == .linkedin && $0.parameterNames.contains("rcm") })
    #expect(opaque.unresolvedRedirectCount == 1)
}

@Test("Detects Snapchat and X opaque redirect domains without network access")
func reportsAdditionalOpaqueRedirects() {
    for (url, platform) in [
        ("https://t.snapchat.com/AbCdEf12", TrackedLinkPlatform.snapchat),
        ("https://t.co/AbCdEf12", TrackedLinkPlatform.x)
    ] {
        let result = URLTrackerCleaner.cleanLinks(in: url)
        #expect(result.text == url)
        #expect(result.unresolvedRedirectCount == 1)
        #expect(result.findings.contains { $0.platform == platform })
    }
}

@Test("Publishes a complete twenty-platform offline coverage matrix")
func publishesCoverageMatrix() {
    #expect(LinkCoverageCatalog.entries.count == 20)
    #expect(LinkCoverageCatalog.entries.map(\.platform) == [
        .facebook, .youtube, .whatsapp, .instagram, .tiktok, .wechat,
        .reddit, .x, .linkedin, .telegram, .snapchat, .pinterest,
        .discord, .douyin, .threads, .vk, .tumblr, .twitch, .line, .fourChan
    ])
    #expect(LinkCoverageCatalog.entries.filter(\.isPriority).map(\.platform) == [
        .reddit, .linkedin, .snapchat, .pinterest, .threads
    ])
}
