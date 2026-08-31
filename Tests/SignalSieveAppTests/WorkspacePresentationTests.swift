// SPDX-License-Identifier: MPL-2.0
@testable import SignalSieve
import SignalSieveCore
import Testing

@Test("Empty Input presents a neutral not-yet-analyzed Findings state")
func emptyInputUsesNeutralFindingsPresentation() {
    let presentation = WorkspaceFindingsEmptyPresentation.presentation(input: "", findingCount: 0)

    #expect(presentation?.tone == .neutral)
    #expect(presentation?.messageKey == "Paste or type text to analyze hidden Unicode risk.")
    #expect(presentation?.systemImage == "text.badge.plus")
}

@Test("Whitespace-only Input stays neutral instead of producing a green verdict")
func whitespaceInputUsesNeutralFindingsPresentation() {
    let presentation = WorkspaceFindingsEmptyPresentation.presentation(input: " \n\t", findingCount: 0)

    #expect(presentation?.tone == .neutral)
    #expect(presentation?.messageKey != "No known hidden Unicode risk found.")
}

@Test("Analyzed text with no hidden findings may present a clear verdict")
func analyzedTextWithoutFindingsUsesClearPresentation() {
    let presentation = WorkspaceFindingsEmptyPresentation.presentation(
        input: "synthetic local sentence",
        findingCount: 0
    )

    #expect(presentation?.tone == .clear)
    #expect(presentation?.messageKey == "No known hidden Unicode risk found.")
    #expect(presentation?.systemImage == "checkmark.shield.fill")
}

@Test("Visible Findings suppress the empty-state presentation")
func visibleFindingsSuppressEmptyPresentation() {
    #expect(
        WorkspaceFindingsEmptyPresentation.presentation(
            input: "synthetic \u{200B}payload",
            findingCount: 1
        ) == nil
    )
}

@Test("Analyze toolbar keeps every action reachable at the minimum workspace width")
func analyzeToolbarKeepsEveryActionReachableAtMinimumWidth() {
    #expect(
        Set(AnalyzeToolbarPresentation.reachableAtMinimumWidth)
            == Set(WorkspaceAnalyzeAction.allCases)
    )
    #expect(
        AnalyzeToolbarPresentation.minimumWidthVisibleControlEstimate
            < AnalyzeToolbarPresentation.minimumSupportedWorkspaceWidth
    )
    #expect(AnalyzeToolbarPresentation.overflowAtMinimumWidth.isEmpty == false)
    #expect(AnalyzeToolbarPresentation.overflowAtMinimumWidth.contains(.communityEngines))
}

@Test("Workspace section labels and shortcuts remain discoverable")
func workspaceSectionLabelsAndShortcutsRemainDiscoverable() {
    #expect(ToolbarSection.review.title == "Review")
    #expect(ToolbarSection.analyze.title == "Analyze")
    #expect(ToolbarSection.clean.title == "Clean")
    #expect(ToolbarSection.review.shortcutDescription == "Command-1")
    #expect(ToolbarSection.analyze.shortcutDescription == "Command-2")
    #expect(ToolbarSection.clean.shortcutDescription == "Command-3")
}

@Test("New workspace presentation strings are localized in English, Spanish, and Norwegian")
func newWorkspacePresentationStringsAreLocalized() {
    let keys = [
        "Paste or type text to analyze hidden Unicode risk.",
        "Paste or type text to inspect. Analysis stays on this Mac.",
        "Clean or analyze Input to prepare a reviewable Result.",
        "More Tools",
        "Open additional Analyze tools.",
        "Shortcut: %@"
    ]

    for key in keys {
        #expect(AppLocalization.text(key, language: .english) == key)
        #expect(AppLocalization.hasTranslation(key, language: .spanish))
        #expect(AppLocalization.hasTranslation(key, language: .norwegianBokmal))
    }

    #expect(AppLocalization.text("More Tools", language: .spanish) == "Más herramientas")
    #expect(AppLocalization.text("More Tools", language: .norwegianBokmal) == "Flere verktøy")
}
