// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum TextWatermarkVerificationMode: String, Codable, Sendable, CaseIterable {
    case sameConfiguration = "same-configuration"
    case providerCompatible = "provider-compatible"
    case researchHeuristic = "research-heuristic"
}

public struct TextWatermarkModuleManifest: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let name: String
    public let version: String
    public let executable: String
    public let schemes: [String]
    public let verificationMode: TextWatermarkVerificationMode
    public let requiresSecretKey: Bool
    public let license: String
    public let homepage: String?

    public init(
        schemaVersion: Int,
        name: String,
        version: String,
        executable: String,
        schemes: [String],
        verificationMode: TextWatermarkVerificationMode,
        requiresSecretKey: Bool,
        license: String,
        homepage: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.name = name
        self.version = version
        self.executable = executable
        self.schemes = schemes
        self.verificationMode = verificationMode
        self.requiresSecretKey = requiresSecretKey
        self.license = license
        self.homepage = homepage
    }
}

public struct ExternalTextWatermarkModule: Sendable, Equatable {
    public let rootURL: URL
    public let executableURL: URL
    public let manifest: TextWatermarkModuleManifest
}

public struct TextWatermarkDetectionResult: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let detector: String
    public let scheme: String
    public let statistic: Double
    public let threshold: Double?
    public let pValue: Double?
    public let detected: Bool?
    public let tokenCount: Int
    public let note: String?

    public init(
        schemaVersion: Int,
        detector: String,
        scheme: String,
        statistic: Double,
        threshold: Double? = nil,
        pValue: Double? = nil,
        detected: Bool? = nil,
        tokenCount: Int,
        note: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.detector = detector
        self.scheme = scheme
        self.statistic = statistic
        self.threshold = threshold
        self.pValue = pValue
        self.detected = detected
        self.tokenCount = tokenCount
        self.note = note
    }
}

public enum ExternalTextWatermarkError: Error, Sendable, Equatable {
    case invalidModule
    case unsupportedSchema
    case unsafeExecutablePath
    case emptyText
    case inputTooLarge
    case couldNotStart
    case timedOut
    case moduleFailed
    case invalidModuleResponse
    case unadvertisedScheme
}

/// Runs explicitly selected, local statistical-watermark detectors. A result
/// is only evidence for the scheme/configuration named by the module; it is not
/// a universal AI-text classifier or a provider oracle.
public enum ExternalTextWatermarkEngine {
    public static let manifestFileName = "signalsieve-text-watermark-module.json"
    public static let maximumManifestBytes = 1 * 1_024 * 1_024
    public static let maximumTextBytes = 1 * 1_024 * 1_024
    public static let maximumResponseBytes = 64 * 1_024
    public static let defaultTimeout: TimeInterval = 120

