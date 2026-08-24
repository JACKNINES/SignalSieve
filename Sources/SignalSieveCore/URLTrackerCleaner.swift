// SPDX-License-Identifier: MPL-2.0
import Foundation

public struct URLCleaningResult: Sendable, Equatable {
    public let text: String
    public let linksFound: Int
    public let linksChanged: Int
    public let removedParameterCount: Int
    public let findings: [LinkSanitizationFinding]

    public init(
        text: String,
        linksFound: Int,
        linksChanged: Int,
        removedParameterCount: Int,
        findings: [LinkSanitizationFinding] = []
    ) {
        self.text = text
        self.linksFound = linksFound
        self.linksChanged = linksChanged
        self.removedParameterCount = removedParameterCount
        self.findings = findings
    }

    public var unresolvedRedirectCount: Int {
        findings.filter { $0.treatment == .detectedOfflineUnresolvable }.count
    }

    public var linksFlagged: Int {
        Set(findings.compactMap { finding in
            switch finding.treatment {
            case .removed, .detectedOfflineUnresolvable:
                finding.originalURL
            case .preservedFunctional, .outsideClipboardScope:
                nil
            }
        }).count
    }

    public var hasTrackingRisk: Bool { linksFlagged > 0 }
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
        "epik",
        "irclickid",
        "li_fat_id",
        "mc_cid",
        "mc_eid",
        "mkt_tok",
        "msclkid",
        "oly_anon_id",
        "oly_enc_id",
        "rb_clickid",
        "rdt_cid",
        "s_cid",
        "sc_channel",
        "sc_click_id",
        "sccid",
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
        ),
        (
            domains: ["reddit.com"],
            parameters: ["share_id", "share_name"]
        ),
        (
            domains: ["threads.com", "threads.net"],
            parameters: ["xmt"]
        ),
        (
            domains: ["linkedin.com"],
            parameters: ["rcm", "trk", "trackingid"]
        )
    ]

    private struct SingleURLResult {
        let url: String
        let removedParameterCount: Int
        let findings: [LinkSanitizationFinding]
    }

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
        var findings: [LinkSanitizationFinding] = []

        for match in matches.reversed() {
            guard let range = Range(match.range, in: output) else { continue }
            let original = String(output[range])
            let cleaned = analyzeURLString(
                original,
                customRules: customRules,
                redirectDepth: 0
            )
            findings.append(contentsOf: cleaned.findings)
            guard cleaned.url != original else { continue }

            output.replaceSubrange(range, with: cleaned.url)
            linksChanged += 1
            removedParameterCount += cleaned.removedParameterCount
        }

        return URLCleaningResult(
            text: output,
            linksFound: matches.count,
            linksChanged: linksChanged,
            removedParameterCount: removedParameterCount,
            findings: findings
        )
    }

    public static func cleanURLString(
        _ input: String,
        customRules: [CustomURLRule] = []
    ) -> (
        url: String,
        removedParameterCount: Int
    ) {
        let result = analyzeURLString(input, customRules: customRules, redirectDepth: 0)
        return (result.url, result.removedParameterCount)
    }

    private static func analyzeURLString(
        _ input: String,
        customRules: [CustomURLRule],
        redirectDepth: Int
    ) -> SingleURLResult {
        guard
            var components = URLComponents(string: input),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return SingleURLResult(url: input, removedParameterCount: 0, findings: [])
        }

        let host = components.host?.lowercased() ?? ""

        if redirectDepth < 2,
           isFacebookRedirect(host: host, path: components.path),
           let destination = components.queryItems?.first(where: { $0.name.lowercased() == "u" })?.value,
           destination != input {
            let unwrapped = analyzeURLString(
                destination,
                customRules: customRules,
                redirectDepth: redirectDepth + 1
            )
            let wrapperParameters = max(1, (components.queryItems?.count ?? 1) - 1)
            let wrapperFinding = LinkSanitizationFinding(
                platform: .facebook,
                treatment: .removed,
                mechanism: .embeddedRedirect,
                originalURL: input,
                resultingURL: unwrapped.url,
                parameterNames: components.queryItems?.map(\.name) ?? []
            )
            return SingleURLResult(
                url: unwrapped.url,
                removedParameterCount: unwrapped.removedParameterCount + wrapperParameters,
                findings: [wrapperFinding] + unwrapped.findings
            )
        }

        let originalItems = components.queryItems ?? []
        let removedItems = originalItems.filter {
            isTrackingParameter($0.name, host: host, customRules: customRules)
        }
        let retainedItems = originalItems.filter {
            !isTrackingParameter($0.name, host: host, customRules: customRules)
        }
        let removedCount = removedItems.count

        if removedCount > 0 {
            components.queryItems = retainedItems.isEmpty ? nil : retainedItems
        }

        if isInstagramPostPath(host: host, path: components.percentEncodedPath),
           components.percentEncodedPath.hasSuffix("/") {
            components.percentEncodedPath.removeLast()
        }

        let resultingURL = components.string ?? input
        let hostPlatform = LinkCoverageCatalog.platform(forHost: host)
        let platform = hostPlatform == .other
            ? inferredPlatform(from: removedItems.map(\.name))
            : hostPlatform
        var findings: [LinkSanitizationFinding] = []

        if !removedItems.isEmpty {
            findings.append(LinkSanitizationFinding(
                platform: platform,
                treatment: .removed,
                mechanism: .queryParameter,
                originalURL: input,
                resultingURL: resultingURL,
                parameterNames: removedItems.map(\.name)
            ))
        }

        if !retainedItems.isEmpty {
            findings.append(LinkSanitizationFinding(
                platform: hostPlatform,
                treatment: .preservedFunctional,
                mechanism: .queryParameter,
                originalURL: input,
                resultingURL: resultingURL,
                parameterNames: retainedItems.map(\.name)
            ))
        }

        if let wrapperPlatform = opaqueRedirectPlatform(host: host, path: components.path) {
            findings.append(LinkSanitizationFinding(
                platform: wrapperPlatform,
                treatment: .detectedOfflineUnresolvable,
                mechanism: .opaqueRedirect,
                originalURL: input,
                resultingURL: resultingURL
            ))
        }

        return SingleURLResult(
            url: resultingURL,
            removedParameterCount: removedCount,
            findings: findings
        )
    }

    private static func inferredPlatform(from parameterNames: [String]) -> TrackedLinkPlatform {
        let names = Set(parameterNames.map { $0.lowercased() })
        if !names.isDisjoint(with: ["sccid", "sc_click_id"]) { return .snapchat }
        if names.contains("epik") { return .pinterest }
        if names.contains("rdt_cid") { return .reddit }
        if names.contains("li_fat_id") { return .linkedin }
        if names.contains("ttclid") { return .tiktok }
        if names.contains("twclid") { return .x }
        if names.contains("fbclid") { return .facebook }
        if names.contains("igsh") || names.contains("igshid") { return .instagram }
        return .other
    }

    private static func opaqueRedirectPlatform(
        host: String,
        path: String
    ) -> TrackedLinkPlatform? {
        guard path.split(separator: "/").isEmpty == false else { return nil }

        if domainMatches(host, domain: "t.snapchat.com") { return .snapchat }
        if domainMatches(host, domain: "redd.it") { return .reddit }
        if domainMatches(host, domain: "reddit.com"), path.contains("/s/") { return .reddit }
        if domainMatches(host, domain: "pin.it") { return .pinterest }
        if domainMatches(host, domain: "lnkd.in") { return .linkedin }
        if domainMatches(host, domain: "t.co") { return .x }
        return nil
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
