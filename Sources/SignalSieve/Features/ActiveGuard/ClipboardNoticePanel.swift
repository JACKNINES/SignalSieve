// SPDX-License-Identifier: MPL-2.0
import AppKit
import SignalSieveCore
import SwiftUI

enum ClipboardWarningKind: String, CaseIterable, Hashable {
    case hiddenUnicode
    case unsafeCode
    case binaryContent
    case fileMetadata
    case trackedLink
    case repeatedPattern
    case opaqueIdentifier
    case scamAttempt
    case adaptiveAnomaly

    var label: String {
        switch self {
        case .hiddenUnicode: "Hidden Unicode"
        case .unsafeCode: "Code risks"
        case .binaryContent: "Binary or encoded data"
        case .fileMetadata: "File or image metadata"
        case .trackedLink: "Tracked links"
        case .repeatedPattern: "Repeated patterns"
        case .opaqueIdentifier: "Opaque identifiers"
        case .scamAttempt: "Possible scam attempts"
        case .adaptiveAnomaly: "Usual copy pattern alerts"
        }
    }
}

struct ClipboardNotice: Identifiable {
    let id = UUID()
    let clipboardText: String
    let hiddenUnicodeCount: Int
    let hiddenUnicodeRiskLevel: HiddenElementRiskLevel?
    let codeRiskCount: Int
    let codeRiskLevel: HiddenElementRiskLevel?
    let codeLanguage: String
    let hasSpecificCodeLanguage: Bool
    let binaryKind: BinaryContentKind?
    let binaryByteCount: Int
    let trackedLinkCount: Int
    let removedParameterCount: Int
    let patternReport: PatternReport
    let identifierAnalysis: OpaqueIdentifierAnalysis
    let scamAnalysis: ScamAttemptAnalysis
    let adaptiveAnalysis: AdaptiveCopyAnalysis
    let clipboardContentKinds: [ClipboardContentKind]
    let pasteboardChangeCount: Int
    let automaticCleaningAudit: ClipboardAutomaticCleaningAudit?

    var priority: ClipboardAlertPriority {
        ClipboardProtectionAnalyzer.alertPriority(
            hiddenUnicodeRisk: hiddenUnicodeRiskLevel,
            codeRisk: codeRiskLevel,
            scamThreat: scamAnalysis.isPotentialScam ? scamAnalysis.threatLevel : nil,
            hasElevatedSignal: trackedLinkCount > 0 || adaptiveAnalysis.isAnomalous
        )
    }

    var isHighPriority: Bool { priority == .high }

    var warningKinds: Set<ClipboardWarningKind> {
        var kinds: Set<ClipboardWarningKind> = []
        if hiddenUnicodeCount > 0 { kinds.insert(.hiddenUnicode) }
        if codeRiskCount > 0 { kinds.insert(.unsafeCode) }
        if binaryKind != nil { kinds.insert(.binaryContent) }
        if clipboardContentKinds.contains(.image) || clipboardContentKinds.contains(.fileURL) {
            kinds.insert(.fileMetadata)
        }
        if trackedLinkCount > 0 { kinds.insert(.trackedLink) }
        if patternReport.hasSuspiciousRepetition { kinds.insert(.repeatedPattern) }
        if identifierAnalysis.containsIdentifiers { kinds.insert(.opaqueIdentifier) }
        if scamAnalysis.isPotentialScam { kinds.insert(.scamAttempt) }
        if adaptiveAnalysis.isAnomalous { kinds.insert(.adaptiveAnomaly) }
        return kinds
    }
}

@MainActor
final class ClipboardNoticePanelController {
    private struct Presentation {
        let notice: ClipboardNotice
        let language: AppLanguage
        let onReview: () -> Void
        let onCleanLinks: () -> Void
        let onEnableAutoClean: () -> Void
        let onShowPatterns: () -> Void
        let onOpenFileInspector: () -> Void
        let alertVisibility: ClipboardAlertVisibility
        let onSetAlertVisibility: (ClipboardAlertVisibility) -> Void
        let clipboardProtocol: ClipboardAutomationProtocol
        let onSetClipboardProtocol: (ClipboardAutomationProtocol) -> Void
    }

    private var panel: NSPanel?
    private var hostingController: NSHostingController<ClipboardNoticeView>?
    private var isShowingHighPriorityNotice = false
    private var queuedHighPriorityPresentations: [Presentation] = []

