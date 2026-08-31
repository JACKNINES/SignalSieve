// SPDX-License-Identifier: MPL-2.0
import AppKit
import SignalSieveCore
import SwiftUI

final class SignalSieveApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct SignalSieveApp: App {
    @NSApplicationDelegateAdaptor(SignalSieveApplicationDelegate.self) private var appDelegate
    @StateObject private var model = SignalSieveViewModel()
    @State private var toolbarSection: ToolbarSection = .review

    var body: some Scene {
        WindowGroup("Signal Sieve", id: "main") {
            MainWindowRoot(model: model, toolbarSection: $toolbarSection)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1_180, height: 800)
        .commands {
            SignalSieveWorkspaceCommands(
                model: model,
                toolbarSection: $toolbarSection
            )
        }
    }
}

private struct SignalSieveWorkspaceCommands: Commands {
    @ObservedObject var model: SignalSieveViewModel
    @Binding var toolbarSection: ToolbarSection

    var body: some Commands {
        CommandMenu(model.localized("Workspace")) {
            ForEach(ToolbarSection.allCases) { section in
                Button(model.localized(section.title)) {
                    toolbarSection = section
                }
                .keyboardShortcut(section.shortcutKey, modifiers: .command)
            }

            Divider()

            Button(model.localized("Paste"), action: model.paste)
                .keyboardShortcut("v", modifiers: [.command, .option])
            Button(model.localized("Inspect"), action: model.inspect)
                .keyboardShortcut(.return, modifiers: .command)

            Divider()

            Button(model.localized("Safe Clean")) { model.clean(mode: .safe) }
                .keyboardShortcut("k", modifiers: .command)
            Button(model.localized("Strict Clean")) { model.clean(mode: .strict) }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Button(model.localized("Clean Links"), action: model.cleanLinks)
                .keyboardShortcut("l", modifiers: [.command, .option])

            Divider()

            Button(model.localized("Use Result"), action: model.moveOutputToInput)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
                .disabled(model.output.isEmpty)
            Button(model.localized("Copy Result"), action: model.copyOutput)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.output.isEmpty)
        }
    }
}

private struct MainWindowRoot: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: SignalSieveViewModel
    @Binding var toolbarSection: ToolbarSection

    var body: some View {
        ContentView(model: model, toolbarSection: $toolbarSection)
            .frame(minWidth: 1_000, minHeight: 720)
            .environment(\.sieveTheme, model.theme)
            .preferredColorScheme(preferredColorScheme)
            .tint(model.theme.usesIridescentPalette ? .pink : .blue)
            .background {
                windowBackground
            }
            .background {
                WindowAppearanceBridge(
                    appearanceOverride: model.theme.appearanceOverride
                )
                .id(model.theme.rawValue)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            .onAppear {
                model.registerMainWindowOpener {
                    openWindow(id: "main")
                }
                model.ensureClipboardMonitoringIsRunning()
                updateApplicationIcon()
            }
            .onChange(of: model.theme) { _ in updateApplicationIcon() }
            .onChange(of: colorScheme) { _ in updateApplicationIcon() }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    model.ensureClipboardMonitoringIsRunning()
                }
            }
    }

    private func updateApplicationIcon() {
        ApplicationIconController.apply(
            theme: model.theme,
            systemIsDark: colorScheme == .dark
        )
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.theme.appearanceOverride {
        case .followSystem: nil
        case .light: .light
        case .dark: .dark
        }
    }

    @ViewBuilder
    private var windowBackground: some View {
        if model.theme.usesIridescentPalette {
            LinearGradient(
                colors: [
                    Color(red: 1.0, green: 0.94, blue: 0.98),
                    Color(red: 0.98, green: 0.95, blue: 1.0),
                    Color(red: 0.93, green: 0.98, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}
