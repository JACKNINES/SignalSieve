// SPDX-License-Identifier: MPL-2.0
import Foundation

public struct URLCleaningResult: Sendable, Equatable {
    public let text: String
    public let linksFound: Int
    public let linksChanged: Int
    public let removedParameterCount: Int

    public init(
        text: String,
        linksFound: Int,
        linksChanged: Int,
        removedParameterCount: Int
    ) {
        self.text = text
        self.linksFound = linksFound
        self.linksChanged = linksChanged
        self.removedParameterCount = removedParameterCount
    }
}

public enum URLTrackerCleaner {
    private static let knownTrackingParameters: Set<String> = [
        "_hsenc",
        "_hsmi",
        "dclid",
        "ef_id",
        "fbclid",
        "gbraid",
        "gclid",
        "hsctatracking",
        "igsh",
        "igshid",
        "irclickid",
        "li_fat_id",
        "mc_cid",
        "mc_eid",
        "mkt_tok",
        "msclkid",
        "oly_anon_id",
        "oly_enc_id",
        "rb_clickid",
        "s_cid",
        "sc_channel",
        "spm",
        "ttclid",
        "twclid",
        "vero_conv",
        "vero_id",
        "wbraid"
    ]

    private static let domainTrackingParameters: [(domains: Set<String>, parameters: Set<String>)] = [
        (
            domains: ["youtube.com", "youtu.be"],
            parameters: ["feature", "pp", "si"]
        ),
        (
            domains: ["facebook.com", "fb.com"],
            parameters: ["__tn__", "eid", "mibextid", "paipv", "refsrc", "sfnsn"]
        ),
        (
            domains: ["tiktok.com"],
            parameters: [
                "_r", "_t", "is_copy_url", "is_from_webapp", "sender_device",
                "sender_web_id", "share_app_id", "share_iid", "social_share_type"
            ]
        ),
        (
            domains: ["x.com", "twitter.com"],
            parameters: ["s", "t"]
        )
    ]

    /// Finds HTTP(S) links in arbitrary text and removes only known tracking
    /// parameters. Functional query parameters are intentionally preserved.
    public static func cleanLinks(
        in text: String,
        customRules: [CustomURLRule] = []
    ) -> URLCleaningResult {
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return URLCleaningResult(
                text: text,
                linksFound: 0,
                linksChanged: 0,
                removedParameterCount: 0
            )
        }

        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector.matches(in: text, options: [], range: fullRange)
            .filter { match in
                guard let scheme = match.url?.scheme?.lowercased() else { return false }
                return scheme == "http" || scheme == "https"
            }

        var output = text
        var linksChanged = 0
        var removedParameterCount = 0

        for match in matches.reversed() {
            guard let range = Range(match.range, in: output) else { continue }
            let original = String(output[range])
            let cleaned = cleanURLString(original, customRules: customRules)
            guard cleaned.url != original else { continue }

            output.replaceSubrange(range, with: cleaned.url)
            linksChanged += 1
            removedParameterCount += cleaned.removedParameterCount
        }

        return URLCleaningResult(
            text: output,
            linksFound: matches.count,
            linksChanged: linksChanged,
            removedParameterCount: removedParameterCount
        )
    }

    public static func cleanURLString(
        _ input: String,
        customRules: [CustomURLRule] = []
    ) -> (
        url: String,
        removedParameterCount: Int
    ) {
        cleanURLString(input, customRules: customRules, redirectDepth: 0)
    }

    private static func cleanURLString(
        _ input: String,
        customRules: [CustomURLRule],
        redirectDepth: Int
    ) -> (url: String, removedParameterCount: Int) {
        guard
            var components = URLComponents(string: input),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return (input, 0)
        }

        let host = components.host?.lowercased() ?? ""

        if redirectDepth < 2,
           isFacebookRedirect(host: host, path: components.path),
           let destination = components.queryItems?.first(where: { $0.name.lowercased() == "u" })?.value,
           destination != input {
            let unwrapped = cleanURLString(
                destination,
                customRules: customRules,
                redirectDepth: redirectDepth + 1
            )
            let wrapperParameters = max(1, (components.queryItems?.count ?? 1) - 1)
            return (
                unwrapped.url,
                unwrapped.removedParameterCount + wrapperParameters
            )
        }

        let originalItems = components.queryItems ?? []
        let retainedItems = originalItems.filter { item in
            !isTrackingParameter(item.name, host: host, customRules: customRules)
        }
        let removedCount = originalItems.count - retainedItems.count

        if removedCount > 0 {
            components.queryItems = retainedItems.isEmpty ? nil : retainedItems
        }

        if isInstagramPostPath(host: host, path: components.percentEncodedPath),
           components.percentEncodedPath.hasSuffix("/") {
            components.percentEncodedPath.removeLast()
        }

        return (components.string ?? input, removedCount)
    }

    private static func isTrackingParameter(
        _ name: String,
        host: String,
        customRules: [CustomURLRule]
    ) -> Bool {
        let normalized = name.lowercased()
        if normalized.hasPrefix("utm_") || knownTrackingParameters.contains(normalized) {
            return true
        }

        for rule in domainTrackingParameters where rule.parameters.contains(normalized) {
            if rule.domains.contains(where: { domainMatches(host, domain: $0) }) {
                return true
            }
        }

        // `si` is also a share identifier on Spotify, but it may be functional
        // elsewhere and is therefore scoped to known services.
        if normalized == "si" && domainMatches(host, domain: "spotify.com") {
            return true
        }

        if customRules.contains(where: { rule in
            rule.parameter == normalized && domainMatches(host, domain: rule.domain)
        }) {
            return true
        }
        return false
    }

    private static func isInstagramPostPath(host: String, path: String) -> Bool {
        let isInstagram = domainMatches(host, domain: "instagram.com")
        guard isInstagram else { return false }

        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 2 else { return false }
        return components[0] == "reel" || components[0] == "p" || components[0] == "tv"
    }

    private static func isFacebookRedirect(host: String, path: String) -> Bool {
        let redirectHosts: Set<String> = ["l.facebook.com", "lm.facebook.com"]
        return redirectHosts.contains(host) && path == "/l.php"
    }

    private static func domainMatches(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }
}
