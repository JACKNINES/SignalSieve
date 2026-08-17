// SPDX-License-Identifier: MPL-2.0
import Foundation
import SignalSieveCore

@main
enum SignalSievePixelBaselineCLI {
    private static let maximumInputBytes = 256 * 1_024 * 1_024

    static func main() {
        do {
            let command = try parse(Array(CommandLine.arguments.dropFirst()))
            switch command {
            case .score(let input):
                let data = try readBounded(input)
                let report = try PixelLSBForensics.analyze(data)
                try emit([
                    "schemaVersion": 1,
                    "detector": "Signal Sieve LSB Forensics v1",
                    "score": report.score,
                    "threshold": report.threshold,
                    "label": report.hasEnoughSamples
                        ? (report.isElevated
                            ? "elevated LSB carrier regularity"
                            : "no elevated LSB carrier regularity")
                        : "insufficient pixel sample"
                ])
            case .regenerate(let input, let output, let strength):
                let data = try readBounded(input)
                let regenerated = try PixelLSBForensics.regenerate(data, strength: strength)
                guard regenerated.count <= maximumInputBytes else { throw CLIError.invalidOutput }
                try regenerated.write(to: output)
                try emit([
                    "schemaVersion": 1,
                    "status": "ok",
                    "method": "deterministic LSB quantization"
                ])
            }
        } catch {
            FileHandle.standardError.write(Data("Pixel baseline failed: \(error)\n".utf8))
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private enum Command {
        case score(input: URL)
        case regenerate(input: URL, output: URL, strength: Double)
    }

    private enum CLIError: Error {
        case invalidArguments
        case invalidInput
        case invalidOutput
    }

    private static func parse(_ arguments: [String]) throws -> Command {
        guard let operation = arguments.first,
              operation == "score" || operation == "regenerate" else {
            throw CLIError.invalidArguments
        }
        var input: URL?
        var output: URL?
        var strength = 0.25
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--input" where index + 1 < arguments.count:
                input = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--output" where index + 1 < arguments.count:
                output = URL(fileURLWithPath: arguments[index + 1])
                index += 2
            case "--strength" where index + 1 < arguments.count:
                guard let value = Double(arguments[index + 1]), value.isFinite else {
                    throw CLIError.invalidArguments
                }
                strength = value
                index += 2
            case "--json":
                index += 1
            default:
                throw CLIError.invalidArguments
            }
        }
        guard let input else { throw CLIError.invalidArguments }
        if operation == "score" { return .score(input: input) }
        guard let output else { throw CLIError.invalidArguments }
        return .regenerate(input: input, output: output, strength: strength)
    }

    private static func readBounded(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              (values.fileSize ?? maximumInputBytes + 1) <= maximumInputBytes else {
            throw CLIError.invalidInput
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= maximumInputBytes else { throw CLIError.invalidInput }
        return data
    }

    private static func emit(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
}
