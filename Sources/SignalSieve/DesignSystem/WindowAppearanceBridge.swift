// SPDX-License-Identifier: MPL-2.0
import AppKit
import SignalSieveCore
import SwiftUI

/// Applies one appearance to the entire AppKit window. SwiftUI's
/// `preferredColorScheme(nil)` can release its environment override before
/// AppKit materials have finished changing, briefly leaving light labels on a
/// dark window (or the reverse). Updating `NSWindow.appearance` makes native
/// materials, semantic text colors, sheets, and the SwiftUI environment move
/// together.
struct WindowAppearanceBridge: NSViewRepresentable {
    let appearanceOverride: AppThemeAppearanceOverride

    func makeNSView(context: Context) -> WindowAppearanceView {
        WindowAppearanceView(appearanceOverride: appearanceOverride)
    }

    func updateNSView(_ nsView: WindowAppearanceView, context: Context) {
        nsView.appearanceOverride = appearanceOverride
    }
}

final class WindowAppearanceView: NSView {
    var appearanceOverride: AppThemeAppearanceOverride {
        didSet { applyAppearanceIfPossible() }
    }

    init(appearanceOverride: AppThemeAppearanceOverride) {
        self.appearanceOverride = appearanceOverride
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyAppearanceIfPossible()
    }

    private func applyAppearanceIfPossible() {
        guard let window else { return }

        let requestedAppearance: NSAppearance?
        switch appearanceOverride {
        case .followSystem:
            requestedAppearance = nil
        case .light:
            requestedAppearance = NSAppearance(named: .aqua)
        case .dark:
            requestedAppearance = NSAppearance(named: .darkAqua)
        }

        // Always assign the explicit override. Comparing with the effective
        // inherited appearance could incorrectly treat a system-dark window as
        // already updated when the person selected Light.
        window.appearance = requestedAppearance
        window.contentView?.appearance = requestedAppearance
        window.contentView?.needsLayout = true
        window.contentView?.needsDisplay = true
        window.contentView?.displayIfNeeded()
        window.invalidateShadow()
    }
}
