import Foundation

struct ArchivePackage: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let itemID: String
    let files: [String]
    let architecture: String
    let mediaVersion: String
    let sizeHint: String
    let sourceNote: String

    var sourcePage: URL {
        URL(string: "https://archive.org/details/\(itemID)")!
    }

    var manifestURL: URL { URL(string: "https://archive.org/metadata/\(itemID)")! }

    func downloadURL(for path: String) -> URL {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
        let encoded = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: allowed)! }.joined(separator: "/")
        return URL(string: "https://archive.org/download/\(itemID)/\(encoded)")!
    }
}

enum InstallerSource: Hashable {
    case softwareUpdate(version: String)
    case appStore(url: String)
    case appleImage(url: String)
    case archive(packages: [ArchivePackage])
    case webPage(url: String, provider: String)

    var sourceLabel: String {
        switch self {
        case .softwareUpdate, .appStore, .appleImage: return "Apple"
        case .archive: return "Архив"
        case .webPage(_, let provider): return provider
        }
    }

    var sourceSymbol: String {
        switch self {
        case .softwareUpdate, .appStore, .appleImage: return "checkmark.seal.fill"
        case .archive: return "archivebox.fill"
        case .webPage: return "arrow.up.right.square"
        }
    }

    var buttonTitle: String {
        switch self {
        case .softwareUpdate: return "Скачать установщик"
        case .appStore: return "Открыть App Store"
        case .appleImage: return "Скачать образ"
        case .archive: return "Выбрать образ"
        case .webPage: return "Открыть источник"
        }
    }
}

struct SystemRelease: Identifiable, Hashable {
    let id: String
    let marketingName: String
    let number: String
    let finalVersion: String
    let year: Int
    let detail: String
    let installerMedia: String
    let architecture: String
    let accent: Int
    let source: InstallerSource
    let remote: ReleaseMetadata?

    init(id: String, marketingName: String, number: String, finalVersion: String, year: Int, detail: String,
         installerMedia: String, architecture: String, accent: Int, source: InstallerSource, remote: ReleaseMetadata? = nil) {
        self.id = id; self.marketingName = marketingName; self.number = number; self.finalVersion = finalVersion
        self.year = year; self.detail = detail; self.installerMedia = installerMedia; self.architecture = architecture
        self.accent = accent; self.source = source; self.remote = remote
    }

    var displayName: String {
        "\(family) \(marketingName)"
    }

    var family: String {
        if let family = remote?.family { return family }
        if ["10.7", "10.8", "10.9", "10.10", "10.11"].contains(id) { return "OS X" }
        if ["10.0", "10.1", "10.2", "10.3", "10.4", "10.5", "10.6"].contains(id) { return "Mac OS X" }
        return "macOS"
    }

    var isModern: Bool { remote?.isModern ?? ["27", "26", "15", "14", "13", "12", "11", "10.15", "10.14", "10.13"].contains(id) }
    var searchIndex: String { "\(displayName) \(number) \(finalVersion) \(year) \(architecture)".folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }

    var archivePackages: [ArchivePackage] {
        if case .archive(let packages) = source { return packages }
        return []
    }
}

enum CatalogScope: String, CaseIterable, Identifiable {
    case all = "Все"
    case current = "Новые"
    case classic = "Классика"
    case favorites = "Избранное"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: return "macwindow"
        case .current: return "sparkles"
        case .classic: return "clock.arrow.circlepath"
        case .favorites: return "heart"
        }
    }

    var title: String {
        switch self {
        case .all: return "Все поколения"
        case .current: return "Современные версии"
        case .classic: return "Классические системы"
        case .favorites: return "Избранное"
        }
    }
}

