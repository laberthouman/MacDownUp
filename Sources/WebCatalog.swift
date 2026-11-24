import Combine
import Foundation

enum WebConfiguration {
    static let catalogURL = "https://raw.githubusercontent.com/laberthouman/MacDownUp/main/catalog.json"
    static let updateURL = "https://raw.githubusercontent.com/laberthouman/MacDownUp/main/app-update.json"
    static let cacheDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("MacDownUp", isDirectory: true)

    static func isVersion(_ value: String) -> Bool {
        let pieces = value.split(separator: ".", omittingEmptySubsequences: false)
        return !pieces.isEmpty && pieces.count <= 4 && pieces.allSatisfy { !$0.isEmpty && $0.count <= 4 && $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }
    static func isHTTPS(_ url: URL) -> Bool { url.scheme == "https" && url.host != nil && url.user == nil && url.password == nil }
    static func githubRawURL(_ value: String) throws -> URL {
        guard let url = URL(string: value), isHTTPS(url), url.host == "raw.githubusercontent.com", url.pathComponents.count >= 5 else {
            throw DownloadFailure.message("Укажите HTTPS-ссылку Raw на JSON-файл GitHub.")
        }
        return url
    }
    static func isGitHubAsset(_ url: URL) -> Bool {
        guard isHTTPS(url), let host = url.host else { return false }
        return host == "github.com" || host == "release-assets.githubusercontent.com" || host == "objects.githubusercontent.com"
    }
    static func fetch(_ url: URL, session: URLSession = .shared) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw DownloadFailure.message("GitHub не выдал файл (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Проверьте публикацию и ссылку Raw.")
        }
        guard data.count <= 2 * 1024 * 1024 else { throw DownloadFailure.message("JSON-файл слишком большой.") }
        return data
    }
}

struct ReleaseMetadata: Hashable {
    let family: String
    let isModern: Bool
    let overview: String
    let compatibility: MacCompatibility
    let options: [InstallerOption]
    let wallpaperURL: URL?
}

struct WebInstallerSource: Codable {
    let id: String
    let title: String
    let subtitle: String
    let kind: String
    let url: String?
    let version: String?
    let provider: String?
    let packages: [ArchivePackage]?
    let reference: URL

    init(_ option: InstallerOption) {
        id = option.id; title = option.title; subtitle = option.subtitle; reference = option.reference
        switch option.source {
        case .appleImage(let link): kind = "appleImage"; url = link; version = nil; provider = nil; packages = nil
        case .appStore(let link): kind = "appStore"; url = link; version = nil; provider = nil; packages = nil
        case .softwareUpdate(let value): kind = "softwareUpdate"; url = nil; version = value; provider = nil; packages = nil
        case .webPage(let link, let name): kind = "webPage"; url = link; version = nil; provider = name; packages = nil
        case .archive(let values): kind = "archive"; url = nil; version = nil; provider = nil; packages = values
        }
    }

    func option() throws -> InstallerOption {
        guard !id.isEmpty, !title.isEmpty, WebConfiguration.isHTTPS(reference) else { throw DownloadFailure.message("Некорректный источник установщика.") }
        let source: InstallerSource
        switch kind {
        case "appleImage", "appStore":
            guard let url, let link = URL(string: url), InstallerLinks.isApple(link) else { throw DownloadFailure.message("Установщик должен использовать серверы Apple.") }
            source = kind == "appleImage" ? .appleImage(url: url) : .appStore(url: url)
        case "softwareUpdate":
            guard let version, WebConfiguration.isVersion(version) else { throw DownloadFailure.message("Некорректная версия Software Update.") }
            source = .softwareUpdate(version: version)
        case "archive":
            guard let packages, !packages.isEmpty, packages.allSatisfy({
                !$0.itemID.isEmpty && $0.itemID.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
                && !$0.files.isEmpty && $0.files.allSatisfy { !$0.isEmpty && !$0.split(separator: "/").contains("..") }
            }) else { throw DownloadFailure.message("Некорректный архивный источник.") }
            source = .archive(packages: packages)
        case "webPage":
            guard let url, let link = URL(string: url), WebConfiguration.isHTTPS(link) else { throw DownloadFailure.message("Некорректная ссылка источника.") }
            source = .webPage(url: url, provider: provider ?? "Источник")
        default: throw DownloadFailure.message("Неизвестный тип установщика: \(kind).")
        }
        return .init(id: id, title: title, subtitle: subtitle, source: source, reference: reference)
    }
}

struct WebSystemRelease: Codable {
    let id: String
    let marketingName: String
    let family: String
    let number: String
    let finalVersion: String
    let year: Int
    let detail: String
    let overview: String
    let installerMedia: String
    let architecture: String
    let isModern: Bool
    let wallpaperURL: URL?
    let compatibility: MacCompatibility
    let sources: [WebInstallerSource]

