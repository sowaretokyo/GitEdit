import SwiftUI
import AppKit

@main
struct GitEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = RepositoryStore()
    @AppStorage(AppLanguage.storageKey) private var appLanguage: String = AppLanguage.system.rawValue
    @AppStorage(AppAppearance.storageKey) private var appAppearance: String = AppAppearance.system.rawValue

    private var currentAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearance) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 800, minHeight: 540)
                .preferredColorScheme(currentAppearance.colorScheme)
                .id(appLanguage)
                .task { await store.loadPersisted() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        // Stop the window shrinking below the content's `minWidth/minHeight`.
        // Without this the window can go narrower than 1100pt while the content
        // refuses to, so the oversized content overflows and the left sidebar /
        // right toggle get clipped off both edges.
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L("リポジトリを追加…")) {
                    store.promptAddRepository()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .preferredColorScheme(currentAppearance.colorScheme)
                .id(appLanguage)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
