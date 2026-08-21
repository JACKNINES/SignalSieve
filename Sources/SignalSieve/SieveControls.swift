// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import SignalSieveCore

/// Which group of tools the contextual toolbar is showing. Replaces the three
/// permanently stacked rows with one row that follows the selected section.
enum ToolbarSection: String, CaseIterable, Identifiable {
    case review
    case analyze
    case clean

    var id: String { rawValue }

    /// English keys already present in `AppLocalization`.
    var title: String {
        switch self {
        case .review: "Review"
        case .analyze: "Analyze"
        case .clean: "Clean"
        }
    }

    var symbolName: String {
        switch self {
        case .review: "doc.text.magnifyingglass"
        case .analyze: "waveform.badge.magnifyingglass"
        case .clean: "wand.and.stars"
        }
    }

    var hint: String {
        switch self {
        case .review: "Inspect pasted text and control clipboard monitoring."
        case .analyze: "Local forensic tools for files, images, and the current text."
        case .clean: "Produces reviewable output. Code is never modified automatically."
        }
    }
}

extension AppTheme {
    /// `nil` hands the window back to the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// How much weight a toolbar control carries. At most one `primary` per
/// section: the control that actually starts the section's task.
enum ToolbarEmphasis {
    /// Opens a tool or performs a secondary action.
    case standard
    /// Acts on the text currently in the Input panel.
    case accented
    /// Starts the section's main task.
    case primary
    /// Removes something. Keeps the standard container and colors the label,
    /// which is how macOS marks a destructive push button.
    case destructive
}

/// Shared palette so buttons, menus, and segmented controls stay identical in
/// both themes, and so disabled controls keep a readable label instead of the
/// system's very low-contrast dimming.
enum SievePalette {
    static func label(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.90) : Color.black.opacity(0.85)
    }

    /// Disabled controls must still say what the app can do. The system default
    /// lands near 26% and disappears into a dark container.
    static func disabledLabel(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.48) : Color.black.opacity(0.45)
    }

    static func controlFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.white
    }

    static func controlStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.18)
    }

    static func disabledFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.045) : Color.white.opacity(0.50)
    }

    static func disabledStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.14)
    }

    static func trackFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.065)
    }

    static func selectedSegmentFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.22) : Color.white
    }

    static func accentFill(_ scheme: ColorScheme) -> Color {
        Color.blue.opacity(scheme == .dark ? 0.22 : 0.13)
    }

    static func accentStroke(_ scheme: ColorScheme) -> Color {
        Color.blue.opacity(scheme == .dark ? 0.55 : 0.42)
    }

    /// Blue readable as text on each theme's control fill.
    static func accentInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.38, green: 0.69, blue: 1.0)
            : Color(red: 0.0, green: 0.38, blue: 0.78)
    }
}

private let sieveControlHeight: CGFloat = 24
private let sieveControlRadius: CGFloat = 6

/// Toolbar button style. Fixes the label at its intrinsic width so a long name
/// such as "Pixel Lab" is never truncated, and keeps disabled labels readable.
struct SieveToolbarButtonStyle: ButtonStyle {
    var emphasis: ToolbarEmphasis = .standard
    /// Sheets use a slightly taller control than the main toolbar.
    var height: CGFloat = sieveControlHeight

    func makeBody(configuration: Configuration) -> some View {
        SieveToolbarButtonBody(configuration: configuration, emphasis: emphasis, height: height)
    }
}

