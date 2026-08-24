// SPDX-License-Identifier: MPL-2.0
import Foundation

public enum CommunityWatermarkOperation: String, Sendable, Codable {
    case inspect
    case clean
}

public struct CommunityWatermarkServiceHealth: Sendable, Equatable {
    public let isHealthy: Bool
    public let version: String
}

public struct CommunityWatermarkServiceResult: Sendable, Equatable {
    public let operation: CommunityWatermarkOperation
    public let kind: String?
    public let suspicious: Bool?
    public let report: String
    public let cleanedText: String?
}

public enum CommunityWatermarkServiceError: Error, Sendable, Equatable {
    case emptyText
    case inputTooLarge
    case couldNotStart
    case timedOut
    case serviceUnavailable
    case responseTooLarge
    case invalidResponse
    case serviceRejected(String)
}

/// Optional bridge to the MIT-licensed watermarks-remover HTTP service. The
/// endpoint is deliberately fixed to numeric loopback. Signal Sieve never
/// downloads, starts, updates, or trusts the service automatically.
public enum CommunityWatermarkService {
    public static let serviceName = "watermarks-remover"
    public static let serviceHomepage = "https://github.com/guillaumemeyer/watermarks-remover"
    public static let baseURL = "http://127.0.0.1:8765"
    public static let maximumTextBytes = 1 * 1_024 * 1_024
    public static let maximumResponseBytes = 2 * 1_024 * 1_024
    public static let defaultTimeout: TimeInterval = 20

    public static func health(timeout: TimeInterval = 4) throws -> CommunityWatermarkServiceHealth {
        let data = try request(path: "/health", method: "GET", body: nil, timeout: timeout)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["ok"] as? Bool == true else {
            throw CommunityWatermarkServiceError.invalidResponse
        }
        return CommunityWatermarkServiceHealth(
            isHealthy: true,
            version: boundedString(object["version"] as? String ?? "unknown", maximum: 120)
        )
    }

    public static func capabilities(timeout: TimeInterval = 8) throws -> String {
        let data = try request(path: "/capabilities", method: "GET", body: nil, timeout: timeout)
        guard let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: pretty, encoding: .utf8) else {
            throw CommunityWatermarkServiceError.invalidResponse
        }
        return boundedString(text, maximum: 24_000)
    }

    public static func inspectText(
        _ text: String,
        timeout: TimeInterval = defaultTimeout
    ) throws -> CommunityWatermarkServiceResult {
        try perform(.inspect, text: text, timeout: timeout)
    }

    public static func cleanText(
        _ text: String,
        timeout: TimeInterval = defaultTimeout
    ) throws -> CommunityWatermarkServiceResult {
        try perform(.clean, text: text, timeout: timeout)
    }

    static func makeTextRequestBody(_ text: String) throws -> Data {
        guard !text.isEmpty else { throw CommunityWatermarkServiceError.emptyText }
        let input = Data(text.utf8)
        guard input.count <= maximumTextBytes else { throw CommunityWatermarkServiceError.inputTooLarge }
        return try JSONSerialization.data(withJSONObject: [
            "file": input.base64EncodedString(),
            "name": "clipboard.txt"
        ], options: [.sortedKeys])
    }

    static func parseResult(
        _ data: Data,
        operation: CommunityWatermarkOperation
    ) throws -> CommunityWatermarkServiceResult {
        guard data.count <= maximumResponseBytes,
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CommunityWatermarkServiceError.invalidResponse
        }
        guard let succeeded = object["ok"] as? Bool else {
            throw CommunityWatermarkServiceError.invalidResponse
        }
        if !succeeded {
            throw CommunityWatermarkServiceError.serviceRejected(
                boundedString(object["error"] as? String ?? "The community engine rejected the request.", maximum: 500)
            )
        }
        let cleanedText: String?
        if let encoded = object["cleaned"] as? String {
            guard let bytes = Data(base64Encoded: encoded), bytes.count <= maximumTextBytes,
                  let decoded = String(data: bytes, encoding: .utf8) else {
                throw CommunityWatermarkServiceError.invalidResponse
            }
            cleanedText = decoded
            object.removeValue(forKey: "cleaned")
            object["cleaned"] = "<decoded locally; omitted from report>"
        } else {
            cleanedText = nil
        }
        guard JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let report = String(data: pretty, encoding: .utf8) else {
            throw CommunityWatermarkServiceError.invalidResponse
        }
        return CommunityWatermarkServiceResult(
            operation: operation,
            kind: object["kind"] as? String,
            suspicious: object["suspicious"] as? Bool,
            report: boundedString(report, maximum: 32_000),
            cleanedText: cleanedText
        )
    }

    private static func perform(
        _ operation: CommunityWatermarkOperation,
        text: String,
        timeout: TimeInterval
    ) throws -> CommunityWatermarkServiceResult {
        let body = try makeTextRequestBody(text)
        let response = try request(
            path: "/\(operation.rawValue)",
            method: "POST",
            body: body,
            timeout: timeout
        )
        return try parseResult(response, operation: operation)
    }

    private static func request(
        path: String,
        method: String,
        body: Data?,
        timeout: TimeInterval
    ) throws -> Data {
        guard ["/health", "/capabilities", "/inspect", "/clean"].contains(path),
              ["GET", "POST"].contains(method) else {
            throw CommunityWatermarkServiceError.invalidResponse
        }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("SignalSieveCommunityEngine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let outputURL = work.appendingPathComponent("response.json")
        let errorURL = work.appendingPathComponent("stderr.txt")
        let bodyURL = work.appendingPathComponent("request.json")
        if let body {
            try body.write(to: bodyURL, options: [.atomic])
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bodyURL.path)
        }
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              FileManager.default.createFile(atPath: errorURL.path, contents: nil),
              let errorHandle = try? FileHandle(forWritingTo: errorURL) else {
            throw CommunityWatermarkServiceError.couldNotStart
        }
        defer { try? errorHandle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        var arguments = [
            "--silent", "--show-error", "--fail-with-body",
            "--noproxy", "*", "--connect-timeout", "2",
            "--max-time", String(Int(max(1, timeout))),
            "--request", method, "--output", outputURL.path
        ]
        if body != nil {
            arguments += [
                "--header", "Content-Type: application/json",
                "--data-binary", "@\(bodyURL.path)"
            ]
        }
        arguments.append(baseURL + path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorHandle
        var environment = ProcessInfo.processInfo.environment
        for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
            environment.removeValue(forKey: key)
        }
        environment["NO_PROXY"] = "*"
        process.environment = environment
        do { try process.run() } catch { throw CommunityWatermarkServiceError.couldNotStart }

        let deadline = Date().addingTimeInterval(max(1, timeout + 1))
        while process.isRunning {
            let size = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > maximumResponseBytes {
                process.terminate()
                process.waitUntilExit()
                throw CommunityWatermarkServiceError.responseTooLarge
            }
            if Date() >= deadline {
                process.terminate()
                process.waitUntilExit()
                throw CommunityWatermarkServiceError.timedOut
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CommunityWatermarkServiceError.serviceUnavailable
        }
        guard let response = try? Data(contentsOf: outputURL), response.count <= maximumResponseBytes else {
            throw CommunityWatermarkServiceError.responseTooLarge
        }
        return response
    }

    private static func boundedString(_ text: String, maximum: Int) -> String {
        text.count <= maximum ? text : String(text.prefix(maximum)) + "…"
    }
}