    func show(
        _ notice: ClipboardNotice,
        language: AppLanguage,
        onReview: @escaping () -> Void,
        onCleanLinks: @escaping () -> Void,
        onEnableAutoClean: @escaping () -> Void,
        onShowPatterns: @escaping () -> Void,
        onOpenFileInspector: @escaping () -> Void,
        alertVisibility: ClipboardAlertVisibility,
        onSetAlertVisibility: @escaping (ClipboardAlertVisibility) -> Void,
        clipboardProtocol: ClipboardAutomationProtocol,
        onSetClipboardProtocol: @escaping (ClipboardAutomationProtocol) -> Void
    ) {
        let presentation = Presentation(
            notice: notice,
            language: language,
            onReview: onReview,
            onCleanLinks: onCleanLinks,
            onEnableAutoClean: onEnableAutoClean,
            onShowPatterns: onShowPatterns,
            onOpenFileInspector: onOpenFileInspector,
            alertVisibility: alertVisibility,
            onSetAlertVisibility: onSetAlertVisibility,
            clipboardProtocol: clipboardProtocol,
            onSetClipboardProtocol: onSetClipboardProtocol
        )

        if isShowingHighPriorityNotice, panel?.isVisible == true {
            if notice.isHighPriority {
                queuedHighPriorityPresentations.append(presentation)
                NSApp.requestUserAttention(.criticalRequest)
            }
            return
        }

        present(presentation)
    }

    func dismissCurrent() {
        panel?.orderOut(nil)
        isShowingHighPriorityNotice = false

        guard !queuedHighPriorityPresentations.isEmpty else { return }
        let queued = queuedHighPriorityPresentations.removeFirst()
        DispatchQueue.main.async { [weak self] in
            self?.present(queued)
        }
    }

    func close() {
        queuedHighPriorityPresentations.removeAll()
        isShowingHighPriorityNotice = false
        panel?.orderOut(nil)
    }

    private func present(_ presentation: Presentation) {
        let notice = presentation.notice
        let language = presentation.language
        let view = ClipboardNoticeView(
            notice: notice,
            language: language,
            onReview: presentation.onReview,
            onCleanLinks: presentation.onCleanLinks,
            onEnableAutoClean: presentation.onEnableAutoClean,
            onShowPatterns: presentation.onShowPatterns,
            onOpenFileInspector: presentation.onOpenFileInspector,
            alertVisibility: presentation.alertVisibility,
            onSetAlertVisibility: presentation.onSetAlertVisibility,
            clipboardProtocol: presentation.clipboardProtocol,
            onSetClipboardProtocol: presentation.onSetClipboardProtocol,
            onDismiss: { [weak self] in self?.dismissCurrent() }
        )

        let panel = panel ?? makePanel()
        panel.title = AppLocalization.text("SignalSieve Active Guard", language: language)
        let hostingController = NSHostingController(rootView: view)
        panel.contentViewController = hostingController
        self.hostingController = hostingController
        let hostingView = hostingController.view
        let panelWidth: CGFloat = 700
        let maximumHeight = max(360, (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 720)
        panel.setContentSize(
            NSSize(
                width: panelWidth,
                height: min(maximumHeight - 80, max(245, hostingView.fittingSize.height))
            )
        )
        self.panel = panel
        isShowingHighPriorityNotice = notice.isHighPriority
        configure(panel, for: notice.priority)
        position(panel)
        if notice.isHighPriority {
            NSApp.requestUserAttention(.criticalRequest)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        } else {
            NSApp.requestUserAttention(.informationalRequest)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 280),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "SignalSieve Active Guard"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 520, height: 245)
        return panel
    }

    private func configure(_ panel: NSPanel, for priority: ClipboardAlertPriority) {
        switch priority {
        case .high:
            panel.becomesKeyOnlyIfNeeded = false
            panel.isFloatingPanel = true
            panel.level = .modalPanel
        case .elevated, .standard:
            // The app commonly runs behind the source application. A normal
            // window level could make a delivered warning completely hidden.
            panel.becomesKeyOnlyIfNeeded = true
            panel.isFloatingPanel = true
            panel.level = .floating
        }
    }

    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let frame = panel.frame
        let topInset = max(70, min(180, visibleFrame.height * 0.10))
        panel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - (frame.width / 2),
                y: visibleFrame.maxY - frame.height - topInset
            )
        )
    }
}