private struct SieveToolbarButtonBody: View {
    let configuration: SieveToolbarButtonStyle.Configuration
    let emphasis: ToolbarEmphasis
    let height: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 12, weight: emphasis == .primary ? .semibold : .medium))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, height > sieveControlHeight ? 13 : 9)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(fill, in: RoundedRectangle(cornerRadius: sieveControlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: sieveControlRadius, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            }
            .shadow(color: shadow, radius: 1, y: 0.5)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .contentShape(RoundedRectangle(cornerRadius: sieveControlRadius, style: .continuous))
    }

    private var foreground: Color {
        guard isEnabled else { return SievePalette.disabledLabel(colorScheme) }
        switch emphasis {
        case .primary: return .white
        case .accented: return SievePalette.accentInk(colorScheme)
        case .destructive: return .red
        case .standard: return SievePalette.label(colorScheme)
        }
    }

    private var fill: Color {
        guard isEnabled else { return SievePalette.disabledFill(colorScheme) }
        switch emphasis {
        case .primary: return .blue
        case .accented: return SievePalette.accentFill(colorScheme)
        case .standard, .destructive: return SievePalette.controlFill(colorScheme)
        }
    }

    private var stroke: Color {
        guard isEnabled else { return SievePalette.disabledStroke(colorScheme) }
        switch emphasis {
        case .primary: return .clear
        case .accented: return SievePalette.accentStroke(colorScheme)
        case .destructive: return Color.red.opacity(colorScheme == .dark ? 0.45 : 0.35)
        case .standard: return SievePalette.controlStroke(colorScheme)
        }
    }

    private var shadow: Color {
        guard isEnabled else { return .clear }
        return colorScheme == .dark ? Color.black.opacity(0.30) : Color.black.opacity(0.10)
    }
}

extension View {
    /// Applies the toolbar button style and keeps the control from shrinking
    /// below its label, which is what caused truncated button titles.
    func sieveToolbarButton(_ emphasis: ToolbarEmphasis = .standard) -> some View {
        buttonStyle(SieveToolbarButtonStyle(emphasis: emphasis))
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Same style at the taller size the sheet header and footer bars use.
    func sieveSheetButton(_ emphasis: ToolbarEmphasis = .standard) -> some View {
        buttonStyle(SieveToolbarButtonStyle(emphasis: emphasis, height: 28))
            .fixedSize(horizontal: true, vertical: false)
    }
}

/// Label that makes a `Menu` match the surrounding toolbar buttons, including
/// its own chevron so the system indicator can stay hidden.
struct SieveMenuLabel: View {
    let title: String
    let systemImage: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 5) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 9)
        .frame(height: sieveControlHeight)
        .foregroundStyle(SievePalette.label(colorScheme))
        .background(
            SievePalette.controlFill(colorScheme),
            in: RoundedRectangle(cornerRadius: sieveControlRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: sieveControlRadius, style: .continuous)
                .stroke(SievePalette.controlStroke(colorScheme), lineWidth: 1)
        }
    }
}

/// A thin vertical rule that groups toolbar controls by consequence.
struct SieveToolbarDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 3)
    }
}

/// Segmented control that selects the visible toolbar section.
struct ToolbarSectionPicker: View {
    @Binding var selection: ToolbarSection
    let localized: (String) -> String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ToolbarSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    Label(localized(section.title), systemImage: section.symbolName)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: selection == section ? .semibold : .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .foregroundStyle(
                            selection == section
                                ? SievePalette.label(colorScheme)
                                : Color.secondary
                        )
                        .background {
                            if selection == section {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(SievePalette.selectedSegmentFill(colorScheme))
                                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.16), radius: 1, y: 1)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == section ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(
            SievePalette.trackFill(colorScheme),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .fixedSize()
    }
}

/// Automatic / Light / Dark, next to the language picker in the header.
struct ThemePicker: View {
    @Binding var selection: AppTheme
    let localized: (String) -> String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Text(localized("Theme"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            HStack(spacing: 2) {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        selection = theme
                    } label: {
                        Image(systemName: theme.symbolName)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 26, height: 20)
                            .foregroundStyle(
                                selection == theme
                                    ? SievePalette.accentInk(colorScheme)
                                    : Color.secondary
                            )
                            .background {
                                if selection == theme {
                                    Capsule().fill(SievePalette.selectedSegmentFill(colorScheme))
                                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.16), radius: 1, y: 1)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(localized(theme.label))
                    .accessibilityLabel(localized(theme.label))
                    .accessibilityAddTraits(selection == theme ? [.isSelected] : [])
                }
            }
            .padding(2)
            .background(SievePalette.trackFill(colorScheme), in: Capsule())
        }
        .fixedSize()
    }
}
