// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Platform-neutral instruction for the window layer. Keeping `followSystem`
/// distinct is important: it must remove any previous Light or Dark override
/// instead of reusing the last forced color scheme.
public enum AppThemeAppearanceOverride: Sendable, Equatable {
    case followSystem
    case light
    case dark
}

/// The application-icon artwork selected by a theme. Keeping this mapping in
/// the core makes the automatic light/dark decision deterministic and testable
/// without AppKit or a running Dock.
public enum AppThemeIconVariant: String, CaseIterable, Sendable, Equatable {
    case light = "SignalSieveIcon-Light"
    case dark = "SignalSieveIcon-Dark"
    case iridescentPink = "SignalSieveIcon-IridescentPink"
}

/// The appearance the person chose for the window, stored next to their
/// language choice. `system` keeps the macOS-wide setting, which is how
/// SignalSieve behaved before the picker existed.
public enum AppTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark
    case iridescentPink

    public var id: String { rawValue }

    /// English label, translated through `AppLocalization.text(_:language:)`.
    public var label: String {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        case .iridescentPink: "Iridescent Pink"
        }
    }

    public var symbolName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        case .iridescentPink: "rainbow"
        }
    }

    public var appearanceOverride: AppThemeAppearanceOverride {
        switch self {
        case .system: .followSystem
        case .light, .iridescentPink: .light
        case .dark: .dark
        }
    }

    public var usesIridescentPalette: Bool {
        self == .iridescentPink
    }

    public func iconVariant(systemIsDark: Bool) -> AppThemeIconVariant {
        switch self {
        case .system:
            systemIsDark ? .dark : .light
        case .light:
            .light
        case .dark:
            .dark
        case .iridescentPink:
            .iridescentPink
        }
    }

    /// Restores an explicit local choice and otherwise follows the system.
    public static func persistedOrSystem(_ rawValue: String?) -> AppTheme {
        rawValue.flatMap(AppTheme.init(rawValue:)) ?? .system
    }
}