enum InstallerCatalog {
    static let releases: [SystemRelease] = [
        .init(id: "27", marketingName: "Golden Gate", number: "27", finalVersion: "27.2.1", year: 2026, detail: "Самое новое поколение macOS", installerMedia: "Полный установщик", architecture: "Apple silicon", accent: 0, source: .softwareUpdate(version: "27.2.1")),
        .init(id: "26", marketingName: "Tahoe", number: "26", finalVersion: "26.7.3", year: 2025, detail: "Новый дизайн и Apple Intelligence", installerMedia: "Полный установщик", architecture: "Apple silicon, Intel на поддерживаемых моделях", accent: 1, source: .softwareUpdate(version: "26.7.3")),
        .init(id: "15", marketingName: "Sequoia", number: "15", finalVersion: "15.8.3", year: 2024, detail: "Зеркалирование iPhone и удобные окна", installerMedia: "App Store", architecture: "Apple silicon и Intel", accent: 2, source: .appStore(url: "https://apps.apple.com/app/macos-sequoia/id6596773750?mt=12")),
        .init(id: "14", marketingName: "Sonoma", number: "14", finalVersion: "14.8.9", year: 2023, detail: "Виджеты на рабочем столе и игровой режим", installerMedia: "App Store", architecture: "Apple silicon и Intel", accent: 3, source: .appStore(url: "https://apps.apple.com/app/macos-sonoma/id6450717509?mt=12")),
        .init(id: "13", marketingName: "Ventura", number: "13", finalVersion: "13.7.8", year: 2022, detail: "Stage Manager и приложения iPhone", installerMedia: "App Store", architecture: "Apple silicon и Intel", accent: 4, source: .appStore(url: "https://apps.apple.com/app/macos-ventura/id1638787999?mt=12")),
        .init(id: "12", marketingName: "Monterey", number: "12", finalVersion: "12.7.6", year: 2021, detail: "Focus, Быстрая заметка и AirPlay на Mac", installerMedia: "App Store", architecture: "Apple silicon и Intel", accent: 5, source: .appStore(url: "https://apps.apple.com/app/macos-monterey/id1576738294?mt=12")),
        .init(id: "11", marketingName: "Big Sur", number: "11", finalVersion: "11.7.11", year: 2020, detail: "Новый облик macOS и Центр управления", installerMedia: "App Store", architecture: "Apple silicon и Intel", accent: 6, source: .appStore(url: "https://apps.apple.com/app/macos-big-sur/id1526878132?mt=12")),
        .init(id: "10.15", marketingName: "Catalina", number: "10.15", finalVersion: "10.15.8", year: 2019, detail: "Музыка, Подкасты и Apple TV на Mac", installerMedia: "App Store", architecture: "Intel", accent: 7, source: .appStore(url: "https://apps.apple.com/app/macos-catalina/id1466841314?mt=12")),
        .init(id: "10.14", marketingName: "Mojave", number: "10.14", finalVersion: "10.14.6", year: 2018, detail: "Темный режим и стопки на рабочем столе", installerMedia: "App Store", architecture: "Intel", accent: 8, source: .appStore(url: "https://apps.apple.com/app/macos-mojave/id1398502828?mt=12")),
        .init(id: "10.13", marketingName: "High Sierra", number: "10.13", finalVersion: "10.13.6", year: 2017, detail: "Файловая система APFS и Metal 2", installerMedia: "App Store", architecture: "Intel", accent: 9, source: .appStore(url: "https://apps.apple.com/app/macos-high-sierra/id1246284741?mt=12")),
        .init(id: "10.12", marketingName: "Sierra", number: "10.12", finalVersion: "10.12.6", year: 2016, detail: "Siri впервые появилась на Mac", installerMedia: "InstallOS.dmg", architecture: "Intel", accent: 10, source: .appleImage(url: "https://updates-http.cdn-apple.com/2019/cert/061-39476-20191023-48f365f4-0015-4c41-9f44-39d3d2aca067/InstallOS.dmg")),
        .init(id: "10.11", marketingName: "El Capitan", number: "10.11", finalVersion: "10.11.6", year: 2015, detail: "Split View и обновленный Spotlight", installerMedia: "InstallMacOSX.dmg", architecture: "Intel", accent: 11, source: .appleImage(url: "https://updates-http.cdn-apple.com/2019/cert/061-41424-20191024-218af9ec-cf50-4516-9011-228c78eda3d2/InstallMacOSX.dmg")),
        .init(id: "10.10", marketingName: "Yosemite", number: "10.10", finalVersion: "10.10.5", year: 2014, detail: "Обновленный интерфейс и Continuity", installerMedia: "InstallMacOSX.dmg", architecture: "Intel", accent: 12, source: .appleImage(url: "https://updates-http.cdn-apple.com/2019/cert/061-41343-20191023-02465f92-3ab5-4c92-bfe2-b725447a070d/InstallMacOSX.dmg")),
        .init(id: "10.9", marketingName: "Mavericks", number: "10.9", finalVersion: "10.9.5", year: 2013, detail: "Первая бесплатная версия OS X", installerMedia: "ISO · полный установщик 10.9.5", architecture: "Intel", accent: 13, source: .archive(packages: [
            .init(id: "mavericks-iso", title: "Retail ISO · Intel", itemID: "os-x-mavericks-10.9.5", files: ["OS X Mavericks 10.9.5.iso"], architecture: "Intel", mediaVersion: "10.9.5 · 13F34", sizeHint: "6.1 GB", sourceNote: "Образ загружен в Internet Archive пользователем MrMacintoshBlog. В сопровождающем материале автор указывает, что сделал его со своей копии, загруженной с Apple в 2015 году.")
        ])),
        .init(id: "10.8", marketingName: "Mountain Lion", number: "10.8", finalVersion: "10.8.5", year: 2012, detail: "Центр уведомлений пришел на Mac", installerMedia: "InstallMacOSX.dmg", architecture: "Intel", accent: 14, source: .appleImage(url: "https://updates.cdn-apple.com/2021/macos/031-0627-20210614-90D11F33-1A65-42DD-BBEA-E1D9F43A6B3F/InstallMacOSX.dmg")),
        .init(id: "10.7", marketingName: "Lion", number: "10.7", finalVersion: "10.7.5", year: 2011, detail: "Жесты Multi-Touch и Launchpad", installerMedia: "InstallMacOSX.dmg", architecture: "Intel", accent: 15, source: .appleImage(url: "https://updates.cdn-apple.com/2021/macos/041-7683-20210614-E610947E-C7CE-46EB-8860-D26D71F0D3EA/InstallMacOSX.dmg")),
        .init(id: "10.6", marketingName: "Snow Leopard", number: "10.6", finalVersion: "10.6.8", year: 2009, detail: "Оптимизация и переход на 64-битную архитектуру", installerMedia: "Retail DVD · ISO", architecture: "Intel", accent: 16, source: .archive(packages: [
            .init(id: "snow-leopard-retail", title: "Retail DVD · Intel", itemID: "mac-os-x-10.6-snow-leopard-retail", files: ["Mac_OS_X_10.6_Snow_Leopard_Retail.iso"], architecture: "Intel", mediaVersion: "10.6.0 · 10A432", sizeHint: "7.2 GB", sourceNote: "Архивная копия розничного установочного DVD в коллекции Internet Archive. После установки можно обновить систему до 10.6.8.")
        ])),
        .init(id: "10.5", marketingName: "Leopard", number: "10.5", finalVersion: "10.5.8", year: 2007, detail: "Time Machine и обновленный Finder", installerMedia: "Retail DVD · DMG", architecture: "PowerPC и Intel", accent: 17, source: .archive(packages: [
            .init(id: "leopard-retail", title: "Retail DVD · Universal", itemID: "gcpd-apple_macosxleopard_9a581_dvd", files: ["leopard_9a581_userdvd.dmg"], architecture: "PowerPC и Intel", mediaVersion: "10.5.0 · Build 9A581", sizeHint: "6.7 GB", sourceNote: "Архивная копия retail DVD Build 9A581. В описании Internet Archive сборка указана как совпадающая с финальным коммерческим релизом.")
        ])),
        .init(id: "10.4", marketingName: "Tiger", number: "10.4", finalVersion: "10.4.11", year: 2005, detail: "Spotlight и Dashboard", installerMedia: "Retail DVD · ISO", architecture: "PowerPC или Intel", accent: 18, source: .archive(packages: [
            .init(id: "tiger-ppc", title: "Retail DVD · PowerPC", itemID: "mac-os-x-10.4-tiger-retail-dvd", files: ["Mac OS X 10.4 Tiger Retail DVD.iso"], architecture: "PowerPC", mediaVersion: "10.4.0", sizeHint: "3.6 GB", sourceNote: "Архивный образ retail DVD для PowerPC. Версия файла и конфигурация носителя проверяются по манифесту Internet Archive перед сохранением."),
            .init(id: "tiger-intel", title: "Intel DVD image", itemID: "macosxtiger", files: ["Mac OS X 10.4 Tiger.iso"], architecture: "Intel", mediaVersion: "10.4.x", sizeHint: "4.4 GB", sourceNote: "Архивный установочный образ для Intel. В Internet Archive он описан как Mac OS X 10.4.6 Tiger Retail Install DVD; перепроверьте совместимость с моделью Mac.")
        ])),
        .init(id: "10.3", marketingName: "Panther", number: "10.3", finalVersion: "10.3.9", year: 2003, detail: "Exposé и быстрый поиск файлов", installerMedia: "Retail CD · 3 диска", architecture: "PowerPC", accent: 19, source: .archive(packages: [
            .init(id: "panther-retail", title: "Retail CD set · PowerPC", itemID: "mac-os-x-panther-10.3", files: ["Apple Mac OS X 10.3.0 - Disk 1.iso", "Apple Mac OS X 10.3.0 - Disk 2.iso", "Apple Mac OS X 10.3.0 - Disk 3.iso"], architecture: "PowerPC", mediaVersion: "10.3.0 · 3 discs", sizeHint: "~2 GB", sourceNote: "Трехдисковый установочный набор из коллекции Internet Archive. Это архивная копия; последующие обновления устанавливаются отдельно.")
        ])),
        .init(id: "10.2", marketingName: "Jaguar", number: "10.2", finalVersion: "10.2.8", year: 2002, detail: "Quartz Extreme и iChat", installerMedia: "Retail CD · 2 диска", architecture: "PowerPC", accent: 20, source: .archive(packages: [
            .init(id: "jaguar-retail", title: "Retail CD set · PowerPC", itemID: "apple-mac-os-x-10.2.0-build-6c115", files: ["disk1.iso", "disk2.iso"], architecture: "PowerPC", mediaVersion: "10.2.0 · Build 6C115", sizeHint: "~1.3 GB", sourceNote: "Двухдисковый установочный набор Jaguar из Internet Archive. Сверяем загруженные файлы с SHA-1 манифестом архива.")
        ])),
        .init(id: "10.1", marketingName: "Puma", number: "10.1", finalVersion: "10.1.5", year: 2001, detail: "Второй крупный выпуск Mac OS X", installerMedia: "ISO · Retail build", architecture: "PowerPC", accent: 21, source: .archive(packages: [
            .init(id: "puma-retail", title: "Retail image · PowerPC", itemID: "mac-os-x-puma", files: ["Mac OS X Puma Build 10.1.5G64/Mac OS X Puma.iso"], architecture: "PowerPC", mediaVersion: "10.1.5 · Build 5G64", sizeHint: "~600 MB", sourceNote: "Архивный retail image для PowerPC. Источник и контрольная сумма берутся из метаданных соответствующего элемента Internet Archive перед загрузкой.")
        ])),
        .init(id: "10.0", marketingName: "Cheetah", number: "10.0", finalVersion: "10.0.4", year: 2001, detail: "Первый публичный выпуск Mac OS X", installerMedia: "ISO · Retail CD", architecture: "PowerPC", accent: 22, source: .archive(packages: [
            .init(id: "cheetah-retail", title: "Install CD · PowerPC", itemID: "osx_100_4k78_install", files: ["osx_100_4k78_install.iso"], architecture: "PowerPC", mediaVersion: "10.0 · Build 4K78", sizeHint: "565 MB", sourceNote: "Образ Mac OS X 10.0 для PowerPC в архивной коллекции Internet Archive. Эта система предназначена для исторического PowerPC-оборудования.")
        ]))
    ]
}
