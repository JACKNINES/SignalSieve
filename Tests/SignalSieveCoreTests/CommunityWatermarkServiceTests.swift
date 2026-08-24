// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import SignalSieveCore

@Test("Community engine request encodes text without placing it in a URL")
func buildsBoundedCommunityRequest() throws {
    let source = "private sample \u{200B}"
    let body = try CommunityWatermarkService.makeTextRequestBody(source)
    let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
    let encoded = try #require(object["file"])
    let decoded = try #require(Data(base64Encoded: encoded))

    #expect(object["name"] == "clipboard.txt")
    #expect(String(data: decoded, encoding: .utf8) == source)
    #expect(CommunityWatermarkService.baseURL == "http://127.0.0.1:8765")
}

@Test("Community clean response decodes output and omits it from the report")
func parsesCommunityCleanResponse() throws {
    let cleaned = "clean result"
    let payload = try JSONSerialization.data(withJSONObject: [
        "ok": true,
        "kind": "text",
        "suspicious": false,
        "cleaned": Data(cleaned.utf8).base64EncodedString(),
        "report": ["removed": 2]
    ])
    let result = try CommunityWatermarkService.parseResult(payload, operation: .clean)

    #expect(result.cleanedText == cleaned)
    #expect(result.kind == "text")
    #expect(result.suspicious == false)
    #expect(!result.report.contains(Data(cleaned.utf8).base64EncodedString()))
}

@Test("Community service errors remain explicit")
func parsesCommunityServiceRejection() throws {
    let payload = try JSONSerialization.data(withJSONObject: [
        "ok": false,
        "error": "unsupported format"
    ])
    #expect(throws: CommunityWatermarkServiceError.serviceRejected("unsupported format")) {
        try CommunityWatermarkService.parseResult(payload, operation: .inspect)
    }
}
