import Foundation

struct InstallerOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let source: InstallerSource
    let reference: URL

    var url: URL? {
        switch source {
        case .appleImage(let link), .appStore(let link), .webPage(let link, _): return URL(string: link)
        case .archive(let packages): return packages.first?.sourcePage
        case .softwareUpdate: return nil
        }
    }

    var isArchive: Bool { if case .archive = source { return true }; return false }
    var actionTitle: String {
        switch source {
        case .appStore: return "App Store"
        case .softwareUpdate: return "Получить"
        case .webPage: return "Открыть"
        default: return "Скачать"
        }
    }
}

extension SystemRelease {
    var options: [InstallerOption] {
        if let remote { return remote.options }
        var result: [InstallerOption] = []
        if let package = InstallerLinks.packages[id] {
            result.append(.init(id: "direct-\(id)", title: "Прямая загрузка Apple", subtitle: "InstallAssistant.pkg · \(finalVersion)", source: .appleImage(url: package), reference: InstallerLinks.database(for: id)))
        }
        switch source {
        case .archive(let packages):
            result += packages.map { .init(id: $0.id, title: $0.title, subtitle: "\($0.mediaVersion) · \($0.architecture) · \($0.sizeHint)", source: .archive(packages: [$0]), reference: $0.sourcePage) }
        case .softwareUpdate:
            result.append(.init(id: "software-\(id)", title: "Apple Software Update", subtitle: "Полный установщик для совместимого Mac", source: source, reference: InstallerLinks.appleGuide))
        case .appStore:
            result.append(.init(id: "store-\(id)", title: "Mac App Store", subtitle: "Официальная страница · нужен совместимый Mac", source: source, reference: InstallerLinks.appleGuide))
            if InstallerLinks.packages[id] != nil {
                result.append(.init(id: "software-\(id)", title: "Apple Software Update", subtitle: "Полный установщик · \(finalVersion)", source: .softwareUpdate(version: finalVersion), reference: InstallerLinks.appleGuide))
            }
        case .appleImage:
            result.append(.init(id: "image-\(id)", title: "Образ с серверов Apple", subtitle: "DMG · установочный носитель", source: source, reference: InstallerLinks.appleGuide))
        case .webPage: break
        }
        if ["10.0", "10.1", "10.2", "10.3"].contains(id) {
            let link = "https://winworldpc.com/product/mac-os-x/\(id.replacingOccurrences(of: ".", with: ""))"
            result.append(.init(id: "winworld-\(id)", title: "WinWorld", subtitle: "Архив носителей · версии, архитектура и контрольные суммы", source: .webPage(url: link, provider: "WinWorld"), reference: URL(string: link)!))
        }
        if id == "10.1" {
            let link = "https://www.macintoshrepository.org/73481-mac-os-x-10-1-puma"
            result.append(.init(id: "repository-puma", title: "Macintosh Repository", subtitle: "Puma 10.1 · Build 5G64 · PowerPC · SHA‑1 на странице", source: .webPage(url: link, provider: "Macintosh Repository"), reference: URL(string: link)!))
        }
        if ["10.0", "10.1", "10.2", "10.3", "10.4", "10.5"].contains(id) {
            let link = "https://www.macintoshrepository.org/45-mac-os-x-for-ppc-and-ppc64-osx-10-0-10-1-10-2-10-3-10-4-10-5-"
            result.append(.init(id: "repository-\(id)", title: "Macintosh Repository · коллекция", subtitle: "Установочные носители и обновления · контрольные суммы на странице", source: .webPage(url: link, provider: "Macintosh Repository"), reference: URL(string: link)!))
        }
        if id == "10.5" {
            let link = "https://www.macintoshrepository.org/69923-leopard-10-5-6-retail-installer-image"
            result.append(.init(id: "repository-leopard", title: "Macintosh Repository · Retail DVD", subtitle: "Leopard 10.5.6 · PowerPC и Intel · SHA‑1 на странице", source: .webPage(url: link, provider: "Macintosh Repository"), reference: URL(string: link)!))
        }
        return result
    }

    var preferredOption: InstallerOption { options[0] }
}

enum InstallerLinks {
    static let checkedDate = "25 ноября 2026"
    static let appleGuide = URL(string: "https://support.apple.com/102662")!
    static let mrGuide = URL(string: "https://mrmacintosh.com/how-to-download-macos-catalina-mojave-or-high-sierra-full-installers/")!

    // Public, general-purpose builds listed as available by Mr. Macintosh.
    // The bytes are served by Apple, not by the reference site. No beta or model-only builds.
    static let packages: [String: String] = [
        "27": "https://swcdn.apple.com/content/downloads/57/06/142-52990-A_M5PDCSKEVA/zkg1s5t3ro2xe0lskvh7wyyc6cf37j4i4f/InstallAssistant.pkg",
        "26": "https://swcdn.apple.com/content/downloads/02/21/142-54128-A_OWMUBNYT6S/xlorkwl2msc8dgn34ayr8dk2jm8xka68z3/InstallAssistant.pkg",
        "15": "https://swcdn.apple.com/content/downloads/35/30/142-54123-A_L1FDSOKH17/4v632s6ip8ranyhu7hc09akv6d5239x9tq/InstallAssistant.pkg",
        "14": "https://swcdn.apple.com/content/downloads/13/30/140-88558-A_TN3FIE7J63/p61cqj3ktmcqilz3q64ls4ekp1os9c8qbp/InstallAssistant.pkg",
        "13": "https://swcdn.apple.com/content/downloads/09/46/093-22004-A_QNZEDC334I/phigx2zvoggml6sh79my4y51fnvgy8hix4/InstallAssistant.pkg",
        "12": "https://swcdn.apple.com/content/downloads/24/16/062-40406-A_LQ4WW26M04/j7bl9ygay5prezturwh72ai10fvseh2uhw/InstallAssistant.pkg",
        "11": "https://swcdn.apple.com/content/downloads/10/18/047-32248-A_Y7S9K47C9M/rqg3zuwb6dkofsdilmz22awvxtq2sxwr15/InstallAssistant.pkg"
    ]

    static func database(for id: String) -> URL {
        let paths = [
            "27": "macos-golden-gate-full-installer-database-download-directly-from-apple",
            "26": "macos-tahoe-full-installer-database-download-directly-from-apple",
            "15": "macos-sequoia-full-installer-database-download-directly-from-apple",
            "14": "macos-sonoma-full-installer-database-download-directly-from-apple",
            "13": "macos-ventura-13-full-installer-database-download-directly-from-apple",
            "12": "macos-12-monterey-full-installer-database-download-directly-from-apple",
            "11": "macos-big-sur-full-installer-database-download-directly-from-apple"
        ]
        guard let path = paths[id] else { return mrGuide }
        return URL(string: "https://mrmacintosh.com/\(path)/")!
    }

    static func isApple(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "apple.com" || host.hasSuffix(".apple.com") || host.hasSuffix(".cdn-apple.com")
    }

    static func isArchive(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "archive.org" || host.hasSuffix(".archive.org")
    }
}
