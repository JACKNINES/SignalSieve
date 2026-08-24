// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import SignalSieveCore

@Test("Runs a bounded same-configuration statistical watermark detector")
func runsExternalTextWatermarkDetector() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SignalSieveTextModule-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let manifest = TextWatermarkModuleManifest(schemaVersion: 1, name: "Fixture KGW", version: "1", executable: "detector.sh", schemes: ["KGW"], verificationMode: .sameConfiguration, requiresSecretKey: true, license: "Test-only")
    try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent(ExternalTextWatermarkEngine.manifestFileName))
    let executable = directory.appendingPathComponent("detector.sh")
    try Data("#!/bin/sh\necho '{\"schemaVersion\":1,\"detector\":\"fixture\",\"scheme\":\"KGW\",\"statistic\":4.2,\"threshold\":3.0,\"pValue\":0.0002,\"detected\":true,\"tokenCount\":180}'\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let module = try ExternalTextWatermarkEngine.loadModule(at: directory)
    let result = try ExternalTextWatermarkEngine.detect("A sufficiently long local test sample.", using: module, timeout: 5)
    #expect(result.scheme == "KGW")
    #expect(result.detected == true)
    #expect(result.pValue == 0.0002)
}

@Test("Rejects a detector response for a scheme it did not advertise")
func rejectsUnadvertisedTextWatermarkScheme() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SignalSieveTextScheme-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let manifest = TextWatermarkModuleManifest(schemaVersion: 1, name: "Fixture", version: "1", executable: "detector.sh", schemes: ["KGW"], verificationMode: .sameConfiguration, requiresSecretKey: false, license: "Test")
    try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent(ExternalTextWatermarkEngine.manifestFileName))
    let executable = directory.appendingPathComponent("detector.sh")
    try Data("#!/bin/sh\necho '{\"schemaVersion\":1,\"detector\":\"fixture\",\"scheme\":\"SynthID\",\"statistic\":1,\"tokenCount\":20}'\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let module = try ExternalTextWatermarkEngine.loadModule(at: directory)
    #expect(throws: ExternalTextWatermarkError.unadvertisedScheme) { try ExternalTextWatermarkEngine.detect("text", using: module, timeout: 5) }
}
