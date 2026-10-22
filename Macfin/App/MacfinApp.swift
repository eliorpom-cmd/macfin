import SwiftUI

@main
struct MacfinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    init() {
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
    }

    var body: some Scene {
        Window("Macfin", id: "main") {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("Refresh") { Task { await model.refresh() } }
                    .keyboardShortcut("r")
                    .disabled(model.phase != .ready || model.playback != nil)
            }
            CommandGroup(after: .appSettings) {
                Button("Connect a Device…") { model.showsQuickConnect = true }
                    .keyboardShortcut("k")
                    .disabled(model.phase != .ready)
                Button("Sign Out") { Task { await model.closePlayer(); await model.signOut() } }
                    .disabled(model.phase != .ready)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Save the playback position before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AppModel.shared.playback != nil else { return .terminateNow }
        Task {
            await AppModel.shared.closePlayer()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            Tokens.Color.base.ignoresSafeArea()
            // The player replaces the library instead of covering it: hiding the library's toolbar
            // would also remove the window's traffic lights on macOS 26.
            if let playback = model.playback {
                PlayerScreen(playback: playback)
                    .transition(.page)
                    .zIndex(1)
            } else {
                switch model.phase {
                case .signedOut: LoginView().transition(.page)
                case .ready:
                    HomeView()
                        .transition(.page)
                        .task { if !model.hasLoaded { await model.refresh() } }
                }
            }
        }
        .sheet(isPresented: $model.showsQuickConnect) { QuickConnectSheet() }
        #if DEBUG
        .task { await DemoAutomation.run(model) }
        #endif
    }
}

extension AnyTransition {
    /// The single UI transition: fade with a slight zoom-out into place (DESIGN.md › Mouvement).
    static let page = AnyTransition.opacity.combined(with: .scale(scale: Tokens.Motion.pageScale))
}
