import AppKit
import SwiftUI

private enum ReleaseSection: String, CaseIterable {
    case about = "Об этой macOS"
    case compatibility = "Совместимые Mac"
    case downloads = "Загрузка"
    case ipsw = "IPSW по модели"
}

struct ReleaseDetailSheet: View {
    let release: SystemRelease
    @ObservedObject var downloads: InstallerDownloadManager
    @ObservedObject var ipsw: IPSWCatalog
    @Environment(\.dismiss) private var dismiss
    @State private var section: ReleaseSection = .compatibility
    @State private var checks: [String: String] = [:]
    @State private var checking = false
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                SystemWallpaper(release: release)
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(release.family) \(release.number)").font(.system(size: 11, weight: .medium)).opacity(0.85)
                    Text(release.marketingName).font(.system(size: 35, weight: .semibold)).tracking(-1)
                    Text("\(release.year) · \(release.detail)").font(.system(size: 12)).opacity(0.9)
                }.foregroundStyle(.white).shadow(color: .black.opacity(0.18), radius: 3).padding(28)
            }.frame(height: 190)
                .overlay(alignment: .topTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                            .padding(9).background(.black.opacity(0.25), in: Circle())
                    }.buttonStyle(.plain).padding(16).help("Закрыть")
                }
            Picker("Раздел системы", selection: $section) {
                ForEach(ReleaseSection.allCases.filter { $0 != .ipsw || release.supportsIPSW }, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 28).padding(.vertical, 18)
            if section == .ipsw {
                IPSWView(catalog: ipsw, downloads: downloads, release: release)
            } else {
              ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    switch section {
                    case .about: about
                    case .compatibility: compatibility
                    case .downloads: sources
                    case .ipsw: EmptyView()
                    }
                    if downloads.status != nil { DownloadStatusBanner(manager: downloads) }
                }.padding(.horizontal, 28).padding(.bottom, 24).frame(maxWidth: .infinity, alignment: .leading)
            }
            }
            Divider()
            HStack {
                Link("Разработчик laberthouman ↗", destination: AppStyle.developerURL).font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Готово") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(.horizontal, 28).padding(.vertical, 14)
        }.frame(width: 800, height: 780).background(AppStyle.background)
            .onDisappear { checkTask?.cancel() }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(release.displayName).font(.system(size: 22, weight: .semibold))
            Text(release.detail + ".").font(.system(size: 15)).foregroundStyle(.secondary)
            Text(release.overview).font(.system(size: 13)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            Divider()
            specification("Год выпуска", String(release.year))
            specification("Версия в каталоге", release.finalVersion)
            specification("Архитектура", release.architecture)
            specification("Установочный носитель", release.installerMedia)
            Divider()
            Button("Посмотреть совместимые Mac") { section = .compatibility }.buttonStyle(.borderless)
            Button("Выбрать источник загрузки") { section = .downloads }.buttonStyle(.borderless)
        }
    }

    private var compatibility: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("На каких Mac работает \(release.marketingName)").font(.system(size: 19, weight: .semibold))
                Spacer()
                Link("Список Apple ↗", destination: release.compatibility.reference).font(.system(size: 10))
            }
            Text("Найдите семейство своего Mac и год выпуска в меню  → «Об этом Mac».")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(release.compatibility.models) { model in
                    HStack(alignment: .top, spacing: 13) {
                        Image(systemName: model.symbol).font(.system(size: 18, weight: .light)).foregroundStyle(.secondary).frame(width: 24)
                        Text(model.family).font(.system(size: 12, weight: .semibold)).frame(width: 125, alignment: .leading)
                        Text(model.models).font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.vertical, 14)
                    Divider()
                }
            }
            Text(release.compatibility.note).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Button { section = .downloads } label: {
                Label("Перейти к загрузке", systemImage: "arrow.down").font(.system(size: 12, weight: .medium))
            }.buttonStyle(.borderedProminent).controlSize(.regular).padding(.top, 3)
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Выберите источник").font(.system(size: 20, weight: .semibold))
                    Text("\(release.options.count) способов получить эту систему").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { checkSources() } label: {
                    Label(checking ? "Проверяем…" : "Проверить ссылки", systemImage: "arrow.clockwise").font(.system(size: 10))
                }.disabled(checking).controlSize(.small)
            }
            ForEach(release.options) { option in optionView(option) }
            if release.supportsIPSW {
                Button { section = .ipsw } label: {
                    Label("Скачать IPSW \(release.marketingName) по модели Mac", systemImage: "externaldrive")
                }.buttonStyle(.borderless).font(.system(size: 12))
            }
            Label(release.archivePackages.isEmpty ? "Выберите установщик для своей модели Mac. Файл PKG сохраняет установщик в «Программы» после открытия." : "Архивные образы: размер и SHA‑1 проверяются перед сохранением. Это проверка целостности архивной копии.", systemImage: "info.circle")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func specification(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 165, alignment: .leading)
            Text(value).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func optionView(_ option: InstallerOption) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 13) {
                Image(systemName: option.source.sourceSymbol)
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(option.isArchive ? Color.secondary : AppStyle.blue)
                    .frame(width: 35, height: 35)
                    .background(AppStyle.blue.opacity(option.isArchive ? 0.04 : 0.07), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(option.title).font(.system(size: 12, weight: .semibold))
                    Text(option.subtitle).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { downloads.start(release: release, option: option) } label: {
                    Text(option.actionTitle).font(.system(size: 11, weight: .semibold)).frame(minWidth: 59)
                }.buttonStyle(.borderedProminent).controlSize(.small).disabled(downloads.isBusy)
            }
            if case .archive(let packages) = option.source, let package = packages.first {
                Text(package.sourceNote).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 9) {
                    ForEach(Array(package.files.enumerated()), id: \.offset) { index, file in
                        Button(package.files.count > 1 ? "Ссылка на диск \(index + 1)" : "Скопировать ссылку на образ") { copyLink(package.downloadURL(for: file)) }
                            .buttonStyle(.borderless).font(.system(size: 9))
                    }
                }
            }
            HStack(spacing: 13) {
                Link(destination: option.reference) {
                    Label("\(option.reference.host == "mrmacintosh.com" ? "Mr. Macintosh" : option.reference.host?.contains("apple.com") == true ? "Инструкция Apple" : "Страница источника")", systemImage: "arrow.up.right.square")
                }
                .font(.system(size: 9)).foregroundStyle(.secondary)
                if let url = option.url, !option.isArchive {
                    Button { copyLink(url) } label: { Label("Копировать ссылку", systemImage: "doc.on.doc") }
                        .buttonStyle(.borderless).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let status = checks[option.id] {
                    Text(status).font(.system(size: 9)).foregroundStyle(status.hasPrefix("✓") ? Color.green : .secondary).lineLimit(2)
                }
            }
        }
        .padding(14)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func checkSources() {
        checking = true
        checks = [:]
        checkTask = Task {
            defer { checking = false }
            for option in release.options {
                if Task.isCancelled { return }
                checks[option.id] = "Проверяем…"
                do {
                    switch option.source {
                    case .archive(let packages):
                        if let package = packages.first {
                            let metadata = try await downloads.archiveMetadata(package.itemID)
                            _ = try metadata.verifiedFiles(for: package)
                            checks[option.id] = "✓ Файлы и SHA‑1 в манифесте"
                        }
                    case .softwareUpdate:
                        checks[option.id] = "Доступность зависит от Mac"
                    default:
                        guard let url = option.url else { continue }
                        var request = URLRequest(url: url, timeoutInterval: 20)
                        request.httpMethod = "HEAD"
                        let (_, response) = try await URLSession.shared.data(for: request)
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                        checks[option.id] = (200..<300).contains(code) ? "✓ Сервер доступен" : "HTTP \(code) · откройте источник"
                    }
                } catch {
                    if Task.isCancelled { return }
                    checks[option.id] = "Не удалось проверить"
                }
            }
        }
    }
}