    init(_ release: SystemRelease) {
        id = release.id; marketingName = release.marketingName; family = release.family; number = release.number
        finalVersion = release.finalVersion; year = release.year; detail = release.detail; overview = release.overview
        installerMedia = release.installerMedia; architecture = release.architecture; isModern = release.isModern
        wallpaperURL = URL(string: "https://raw.githubusercontent.com/laberthouman/MacDownUp/main/wallpapers/\(release.id).jpg")
        compatibility = release.compatibility; sources = release.options.map(WebInstallerSource.init)
    }

    func release(accent: Int) throws -> SystemRelease {
        guard WebConfiguration.isVersion(id), WebConfiguration.isVersion(number), WebConfiguration.isVersion(finalVersion),
              !marketingName.isEmpty, !family.isEmpty, (2000...2100).contains(year), !overview.isEmpty,
              !compatibility.models.isEmpty, WebConfiguration.isHTTPS(compatibility.reference),
              compatibility.models.allSatisfy({ !$0.family.isEmpty && !$0.models.isEmpty }),
              wallpaperURL == nil || WebConfiguration.isHTTPS(wallpaperURL!) else { throw DownloadFailure.message("Некорректные данные macOS \(id).") }
        let options = try sources.map { try $0.option() }
        guard !options.isEmpty, Set(options.map(\.id)).count == options.count else { throw DownloadFailure.message("У macOS \(id) нет источников или есть дубликаты.") }
        return .init(id: id, marketingName: marketingName, number: number, finalVersion: finalVersion, year: year,
                     detail: detail, installerMedia: installerMedia, architecture: architecture, accent: accent, source: options[0].source,
                     remote: .init(family: family, isModern: isModern, overview: overview, compatibility: compatibility, options: options, wallpaperURL: wallpaperURL))
    }
}

struct WebCatalogDocument: Codable {
    let schemaVersion: Int
    let revision: Int
    let updatedAt: String
    let releases: [WebSystemRelease]

    func merged(with baseline: [SystemRelease] = InstallerCatalog.releases) throws -> [SystemRelease] {
        guard schemaVersion == 1, revision > 0, !releases.isEmpty, releases.count <= 150,
              Set(releases.map(\.id)).count == releases.count else { throw DownloadFailure.message("Некорректная схема или дубликаты в веб-каталоге.") }
        var result = Dictionary(uniqueKeysWithValues: baseline.map { ($0.id, $0) })
        for (index, value) in releases.enumerated() { result[value.id] = try value.release(accent: index) }
        return result.values.sorted {
            if $0.year != $1.year { return $0.year > $1.year }
            return $0.number.compare($1.number, options: .numeric) == .orderedDescending
        }
    }
}

private struct CachedCatalog: Codable {
    let source: String
    let checkedAt: Date
    let document: WebCatalogDocument
}

@MainActor
final class WebCatalogStore: ObservableObject {
    @Published private(set) var releases = InstallerCatalog.releases
    @Published private(set) var refreshing = false
    @Published private(set) var status = "Встроенный каталог"
    @Published private(set) var lastChecked: Date?
    @Published private(set) var revision = 0
    private var currentSource = ""
    private let cacheURL: URL
    private let session: URLSession
    private var lastAttempt: Date?

    init(cacheURL: URL = WebConfiguration.cacheDirectory.appendingPathComponent("catalog-cache.json"), session: URLSession = .shared) {
        self.cacheURL = cacheURL; self.session = session
        if let data = try? Data(contentsOf: cacheURL), let cached = try? JSONDecoder().decode(CachedCatalog.self, from: data),
           let values = try? cached.document.merged() {
            releases = values; revision = cached.document.revision; currentSource = cached.source
            lastChecked = cached.checkedAt; status = "Сохранённый веб-каталог · ревизия \(revision)"
        }
    }

    func refresh(source: String, force: Bool = false) async {
        guard !refreshing else { return }
        if !force, currentSource == source, let lastAttempt, Date().timeIntervalSince(lastAttempt) < 60 { return }
        refreshing = true; lastAttempt = Date()
        defer { refreshing = false }
        do {
            let url = try WebConfiguration.githubRawURL(source)
            let data = try await WebConfiguration.fetch(url, session: session)
            let document = try JSONDecoder().decode(WebCatalogDocument.self, from: data)
            let values = try document.merged()
            guard currentSource != source || document.revision >= revision else { throw DownloadFailure.message("GitHub вернул более старую ревизию. Сохранена текущая копия.") }
            let checkedAt = Date()
            let cached = CachedCatalog(source: source, checkedAt: checkedAt, document: document)
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(cached).write(to: cacheURL, options: .atomic)
            releases = values; revision = document.revision; currentSource = source; lastChecked = checkedAt
            status = "Веб-каталог обновлён · ревизия \(revision)"
        } catch {
            if !Task.isCancelled { status = "\(revision > 0 ? "Сохранённый" : "Встроенный") каталог · " + error.localizedDescription }
        }
    }
}
