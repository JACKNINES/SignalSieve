// SPDX-License-Identifier: MPL-2.0
import Foundation

public struct VaccineChangePreview: Sendable, Equatable {
    public let line: Int
    public let before: String
    public let after: String

    public init(line: Int, before: String, after: String) {
        self.line = line
        self.before = before
        self.after = after
    }
}

public struct VaccineFileFinding: Identifiable, Sendable, Equatable {
    public let id: String
    public let fileURL: URL
    public let relativePath: String
    public let detectedLanguage: String?
    public let unicodeFindingCount: Int
    public let sanitizableFindingCount: Int
    public let reviewOnlyFindingCount: Int
    public let encodedDataKind: BinaryContentKind?
    public let codeFindings: [CodeGuardFinding]
    public let hiddenFindings: [HiddenElement]
    public let revealedFragments: [RevealedInvisibleFragment]
    public let textEncoding: TextEncodingKind
    public let hasByteOrderMark: Bool
    public let isTextFile: Bool
    public let provenanceReport: FileProvenanceReport?
    public let changePreview: VaccineChangePreview?
    public let fingerprint: UInt64

    public init(
        fileURL: URL,
        relativePath: String,
        detectedLanguage: String?,
        unicodeFindingCount: Int,
        sanitizableFindingCount: Int,
        reviewOnlyFindingCount: Int,
        encodedDataKind: BinaryContentKind?,
        codeFindings: [CodeGuardFinding],
        hiddenFindings: [HiddenElement],
        revealedFragments: [RevealedInvisibleFragment],
        textEncoding: TextEncodingKind,
        hasByteOrderMark: Bool,
        isTextFile: Bool = true,
        provenanceReport: FileProvenanceReport? = nil,
        changePreview: VaccineChangePreview?,
        fingerprint: UInt64
    ) {
        self.id = relativePath
        self.fileURL = fileURL
        self.relativePath = relativePath
        self.detectedLanguage = detectedLanguage
        self.unicodeFindingCount = unicodeFindingCount
        self.sanitizableFindingCount = sanitizableFindingCount
        self.reviewOnlyFindingCount = reviewOnlyFindingCount
        self.encodedDataKind = encodedDataKind
        self.codeFindings = codeFindings
        self.hiddenFindings = hiddenFindings
        self.revealedFragments = revealedFragments
        self.textEncoding = textEncoding
        self.hasByteOrderMark = hasByteOrderMark
        self.isTextFile = isTextFile
        self.provenanceReport = provenanceReport
        self.changePreview = changePreview
        self.fingerprint = fingerprint
    }
}

public struct VaccineScanReport: Sendable, Equatable {
    public let rootURL: URL
    public let scannedFileCount: Int
    public let binaryFileCount: Int
    public let provenanceScannedFileCount: Int
    public let skippedFileCount: Int
    public let excludedDirectoryCount: Int
    public let ignoredPathCount: Int
    public let isSignalSieveTarget: Bool
    public let findings: [VaccineFileFinding]

    public init(
        rootURL: URL,
        scannedFileCount: Int,
        binaryFileCount: Int,
        provenanceScannedFileCount: Int = 0,
        skippedFileCount: Int,
        excludedDirectoryCount: Int,
        ignoredPathCount: Int,
        isSignalSieveTarget: Bool,
        findings: [VaccineFileFinding]
    ) {
        self.rootURL = rootURL
        self.scannedFileCount = scannedFileCount
        self.binaryFileCount = binaryFileCount
        self.provenanceScannedFileCount = provenanceScannedFileCount
        self.skippedFileCount = skippedFileCount
        self.excludedDirectoryCount = excludedDirectoryCount
        self.ignoredPathCount = ignoredPathCount
        self.isSignalSieveTarget = isSignalSieveTarget
        self.findings = findings
    }

    public var affectedFileCount: Int { findings.count }
    public var sanitizableFileCount: Int {
        findings.filter { $0.sanitizableFindingCount > 0 }.count
    }
    public var totalUnicodeFindingCount: Int {
        findings.reduce(0) { $0 + $1.unicodeFindingCount }
    }
    public var metadataAffectedFileCount: Int {
        findings.filter { !($0.provenanceReport?.findings.isEmpty ?? true) }.count
    }
    public var totalMetadataFindingCount: Int {
        findings.reduce(0) { $0 + ($1.provenanceReport?.findings.count ?? 0) }
    }
}

