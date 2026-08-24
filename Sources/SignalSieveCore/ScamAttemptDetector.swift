// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum ScamSignalKind: String, Sendable, Codable, Equatable {
    case brandLookalike = "Brand look-alike"
    case brandDomainMismatch = "Brand and domain mismatch"
    case urgencyOrPressure = "Urgency or pressure"
    case sensitiveAction = "Sensitive account or device action"
    case dangerousURLStructure = "Dangerous URL structure"
}

public enum ScamThreatLevel: String, Sendable, Codable, Equatable, Comparable {
    case review
    case suspicious
    case high

    private var rank: Int {
        switch self {
        case .review: 0
        case .suspicious: 1
        case .high: 2
        }
    }

    public static func < (lhs: ScamThreatLevel, rhs: ScamThreatLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct ScamSignal: Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: ScamSignalKind
    public let evidence: String
    public let detail: String
    public let score: Int

    public init(kind: ScamSignalKind, evidence: String, detail: String, score: Int) {
        self.id = "\(kind.rawValue):\(evidence.lowercased())"
        self.kind = kind
        self.evidence = evidence
        self.detail = detail
        self.score = max(0, score)
    }

    /// The query describes the category and excludes copied text, host, and URL.
    public var researchURL: URL? {
        var components = URLComponents(string: "https://duckduckgo.com/")
        components?.queryItems = [
            URLQueryItem(name: "q", value: "\(kind.rawValue) phishing scam security explanation")
        ]
        return components?.url
    }
}

public struct ScamAttemptAnalysis: Sendable, Equatable {
    public let score: Int
    public let threatLevel: ScamThreatLevel
    public let signals: [ScamSignal]
    public let inspectedHosts: [String]

    public init(score: Int, threatLevel: ScamThreatLevel, signals: [ScamSignal], inspectedHosts: [String]) {
        self.score = min(max(score, 0), 100)
        self.threatLevel = threatLevel
        self.signals = signals
        self.inspectedHosts = inspectedHosts
    }

    public var isPotentialScam: Bool { score >= ScamAttemptDetector.alertThreshold }
}

/// An explainable, offline detector. It never opens or contacts a URL and it
/// reports combinations of signals instead of claiming that a message is
/// definitively fraudulent.
public enum ScamAttemptDetector {
    public static let alertThreshold = 50

    private struct Brand {
        let canonicalWords: Set<String>
        let trustedDomains: Set<String>
    }

    private static let brands: [String: Brand] = [
        "Apple": Brand(
            canonicalWords: ["apple", "iphone", "ipad", "icloud"],
            trustedDomains: ["apple.com", "icloud.com"]
        ),
        "Google": Brand(
            canonicalWords: ["google", "gmail", "youtube"],
            trustedDomains: ["google.com", "gmail.com", "youtube.com", "youtu.be"]
        ),
        "Microsoft": Brand(
            canonicalWords: ["microsoft", "outlook", "onedrive"],
            trustedDomains: ["microsoft.com", "live.com", "outlook.com", "office.com"]
        ),
        "Meta": Brand(
            canonicalWords: ["facebook", "instagram", "whatsapp"],
            trustedDomains: ["facebook.com", "fb.com", "instagram.com", "whatsapp.com"]
        ),
        "PayPal": Brand(
            canonicalWords: ["paypal"],
            trustedDomains: ["paypal.com"]
        )
    ]