    public static func loadModule(at rootURL: URL) throws -> ExternalTextWatermarkModule {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let manifestURL = root.appendingPathComponent(manifestFileName)
        let values = try? manifestURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true,
              (values?.fileSize ?? maximumManifestBytes + 1) <= maximumManifestBytes,
              let bytes = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(TextWatermarkModuleManifest.self, from: bytes) else {
            throw ExternalTextWatermarkError.invalidModule
        }
        guard manifest.schemaVersion == 1 else { throw ExternalTextWatermarkError.unsupportedSchema }
        guard bounded(manifest), safeRelativePath(manifest.executable) else {
            throw ExternalTextWatermarkError.invalidModule
        }
        let executable = root.appendingPathComponent(manifest.executable)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard descendant(executable, of: root) else { throw ExternalTextWatermarkError.unsafeExecutablePath }
        let executableValues = try? executable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard executableValues?.isRegularFile == true, executableValues?.isSymbolicLink != true,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ExternalTextWatermarkError.unsafeExecutablePath
        }
        return ExternalTextWatermarkModule(rootURL: root, executableURL: executable, manifest: manifest)
    }

    public static func detect(
        _ text: String,
        using module: ExternalTextWatermarkModule,
        timeout: TimeInterval = defaultTimeout
    ) throws -> TextWatermarkDetectionResult {
        guard !text.isEmpty else { throw ExternalTextWatermarkError.emptyText }
        let input = Data(text.utf8)
        guard input.count <= maximumTextBytes else { throw ExternalTextWatermarkError.inputTooLarge }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("SignalSieveTextDetector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let inputURL = work.appendingPathComponent("input.txt")
        try input.write(to: inputURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: inputURL.path)
        let response = try run(module: module, inputURL: inputURL, workURL: work, timeout: timeout)
        guard let result = try? JSONDecoder().decode(TextWatermarkDetectionResult.self, from: response),
              result.schemaVersion == 1, result.statistic.isFinite,
              result.threshold?.isFinite ?? true,
              result.pValue.map({ $0.isFinite && (0...1).contains($0) }) ?? true,
              result.tokenCount >= 0, result.tokenCount <= 10_000_000,
              !result.detector.isEmpty, result.detector.count <= 200,
              !result.scheme.isEmpty, result.scheme.count <= 120,
              (result.note?.count ?? 0) <= 2_000 else {
            throw ExternalTextWatermarkError.invalidModuleResponse
        }
        guard module.manifest.schemes.contains(where: { $0.caseInsensitiveCompare(result.scheme) == .orderedSame }) else {
            throw ExternalTextWatermarkError.unadvertisedScheme
        }
        return result
    }

    private static func run(
        module: ExternalTextWatermarkModule,
        inputURL: URL,
        workURL: URL,
        timeout: TimeInterval
    ) throws -> Data {
        let outputURL = workURL.appendingPathComponent("response.json")
        let errorURL = workURL.appendingPathComponent("stderr.txt")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              FileManager.default.createFile(atPath: errorURL.path, contents: nil),
              let output = try? FileHandle(forWritingTo: outputURL),
              let error = try? FileHandle(forWritingTo: errorURL) else {
            throw ExternalTextWatermarkError.couldNotStart
        }
        defer { try? output.close(); try? error.close() }
        let process = Process()
        process.executableURL = module.executableURL
        process.arguments = ["detect", "--input", inputURL.path, "--json"]
        process.currentDirectoryURL = module.rootURL
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = error
        var environment = ProcessInfo.processInfo.environment
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] { environment.removeValue(forKey: key) }
        environment["NO_PROXY"] = "*"
        environment["HF_HUB_OFFLINE"] = "1"
        environment["TRANSFORMERS_OFFLINE"] = "1"
        environment["SIGNALSIEVE_OFFLINE"] = "1"
        process.environment = environment
        do { try process.run() } catch { throw ExternalTextWatermarkError.couldNotStart }
        let deadline = Date().addingTimeInterval(max(1, timeout))
        while process.isRunning {
            let size = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > maximumResponseBytes { process.terminate(); process.waitUntilExit(); throw ExternalTextWatermarkError.invalidModuleResponse }
            if Date() >= deadline { process.terminate(); process.waitUntilExit(); throw ExternalTextWatermarkError.timedOut }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ExternalTextWatermarkError.moduleFailed }
        guard let bytes = try? Data(contentsOf: outputURL), bytes.count <= maximumResponseBytes else {
            throw ExternalTextWatermarkError.invalidModuleResponse
        }
        return bytes
    }

    private static func bounded(_ value: TextWatermarkModuleManifest) -> Bool {
        !value.name.isEmpty && value.name.count <= 120
            && !value.version.isEmpty && value.version.count <= 80
            && !value.executable.isEmpty && value.executable.count <= 500
            && !value.schemes.isEmpty && value.schemes.count <= 64
            && value.schemes.allSatisfy { !$0.isEmpty && $0.count <= 120 }
            && !value.license.isEmpty && value.license.count <= 200
            && (value.homepage?.count ?? 0) <= 500
    }
    private static func safeRelativePath(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.hasPrefix("\\") && !path.split(separator: "/").contains("..")
    }
    private static func descendant(_ candidate: URL, of root: URL) -> Bool {
        candidate.path == root.path || candidate.path.hasPrefix(root.path + "/")
    }
}