public struct VaccineResult: Sendable, Equatable {
    public let sanitizedFileCount: Int
    public let removedCount: Int
    public let replacedCount: Int
    public let backupURL: URL
    public let filesChangedSinceScan: [String]

    public init(
        sanitizedFileCount: Int,
        removedCount: Int,
        replacedCount: Int,
        backupURL: URL,
        filesChangedSinceScan: [String]
    ) {
        self.sanitizedFileCount = sanitizedFileCount
        self.removedCount = removedCount
        self.replacedCount = replacedCount
        self.backupURL = backupURL
        self.filesChangedSinceScan = filesChangedSinceScan
    }
}

public enum VaccineError: LocalizedError {
    case invalidRoot
    case cannotEnumerate
    case selfVaccinationBlocked
    case backupFailed(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRoot: "The selected Vaccine root is not a readable directory."
        case .cannotEnumerate: "SignalSieve could not enumerate the selected directory."
        case .selfVaccinationBlocked: "SignalSieve cannot vaccinate itself. Its security fixtures may contain intentional test payloads."
        case .backupFailed(let path): "A backup could not be created for \(path). No source files were changed."
        case .writeFailed(let path): "Sanitization failed for \(path). Previously changed files were restored."
        }
    }
}

public enum VaccineEngine {
    public static let maximumFileSize = 5 * 1_024 * 1_024
    public static let provenanceFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "svg", "pdf", "docx", "odt",
        "html", "htm", "md", "markdown"
    ]
    public static let excludedDirectoryNames: Set<String> = [
        ".git", ".hg", ".svn", ".build", ".signalsieve-backups",
        "node_modules", "Pods", "DerivedData", ".next", "dist", "build"
    ]

    /// Recognizes the app bundle and source project by stable internal markers,
    /// not merely by a folder name that another project could share.
    public static func isSignalSieveTarget(_ rootURL: URL) -> Bool {
        let root = rootURL.standardizedFileURL
        let appInfoURL = root.appendingPathComponent("Contents/Info.plist")
        if bundleIdentifier(at: appInfoURL) == "com.signalsieve.app" {
            return true
        }

        let packagingInfoURL = root.appendingPathComponent("Packaging/Info.plist")
        let packageURL = root.appendingPathComponent("Package.swift")
        let appSourceURL = root.appendingPathComponent("Sources/SignalSieve/SignalSieveApp.swift")
        guard bundleIdentifier(at: packagingInfoURL) == "com.signalsieve.app",
              FileManager.default.fileExists(atPath: appSourceURL.path),
              let packageText = try? String(contentsOf: packageURL, encoding: .utf8) else {
            return false
        }
        return packageText.contains("name: \"SignalSieve\"")
            && packageText.contains("executable(name: \"SignalSieve\"")
    }

    public static func scan(rootURL: URL) throws -> VaccineScanReport {
        let root = rootURL.standardizedFileURL
        let selfTarget = isSignalSieveTarget(root)
        let ignoreRules = SignalSieveIgnore.load(from: root)
        let rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        guard rootValues.isDirectory == true, rootValues.isReadable != false else {
            throw VaccineError.invalidRoot
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { throw VaccineError.cannotEnumerate }

        var scanned = 0
        var binary = 0
        var provenanceScanned = 0
        var skipped = 0
        var excludedDirectories = 0
        var ignoredPaths = 0
        var findings: [VaccineFileFinding] = []

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            let relativePath = relativePath(of: fileURL, under: root)
            if values?.isDirectory == true {
                if ignoreRules.ignores(relativePath, isDirectory: true) {
                    enumerator.skipDescendants()
                    ignoredPaths += 1
                    continue
                }
                if excludedDirectoryNames.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                    excludedDirectories += 1
                }
                continue
            }
            if ignoreRules.ignores(relativePath, isDirectory: false) {
                ignoredPaths += 1
                continue
            }
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
                skipped += 1
                continue
            }
            let fileSize = values?.fileSize ?? 0
            let shouldInspectProvenance = provenanceFileExtensions.contains(
                fileURL.pathExtension.lowercased()
            )

            if fileSize > maximumFileSize {
                if shouldInspectProvenance,
                   fileSize <= FileProvenanceAnalyzer.maximumScanBytes,
                   let provenance = try? FileProvenanceAnalyzer.analyze(url: fileURL) {
                    provenanceScanned += 1
                    if !provenance.findings.isEmpty {
                        findings.append(metadataOnlyFinding(
                            fileURL: fileURL,
                            relativePath: relativePath,
                            provenance: provenance,
                            fingerprint: 0
                        ))
                    }
                }
                skipped += 1
                continue
            }

            let data: Data
            do { data = try Data(contentsOf: fileURL, options: [.mappedIfSafe]) }
            catch {
                skipped += 1
                continue
            }

            var provenanceReport: FileProvenanceReport?
            if shouldInspectProvenance {
                provenanceScanned += 1
                let provenance = FileProvenanceAnalyzer.analyze(
                    data,
                    fileName: fileURL.lastPathComponent
                )
                if !provenance.findings.isEmpty {
                    provenanceReport = provenance
                }
            }

            let rawBinary = BinaryContentDetector.analyze(data)
            if rawBinary.kind == .rawBinary, rawBinary.evidence.contains("signature") {
                binary += 1
                if let provenanceReport {
                    findings.append(metadataOnlyFinding(
                        fileURL: fileURL,
                        relativePath: relativePath,
                        provenance: provenanceReport,
                        fingerprint: fingerprint(data)
                    ))
                }
                continue
            }
            guard let decodedFile = TextEncodingDetector.decode(data) else {
                binary += 1
                if let provenanceReport {
                    findings.append(metadataOnlyFinding(
                        fileURL: fileURL,
                        relativePath: relativePath,
                        provenance: provenanceReport,
                        fingerprint: fingerprint(data)
                    ))
                }
                continue
            }
            if rawBinary.kind == .rawBinary, decodedFile.encoding == .utf8 {
                binary += 1
                if let provenanceReport {
                    findings.append(metadataOnlyFinding(
                        fileURL: fileURL,
                        relativePath: relativePath,
                        provenance: provenanceReport,
                        fingerprint: fingerprint(data)
                    ))
                }
                continue
            }
            let text = decodedFile.text
            scanned += 1

            let codeAnalysis = CodeGuardAnalyzer.analyze(text)
            let inspection = HiddenTextAnalyzer.inspect(text)
            let encoded = BinaryContentDetector.analyze(text)
            let cleaned: CodeSanitizationResult
            if codeAnalysis.isLikelyCode {
                cleaned = CodeGuardAnalyzer.sanitize(text)
            } else {
                let result = TextCleaner.clean(text, mode: .safe)
                cleaned = CodeSanitizationResult(
                    text: result.text,
                    removedCount: result.removedCount,
                    replacedCount: result.replacedCount
                )
            }
            let sanitizable = cleaned.text == text ? 0 : cleaned.removedCount + cleaned.replacedCount
            let unicodeCount = codeAnalysis.isLikelyCode
                ? codeAnalysis.findings.count
                : inspection.actionableFindings.count
            let reviewOnly = max(0, unicodeCount - sanitizable)
                + (provenanceReport?.findings.count ?? 0)

            guard unicodeCount > 0 || encoded.isDetected || provenanceReport != nil else { continue }
            findings.append(VaccineFileFinding(
                fileURL: fileURL,
                relativePath: relativePath,
                detectedLanguage: codeAnalysis.isLikelyCode ? codeAnalysis.detectedLanguage : nil,
                unicodeFindingCount: unicodeCount,
                sanitizableFindingCount: sanitizable,
                reviewOnlyFindingCount: reviewOnly,
                encodedDataKind: encoded.kind == .rawBinary ? nil : encoded.kind,
                codeFindings: codeAnalysis.findings,
                hiddenFindings: inspection.actionableFindings,
                revealedFragments: InvisibleFragmentRevealer.reveal(in: text),
                textEncoding: decodedFile.encoding,
                hasByteOrderMark: decodedFile.hasByteOrderMark,
                provenanceReport: provenanceReport,
                changePreview: cleaned.text == text
                    ? nil
                    : changePreview(before: text, after: cleaned.text),
                fingerprint: fingerprint(data)
            ))
        }

        return VaccineScanReport(
            rootURL: root,
            scannedFileCount: scanned,
            binaryFileCount: binary,
            provenanceScannedFileCount: provenanceScanned,
            skippedFileCount: skipped,
            excludedDirectoryCount: excludedDirectories,
            ignoredPathCount: ignoredPaths,
            isSignalSieveTarget: selfTarget,
            findings: findings.sorted { $0.relativePath < $1.relativePath }
        )
    }

    private static func metadataOnlyFinding(
        fileURL: URL,
        relativePath: String,
        provenance: FileProvenanceReport,
        fingerprint: UInt64
    ) -> VaccineFileFinding {
        VaccineFileFinding(
            fileURL: fileURL,
            relativePath: relativePath,
            detectedLanguage: nil,
            unicodeFindingCount: 0,
            sanitizableFindingCount: 0,
            reviewOnlyFindingCount: provenance.findings.count,
            encodedDataKind: nil,
            codeFindings: [],
            hiddenFindings: [],
            revealedFragments: [],
            textEncoding: .utf8,
            hasByteOrderMark: false,
            isTextFile: false,
            provenanceReport: provenance,
            changePreview: nil,
            fingerprint: fingerprint
        )
    }

    public static func vaccinate(
        _ report: VaccineScanReport,
        backupBaseURL: URL
    ) throws -> VaccineResult {
        guard !report.isSignalSieveTarget else {
            throw VaccineError.selfVaccinationBlocked
        }
        let candidates = report.findings.filter { $0.sanitizableFindingCount > 0 }
        let backupURL = backupBaseURL
            .appendingPathComponent(backupFolderName(for: report.rootURL), isDirectory: true)
        var plans: [(finding: VaccineFileFinding, data: Data, sanitizedData: Data, removed: Int, replaced: Int)] = []
        var changedSinceScan: [String] = []

        for finding in candidates {
            let values = try? finding.fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isRegularFile == true, values?.isSymbolicLink != true,
                  isDescendant(finding.fileURL, of: report.rootURL),
                  let data = try? Data(contentsOf: finding.fileURL),
                  fingerprint(data) == finding.fingerprint,
                  let decodedFile = TextEncodingDetector.decode(data) else {
                changedSinceScan.append(finding.relativePath)
                continue
            }
            let text = decodedFile.text
            let code = CodeGuardAnalyzer.analyze(text)
            let result: CodeSanitizationResult
            if code.isLikelyCode {
                result = CodeGuardAnalyzer.sanitize(text)
            } else {
                let clean = TextCleaner.clean(text, mode: .safe)
                result = CodeSanitizationResult(
                    text: clean.text,
                    removedCount: clean.removedCount,
                    replacedCount: clean.replacedCount
                )
            }
            guard result.text != text else { continue }
            guard let sanitizedData = TextEncodingDetector.encode(
                result.text,
                as: decodedFile.encoding,
                includeByteOrderMark: decodedFile.hasByteOrderMark
            ) else {
                changedSinceScan.append(finding.relativePath)
                continue
            }
            plans.append((finding, data, sanitizedData, result.removedCount, result.replacedCount))
        }

        try FileManager.default.createDirectory(
            at: backupURL,
            withIntermediateDirectories: true
        )
        for plan in plans {
            let destination = backupURL.appendingPathComponent(plan.finding.relativePath)
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try plan.data.write(to: destination, options: [.atomic])
            } catch {
                try? FileManager.default.removeItem(at: backupURL)
                throw VaccineError.backupFailed(plan.finding.relativePath)
            }
        }

        var modified: [(source: URL, backup: URL)] = []
        for plan in plans {
            let backup = backupURL.appendingPathComponent(plan.finding.relativePath)
            do {
                let attributes = try? FileManager.default.attributesOfItem(atPath: plan.finding.fileURL.path)
                try plan.sanitizedData.write(to: plan.finding.fileURL, options: [.atomic])
                if let permissions = attributes?[.posixPermissions] {
                    try? FileManager.default.setAttributes(
                        [.posixPermissions: permissions],
                        ofItemAtPath: plan.finding.fileURL.path
                    )
                }
                modified.append((plan.finding.fileURL, backup))
            } catch {
                for item in modified.reversed() {
                    if let original = try? Data(contentsOf: item.backup) {
                        try? original.write(to: item.source, options: [.atomic])
                    }
                }
                throw VaccineError.writeFailed(plan.finding.relativePath)
            }
        }

        let manifest = VaccineManifest(
            sourceRoot: report.rootURL.path,
            createdAt: Date(),
            files: plans.map(\.finding.relativePath)
        )
        if let manifestData = try? JSONEncoder.pretty.encode(manifest) {
            try? manifestData.write(
                to: backupURL.appendingPathComponent("manifest.json"),
                options: [.atomic]
            )
        }

        return VaccineResult(
            sanitizedFileCount: plans.count,
            removedCount: plans.reduce(0) { $0 + $1.removed },
            replacedCount: plans.reduce(0) { $0 + $1.replaced },
            backupURL: backupURL,
            filesChangedSinceScan: changedSinceScan.sorted()
        )
    }

    private static func bundleIdentifier(at infoURL: URL) -> String? {
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        return dictionary["CFBundleIdentifier"] as? String
    }

    private static func relativePath(of fileURL: URL, under rootURL: URL) -> String {
        let root = rootURL.standardizedFileURL.path
        let file = fileURL.standardizedFileURL.path
        return String(file.dropFirst(min(file.count, root.count + 1)))
    }

    private static func isDescendant(_ fileURL: URL, of rootURL: URL) -> Bool {
        let root = rootURL.standardizedFileURL.path
        let file = fileURL.standardizedFileURL.path
        return file.hasPrefix(root + "/")
    }

    private static func fingerprint(_ data: Data) -> UInt64 {
        data.reduce(1_469_598_103_934_665_603) { value, byte in
            (value ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }

    private static func changePreview(before: String, after: String) -> VaccineChangePreview? {
        let beforeLines = before.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let afterLines = after.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let count = max(beforeLines.count, afterLines.count)
        for index in 0..<count {
            let oldLine = index < beforeLines.count ? beforeLines[index] : ""
            let newLine = index < afterLines.count ? afterLines[index] : ""
            if oldLine != newLine {
                return VaccineChangePreview(
                    line: index + 1,
                    before: visibleLine(oldLine),
                    after: visibleLine(newLine)
                )
            }
        }
        return nil
    }

    private static func visibleLine(_ line: String) -> String {
        let scalars = Array(line.unicodeScalars)
        var result = ""
        var index = 0
        while index < scalars.count, result.count < 220 {
            let scalar = scalars[index]
            if HiddenTextAnalyzer.classify(scalar) != nil {
                let firstCodePoint = scalar.value <= 0xFFFF
                    ? String(format: "U+%04X", scalar.value)
                    : String(format: "U+%06X", scalar.value)
                var runCount = 1
                index += 1
                while index < scalars.count,
                      HiddenTextAnalyzer.classify(scalars[index]) != nil {
                    runCount += 1
                    index += 1
                }
                result += runCount == 1
                    ? "⟦\(firstCodePoint)⟧"
                    : "⟦\(firstCodePoint) ×\(runCount)⟧"
            } else {
                result.unicodeScalars.append(scalar)
                index += 1
            }
        }
        if index < scalars.count { result += "…" }
        return result
    }

    private static func backupFolderName(for rootURL: URL) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let rootName = rootURL.lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
        return "\(formatter.string(from: Date()))-\(rootName)-\(UUID().uuidString.prefix(8))"
    }
}

private struct VaccineManifest: Codable {
    let sourceRoot: String
    let createdAt: Date
    let files: [String]
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
