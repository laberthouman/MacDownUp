import AppKit
import SwiftUI

@main
struct MacDownUpApp: App {
    @StateObject private var downloads = InstallerDownloadManager()
    @StateObject private var library = WebCatalogStore()
    @StateObject private var updater = AppUpdateManager()
    @State private var showUpdates = false
    @AppStorage("webCatalogURL") private var catalogURL = WebConfiguration.catalogURL
    @AppStorage("appUpdateURL") private var updateURL = WebConfiguration.updateURL
    @AppStorage("automaticWebUpdates") private var automaticUpdates = true
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup("MacDownUp") {
            CatalogView(downloads: downloads, library: library, updater: updater, showUpdates: $showUpdates)
                .frame(minWidth: 1000, minHeight: 760)
                .task {
                    while !Task.isCancelled {
                        if automaticUpdates {
                            async let catalog: Void = library.refresh(source: catalogURL)
                            async let app: Void = updater.check(source: updateURL)
                            _ = await (catalog, app)
                        }
                        do { try await Task.sleep(nanoseconds: 3_600_000_000_000) } catch { return }
                    }
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active && automaticUpdates { Task { await library.refresh(source: catalogURL) } }
                }
        }
        .defaultSize(width: 1180, height: 850)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            SidebarCommands()
            CommandGroup(after: .appInfo) {
                Button("Проверить обновления…") { showUpdates = true }
            }
            CommandGroup(replacing: .appInfo) {
                Button("О MacDownUp") {
                    NSApplication.shared.orderFrontStandardAboutPanel(options: [
                        .applicationName: "MacDownUp",
                        .applicationVersion: updater.currentVersion,
                        .version: "\(library.releases.count) поколений macOS · IPSW по моделям",
                        .credits: NSAttributedString(string: "Разработчик laberthouman\nhttps://github.com/laberthouman", attributes: [.link: AppStyle.developerURL])
                    ])
                }
            }
        }
    }
}
