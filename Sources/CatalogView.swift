import AppKit
import SwiftUI

struct CatalogView: View {
    @ObservedObject var downloads: InstallerDownloadManager
    @ObservedObject var library: WebCatalogStore
    @ObservedObject var updater: AppUpdateManager
    @Binding var showUpdates: Bool
    @StateObject private var ipsw = IPSWCatalog()
    @State private var scope: CatalogScope = .all
    @State private var searchText = ""
    @State private var selectedRelease: SystemRelease?
    @AppStorage("favoriteReleases") private var favorites = ""
    @AppStorage("catalogOldestFirst") private var oldestFirst = false
    @AppStorage("appearance") private var appearance = "system"
    @FocusState private var searchFocused: Bool

    private var favoriteIDs: Set<String> { Set(favorites.split(separator: ",").map(String.init)) }
    private var visibleReleases: [SystemRelease] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let words = query.split(separator: " ")
        let releases = library.releases.compactMap { release -> SystemRelease? in
            let index = release.searchIndex
            guard matchesScope(release), words.allSatisfy({ index.contains($0) }) else { return nil }
            return release
        }
        return oldestFirst ? Array(releases.reversed()) : releases
    }

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 195, ideal: 215, max: 250)
        } detail: {
            catalog
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Text("Библиотека macOS")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { searchFocused = true } label: { Image(systemName: "magnifyingglass") }
                        .help("Поиск · ⌘F").keyboardShortcut("f", modifiers: .command)
                    Menu {
                        Picker("Оформление", selection: $appearance) {
                            Text("Как в системе").tag("system")
                            Text("Светлое").tag("light")
                            Text("Тёмное").tag("dark")
                        }
                    } label: { Image(systemName: "circle.lefthalf.filled") }
                    .help("Оформление")
                    Button { openDownloads() } label: { Image(systemName: "folder") }.help("Открыть папку загрузок")
                    Button { showUpdates = true } label: { Image(systemName: updater.manifest == nil ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill") }
                        .help("Веб-каталог и обновления приложения")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(AppStyle.blue)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .sheet(item: $selectedRelease) { release in
            ReleaseDetailSheet(release: release, downloads: downloads, ipsw: ipsw)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
        .sheet(isPresented: $showUpdates) { UpdatesView(library: library, updater: updater, downloads: downloads) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable().scaledToFit().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacDownUp").font(.system(size: 16, weight: .semibold))
                    Text("История вашего Mac").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 25)
            Text("Библиотека").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.leading, 22).padding(.bottom, 10)
            ForEach(CatalogScope.allCases) { item in
                Button { scope = item; searchText = "" } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol).font(.system(size: 14)).frame(width: 20)
                        Text(item.rawValue).font(.system(size: 12, weight: scope == item ? .semibold : .regular))
                        Spacer()
                        Text(String(count(item))).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .foregroundStyle(scope == item ? AppStyle.blue : .primary)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(scope == item ? AppStyle.blue.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 10).padding(.bottom, 3)
            }
            Divider().padding(.horizontal, 22).padding(.vertical, 20)
            Button { openDownloads() } label: {
                Label("Загрузки", systemImage: "arrow.down.circle").font(.system(size: 12)).foregroundStyle(.secondary)
            }.buttonStyle(.plain).padding(.horizontal, 22)
            if downloads.isBusy {
                VStack(alignment: .leading, spacing: 8) {
                    Text(downloads.releaseName).font(.system(size: 10, weight: .medium)).lineLimit(2)
                    ProgressView(value: downloads.progress).progressViewStyle(.linear)
                    Button("Отменить загрузку") { downloads.cancel() }.buttonStyle(.borderless).font(.system(size: 10))
                }.padding(22)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 7) {
                Text("Создано для Mac.").font(.system(size: 12, weight: .medium))
                Text("Разработчик laberthouman").font(.system(size: 10)).foregroundStyle(.secondary)
                Link("github.com/laberthouman", destination: AppStyle.developerURL).font(.system(size: 10))
                Text("MACDOWNUP  \(updater.currentVersion)").font(.system(size: 8, weight: .medium)).tracking(1.4).foregroundStyle(.tertiary).padding(.top, 7)
            }.padding(22)
        }.frame(maxHeight: .infinity).background(.ultraThinMaterial)
    }

    private var catalog: some View {
        let releases = visibleReleases
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 20) {
                    if downloads.status != nil { DownloadStatusBanner(manager: downloads) }
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(scope == .all ? "История macOS." : scope.title)
                                .font(.system(size: 32, weight: .semibold)).tracking(-1)
                            Text("\(releases.count) версий. Обои, совместимость и загрузка.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 15)
                        search
                    }
                    HStack {
                        Text("Откройте систему, чтобы выбрать версию для своего Mac.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Menu {
                            Button("Сначала новые") { oldestFirst = false }
                            Button("Сначала классика") { oldestFirst = true }
                        } label: {
                            Label(oldestFirst ? "Сначала классика" : "Сначала новые", systemImage: "arrow.up.arrow.down")
                                .font(.system(size: 10))
                        }.menuStyle(.borderlessButton).fixedSize()
                    }
                }.padding(30)
                if releases.isEmpty { emptyState }
                else {
                    LazyVStack(spacing: 2) {
                        ForEach(releases) { release in
                            ReleaseWallpaperStrip(release: release, isFavorite: favoriteIDs.contains(release.id),
                                                  height: release.id == releases.first?.id ? 260 : 202,
                                                  details: { selectedRelease = release }, favorite: { toggleFavorite(release.id) })
                        }
                    }
                }
                HStack(spacing: 6) {
                    Text(library.refreshing ? "Обновление веб-каталога…" : library.revision > 0 ? "Веб-каталог · ревизия \(library.revision)" : "Встроенный каталог")
                    Spacer()
                    Link("GitHub ↗", destination: AppStyle.developerURL)
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(30)
            }.frame(maxWidth: .infinity)
        }.background(AppStyle.background)
    }

    private var search: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Название, версия, год", text: $searchText).textFieldStyle(.plain)
                .focused($searchFocused).font(.system(size: 11)).accessibilityLabel("Поиск по каталогу")
            if !searchText.isEmpty {
                Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 10).frame(width: 200, height: 32)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: scope == .favorites ? "heart" : "magnifyingglass").font(.system(size: 36, weight: .ultraLight)).foregroundStyle(.secondary)
            Text(scope == .favorites && searchText.isEmpty ? "Ваши любимые системы" : "Ничего не найдено").font(.system(size: 18, weight: .semibold))
            Text(scope == .favorites && searchText.isEmpty ? "Нажмите сердечко на обоях нужной системы." : "Попробуйте другое название, версию или год.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if !searchText.isEmpty { Button("Сбросить поиск") { searchText = "" } }
        }.frame(maxWidth: .infinity).padding(.vertical, 70)
    }

    private func matchesScope(_ release: SystemRelease) -> Bool {
        switch scope {
        case .all: return true
        case .current: return release.isModern
        case .classic: return !release.isModern
        case .favorites: return favoriteIDs.contains(release.id)
        }
    }
    private func count(_ item: CatalogScope) -> Int {
        switch item {
        case .all: return library.releases.count
        case .current: return library.releases.filter(\.isModern).count
        case .classic: return library.releases.filter { !$0.isModern }.count
        case .favorites: return library.releases.filter { favoriteIDs.contains($0.id) }.count
        }
    }
    private func toggleFavorite(_ id: String) {
        var ids = favoriteIDs
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        favorites = ids.sorted().joined(separator: ",")
    }
    private func openDownloads() {
        let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!.appendingPathComponent("MacDownUp", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
