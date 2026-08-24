// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// A consistent, discoverable copy control for individual analyzer cards.
struct FindingCopyButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "doc.on.doc")
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(title)
        .accessibilityLabel(title)
    }
}
