// SPDX-License-Identifier: MPL-2.0
import Foundation

/// The appearance the person chose for the window, stored next to their
/// language choice. `system` keeps the macOS-wide setting, which is how
/// SignalSieve behaved before the picker existed.
public enum AppTheme: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    /// English label, translated through `AppLocalization.text(_:language:)`.
    public var label: String {
        switch self {
        case .system: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public var symbolName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// Restores an explicit local choice and otherwise follows the system.
    public static func persistedOrSystem(_ rawValue: String?) -> AppTheme {
        rawValue.flatMap(AppTheme.init(rawValue:)) ?? .system
    }
}
