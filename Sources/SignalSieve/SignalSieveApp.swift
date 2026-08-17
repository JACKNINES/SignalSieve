// SPDX-License-Identifier: MPL-2.0
import SwiftUI

@main
struct SignalSieveApp: App {
    @StateObject private var model = SignalSieveViewModel()

    var body: some Scene {
        WindowGroup("Signal Sieve", id: "main") {
            MainWindowRoot(model: model)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1_180, height: 800)
    }
}

private struct MainWindowRoot: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: SignalSieveViewModel

    var body: some View {
        ContentView(model: model)
            .frame(minWidth: 1_000, minHeight: 720)
            .onAppear {
                model.registerMainWindowOpener {
                    openWindow(id: "main")
                }
            }
    }
}
