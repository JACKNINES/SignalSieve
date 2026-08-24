// SPDX-License-Identifier: MPL-2.0
import AppKit
import SignalSieveCore

/// Applies only bundled, immutable artwork to the running application's Dock
/// icon. Finder continues to use the signed bundle's base ICNS; no bundle file
/// or system icon cache is modified at runtime.
@MainActor
enum ApplicationIconController {
    static func apply(theme: AppTheme, systemIsDark: Bool) {
        guard let image = image(theme: theme, systemIsDark: systemIsDark) else { return }
        NSApplication.shared.applicationIconImage = image
    }

    /// Returns the same immutable themed artwork used by the Dock so other
    /// brand surfaces cannot drift to a different icon or theme mapping.
    static func image(theme: AppTheme, systemIsDark: Bool) -> NSImage? {
        let variant = theme.iconVariant(systemIsDark: systemIsDark)
        guard let image = bundledImage(for: variant) else { return nil }
        image.isTemplate = false
        return image
    }

    private static func bundledImage(for variant: AppThemeIconVariant) -> NSImage? {
        guard let url = Bundle.main.url(
            forResource: variant.rawValue,
            withExtension: "png",
            subdirectory: "ThemeIcons"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
