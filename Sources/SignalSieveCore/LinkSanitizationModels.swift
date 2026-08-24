// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum LinkSanitizationTreatment: String, CaseIterable, Codable, Sendable {
    case removed = "Removed"
    case detectedOfflineUnresolvable = "Detected but not resolvable offline"
    case preservedFunctional = "Preserved because it may be functional"
    case outsideClipboardScope = "Outside clipboard scope"
}

public enum LinkTrackingMechanism: String, Codable, Sendable {
    case queryParameter = "Tracking query parameter"
    case embeddedRedirect = "Embedded redirect destination"
    case opaqueRedirect = "Opaque redirect or short link"
    case externalTracking = "Tracker outside copied content"
}

public enum TrackedLinkPlatform: String, CaseIterable, Codable, Identifiable, Sendable {
    case facebook = "Facebook"
    case youtube = "YouTube"
    case whatsapp = "WhatsApp"
    case instagram = "Instagram"
    case tiktok = "TikTok"
    case wechat = "WeChat"
    case reddit = "Reddit"
    case x = "X (Twitter)"
    case linkedin = "LinkedIn"
    case telegram = "Telegram"
    case snapchat = "Snapchat"
    case pinterest = "Pinterest"
    case discord = "Discord"
    case douyin = "Douyin"
    case threads = "Threads"
    case vk = "VK"
    case tumblr = "Tumblr"
    case twitch = "Twitch"
    case line = "Line"
    case fourChan = "4chan"
    case other = "Other"

    public var id: String { rawValue }
}

public struct LinkSanitizationFinding: Hashable, Sendable {
    public let platform: TrackedLinkPlatform
    public let treatment: LinkSanitizationTreatment
    public let mechanism: LinkTrackingMechanism
    public let originalURL: String
    public let resultingURL: String
    public let parameterNames: [String]

    public init(
        platform: TrackedLinkPlatform,
        treatment: LinkSanitizationTreatment,
        mechanism: LinkTrackingMechanism,
        originalURL: String,
        resultingURL: String,
        parameterNames: [String] = []
    ) {
        self.platform = platform
        self.treatment = treatment
        self.mechanism = mechanism
        self.originalURL = originalURL
        self.resultingURL = resultingURL
        self.parameterNames = parameterNames
    }
}

public enum LinkCoverageLevel: String, Codable, Sendable {
    case strong = "Strong"
    case targeted = "Targeted"
    case universalOnly = "Universal only"
    case detectionOnly = "Detection only"
}

public enum LinkCoverageCapability: String, Codable, Sendable {
    case universalParameters = "Universal tracking parameters"
    case platformParameters = "Platform-specific parameters"
    case embeddedRedirects = "Embedded redirects"
    case opaqueRedirectDetection = "Opaque redirect detection"
    case canonicalPaths = "Canonical share paths"
}

public struct LinkPlatformCoverage: Identifiable, Sendable {
    public let platform: TrackedLinkPlatform
    public let domains: [String]
    public let level: LinkCoverageLevel
    public let capabilities: [LinkCoverageCapability]
    public let limitation: String
    public let isPriority: Bool

    public var id: String { platform.rawValue }

    public init(
        platform: TrackedLinkPlatform,
        domains: [String],
        level: LinkCoverageLevel,
        capabilities: [LinkCoverageCapability],
        limitation: String,
        isPriority: Bool = false
    ) {
        self.platform = platform
        self.domains = domains
        self.level = level
        self.capabilities = capabilities
        self.limitation = limitation
        self.isPriority = isPriority
    }
}

public enum LinkCoverageCatalog {
    public static let opaqueRedirectLimitation = "Opaque redirects are detected but not contacted or resolved offline."
    public static let universalOnlyLimitation = "Only verified universal parameters are removed; no platform-specific signature is claimed."

    public static let entries: [LinkPlatformCoverage] = [
        entry(.facebook, ["facebook.com", "fb.com"], .strong,
              [.universalParameters, .platformParameters, .embeddedRedirects]),
        entry(.youtube, ["youtube.com", "youtu.be"], .strong,
              [.universalParameters, .platformParameters, .canonicalPaths]),
        entry(.whatsapp, ["whatsapp.com", "wa.me"], .universalOnly,
              [.universalParameters], universalOnlyLimitation),
        entry(.instagram, ["instagram.com"], .strong,
              [.universalParameters, .platformParameters, .canonicalPaths]),
        entry(.tiktok, ["tiktok.com"], .strong,
              [.universalParameters, .platformParameters, .canonicalPaths]),
        entry(.wechat, ["weixin.qq.com", "wechat.com"], .universalOnly,
              [.universalParameters], universalOnlyLimitation),
        entry(.reddit, ["reddit.com", "redd.it"], .targeted,
              [.universalParameters, .platformParameters, .opaqueRedirectDetection],
              opaqueRedirectLimitation, priority: true),
        entry(.x, ["x.com", "twitter.com", "t.co"], .targeted,
              [.universalParameters, .platformParameters, .opaqueRedirectDetection],
              opaqueRedirectLimitation),
        entry(.linkedin, ["linkedin.com", "lnkd.in"], .targeted,
              [.universalParameters, .platformParameters, .opaqueRedirectDetection],
              opaqueRedirectLimitation, priority: true),
        entry(.telegram, ["telegram.org", "t.me"], .universalOnly,
              [.universalParameters], universalOnlyLimitation),
        entry(.snapchat, ["snapchat.com", "t.snapchat.com"], .targeted,
              [.universalParameters, .platformParameters, .opaqueRedirectDetection],
              opaqueRedirectLimitation, priority: true),
        entry(.pinterest, ["pinterest.com", "pin.it"], .targeted,
              [.universalParameters, .platformParameters, .opaqueRedirectDetection],
              opaqueRedirectLimitation, priority: true),
        entry(.discord, ["discord.com", "discord.gg"], .universalOnly,
              [.universalParameters], universalOnlyLimitation),
        entry(.douyin, ["douyin.com"], .universalOnly,
              [.universalParameters], universalOnlyLimitation),
        entry(.threads, ["threads.com", "threads.net"], .targeted,
              [.universalParameters, .platformParameters],
              "Only verified URL-carried share identifiers are removed.", priority: true),
        entry(.vk, ["vk.com"], .universalOnly,
              [.universalParameters], universalOnlyLimitation),
        entry(.tumblr, ["tumblr.com"], .universalOnly,
              [.universalParameters], universalOnlyLimitation),
        entry(.twitch, ["twitch.tv"], .universalOnly,
              [.universalParameters], universalOnlyLimitation),
        entry(.line, ["line.me"], .universalOnly,
              [.universalParameters], universalOnlyLimitation),
        entry(.fourChan, ["4chan.org", "4channel.org"], .universalOnly,
              [.universalParameters], universalOnlyLimitation)
    ]

    public static func platform(forHost host: String) -> TrackedLinkPlatform {
        let normalized = host.lowercased()
        for entry in entries where entry.domains.contains(where: { domainMatches(normalized, domain: $0) }) {
            return entry.platform
        }
        return .other
    }

    private static func entry(
        _ platform: TrackedLinkPlatform,
        _ domains: [String],
        _ level: LinkCoverageLevel,
        _ capabilities: [LinkCoverageCapability],
        _ limitation: String = "No known offline limitation for the supported URL transformations.",
        priority: Bool = false
    ) -> LinkPlatformCoverage {
        LinkPlatformCoverage(
            platform: platform,
            domains: domains,
            level: level,
            capabilities: capabilities,
            limitation: limitation,
            isPriority: priority
        )
    }

    private static func domainMatches(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }
}