private struct ClipboardNoticeView: View {
    let notice: ClipboardNotice
    let language: AppLanguage
    let onReview: () -> Void
    let onCleanLinks: () -> Void
    let onEnableAutoClean: () -> Void
    let onShowPatterns: () -> Void
    let onOpenFileInspector: () -> Void
    let alertVisibility: ClipboardAlertVisibility
    let onSetAlertVisibility: (ClipboardAlertVisibility) -> Void
    let clipboardProtocol: ClipboardAutomationProtocol
    let onSetClipboardProtocol: (ClipboardAutomationProtocol) -> Void
    let onDismiss: () -> Void
    @State private var selectedProtocol: ClipboardAutomationProtocol = .reviewAll
    @State private var selectedAlertVisibility: ClipboardAlertVisibility = .showAll

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(priorityColor.opacity(0.16))
                    Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(priorityColor)
                }
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(.headline)
                    Text(localized("SignalSieve inspected this copy locally. Clipboard contents were not uploaded."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // The severity notice belongs with the headline, not as a
                    // loose line under it.
                    if notice.isHighPriority {
                        Label(
                            localized("High-priority finding · this alert stays in front until you close it"),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.top, 1)
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(localized("Dismiss"))
            }

            if notice.isHighPriority, let audit = notice.automaticCleaningAudit {
                automaticRedRiskBanner(audit)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                if notice.codeRiskCount > 0 {
                    warningCard(
                        kind: .unsafeCode,
                        icon: "chevron.left.forwardslash.chevron.right",
                        color: riskColor(notice.codeRiskLevel),
                        title: formatted(
                            "%d source-code risk(s) detected",
                            notice.codeRiskCount
                        ),
                        detail: localized("Code Guard found invisible controls, look-alike identifiers, or characters that can change how copied code is interpreted. Open the details before running or sharing it.")
                    )
                }
                if notice.hiddenUnicodeCount > 0 {
                    warningCard(
                        kind: .hiddenUnicode,
                        icon: "character.cursor.ibeam",
                        color: riskColor(notice.hiddenUnicodeRiskLevel),
                        title: formatted(
                            "%d hidden Unicode element(s) detected",
                            notice.hiddenUnicodeCount
                        ),
                        detail: localized("Invisible Unicode controls can change how text is displayed or interpreted. Open the details to review the exact code points before sharing.")
                    )
                }
                if let binaryKind = notice.binaryKind {
                    warningCard(
                        kind: .binaryContent,
                        icon: "shippingbox.fill",
                        color: .yellow,
                        title: formatted(
                            "%@ detected · approximately %d byte(s)",
                            AppLocalization.text(binaryKind.rawValue, language: language),
                            notice.binaryByteCount
                        ),
                        detail: localized("Binary Guard reports encoded or binary-looking content without decoding or executing it. Review the source before using it.")
                    )
                }
                if notice.clipboardContentKinds.contains(.image)
                    || notice.clipboardContentKinds.contains(.fileURL) {
                    warningCard(
                        kind: .fileMetadata,
                        icon: "photo.on.rectangle.angled",
                        color: .blue,
                        title: localized("Image or file copied"),
                        detail: localized("This clipboard item may carry C2PA, EXIF, XMP, or other metadata. SignalSieve recognized the content type but has not inspected the file bytes.")
                    )
                }
                if notice.trackedLinkCount > 0 {
                    let hasRemovedParameters = notice.removedParameterCount > 0
                    warningCard(
                        kind: .trackedLink,
                        icon: "link.badge.plus",
                        color: .orange,
                        title: hasRemovedParameters
                            ? formatted("%d known tracking parameter(s) detected", notice.removedParameterCount)
                            : localized("Opaque redirect or short link detected"),
                        detail: hasRemovedParameters
                            ? localized("These are known campaign or share identifiers. Cleaning removes known tracking parameters while preserving functional link parameters.")
                            : localized("Signal Sieve did not contact the redirect server. Its final destination cannot be resolved offline, so the link was reported but not rewritten.")
                    )
                }
                if notice.patternReport.hasSuspiciousRepetition {
                    warningCard(
                        kind: .repeatedPattern,
                        icon: "brain.head.profile",
                        color: .yellow,
                        title: localized("A pattern appeared across your last 3 substantial copies"),
                        detail: localized("Similar wording or structure appeared repeatedly. This is a correlation signal, not proof of a watermark, authorship, or source.")
                    )
                }
                if notice.identifierAnalysis.containsIdentifiers {
                    warningCard(
                        kind: .opaqueIdentifier,
                        icon: "number.square.fill",
                        color: .yellow,
                        title: formatted(
                            "%d opaque identifier(s) detected",
                            notice.identifierAnalysis.findings.count
                        ),
                        detail: localized("UUIDs can be legitimate, but they can also correlate a copied message, document, device, or account across systems. Review before sharing.")
                    )
                }
                if notice.scamAnalysis.isPotentialScam {
                    warningCard(
                        kind: .scamAttempt,
                        icon: "exclamationmark.bubble.fill",
                        color: notice.scamAnalysis.threatLevel == .high ? .red : .orange,
                        title: formatted(
                            "Possible scam attempt · score %d/100",
                            notice.scamAnalysis.score
                        ),
                        detail: formatted(
                            "%d explainable signal(s), including brand look-alikes, domain mismatch, urgency, or a dangerous URL structure. SignalSieve did not open the link.",
                            notice.scamAnalysis.signals.count
                        )
                    )
                }
                if notice.adaptiveAnalysis.isAnomalous {
                    warningCard(
                        kind: .adaptiveAnomaly,
                        icon: "waveform.path.ecg.rectangle.fill",
                        color: .orange,
                        title: localized("This copy looks different from your usual copies"),
                        detail: formatted(
                            "%d writing measurement(s) were unusual. This local learner never stores clipboard text.",
                            notice.adaptiveAnalysis.deviations.count
                        )
                    )
                }
                }
            }
            .frame(maxHeight: 420)

            VStack(alignment: .leading, spacing: 7) {
                Text(localized("Copying Settings"))
                    .font(.caption.weight(.semibold))
                settingsCheckbox(
                    isSelected: selectedAlertVisibility == .hideGreenAndYellow,
                    label: "Stop showing green and yellow alerts",
                    help: "Orange and red alerts remain visible. Red alerts cannot be disabled."
                ) {
                    selectedAlertVisibility = selectedAlertVisibility == .hideGreenAndYellow
                        ? .showAll
                        : .hideGreenAndYellow
                    onSetAlertVisibility(selectedAlertVisibility)
                }
                settingsCheckbox(
                    isSelected: selectedAlertVisibility == .redOnly,
                    label: "Stop showing green through orange alerts",
                    help: "Only red alerts remain visible. Red alerts cannot be disabled."
                ) {
                    selectedAlertVisibility = selectedAlertVisibility == .redOnly
                        ? .showAll
                        : .redOnly
                    onSetAlertVisibility(selectedAlertVisibility)
                }
                Text(localized("Alert visibility choices are mutually exclusive."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                protocolToggle(
                    .safeClean,
                    label: "Automatically use Safe Clean for copied text",
                    help: "Eligible future text copies are Safe Cleaned. Alert visibility is controlled separately."
                )
                protocolToggle(
                    .strictClean,
                    label: "Automatically use Strict Clean for copied text",
                    help: "Eligible future text copies are Strict Cleaned. Emoji and some writing systems may change. Alert visibility is controlled separately."
                )
                Text(localized("Safe Clean and Strict Clean are mutually exclusive. Alert visibility is a separate setting."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(localized("Automatic text cleaning skips source code, files, images, and privacy-sensitive clipboard types."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if !notice.clipboardText.isEmpty {
                        Button(localized("Open Details"), action: onReview)
                            .sieveSheetButton(.primary)
                            .help(localized("Opens SignalSieve with the copied text and its exact findings."))
                    }
                    if notice.clipboardContentKinds.contains(.image)
                        || notice.clipboardContentKinds.contains(.fileURL) {
                        Button(
                            localized(notice.clipboardContentKinds.contains(.image)
                                ? "Inspect Copied Image"
                                : "Open File Inspector"),
                            action: onOpenFileInspector
                        )
                            .sieveSheetButton(.primary)
                            .help(localized(notice.clipboardContentKinds.contains(.image)
                                ? "Paste the current clipboard image into the read-only inspector and analyze it locally."
                                : "Open the read-only inspector to choose and analyze the copied file."))
                    }
                    if notice.trackedLinkCount > 0 {
                        Button(
                            localized(notice.removedParameterCount > 0 ? "Clean Link Once" : "Review Link Report"),
                            action: notice.removedParameterCount > 0 ? onCleanLinks : onReview
                        )
                            .sieveSheetButton(.primary)
                            .help(localized(notice.removedParameterCount > 0
                                ? "Cleans only the current clipboard copy after confirming it has not changed."
                                : "Opens the local report without contacting or resolving the link."))
                    }
                    if notice.patternReport.hasSuspiciousRepetition {
                        Button(localized("Open Pattern Report"), action: onShowPatterns)
                            .sieveSheetButton()
                            .help(localized("Opens the local comparison of recent session-only text samples."))
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    if notice.removedParameterCount > 0 {
                        Text(localized("For future copied links:"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(localized("Turn On Automatic Link Cleaning"), action: onEnableAutoClean)
                            .sieveSheetButton()
                            .help(localized("Automatically cleans known tracking parameters from future copied links."))
                    }
                    Spacer()
                    Button(localized("Close"), action: onDismiss)
                        .sieveSheetButton()
                }
            }
            .controlSize(.regular)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 700)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            // Severity reads before any word does.
            Rectangle()
                .fill(priorityColor)
                .frame(height: 3)
        }
        .onAppear {
            selectedProtocol = clipboardProtocol
            selectedAlertVisibility = alertVisibility
        }
    }

    private var headline: String {
        if notice.warningKinds.count > 1 {
            return localized("Multiple clipboard warnings")
        }
        if notice.hiddenUnicodeCount > 0 {
            return localized("Hidden Unicode detected in copied text")
        }
        if notice.scamAnalysis.isPotentialScam {
            return localized("Possible scam attempt detected")
        }
        if notice.identifierAnalysis.containsIdentifiers {
            return localized("Opaque identifier detected in copied text")
        }
        if notice.adaptiveAnalysis.isAnomalous {
            return localized("This copy looks different from your usual copies")
        }
        if notice.codeRiskCount > 0 {
            return notice.hasSpecificCodeLanguage
                ? formatted("%@ code contains suspicious Unicode", notice.codeLanguage)
                : localized("Source code contains suspicious Unicode")
        }
        if notice.binaryKind != nil {
            return localized("Binary or encoded data detected in copied text")
        }
        if notice.clipboardContentKinds.contains(.image)
            || notice.clipboardContentKinds.contains(.fileURL) {
            return localized("Image copied · metadata not yet inspected")
        }
        if notice.trackedLinkCount > 0 {
            return localized("Tracking detected in a copied link")
        }
        return localized("Repeated pattern detected across recent copies")
    }

    private func warningCard(
        kind: ClipboardWarningKind,
        icon: String,
        color: Color,
        title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title).font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: icon).foregroundStyle(color)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(color.opacity(0.45), lineWidth: 1)
        }
    }

    private func automaticRedRiskBanner(
        _ audit: ClipboardAutomaticCleaningAudit
    ) -> some View {
        let removed = audit.redRiskWasRemoved
        let mode = localized(audit.mode == .safe ? "Safe Clean" : "Strict Clean")
        let title = removed
            ? formatted("%@ removed the detected red text risk from the current clipboard", mode)
            : formatted("%@ did not remove every red finding", mode)
        let detail = removed
            ? localized("The clipboard text was reanalyzed after cleaning and no red text finding remained. Still use caution: the original source may have malicious intent.")
            : localized("A red finding remains or automatic cleaning was skipped. Do not trust the content solely because cleaning is enabled; its source may have malicious intent.")
        let color: Color = removed ? .green : .red

        return VStack(alignment: .leading, spacing: 6) {
            Label(
                title,
                systemImage: removed ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(color.opacity(0.35), lineWidth: 1)
        }
    }

    private func riskColor(_ level: HiddenElementRiskLevel?) -> Color {
        switch level {
        case .high: .red
        case .medium: .orange
        case .clear: .green
        case .suspicious, nil: .yellow
        }
    }

    private var priorityColor: Color {
        switch notice.priority {
        case .high: .red
        case .elevated: .orange
        case .standard: .yellow
        }
    }

    private func protocolToggle(
        _ value: ClipboardAutomationProtocol,
        label: String,
        help: String
    ) -> some View {
        settingsCheckbox(
            isSelected: selectedProtocol == value,
            label: label,
            help: help
        ) {
            selectedProtocol = selectedProtocol == value ? .reviewAll : value
            onSetClipboardProtocol(selectedProtocol)
        }
    }

    private func settingsCheckbox(
        isSelected: Bool,
        label: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(localized(label))
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.caption)
        .help(localized(help))
        .accessibilityValue(isSelected ? "On" : "Off")
    }

    private func localized(_ english: String) -> String {
        AppLocalization.text(english, language: language)
    }

    private func formatted(_ englishFormat: String, _ arguments: CVarArg...) -> String {
        String(
            format: AppLocalization.text(englishFormat, language: language),
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }
}
