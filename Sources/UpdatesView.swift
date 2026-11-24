import SwiftUI

struct UpdatesView: View {
    @ObservedObject var library: WebCatalogStore
    @ObservedObject var updater: AppUpdateManager
    @ObservedObject var downloads: InstallerDownloadManager
    @Environment(\.dismiss) private var dismiss
    @AppStorage("webCatalogURL") private var catalogURL = WebConfiguration.catalogURL
    @AppStorage("appUpdateURL") private var updateURL = WebConfiguration.updateURL
    @AppStorage("automaticWebUpdates") private var automatic = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Обновления").font(.system(size: 28, weight: .semibold)).tracking(-0.6)
                    Text("MacDownUp \(updater.currentVersion) · Разработчик laberthouman")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(28)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    Toggle("Автоматически проверять веб-каталог и обновления", isOn: $automatic).font(.system(size: 12))
                    Text("При запуске, возвращении в приложение и каждый час. Последняя рабочая копия каталога сохраняется на Mac.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    Text("Версии и ссылки macOS").font(.system(size: 18, weight: .semibold))
                    TextField("Raw-ссылка на catalog.json", text: $catalogURL).textFieldStyle(.roundedBorder).font(.system(size: 11))
                        .accessibilityLabel("URL веб-каталога macOS")
                    Text(library.status).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let checked = library.lastChecked {
                        Text("Последняя успешная проверка: \(checked.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Button(library.refreshing ? "Проверяем каталог…" : "Обновить каталог сейчас") {
                        Task { await library.refresh(source: catalogURL, force: true) }
                    }.disabled(library.refreshing)
                    Divider()
                    Text("Приложение MacDownUp").font(.system(size: 18, weight: .semibold))
                    TextField("Raw-ссылка на app-update.json", text: $updateURL).textFieldStyle(.roundedBorder).font(.system(size: 11))
                        .accessibilityLabel("URL обновлений MacDownUp")
                    Text(updater.status).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    if let manifest = updater.manifest {
                        Text(manifest.releaseNotes).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if updater.downloading {
                            ProgressView(value: updater.progress)
                            Button("Отменить") { updater.cancel() }
                        } else if updater.preparedApp != nil {
                            Button("Установить и перезапустить") { updater.installAndRestart() }
                                .buttonStyle(.borderedProminent).disabled(downloads.isBusy)
                            Text("Предыдущая сборка сохранится рядом с приложением. Каталог и настройки останутся на Mac.")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        } else {
                            Button("Скачать MacDownUp \(manifest.version)") { updater.download() }.buttonStyle(.borderedProminent)
                        }
                    }
                    Button(updater.checking ? "Проверяем приложение…" : "Проверить обновление приложения") {
                        Task { await updater.check(source: updateURL) }
                    }.disabled(updater.checking || updater.downloading)
                    Divider()
                    Link("github.com/laberthouman ↗", destination: AppStyle.developerURL).font(.system(size: 11))
                }.padding(28)
            }
        }.frame(width: 700, height: 680).background(AppStyle.background)
    }
}
