// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum FolderTriageSeverity: Int, Sendable, Codable, CaseIterable, Comparable {
    case green = 0
    case yellow = 1
    case orange = 2
    case red = 3

    public static func < (lhs: FolderTriageSeverity, rhs: FolderTriageSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .green: "Green"
        case .yellow: "Yellow"
        case .orange: "Orange"
        case .red: "Red"
        }
    }
}

public enum FolderTriageEvidenceKind: String, Sendable, Codable, Equatable, Hashable {
    case noSupportedFinding = "No supported finding"
    case suspiciousUnicode = "Suspicious Unicode evidence"
    case mediumUnicode = "Medium Unicode evidence"
    case highUnicode = "High Unicode evidence"
    case suspiciousCode = "Suspicious code evidence"
    case mediumCode = "Medium code evidence"
    case highCode = "High code evidence"
    case encodedData = "Encoded data evidence"
    case metadata = "Metadata evidence"
    case structuralAnomaly = "Container structure anomaly"
}

public struct FolderTriageFileAssessment: Identifiable, Sendable, Equatable {
    public let id: String
    public let fileURL: URL
    public let relativePath: String
    public let severity: FolderTriageSeverity
    public let evidenceKinds: [FolderTriageEvidenceKind]
    public let evidenceSummary: String
    public let finding: VaccineFileFinding?
    public let identity: VaccineFileIdentity

    public init(
        fileURL: URL,
        relativePath: String,
        severity: FolderTriageSeverity,
        evidenceKinds: [FolderTriageEvidenceKind],
        evidenceSummary: String,
        finding: VaccineFileFinding?,
        identity: VaccineFileIdentity
    ) {
        self.id = relativePath
        self.fileURL = fileURL
        self.relativePath = relativePath
        self.severity = severity
        self.evidenceKinds = evidenceKinds
        self.evidenceSummary = evidenceSummary
        self.finding = finding
        self.identity = identity
    }
}

public struct FolderTriageReport: Sendable, Equatable {
    public let rootURL: URL
    public let scannedFileCount: Int
    public let binaryFileCount: Int
    public let skippedFileCount: Int
    public let excludedDirectoryCount: Int
    public let ignoredPathCount: Int
    public let assessments: [FolderTriageFileAssessment]
    public let unassessedFiles: [VaccineSkippedFile]
    public let isAssessmentBounded: Bool
    public let redDoesNotMeanMalwareNotice: String
    public let totalSeverityCounts: [FolderTriageSeverity: Int]
    public let totalUnassessedFileCount: Int

    public init(
        rootURL: URL,
        scannedFileCount: Int,
        binaryFileCount: Int,
        skippedFileCount: Int,
        excludedDirectoryCount: Int,
        ignoredPathCount: Int,
        assessments: [FolderTriageFileAssessment],
        unassessedFiles: [VaccineSkippedFile],
        isAssessmentBounded: Bool,
        totalSeverityCounts: [FolderTriageSeverity: Int]? = nil,
        totalUnassessedFileCount: Int? = nil,
        redDoesNotMeanMalwareNotice: String = FolderTriageEngine.redDoesNotMeanMalwareNotice
    ) {
        self.rootURL = rootURL
        self.scannedFileCount = scannedFileCount
        self.binaryFileCount = binaryFileCount
        self.skippedFileCount = skippedFileCount
        self.excludedDirectoryCount = excludedDirectoryCount
        self.ignoredPathCount = ignoredPathCount
        self.assessments = assessments
        self.unassessedFiles = unassessedFiles
        self.isAssessmentBounded = isAssessmentBounded
        self.totalSeverityCounts = totalSeverityCounts
            ?? Dictionary(grouping: assessments, by: \.severity).mapValues(\.count)
        self.totalUnassessedFileCount = max(
            0,
            totalUnassessedFileCount ?? unassessedFiles.count
        )
        self.redDoesNotMeanMalwareNotice = redDoesNotMeanMalwareNotice
    }

    public var redFiles: [FolderTriageFileAssessment] {
        assessments.filter { $0.severity == .red }
    }

    public func count(for severity: FolderTriageSeverity) -> Int {
        totalSeverityCounts[severity, default: 0]
    }
}

public struct FinderMarkerState: Sendable, Codable, Equatable {
    public let tagNames: [String]
    public let labelNumber: Int?

