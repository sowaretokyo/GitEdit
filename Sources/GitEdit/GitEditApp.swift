import SwiftUI
import AppKit
import Combine
import Sparkle

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var viewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button(L("アップデートを確認…"), action: updater.checkForUpdates)
            .disabled(!viewModel.canCheckForUpdates)
    }
}

@main
struct GitEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
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
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
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
