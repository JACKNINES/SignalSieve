// SPDX-License-Identifier: MPL-2.0
import Foundation
import ImageIO

public enum PixelModuleCapability: String, Codable, Sendable, CaseIterable {
    case score
    case regenerate
}

public struct PixelWatermarkModuleManifest: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let name: String
    public let version: String
    public let executable: String
    public let capabilities: [PixelModuleCapability]
    public let license: String
    public let homepage: String?

    public init(
        schemaVersion: Int,
        name: String,
        version: String,
        executable: String,
        capabilities: [PixelModuleCapability],
        license: String,
        homepage: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.version = version
        self.executable = executable
        self.capabilities = capabilities
        self.license = license
        self.homepage = homepage
    }
}

public struct ExternalPixelWatermarkModule: Sendable, Equatable {
    public let rootURL: URL
    public let executableURL: URL
    public let manifest: PixelWatermarkModuleManifest

    public init(
        rootURL: URL,
        executableURL: URL,
        manifest: PixelWatermarkModuleManifest
    ) {
        self.rootURL = rootURL
        self.executableURL = executableURL
        self.manifest = manifest
    }

    public func supports(_ capability: PixelModuleCapability) -> Bool {
        manifest.capabilities.contains(capability)
    }
}

public struct PixelWatermarkScore: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let detector: String
    public let score: Double
    public let threshold: Double?
    public let label: String?

    public init(
        schemaVersion: Int,
        detector: String,
        score: Double,
        threshold: Double? = nil,
        label: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.detector = detector
        self.score = score
        self.threshold = threshold
        self.label = label
    }

    public var isElevated: Bool? {
        threshold.map { score >= $0 }
    }
}

public struct PixelWatermarkRegenerationResult: Sendable, Equatable {
    public let outputURL: URL
    public let width: Int
    public let height: Int
    public let originalWasUnchanged: Bool
    public let outputProvenanceReport: FileProvenanceReport
    public let beforeScore: PixelWatermarkScore?
    public let afterScore: PixelWatermarkScore?

    public init(
        outputURL: URL,
        width: Int,
        height: Int,
        originalWasUnchanged: Bool,
        outputProvenanceReport: FileProvenanceReport,
        beforeScore: PixelWatermarkScore?,
        afterScore: PixelWatermarkScore?
    ) {
        self.outputURL = outputURL
        self.width = width
        self.height = height
        self.originalWasUnchanged = originalWasUnchanged
        self.outputProvenanceReport = outputProvenanceReport
        self.beforeScore = beforeScore
        self.afterScore = afterScore
    }
}

public enum ExternalPixelWatermarkError: Error, Sendable, Equatable {
    case invalidModule
    case unsupportedSchema
    case unsafeExecutablePath
    case capabilityUnavailable
    case invalidImage
    case inputTooLarge
    case destinationMatchesSource
    case destinationAlreadyExists
    case couldNotStart
    case timedOut
    case moduleFailed
    case invalidModuleResponse
    case invalidOutput
    case outputTooLarge
    case dimensionsChanged
    case noPixelChange
    case sourceChangedDuringOperation
    case couldNotCreateCopy
}

/// Executes an explicitly selected third-party image module under a narrow CLI
/// contract. Network isolation cannot be guaranteed for an external process;
/// offline environment flags are applied and the UI must disclose the boundary.
public enum ExternalPixelWatermarkEngine {
    public static let manifestFileName = "signalsieve-pixel-module.json"
    public static let maximumManifestBytes = 1 * 1_024 * 1_024
    public static let maximumImageBytes = 256 * 1_024 * 1_024
    public static let maximumResponseBytes = 1 * 1_024 * 1_024
    public static let defaultTimeout: TimeInterval = 300

    private struct ImageProperties: Equatable {
        let width: Int
        let height: Int
    }