    public init(tagNames: [String], labelNumber: Int?) {
        self.tagNames = tagNames
        self.labelNumber = labelNumber
    }
}

public protocol FinderMarkerStore: Sendable {
    func state(for url: URL) throws -> FinderMarkerState
    func setState(_ state: FinderMarkerState, for url: URL) throws
}

public struct SystemFinderMarkerStore: FinderMarkerStore {
    public init() {}

    public func state(for url: URL) throws -> FinderMarkerState {
        let values = try url.resourceValues(forKeys: [.tagNamesKey, .labelNumberKey])
        return FinderMarkerState(
            tagNames: values.tagNames ?? [],
            labelNumber: values.labelNumber
        )
    }

    public func setState(_ state: FinderMarkerState, for url: URL) throws {
        let original = try self.state(for: url)
        do {
            try (url as NSURL).setResourceValue(
                state.tagNames,
                forKey: URLResourceKey.tagNamesKey
            )
            try (url as NSURL).setResourceValue(
                state.labelNumber,
                forKey: URLResourceKey.labelNumberKey
            )
            let persisted = try self.state(for: url)
            guard Set(persisted.tagNames) == Set(state.tagNames),
                  persisted.labelNumber == state.labelNumber else {
                throw FolderTriageError.finderStateVerificationFailed
            }
        } catch {
            try? (url as NSURL).setResourceValue(
                original.tagNames,
                forKey: URLResourceKey.tagNamesKey
            )
            try? (url as NSURL).setResourceValue(
                original.labelNumber,
                forKey: URLResourceKey.labelNumberKey
            )
            throw error
        }
    }
}

public struct FolderTriageMarkerManifest: Sendable, Codable, Equatable {
    public struct Entry: Sendable, Codable, Equatable, Identifiable {
        public let id: String
        public let relativePath: String
        public let identity: VaccineFileIdentity
        public let priorState: FinderMarkerState
        public let appliedState: FinderMarkerState
        public let markedAt: Date

        public init(
            relativePath: String,
            identity: VaccineFileIdentity,
            priorState: FinderMarkerState,
            appliedState: FinderMarkerState,
            markedAt: Date
        ) {
            self.id = relativePath
            self.relativePath = relativePath
            self.identity = identity
            self.priorState = priorState
            self.appliedState = appliedState
            self.markedAt = markedAt
        }
    }

    public let sourceRoot: String
    public let appMarkerTag: String
    public let createdAt: Date
    public let entries: [Entry]

    public init(sourceRoot: String, appMarkerTag: String, createdAt: Date, entries: [Entry]) {
        self.sourceRoot = sourceRoot
        self.appMarkerTag = appMarkerTag
        self.createdAt = createdAt
        self.entries = entries
    }
}

public enum FolderTriageMarkerOutcomeKind: String, Sendable, Codable, Equatable {
    case applied = "Applied"
    case alreadyMarked = "Already marked"
    case restored = "Restored"
    case alreadyUnmarked = "Already unmarked"
    case changedSinceScan = "Changed since scan"
    case unavailable = "Unavailable"
    case failed = "Failed"
    case labelNotRestored = "Label not restored"
    case manifestLimit = "Manifest limit"
    case ownershipConflict = "Marker ownership conflict"
}

public struct FolderTriageMarkerOutcome: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let relativePath: String
    public let kind: FolderTriageMarkerOutcomeKind
    public let message: String

    public init(relativePath: String, kind: FolderTriageMarkerOutcomeKind, message: String) {
        self.id = "\(relativePath):\(kind.rawValue)"
        self.relativePath = relativePath
        self.kind = kind
        self.message = message
    }
}

public struct FolderTriageMarkerResult: Sendable, Codable, Equatable {
    public let manifestURL: URL
    public let outcomes: [FolderTriageMarkerOutcome]

    public init(manifestURL: URL, outcomes: [FolderTriageMarkerOutcome]) {
        self.manifestURL = manifestURL
        self.outcomes = outcomes
    }

    public func count(_ kind: FolderTriageMarkerOutcomeKind) -> Int {
        outcomes.filter { $0.kind == kind }.count
    }

    public var successfulMutationCount: Int {
        count(.applied) + count(.alreadyMarked) + count(.restored) + count(.alreadyUnmarked) + count(.labelNotRestored)
    }
}

