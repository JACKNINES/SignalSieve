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

    var label: String {
        switch self {
        case .hiddenUnicode: "Hidden Unicode"
        case .unsafeCode: "Code risks"
        case .binaryContent: "Binary or encoded data"
        case .fileMetadata: "File or image metadata"
        case .trackedLink: "Tracked links"
        case .repeatedPattern: "Repeated patterns"
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
    let clipboardContentKinds: [ClipboardContentKind]
    let pasteboardChangeCount: Int

    var priority: ClipboardAlertPriority {
        ClipboardProtectionAnalyzer.alertPriority(
            hiddenUnicodeRisk: hiddenUnicodeRiskLevel,
            codeRisk: codeRiskLevel
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
        let onSetSuppressed: (ClipboardWarningKind, Bool) -> Void
    }

    private var panel: NSPanel?
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
        onSetSuppressed: @escaping (ClipboardWarningKind, Bool) -> Void
    ) {
        let presentation = Presentation(
            notice: notice,
            language: language,
            onReview: onReview,
            onCleanLinks: onCleanLinks,
            onEnableAutoClean: onEnableAutoClean,
            onShowPatterns: onShowPatterns,
            onOpenFileInspector: onOpenFileInspector,
            onSetSuppressed: onSetSuppressed
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
            onSetSuppressed: presentation.onSetSuppressed,
            onDismiss: { [weak self] in self?.dismissCurrent() }
        )

        let panel = panel ?? makePanel()
        panel.title = AppLocalization.text("SignalSieve Active Guard", language: language)
        let hostingView = NSHostingView(rootView: view)
        panel.contentView = hostingView
        let panelWidth: CGFloat = 700
        panel.setContentSize(
            NSSize(
                width: panelWidth,
                height: max(245, hostingView.fittingSize.height)
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
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 520, height: 245)
        return panel
    }

    private func configure(_ panel: NSPanel, for priority: ClipboardAlertPriority) {
        switch priority {
        case .high:
            panel.isFloatingPanel = true
            panel.level = .modalPanel
        case .standard:
            panel.isFloatingPanel = false
            panel.level = .normal
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
    let onSetSuppressed: (ClipboardWarningKind, Bool) -> Void
    let onDismiss: () -> Void
    @State private var suppressedKinds: Set<ClipboardWarningKind> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill((notice.isHighPriority ? Color.red : Color.orange).opacity(0.16))
                    Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(notice.isHighPriority ? .red : .orange)
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
                    warningCard(
                        kind: .trackedLink,
                        icon: "link.badge.plus",
                        color: .orange,
                        title: formatted(
                            "%d known tracking parameter(s) detected",
                            notice.removedParameterCount
                        ),
                        detail: localized("These are known campaign or share identifiers. Cleaning removes known tracking parameters while preserving functional link parameters.")
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
            }

            Text(localized("These checkboxes take effect immediately. Re-enable a warning later from the Active Guard menu."))
                .font(.caption2)
                .foregroundStyle(.secondary)

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
                        Button(localized("Clean Link Once"), action: onCleanLinks)
                            .sieveSheetButton(.primary)
                            .help(localized("Cleans only the current clipboard copy after confirming it has not changed."))
                    }
                    if notice.patternReport.hasSuspiciousRepetition {
                        Button(localized("Open Pattern Report"), action: onShowPatterns)
                            .sieveSheetButton()
                            .help(localized("Opens the local comparison of recent session-only text samples."))
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    if notice.trackedLinkCount > 0 {
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
                .fill(notice.isHighPriority ? Color.red : Color.orange)
                .frame(height: 3)
        }
    }

    private var headline: String {
        if notice.warningKinds.count > 1 {
            return localized("Multiple clipboard warnings")
        }
        if notice.hiddenUnicodeCount > 0 {
            return localized("Hidden Unicode detected in copied text")
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
            Toggle(suppressionLabel(for: kind), isOn: suppressionBinding(for: kind))
                .toggleStyle(.checkbox)
                .font(.caption)
        }
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(color.opacity(0.45), lineWidth: 1)
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

    private func suppressionLabel(for kind: ClipboardWarningKind) -> String {
        switch kind {
        case .hiddenUnicode:
            localized("Don't show hidden Unicode warnings again")
        case .unsafeCode:
            localized("Don't show source-code warnings again")
        case .binaryContent:
            localized("Don't show binary-data warnings again")
        case .fileMetadata:
            localized("Don't show file-or-image metadata warnings again")
        case .trackedLink:
            localized("Don't show tracked-link warnings again")
        case .repeatedPattern:
            localized("Don't show repeated-pattern warnings again")
        }
    }

    private func suppressionBinding(for kind: ClipboardWarningKind) -> Binding<Bool> {
        Binding(
            get: { suppressedKinds.contains(kind) },
            set: { isSuppressed in
                if isSuppressed {
                    suppressedKinds.insert(kind)
                } else {
                    suppressedKinds.remove(kind)
                }
                onSetSuppressed(kind, isSuppressed)
            }
        )
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