    private static let wordExpression = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)
    private static let urlExpression = try? NSRegularExpression(pattern: #"(?i)https?://[^\s<>\"']+"#)

    public static func analyze(_ text: String) -> ScamAttemptAnalysis {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ScamAttemptAnalysis(score: 0, threatLevel: .review, signals: [], inspectedHosts: [])
        }

        let words = wordMatches(in: text)
        var signals: [ScamSignal] = []
        var mentionedBrands: Set<String> = []

        for (brandName, brand) in brands {
            for word in words {
                let normalized = foldCommonUnicodeConfusables(word).lowercased()
                if brand.canonicalWords.contains(normalized) {
                    mentionedBrands.insert(brandName)
                    if word.lowercased() != normalized {
                        signals.append(ScamSignal(
                            kind: .brandLookalike,
                            evidence: word,
                            detail: "\(word) uses Unicode letters that resemble a recognized brand word.",
                            score: 40
                        ))
                    }
                    continue
                }
                guard let canonical = brand.canonicalWords.first(where: {
                    isLookalike(normalized, of: $0)
                }) else { continue }

                mentionedBrands.insert(brandName)
                signals.append(ScamSignal(
                    kind: .brandLookalike,
                    evidence: word,
                    detail: "\(word) resembles \(canonical) through confusable letters.",
                    score: 40
                ))
            }
        }

        let urls = urlMatches(in: text)
        let hosts = urls.compactMap { URL(string: $0)?.host?.lowercased() }
        for brandName in mentionedBrands {
            guard let brand = brands[brandName] else { continue }
            for host in hosts where !brand.trustedDomains.contains(where: { domainMatches(host, trusted: $0) }) {
                signals.append(ScamSignal(
                    kind: .brandDomainMismatch,
                    evidence: host,
                    detail: "The message mentions \(brandName), but \(host) is not one of its recognized domains.",
                    score: 35
                ))
            }
        }

        let lowered = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        if containsAny(lowered, phrases: [
            "urgente", "immediately", "inmediatamente", "hoy a las", "expires", "expira",
            "ultimo aviso", "último aviso", "act now", "ahora mismo"
        ]) {
            signals.append(ScamSignal(
                kind: .urgencyOrPressure,
                evidence: "time-sensitive wording",
                detail: "The message uses urgency or time pressure to encourage an immediate response.",
                score: 15
            ))
        }

        if containsAny(lowered, phrases: [
            "modo perdido", "lost mode", "ver ubicacion", "ver ubicación", "current location",
            "cuenta bloqueada", "account locked", "verify your account", "verifica tu cuenta",
            "iniciar sesion", "iniciar sesión", "sign in", "password", "contrasena", "contraseña"
        ]) {
            signals.append(ScamSignal(
                kind: .sensitiveAction,
                evidence: "account, device, or location request",
                detail: "The message asks the reader to act on sensitive account, device, or location information.",
                score: 15
            ))
        }

        for rawURL in urls {
            guard let components = URLComponents(string: rawURL),
                  let host = components.host?.lowercased() else { continue }
            let structuralReasons = dangerousURLReasons(components: components, host: host)
            guard !structuralReasons.isEmpty else { continue }
            signals.append(ScamSignal(
                kind: .dangerousURLStructure,
                evidence: host,
                detail: structuralReasons.joined(separator: "; "),
                score: 25
            ))
        }

        signals = deduplicated(signals)
        // Repeated evidence of the same kind improves the explanation, but it
        // must not inflate the risk score by itself.
        let scoreByKind = Dictionary(grouping: signals, by: \.kind).mapValues { group in
            group.map(\.score).max() ?? 0
        }
        let total = min(100, scoreByKind.values.reduce(0, +))
        let level: ScamThreatLevel = total >= 75 ? .high : (total >= alertThreshold ? .suspicious : .review)
        return ScamAttemptAnalysis(score: total, threatLevel: level, signals: signals, inspectedHosts: hosts)
    }

    private static func wordMatches(in text: String) -> [String] {
        guard let wordExpression else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return wordExpression.matches(in: text, range: range).compactMap { match -> String? in
            guard let swiftRange: Range<String.Index> = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    private static func urlMatches(in text: String) -> [String] {
        guard let urlExpression else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return urlExpression.matches(in: text, range: range).compactMap { match -> String? in
            guard let swiftRange: Range<String.Index> = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
                .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)]}"))
        }
    }

    private static func foldCommonUnicodeConfusables(_ word: String) -> String {
        let mapping: [UnicodeScalar: Character] = [
            "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "х": "x", "і": "i",
            "А": "a", "Е": "e", "О": "o", "Р": "p", "С": "c", "Х": "x", "І": "i",
            "α": "a", "β": "b", "ε": "e", "ι": "i", "κ": "k", "μ": "m", "ν": "n",
            "ο": "o", "ρ": "p", "τ": "t", "χ": "x", "υ": "y",
            "Α": "a", "Β": "b", "Ε": "e", "Ι": "i", "Κ": "k", "Μ": "m", "Ν": "n",
            "Ο": "o", "Ρ": "p", "Τ": "t", "Χ": "x", "Υ": "y"
        ]
        return String(word.unicodeScalars.map { mapping[$0] ?? Character(String($0)) })
    }

    private static func isLookalike(_ candidate: String, of canonical: String) -> Bool {
        let left = Array(candidate)
        let right = Array(canonical)
        guard left.count == right.count else { return false }
        let mismatches = zip(left, right).filter { $0 != $1 }
        guard !mismatches.isEmpty, mismatches.count <= 2 else { return false }
        return mismatches.allSatisfy { pair in
            let ambiguous: Set<Character> = ["i", "l", "1", "|", "0", "o"]
            return ambiguous.contains(pair.0) && ambiguous.contains(pair.1)
        }
    }

    private static func domainMatches(_ host: String, trusted: String) -> Bool {
        host == trusted || host.hasSuffix("." + trusted)
    }

    private static func containsAny(_ text: String, phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private static func dangerousURLReasons(
        components: URLComponents,
        host: String
    ) -> [String] {
        var reasons: [String] = []
        if components.scheme?.lowercased() != "https" {
            reasons.append("the link is not HTTPS")
        }
        if components.user != nil || components.password != nil {
            reasons.append("the link contains embedded user information")
        }
        if host.contains("xn--") {
            reasons.append("the hostname uses Punycode")
        }
        if isIPAddress(host) {
            reasons.append("the hostname is a raw IP address")
        }
        let labels = host.split(separator: ".")
        if labels.count >= 5 {
            reasons.append("the hostname has an unusually deep subdomain chain")
        }
        return reasons
    }

    private static func isIPAddress(_ host: String) -> Bool {
        let ipv4Parts = host.split(separator: ".")
        if ipv4Parts.count == 4,
           ipv4Parts.allSatisfy({ Int($0).map { (0...255).contains($0) } == true }) {
            return true
        }
        return host.contains(":")
    }

    private static func deduplicated(_ signals: [ScamSignal]) -> [ScamSignal] {
        var seen: Set<String> = []
        return signals.filter { seen.insert($0.id).inserted }
    }
}
