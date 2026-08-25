// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import SignalSieveCore

@Test("Loads, scores, and verifies a local external pixel module")
func runsExternalPixelModuleContract() throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory
        .appendingPathComponent("SignalSievePixelModule-\(UUID().uuidString)", isDirectory: true)
    let moduleDirectory = directory.appendingPathComponent("module", isDirectory: true)
    let imageURL = directory.appendingPathComponent("input.png")
    let outputURL = directory.appendingPathComponent("output.png")
    defer { try? manager.removeItem(at: directory) }
    try manager.createDirectory(at: moduleDirectory, withIntermediateDirectories: true)

    let manifest = PixelWatermarkModuleManifest(
        schemaVersion: 1,
        name: "Fixture Pixel Module",
        version: "1.0.0",
        executable: "module.sh",
        capabilities: [.score, .regenerate],
        license: "Test-only"
    )
    try JSONEncoder().encode(manifest).write(
        to: moduleDirectory.appendingPathComponent(ExternalPixelWatermarkEngine.manifestFileName)
    )
    let executableURL = moduleDirectory.appendingPathComponent("module.sh")
    try Data(pixelModuleScript.utf8).write(to: executableURL)
    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executableURL.path)

    let image = try #require(Data(base64Encoded: onePixelPNGBase64))
    try image.write(to: imageURL)
    let module = try ExternalPixelWatermarkEngine.loadModule(at: moduleDirectory)
    let score = try ExternalPixelWatermarkEngine.score(
        imageURL: imageURL,
        using: module,
        timeout: 5
    )
    let result = try ExternalPixelWatermarkEngine.regenerateCopy(
        imageURL: imageURL,
        destinationURL: outputURL,
        strength: 0.25,
        using: module,
        timeout: 5
    )

    #expect(score.detector == "fixture")
    #expect(score.score == 0.73)
    #expect(score.isElevated == true)
    #expect(result.width == 1 && result.height == 1)
    #expect(result.originalWasUnchanged)
    #expect(result.beforeScore?.score == 0.73)
    #expect(result.afterScore?.score == 0.73)
    #expect(try Data(contentsOf: imageURL) == image)
    #expect(try Data(contentsOf: outputURL) != image)
}

@Test("Rejects module executables that escape the selected folder")
func rejectsEscapingPixelModuleExecutable() throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory
        .appendingPathComponent("SignalSievePixelEscape-\(UUID().uuidString)", isDirectory: true)
    defer { try? manager.removeItem(at: directory) }
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let manifest = PixelWatermarkModuleManifest(
        schemaVersion: 1,
        name: "Unsafe",
        version: "1",
        executable: "../outside",
        capabilities: [.score],
        license: "Unknown"
    )
    try JSONEncoder().encode(manifest).write(
        to: directory.appendingPathComponent(ExternalPixelWatermarkEngine.manifestFileName)
    )

    #expect(throws: ExternalPixelWatermarkError.unsafeExecutablePath) {
        try ExternalPixelWatermarkEngine.loadModule(at: directory)
    }
}

@Test("External pixel bridge rejects non-finite strength before staging files")
func rejectsInvalidExternalPixelStrength() {
    let root = FileManager.default.temporaryDirectory
    let module = ExternalPixelWatermarkModule(
        rootURL: root,
        executableURL: root.appendingPathComponent("unused"),
        manifest: PixelWatermarkModuleManifest(
            schemaVersion: 1,
            name: "Fixture",
            version: "1",
            executable: "unused",
            capabilities: [.regenerate],
            license: "Test"
        )
    )
    #expect(throws: ExternalPixelWatermarkError.invalidStrength) {
        try ExternalPixelWatermarkEngine.regenerateCopy(
            imageURL: root.appendingPathComponent("missing.png"),
            destinationURL: root.appendingPathComponent("missing-output.png"),
            strength: .nan,
            using: module
        )
    }
}

private let onePixelPNGBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII="

private let pixelModuleScript = """
#!/bin/sh
set -eu
operation="$1"
shift
input=""
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --input) input="$2"; shift 2 ;;
    --output) output="$2"; shift 2 ;;
    --strength) shift 2 ;;
    --json) shift ;;
    *) exit 64 ;;
  esac
done
if [ "$operation" = "score" ]; then
  echo '{"schemaVersion":1,"detector":"fixture","score":0.73,"threshold":0.50,"label":"elevated"}'
elif [ "$operation" = "regenerate" ]; then
  cp "$input" "$output"
  printf 'x' >> "$output"
  echo '{"schemaVersion":1,"status":"ok"}'
else
  exit 64
fi
"""