    public static func loadModule(at rootURL: URL) throws -> ExternalPixelWatermarkModule {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let manifestURL = root.appendingPathComponent(manifestFileName)
        let manifestValues = try? manifestURL.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
        ])
        guard manifestValues?.isRegularFile == true,
              manifestValues?.isSymbolicLink != true,
              (manifestValues?.fileSize ?? maximumManifestBytes + 1) <= maximumManifestBytes,
              let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(
                PixelWatermarkModuleManifest.self,
                from: manifestData
              ) else {
            throw ExternalPixelWatermarkError.invalidModule
        }
        guard manifest.schemaVersion == 1 else {
            throw ExternalPixelWatermarkError.unsupportedSchema
        }
        guard isBoundedManifest(manifest) else {
            throw ExternalPixelWatermarkError.invalidModule
        }

        guard !manifest.executable.hasPrefix("/"),
              !manifest.executable.hasPrefix("\\"),
              !manifest.executable.split(separator: "/").contains("..") else {
            throw ExternalPixelWatermarkError.unsafeExecutablePath
        }
        let executable = root.appendingPathComponent(manifest.executable)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard isDescendant(executable, of: root) else {
            throw ExternalPixelWatermarkError.unsafeExecutablePath
        }
        let executableValues = try? executable.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey
        ])
        guard executableValues?.isRegularFile == true,
              executableValues?.isSymbolicLink != true,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ExternalPixelWatermarkError.unsafeExecutablePath
        }
        return ExternalPixelWatermarkModule(
            rootURL: root,
            executableURL: executable,
            manifest: manifest
        )
    }

    public static func score(
        imageURL: URL,
        using module: ExternalPixelWatermarkModule,
        timeout: TimeInterval = defaultTimeout
    ) throws -> PixelWatermarkScore {
        guard module.supports(.score) else {
            throw ExternalPixelWatermarkError.capabilityUnavailable
        }
        let originalData = try validatedImageData(at: imageURL)
        return try withStagedInput(originalData, extension: imageURL.pathExtension) { stagedURL, workURL in
            let response = try run(
                module: module,
                arguments: ["score", "--input", stagedURL.path, "--json"],
                workURL: workURL,
                timeout: timeout
            )
            guard let score = try? JSONDecoder().decode(PixelWatermarkScore.self, from: response),
                  score.schemaVersion == 1,
                  score.score.isFinite,
                  (0...1).contains(score.score),
                  score.threshold.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
                  !score.detector.isEmpty,
                  score.detector.count <= 200 else {
                throw ExternalPixelWatermarkError.invalidModuleResponse
            }
            return score
        }
    }

    public static func regenerateCopy(
        imageURL: URL,
        destinationURL: URL,
        strength: Double,
        using module: ExternalPixelWatermarkModule,
        timeout: TimeInterval = defaultTimeout
    ) throws -> PixelWatermarkRegenerationResult {
        guard module.supports(.regenerate) else {
            throw ExternalPixelWatermarkError.capabilityUnavailable
        }
        let source = imageURL.standardizedFileURL
        let destination = destinationURL.standardizedFileURL
        guard source != destination else {
            throw ExternalPixelWatermarkError.destinationMatchesSource
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw ExternalPixelWatermarkError.destinationAlreadyExists
        }
        let originalData = try validatedImageData(at: source)
        guard let originalProperties = imageProperties(originalData) else {
            throw ExternalPixelWatermarkError.invalidImage
        }

        var beforeScore: PixelWatermarkScore?
        if module.supports(.score) {
            beforeScore = try? score(imageURL: source, using: module, timeout: timeout)
        }

        let generatedData: Data = try withStagedInput(
            originalData,
            extension: source.pathExtension
        ) { stagedURL, workURL in
            let generatedURL = workURL.appendingPathComponent(
                "generated.\(source.pathExtension.isEmpty ? "png" : source.pathExtension)"
            )
            guard FileManager.default.createFile(
                atPath: generatedURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw ExternalPixelWatermarkError.couldNotStart
            }
            _ = try run(
                module: module,
                arguments: [
                    "regenerate",
                    "--input", stagedURL.path,
                    "--output", generatedURL.path,
                    "--strength", String(format: "%.3f", min(max(strength, 0.05), 0.70)),
                    "--json"
                ],
                workURL: workURL,
                timeout: timeout
            )
            let values = try? generatedURL.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
            ])
            guard values?.isRegularFile == true,
                  values?.isSymbolicLink != true,
                  (values?.fileSize ?? maximumImageBytes + 1) <= maximumImageBytes,
                  let data = try? Data(contentsOf: generatedURL),
                  let properties = imageProperties(data) else {
                throw ExternalPixelWatermarkError.invalidOutput
            }
            guard properties == originalProperties else {
                throw ExternalPixelWatermarkError.dimensionsChanged
            }
            guard data != originalData else {
                throw ExternalPixelWatermarkError.noPixelChange
            }
            return data
        }

        let sourceAfterModule = try Data(contentsOf: source, options: .mappedIfSafe)
        guard sourceAfterModule == originalData else {
            throw ExternalPixelWatermarkError.sourceChangedDuringOperation
        }
        let temporaryDestination = destination.deletingLastPathComponent().appendingPathComponent(
            ".signalsieve-pixel-\(UUID().uuidString).tmp"
        )
        defer { try? FileManager.default.removeItem(at: temporaryDestination) }
        do {
            try generatedData.write(to: temporaryDestination, options: .atomic)
            try FileManager.default.moveItem(at: temporaryDestination, to: destination)
        } catch {
            throw ExternalPixelWatermarkError.couldNotCreateCopy
        }

        var verified = false
        defer {
            if !verified { try? FileManager.default.removeItem(at: destination) }
        }
        guard let verifiedData = try? Data(contentsOf: destination),
              verifiedData == generatedData,
              let properties = imageProperties(verifiedData) else {
            throw ExternalPixelWatermarkError.invalidOutput
        }
        let sourceAfterWrite = try Data(contentsOf: source, options: .mappedIfSafe)
        guard sourceAfterWrite == originalData else {
            throw ExternalPixelWatermarkError.sourceChangedDuringOperation
        }
        let provenance = try FileProvenanceAnalyzer.analyze(url: destination)
        var afterScore: PixelWatermarkScore?
        if module.supports(.score) {
            afterScore = try? score(imageURL: destination, using: module, timeout: timeout)
        }
        verified = true
        return PixelWatermarkRegenerationResult(
            outputURL: destination,
            width: properties.width,
            height: properties.height,
            originalWasUnchanged: true,
            outputProvenanceReport: provenance,
            beforeScore: beforeScore,
            afterScore: afterScore
        )
    }

    private static func validatedImageData(at url: URL) throws -> Data {
        let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
        ])
        guard values?.isRegularFile == true,
              values?.isSymbolicLink != true else {
            throw ExternalPixelWatermarkError.invalidImage
        }
        guard (values?.fileSize ?? maximumImageBytes + 1) <= maximumImageBytes else {
            throw ExternalPixelWatermarkError.inputTooLarge
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count <= maximumImageBytes,
              imageProperties(data) != nil else {
            throw ExternalPixelWatermarkError.invalidImage
        }
        return data
    }

    private static func imageProperties(_ data: Data) -> ImageProperties? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            return nil
        }
        return ImageProperties(width: width, height: height)
    }

    private static func withStagedInput<T>(
        _ data: Data,
        extension fileExtension: String,
        body: (URL, URL) throws -> T
    ) throws -> T {
        let workURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SignalSievePixel-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workURL) }
        let stagedURL = workURL.appendingPathComponent(
            "input.\(fileExtension.isEmpty ? "png" : fileExtension)"
        )
        try data.write(to: stagedURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o400],
            ofItemAtPath: stagedURL.path
        )
        return try body(stagedURL, workURL)
    }

    private static func run(
        module: ExternalPixelWatermarkModule,
        arguments: [String],
        workURL: URL,
        timeout: TimeInterval
    ) throws -> Data {
        let outputURL = workURL.appendingPathComponent("module-response-\(UUID().uuidString).json")
        let errorURL = workURL.appendingPathComponent("module-error-\(UUID().uuidString).txt")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              FileManager.default.createFile(atPath: errorURL.path, contents: nil),
              let outputHandle = try? FileHandle(forWritingTo: outputURL),
              let errorHandle = try? FileHandle(forWritingTo: errorURL) else {
            throw ExternalPixelWatermarkError.couldNotStart
        }
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = module.executableURL
        process.arguments = arguments
        process.currentDirectoryURL = module.rootURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        var environment = ProcessInfo.processInfo.environment
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
            environment.removeValue(forKey: key)
        }
        environment["NO_PROXY"] = "*"
        environment["HF_HUB_OFFLINE"] = "1"
        environment["TRANSFORMERS_OFFLINE"] = "1"
        environment["HF_DATASETS_OFFLINE"] = "1"
        environment["SIGNALSIEVE_OFFLINE"] = "1"
        process.environment = environment

        do { try process.run() }
        catch { throw ExternalPixelWatermarkError.couldNotStart }

        let deadline = Date().addingTimeInterval(max(1, timeout))
        while process.isRunning {
            let responseSize = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if responseSize > maximumResponseBytes {
                process.terminate()
                process.waitUntilExit()
                throw ExternalPixelWatermarkError.invalidModuleResponse
            }
            if Date() >= deadline {
                process.terminate()
                process.waitUntilExit()
                throw ExternalPixelWatermarkError.timedOut
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ExternalPixelWatermarkError.moduleFailed
        }
        guard let output = try? Data(contentsOf: outputURL),
              output.count <= maximumResponseBytes else {
            throw ExternalPixelWatermarkError.invalidModuleResponse
        }
        return output
    }

    private static func isBoundedManifest(_ manifest: PixelWatermarkModuleManifest) -> Bool {
        !manifest.name.isEmpty
            && manifest.name.count <= 120
            && !manifest.version.isEmpty
            && manifest.version.count <= 80
            && !manifest.executable.isEmpty
            && manifest.executable.count <= 500
            && !manifest.capabilities.isEmpty
            && manifest.license.count <= 200
            && (manifest.homepage?.count ?? 0) <= 500
    }

    private static func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}
