// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// Shared chrome for every sheet: a fixed header that names the tool, a body
/// that owns the scrolling, and a fixed footer whose trailing edge always holds
/// the sheet's main action. Before this, each sheet placed "Done" and its
/// primary action wherever the flowing content happened to put them.
struct SheetScaffold<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let doneTitle: String
    let onDone: () -> Void
    /// A short count shown next to the title, e.g. "12 copies".
    var headerBadge: String?
    var footerNote: String?
    var showsFooter: Bool = true
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(20)

            if showsFooter {
                Divider()
                footerBar
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(SievePalette.accentFill(colorScheme))
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SievePalette.accentInk(colorScheme))
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if let headerBadge {
                Text(headerBadge)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SievePalette.trackFill(colorScheme), in: Capsule())
            }

            Button(doneTitle, action: onDone)
                .sieveSheetButton()
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(headerBackground)
    }

    private var footerBar: some View {
        HStack(spacing: 9) {
            if let footerNote {
                Text(footerNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            footer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(headerBackground)
    }

    private var headerBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.035) : Color.black.opacity(0.030)
    }
}

extension SheetScaffold where Footer == EmptyView {
    /// A sheet whose only action is closing it.
    init(
        title: String,
        subtitle: String,
        systemImage: String,
        doneTitle: String,
        onDone: @escaping () -> Void,
        headerBadge: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            doneTitle: doneTitle,
            onDone: onDone,
            headerBadge: headerBadge,
            footerNote: nil,
            showsFooter: false,
            content: content,
            footer: { EmptyView() }
        )
    }
}

/// A metric from a scan report: the number reads first, the label explains it.
struct SheetStatTile: View {
    let value: String
    let label: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        }
    }
}