public enum FolderTriageError: LocalizedError, Equatable {
    case manifestUnavailable
    case manifestInvalid
    case manifestTooLarge
    case finderStateVerificationFailed

    public var errorDescription: String? {
        switch self {
        case .manifestUnavailable: "No Folder Triage marker manifest was found."
        case .manifestInvalid: "The Folder Triage marker manifest is invalid."
        case .manifestTooLarge: "The Folder Triage marker manifest exceeds the defensive size limit."
        case .finderStateVerificationFailed: "Finder did not preserve the requested marker state."
        }
    }
}

public enum FolderTriageEngine {
    public static let maximumReportedAssessments = 500
    public static let maximumReportedUnassessedFiles = 500
    public static let maximumManifestEntries = 250
    public static let maximumManifestBytes = 512 * 1_024
    public static let maximumManifestPathCharacters = 1_024
    public static let maximumFinderTagsPerFile = 128
    public static let maximumFinderTagCharacters = 256
    public static let appMarkerTag = "SignalSieve Red Review"
    public static let markerLabelNumber = 6
    public static let redDoesNotMeanMalwareNotice = "Red means a supported high-risk signal needs review. It is not proof of malware, authorship, intent, or compromise."

    public static func scan(rootURL: URL) throws -> FolderTriageReport {
        let vaccineReport = try VaccineEngine.scan(rootURL: rootURL)
        return report(from: vaccineReport)
    }

