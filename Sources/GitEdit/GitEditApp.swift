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
                .frame(minWidth: 1100, minHeight: 680)
                .preferredColorScheme(currentAppearance.colorScheme)
                .id(appLanguage)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
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
        // SPM 実行形式は .app バンドルを生成しないため、Dock/ウインドウ用の
        // アイコンを起動時に NSImage から設定する。
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
