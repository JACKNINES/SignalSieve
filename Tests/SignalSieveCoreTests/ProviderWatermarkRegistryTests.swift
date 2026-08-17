// SPDX-License-Identifier: MPL-2.0
import SignalSieveCore
import Testing

@Test("Provider registry never invents undisclosed Claude implementation details")
func recordsClaudeProfileConservatively() throws {
    let profile = try #require(
        ProviderWatermarkRegistry.profile(id: "anthropic.claude.text.2026-08")
    )

    #expect(profile.mechanism == .undisclosed)
    #expect(profile.detectorAvailability == .forthcoming)
    #expect(profile.effectiveFrom == "2026-08-02")
    #expect(profile.officialDocumentationURL.host == "support.claude.com")
    #expect(!ProviderWatermarkRegistry.integratedAdapterProfileIDs.contains(profile.id))
}

@Test("No compatible provider detector is claimed as integrated")
func hasNoInventedProviderAdapters() {
    #expect(ProviderWatermarkRegistry.integratedAdapterProfileIDs.isEmpty)
}