    public static func report(from vaccineReport: VaccineScanReport) -> FolderTriageReport {
        let findingsByPath = Dictionary(uniqueKeysWithValues: vaccineReport.findings.map { ($0.relativePath, $0) })
        let unassessedPaths = Set(vaccineReport.unassessedFiles.map(\.relativePath))
        let assessments: [FolderTriageFileAssessment] = vaccineReport.assessedFiles.compactMap { assessed -> FolderTriageFileAssessment? in
            let finding = findingsByPath[assessed.relativePath]
            // A partially inspected binary or oversized file may still expose
            // metadata evidence, but absence of such evidence is never green.
            guard finding != nil || !unassessedPaths.contains(assessed.relativePath) else {
                return nil
            }
            return assessment(for: assessed, finding: finding)
        }
        .sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
            return lhs.relativePath < rhs.relativePath
        }
        let severityCounts: [FolderTriageSeverity: Int] = Dictionary(
            grouping: assessments,
            by: { $0.severity }
        ).mapValues { $0.count }
        let totalUnassessed = vaccineReport.unassessedFiles.count
            + vaccineReport.omittedUnassessedFileCount
        let boundedAssessments = Array(assessments.prefix(maximumReportedAssessments))
        let boundedUnassessed = Array(vaccineReport.unassessedFiles.prefix(maximumReportedUnassessedFiles))
        return FolderTriageReport(
            rootURL: vaccineReport.rootURL,
            scannedFileCount: vaccineReport.scannedFileCount,
            binaryFileCount: vaccineReport.binaryFileCount,
            skippedFileCount: vaccineReport.skippedFileCount,
            excludedDirectoryCount: vaccineReport.excludedDirectoryCount,
            ignoredPathCount: vaccineReport.ignoredPathCount,
            assessments: boundedAssessments,
            unassessedFiles: boundedUnassessed,
            isAssessmentBounded: boundedAssessments.count < assessments.count
                || boundedUnassessed.count < vaccineReport.unassessedFiles.count
                || vaccineReport.omittedAssessedFileCount > 0
                || vaccineReport.omittedUnassessedFileCount > 0
                || vaccineReport.omittedFindingCount > 0,
            totalSeverityCounts: severityCounts,
            totalUnassessedFileCount: totalUnassessed
        )
    }

    public static func applyRedMarkers(
        to report: FolderTriageReport,
        manifestDirectory: URL,
        markerStore: FinderMarkerStore = SystemFinderMarkerStore()
    ) throws -> FolderTriageMarkerResult {
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        let manifestURL = manifestURL(forRoot: report.rootURL, in: manifestDirectory)
        let existingManifest: FolderTriageMarkerManifest?
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            existingManifest = try loadManifest(at: manifestURL)
            guard existingManifest?.sourceRoot == report.rootURL.standardizedFileURL.path,
                  existingManifest?.appMarkerTag == appMarkerTag else {
                throw FolderTriageError.manifestInvalid
            }
        } else {
            existingManifest = nil
        }
        var entriesByPath = Dictionary(
            uniqueKeysWithValues: (existingManifest?.entries ?? []).map { ($0.relativePath, $0) }
        )
        var outcomes: [FolderTriageMarkerOutcome] = []
        let candidates = report.redFiles.sorted { $0.relativePath < $1.relativePath }

        for candidate in candidates {
            guard revalidates(candidate: candidate, rootURL: report.rootURL) else {
                outcomes.append(FolderTriageMarkerOutcome(
                    relativePath: candidate.relativePath,
                    kind: .changedSinceScan,
                    message: "The file is no longer the same regular descendant scanned."
                ))
                continue
            }
            do {
                let state = try markerStore.state(for: candidate.fileURL)
                let existingEntry = entriesByPath[candidate.relativePath]
                if state.tagNames.contains(appMarkerTag), existingEntry == nil {
                    outcomes.append(FolderTriageMarkerOutcome(
                        relativePath: candidate.relativePath,
                        kind: .ownershipConflict,
                        message: "The marker name already exists without a matching Signal Sieve manifest entry."
                    ))
                    continue
                }
                if let existingEntry, existingEntry.identity != candidate.identity {
                    outcomes.append(FolderTriageMarkerOutcome(
                        relativePath: candidate.relativePath,
                        kind: .ownershipConflict,
                        message: "The existing marker manifest belongs to a different file identity."
                    ))
                    continue
                }
                if state.tagNames.contains(appMarkerTag), existingEntry != nil {
                    outcomes.append(FolderTriageMarkerOutcome(
                        relativePath: candidate.relativePath,
                        kind: .alreadyMarked,
                        message: "The app-owned Finder marker is already present."
                    ))
                    continue
                }
                if let existingEntry, state != existingEntry.priorState {
                    outcomes.append(FolderTriageMarkerOutcome(
                        relativePath: candidate.relativePath,
                        kind: .ownershipConflict,
                        message: "Finder metadata changed after the marker journal was created."
                    ))
                    continue
                }
                guard state.tagNames.count < maximumFinderTagsPerFile,
                      Set(state.tagNames).count == state.tagNames.count,
                      state.tagNames.allSatisfy(isValidFinderTag),
                      isValidFinderLabel(state.labelNumber) else {
                    outcomes.append(FolderTriageMarkerOutcome(
                        relativePath: candidate.relativePath,
                        kind: .ownershipConflict,
                        message: "Existing Finder tags exceed the defensive marker limits."
                    ))
                    continue
                }
                if existingEntry == nil, entriesByPath.count >= maximumManifestEntries {
                    outcomes.append(FolderTriageMarkerOutcome(
                        relativePath: candidate.relativePath,
                        kind: .manifestLimit,
                        message: "Not marked because the local manifest entry limit was reached."
                    ))
                    continue
                }
                let appliedState = FinderMarkerState(
                    tagNames: appendedMarkerTag(to: state.tagNames),
                    labelNumber: markerLabelNumber
                )
                if existingEntry == nil {
                    // Persist the undo journal before mutating Finder metadata.
                    // If the process stops between these operations, Restore
                    // safely recognizes the absent app marker and clears it.
                    entriesByPath[candidate.relativePath] = FolderTriageMarkerManifest.Entry(
                        relativePath: candidate.relativePath,
                        identity: candidate.identity,
                        priorState: state,
                        appliedState: appliedState,
                        markedAt: Date()
                    )
                    do {
                        try saveManifest(
                            manifest(
                                rootURL: report.rootURL,
                                createdAt: existingManifest?.createdAt ?? Date(),
                                entriesByPath: entriesByPath
                            ),
                            at: manifestURL
                        )
                    } catch {
                        entriesByPath.removeValue(forKey: candidate.relativePath)
                        throw error
                    }
                }
                guard revalidates(candidate: candidate, rootURL: report.rootURL) else {
                    if existingEntry == nil {
                        entriesByPath.removeValue(forKey: candidate.relativePath)
                        try? persistOrRemoveManifest(
                            rootURL: report.rootURL,
                            createdAt: existingManifest?.createdAt ?? Date(),
                            entriesByPath: entriesByPath,
                            manifestURL: manifestURL
                        )
                    }
                    outcomes.append(FolderTriageMarkerOutcome(
                        relativePath: candidate.relativePath,
                        kind: .changedSinceScan,
                        message: "The file changed immediately before Finder metadata mutation."
                    ))
                    continue
                }
                do {
                    try markerStore.setState(appliedState, for: candidate.fileURL)
                } catch {
                    if existingEntry == nil {
                        entriesByPath.removeValue(forKey: candidate.relativePath)
                        try? persistOrRemoveManifest(
                            rootURL: report.rootURL,
                            createdAt: existingManifest?.createdAt ?? Date(),
                            entriesByPath: entriesByPath,
                            manifestURL: manifestURL
                        )
                    }
                    throw error
                }
                outcomes.append(FolderTriageMarkerOutcome(
                    relativePath: candidate.relativePath,
                    kind: .applied,
                    message: "Applied the app-owned Finder marker without changing document content."
                ))
            } catch {
                outcomes.append(FolderTriageMarkerOutcome(
                    relativePath: candidate.relativePath,
                    kind: .failed,
                    message: "Finder metadata could not be updated."
                ))
            }
        }
        return FolderTriageMarkerResult(manifestURL: manifestURL, outcomes: outcomes)
    }

    public static func restoreMarkers(
        rootURL: URL,
        manifestDirectory: URL,
        markerStore: FinderMarkerStore = SystemFinderMarkerStore()
    ) throws -> FolderTriageMarkerResult {
        let manifestURL = manifestURL(forRoot: rootURL, in: manifestDirectory)
        let manifest = try loadManifest(at: manifestURL)
        guard manifest.appMarkerTag == appMarkerTag,
              manifest.sourceRoot == rootURL.standardizedFileURL.path else {
            throw FolderTriageError.manifestInvalid
        }

        var outcomes: [FolderTriageMarkerOutcome] = []
        var entriesNeedingRetry: [FolderTriageMarkerManifest.Entry] = []
        for entry in manifest.entries.prefix(maximumManifestEntries) {
            guard let fileURL = fileURL(for: entry.relativePath, under: rootURL) else {
                outcomes.append(FolderTriageMarkerOutcome(
                    relativePath: entry.relativePath,
                    kind: .unavailable,
                    message: "The manifest path is not a safe descendant."
                ))
                entriesNeedingRetry.append(entry)
                continue
            }
            guard revalidates(fileURL: fileURL, rootURL: rootURL, identity: entry.identity) else {
                outcomes.append(FolderTriageMarkerOutcome(
                    relativePath: entry.relativePath,
                    kind: .changedSinceScan,
                    message: "The file is no longer the same regular descendant that was marked."
                ))
                entriesNeedingRetry.append(entry)
                continue
            }
            do {
                let state = try markerStore.state(for: fileURL)
                guard state.tagNames.contains(appMarkerTag) else {
                    outcomes.append(FolderTriageMarkerOutcome(
                        relativePath: entry.relativePath,
                        kind: .alreadyUnmarked,
                        message: "The app-owned Finder marker is no longer present."
                    ))
                    continue
                }
                let restoredTags = state.tagNames.filter { $0 != appMarkerTag }
                let labelCanBeRestored = state.labelNumber == entry.appliedState.labelNumber
                    || state.labelNumber == entry.priorState.labelNumber
                let restoredLabel = labelCanBeRestored ? entry.priorState.labelNumber : state.labelNumber
                guard revalidates(fileURL: fileURL, rootURL: rootURL, identity: entry.identity) else {
                    outcomes.append(FolderTriageMarkerOutcome(
                        relativePath: entry.relativePath,
                        kind: .changedSinceScan,
                        message: "The file changed immediately before Finder metadata restoration."
                    ))
                    entriesNeedingRetry.append(entry)
                    continue
                }
                try markerStore.setState(
                    FinderMarkerState(tagNames: restoredTags, labelNumber: restoredLabel),
                    for: fileURL
                )
                outcomes.append(FolderTriageMarkerOutcome(
                    relativePath: entry.relativePath,
                    kind: labelCanBeRestored ? .restored : .labelNotRestored,
                    message: labelCanBeRestored
                        ? "Removed the app-owned marker and restored the prior Finder label."
                        : "Removed the app-owned marker but left a newer Finder label untouched."
                ))
            } catch {
                outcomes.append(FolderTriageMarkerOutcome(
                    relativePath: entry.relativePath,
                    kind: .failed,
                    message: "Finder metadata could not be restored."
                ))
                entriesNeedingRetry.append(entry)
            }
        }

        if entriesNeedingRetry.isEmpty {
            try FileManager.default.removeItem(at: manifestURL)
        } else {
            let retryManifest = FolderTriageMarkerManifest(
                sourceRoot: manifest.sourceRoot,
                appMarkerTag: manifest.appMarkerTag,
                createdAt: manifest.createdAt,
                entries: entriesNeedingRetry
            )
            try saveManifest(retryManifest, at: manifestURL)
        }
        return FolderTriageMarkerResult(manifestURL: manifestURL, outcomes: outcomes)
    }

    public static func manifestURL(forRoot rootURL: URL, in directory: URL) -> URL {
        let name = rootURL.lastPathComponent.isEmpty ? "root" : rootURL.lastPathComponent
        let safeName = String(name.map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        })
        let digest = String(
            VaccineEngine.contentFingerprint(Data(rootURL.standardizedFileURL.path.utf8)),
            radix: 16
        )
        return directory.appendingPathComponent("\(safeName)-\(digest).json")
    }

    private static func assessment(
        for assessed: VaccineAssessedFile,
        finding: VaccineFileFinding?
    ) -> FolderTriageFileAssessment {
        guard let finding else {
            return FolderTriageFileAssessment(
                fileURL: assessed.fileURL,
                relativePath: assessed.relativePath,
                severity: .green,
                evidenceKinds: [.noSupportedFinding],
                evidenceSummary: "No supported high, medium, encoded-data, or metadata evidence found.",
                finding: nil,
                identity: assessed.identity
            )
        }

        var severity: FolderTriageSeverity = .green
        var kinds: [FolderTriageEvidenceKind] = []
        let codeRisk = finding.highestCodeRiskLevel
        let hiddenRisk = finding.highestHiddenRiskLevel
        for risk in [codeRisk, hiddenRisk].compactMap({ $0 }) {
            switch risk {
            case .high:
                severity = max(severity, .red)
            case .medium:
                severity = max(severity, .orange)
            case .suspicious:
                severity = max(severity, .yellow)
            case .clear:
                break
            }
        }
        if let codeRisk {
            kinds.append(kind(forCodeRisk: codeRisk))
        }
        if let hiddenRisk {
            kinds.append(kind(forHiddenRisk: hiddenRisk))
        }
        if finding.encodedDataKind != nil {
            severity = max(severity, .orange)
            kinds.append(.encodedData)
        }
        if let provenance = finding.provenanceReport, !provenance.findings.isEmpty {
            let hasStructuralAnomaly = provenance.findings.contains { finding in
                switch finding.kind {
                case .extensionContentMismatch, .leadingContainerData,
                     .trailingContainerData, .protectedContainer:
                    true
                default:
                    false
                }
            }
            severity = max(severity, hasStructuralAnomaly ? .orange : .yellow)
            kinds.append(hasStructuralAnomaly ? .structuralAnomaly : .metadata)
        }
        if kinds.isEmpty {
            kinds.append(.noSupportedFinding)
        }

        return FolderTriageFileAssessment(
            fileURL: finding.fileURL,
            relativePath: finding.relativePath,
            severity: severity,
            evidenceKinds: Array(Set(kinds)).sorted { $0.rawValue < $1.rawValue },
            evidenceSummary: summary(for: finding, severity: severity),
            finding: finding,
            identity: finding.identity ?? assessed.identity
        )
    }

    private static func kind(forCodeRisk risk: HiddenElementRiskLevel) -> FolderTriageEvidenceKind {
        switch risk {
        case .high: .highCode
        case .medium: .mediumCode
        case .suspicious: .suspiciousCode
        case .clear: .noSupportedFinding
        }
    }

    private static func kind(forHiddenRisk risk: HiddenElementRiskLevel) -> FolderTriageEvidenceKind {
        switch risk {
        case .high: .highUnicode
        case .medium: .mediumUnicode
        case .suspicious: .suspiciousUnicode
        case .clear: .noSupportedFinding
        }
    }

    private static func summary(for finding: VaccineFileFinding, severity: FolderTriageSeverity) -> String {
        var parts: [String] = []
        if let risk = finding.highestCodeRiskLevel {
            parts.append(riskSummary(risk, scope: "code"))
        }
        if let risk = finding.highestHiddenRiskLevel {
            parts.append(riskSummary(risk, scope: "Unicode"))
        }
        if finding.encodedDataKind != nil {
            parts.append("Encoded data evidence detected.")
        }
        if let provenance = finding.provenanceReport, !provenance.findings.isEmpty {
            let hasStructuralAnomaly = provenance.findings.contains { item in
                switch item.kind {
                case .extensionContentMismatch, .leadingContainerData,
                     .trailingContainerData, .protectedContainer:
                    true
                default:
                    false
                }
            }
            parts.append(hasStructuralAnomaly
                ? "Container structure anomaly detected."
                : "Metadata evidence detected.")
        }
        if parts.isEmpty {
            return "No supported finding."
        }
        let suffix = severity == .red ? " Requires review; red is not a malware verdict." : ""
        return parts.joined(separator: " ") + suffix
    }

    private static func riskSummary(_ risk: HiddenElementRiskLevel, scope: String) -> String {
        let level: String
        switch risk {
        case .high: level = "High-risk"
        case .medium: level = "Medium-risk"
        case .suspicious: level = "Suspicious"
        case .clear: level = "Clear"
        }
        return "\(level) \(scope) evidence detected."
    }

    private static func appendedMarkerTag(to tags: [String]) -> [String] {
        var result = tags
        if !result.contains(appMarkerTag) {
            result.append(appMarkerTag)
        }
        return result
    }

    private static func revalidates(candidate: FolderTriageFileAssessment, rootURL: URL) -> Bool {
        revalidates(fileURL: candidate.fileURL, rootURL: rootURL, identity: candidate.identity)
    }

    private static func revalidates(fileURL: URL, rootURL: URL, identity: VaccineFileIdentity) -> Bool {
        guard isSafeDescendant(fileURL, of: rootURL) else { return false }
        guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            return false
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard unsignedAttribute(attributes?[.size]) == identity.fileSize,
              identityMatches(identity.fileNumber, current: unsignedAttribute(attributes?[.systemFileNumber])),
              identityMatches(identity.systemNumber, current: unsignedAttribute(attributes?[.systemNumber])),
              modificationTimeMatches(
                identity.modificationTime,
                current: (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970
              ),
              let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
              data.count <= VaccineEngine.maximumFileSize,
              VaccineEngine.contentFingerprint(data) == identity.fingerprint else {
            return false
        }
        return true
    }

    private static func isSafeDescendant(_ fileURL: URL, of rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
        let filePath = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        return filePath.hasPrefix(rootPath + "/")
    }

    private static func fileURL(for relativePath: String, under rootURL: URL) -> URL? {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            return nil
        }
        let url = rootURL.appendingPathComponent(relativePath)
        return isSafeDescendant(url, of: rootURL) ? url : nil
    }

    private static func loadManifest(at url: URL) throws -> FolderTriageMarkerManifest {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FolderTriageError.manifestUnavailable
        }
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
        ]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              let byteCount = values.fileSize,
              byteCount >= 0,
              byteCount <= maximumManifestBytes else {
            throw FolderTriageError.manifestTooLarge
        }
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw FolderTriageError.manifestUnavailable
        }
        guard data.count <= maximumManifestBytes else {
            throw FolderTriageError.manifestTooLarge
        }
        do {
            let manifest = try JSONDecoder.iso8601.decode(FolderTriageMarkerManifest.self, from: data)
            try validateManifest(manifest)
            return manifest
        } catch let error as FolderTriageError {
            throw error
        } catch {
            throw FolderTriageError.manifestInvalid
        }
    }

    private static func saveManifest(_ manifest: FolderTriageMarkerManifest, at url: URL) throws {
        try validateManifest(manifest)
        let data = try JSONEncoder.iso8601Pretty.encode(manifest)
        guard data.count <= maximumManifestBytes else {
            throw FolderTriageError.manifestTooLarge
        }
        try data.write(to: url, options: [.atomic])
    }

    private static func manifest(
        rootURL: URL,
        createdAt: Date,
        entriesByPath: [String: FolderTriageMarkerManifest.Entry]
    ) -> FolderTriageMarkerManifest {
        FolderTriageMarkerManifest(
            sourceRoot: rootURL.standardizedFileURL.path,
            appMarkerTag: appMarkerTag,
            createdAt: createdAt,
            entries: entriesByPath.values.sorted { $0.relativePath < $1.relativePath }
        )
    }

    private static func persistOrRemoveManifest(
        rootURL: URL,
        createdAt: Date,
        entriesByPath: [String: FolderTriageMarkerManifest.Entry],
        manifestURL: URL
    ) throws {
        if entriesByPath.isEmpty {
            if FileManager.default.fileExists(atPath: manifestURL.path) {
                try FileManager.default.removeItem(at: manifestURL)
            }
            return
        }
        try saveManifest(
            manifest(rootURL: rootURL, createdAt: createdAt, entriesByPath: entriesByPath),
            at: manifestURL
        )
    }

    private static func validateManifest(_ manifest: FolderTriageMarkerManifest) throws {
        guard !manifest.sourceRoot.isEmpty,
            manifest.sourceRoot.hasPrefix("/"),
            manifest.sourceRoot.count <= maximumManifestPathCharacters,
              !manifest.sourceRoot.contains("\0"),
              !manifest.sourceRoot.contains("\n"),
              !manifest.sourceRoot.contains("\r"),
              manifest.appMarkerTag == appMarkerTag,
              manifest.entries.count <= maximumManifestEntries else {
            throw FolderTriageError.manifestInvalid
        }
        var paths = Set<String>()
        for entry in manifest.entries {
            guard isValidManifestPath(entry.relativePath),
                  paths.insert(entry.relativePath).inserted,
                  entry.id == entry.relativePath,
                  entry.priorState.tagNames.count <= maximumFinderTagsPerFile,
                  entry.appliedState.tagNames.count <= maximumFinderTagsPerFile,
                  Set(entry.priorState.tagNames).count == entry.priorState.tagNames.count,
                  Set(entry.appliedState.tagNames).count == entry.appliedState.tagNames.count,
                  entry.priorState.tagNames.allSatisfy(isValidFinderTag),
                  entry.appliedState.tagNames.allSatisfy(isValidFinderTag),
                  !entry.priorState.tagNames.contains(appMarkerTag),
                  entry.appliedState.tagNames.contains(appMarkerTag),
                  Set(entry.appliedState.tagNames) == Set(entry.priorState.tagNames + [appMarkerTag]),
                  isValidFinderLabel(entry.priorState.labelNumber),
                  entry.appliedState.labelNumber == markerLabelNumber else {
                throw FolderTriageError.manifestInvalid
            }
        }
    }

    private static func isValidManifestPath(_ path: String) -> Bool {
        !path.isEmpty
            && path.count <= maximumManifestPathCharacters
            && !path.hasPrefix("/")
            && !path.contains("\0")
            && !path.contains("\n")
            && !path.contains("\r")
            && !path.contains("//")
            && !path.split(separator: "/").contains("..")
            && !path.split(separator: "/").contains(".")
    }

    private static func isValidFinderTag(_ tag: String) -> Bool {
        !tag.isEmpty
            && tag.count <= maximumFinderTagCharacters
            && !tag.contains("\0")
            && !tag.contains("\n")
            && !tag.contains("\r")
    }

    private static func isValidFinderLabel(_ label: Int?) -> Bool {
        guard let label else { return true }
        return (0...7).contains(label)
    }

    private static func identityMatches(_ scanned: UInt64?, current: UInt64?) -> Bool {
        guard let scanned else { return true }
        return current == scanned
    }

    private static func modificationTimeMatches(_ scanned: TimeInterval?, current: TimeInterval?) -> Bool {
        guard let scanned else { return true }
        guard let current else { return false }
        return abs(scanned - current) < 0.001
    }

    private static func unsignedAttribute(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let value = value as? UInt64 { return value }
        if let value = value as? UInt { return UInt64(value) }
        if let value = value as? Int, value >= 0 { return UInt64(value) }
        return nil
    }
}

private extension JSONEncoder {
    static var iso8601Pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
