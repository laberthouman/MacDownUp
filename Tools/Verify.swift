import Foundation

struct VerificationError: Error { let message: String }
func require(_ value: Bool, _ message: String) throws {
    guard value else { throw VerificationError(message: message) }
    print("PASS: \(message)")
}

@main
struct Verify {
    @MainActor static func main() async throws {
        let releases = InstallerCatalog.releases
        try require(releases.count == 23 && Set(releases.map(\.id)).count == 23, "Все 23 поколения представлены без дублей")
        try require(releases.allSatisfy { !$0.options.isEmpty }, "У каждой версии есть источник")
        try require(releases.allSatisfy { !$0.compatibility.models.isEmpty && !$0.overview.isEmpty }, "Все системы содержат описание и совместимые Mac")
        let tahoe = releases.first { $0.id == "26" }!.compatibility
        try require(tahoe.models.first { $0.family == "MacBook Pro" }!.models.contains("четыре порта"), "Tahoe учитывает исключение Intel MacBook Pro 2020")
        try require(releases.first { $0.id == "10.4" }!.compatibility.note.contains("Retail"), "Tiger отличает Retail PowerPC от модельных дисков Intel")
        try require(releases.filter(\.isModern).count == 10, "Категории согласованы с каталогом")
        try require(releases.first(where: { $0.id == "10.9" })!.displayName == "OS X Mavericks", "Исторические названия семейств исправлены")
        try require(InstallerLinks.packages.count == 7 && InstallerLinks.packages.values.allSatisfy { InstallerLinks.isApple(URL(string: $0)!) }, "Семь прямых пакетов используют HTTPS серверы Apple")
        try require(!InstallerLinks.isApple(URL(string: "https://apple.com.evil.test/file")!) && !InstallerLinks.isApple(URL(string: "http://swcdn.apple.com/file")!), "Поддельные домены и HTTP не принимаются")
        try require(releases.flatMap(\.options).compactMap(\.url).allSatisfy { $0.scheme == "https" }, "Все опубликованные ссылки используют HTTPS")
        let package = releases.first(where: { $0.id == "10.3" })!.archivePackages[0]
        let incomplete = ArchiveMetadata(files: [.init(name: package.files[0], size: "100", sha1: String(repeating: "0", count: 40))])
        do {
            _ = try incomplete.verifiedFiles(for: package)
            throw VerificationError(message: "Неполный набор дисков принят")
        } catch is DownloadFailure { print("PASS: Неполный набор дисков отклонён до скачивания") }
        let corrupt = ArchiveMetadata(files: package.files.map { .init(name: $0, size: "100", sha1: String(repeating: "z", count: 40)) })
        do {
            _ = try corrupt.verifiedFiles(for: package)
            throw VerificationError(message: "Неверный формат SHA‑1 принят")
        } catch is DownloadFailure { print("PASS: Неверный SHA‑1 в манифесте отклонён") }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let transport = DownloadTransport(configuration: configuration)
        let base = "https://swcdn.apple.com"
        let first = try await transport.download(URL(string: base + "/file.dmg")!) { _, _ in }
        let bytes = try Data(contentsOf: first)
        try require(bytes == Data("MacDownUp fixture\n".utf8), "Файл сохранён до истечения срока временного URLSession URL")
        let digest = try await InstallerDownloadManager.sha1(of: first)
        try require(digest == "38b0643c2c5381c4f95e0b31ff520b8498ed8ca2", "Потоковая SHA‑1 сверена с независимым эталоном")
        try FileManager.default.removeItem(at: first)
        for path in ["/missing.dmg", "/html.dmg"] {
            do {
                let staged = try await transport.download(URL(string: base + path)!) { _, _ in }
                try? FileManager.default.removeItem(at: staged)
                throw VerificationError(message: "Ошибочный ответ принят: \(path)")
            } catch is DownloadFailure { print("PASS: Отклонён \(path)") }
        }
        let cancelled = Task { try await transport.download(URL(string: base + "/slow.dmg")!) { _, _ in } }
        try await Task.sleep(nanoseconds: 100_000_000)
        cancelled.cancel()
        do {
            let staged = try await cancelled.value
            try? FileManager.default.removeItem(at: staged)
            throw VerificationError(message: "Отмена не остановила загрузку")
        } catch is CancellationError { print("PASS: Отмена прекращает ожидание и сетевую задачу") }
        let retry = try await transport.download(URL(string: base + "/file.dmg")!) { _, _ in }
        let retryBytes = try Data(contentsOf: retry)
        try require(retryBytes == bytes, "Повторная загрузка после отмены работает")
        try FileManager.default.removeItem(at: retry)
        let session = URLSession(configuration: configuration)
        let devices = try await IPSWAPI.devices(session: session)
        try require(devices.count == 2 && devices.allSatisfy(\.isMac), "API фильтрует iPhone и оставляет только Mac")
        let firmware = try await IPSWAPI.firmwares(for: "MacBookAir10,1", session: session)[0]
        try require(firmware.generationID == "27", "IPSW фильтруется по выбранному поколению macOS")
        _ = try firmware.validateDownload()
        do {
            _ = try await IPSWAPI.firmwares(for: "Mac99,4", session: session)
            throw VerificationError(message: "Приняты прошивки другой модели")
        } catch is DownloadFailure { print("PASS: Прошивки другой модели отклонены") }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("MacDownUp-verify-\(UUID())")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let manager = InstallerDownloadManager(transport: transport, catalogSession: session, downloadsRoot: temporary)
        manager.startIPSW(device: .init(name: "MacBook Air (M1)", identifier: "MacBookAir10,1"), firmware: firmware)
        try await waitForDownload(manager)
        try require(!manager.isError && manager.resultURL?.pathExtension == "ipsw", "IPSW загружен и проверен до сохранения · \(manager.status ?? "")")
        let savedBytes = try Data(contentsOf: manager.resultURL!)
        try require(savedBytes == bytes && manager.resultURL!.path.contains("MacBookAir10,1"), "IPSW сохраняется в папке выбранной модели")
        for identifier in ["Mac99,1", "Mac99,2", "Mac99,3"] {
            // The user's previously loaded selection was signed. Fresh API data may revoke it.
            manager.startIPSW(device: .init(name: "Mac fixture", identifier: identifier), firmware: firmware)
            try await waitForDownload(manager)
            try require(manager.isError && manager.resultURL == nil, "Отклонён IPSW: \(identifier) (подпись / хеш / размер)")
        }
        let actualDevices = try JSONDecoder().decode([MacDevice].self, from: Data(contentsOf: URL(fileURLWithPath: "Verification/macdownup-devices.json")))
        let actualFirmware = try JSONDecoder().decode(IPSWDeviceResponse.self, from: Data(contentsOf: URL(fileURLWithPath: "Verification/macdownup-firmware.json")))
        try require(actualDevices.filter(\.isMac).count == 65 && !actualFirmware.firmwares.isEmpty, "Реальные ответы IPSW.me успешно разобраны")
        _ = try actualFirmware.firmwares.first { $0.signed }!.validateDownload()
        let webData = try Data(contentsOf: webFixtureURL("catalog.json"))
        let webDocument = try JSONDecoder().decode(WebCatalogDocument.self, from: webData)
        let webCount = try webDocument.merged().count
        try require(webCount >= 23, "Опубликованный JSON содержит все встроенные поколения")
        let catalogCache = temporary.appendingPathComponent("catalog-cache.json")
        let library = WebCatalogStore(cacheURL: catalogCache, session: session)
        await library.refresh(source: "https://raw.githubusercontent.com/test/repo/main/future.json", force: true)
        try require(library.releases.count == webCount + 1 && library.releases[0].id == "99", "Новая macOS появляется из веб-файла без пересборки приложения")
        let cachedLibrary = WebCatalogStore(cacheURL: catalogCache, session: session)
        try require(cachedLibrary.releases[0].finalVersion == "99.1", "Новая macOS сохраняется в JSON и восстанавливается после перезапуска")
        await cachedLibrary.refresh(source: "https://raw.githubusercontent.com/test/repo/main/invalid.json", force: true)
        try require(cachedLibrary.releases.count == webCount + 1, "Ошибочная новая схема не повреждает сохранённый каталог")
        await cachedLibrary.refresh(source: "https://raw.githubusercontent.com/test/repo/main/missing.json", force: true)
        try require(cachedLibrary.releases[0].id == "99", "Недоступный GitHub сохраняет последнюю рабочую копию")
        let updateManifest = try JSONDecoder().decode(AppUpdateManifest.self, from: Data(contentsOf: webFixtureURL("app-update.json")))
        try updateManifest.validate(source: URL(string: WebConfiguration.updateURL)!)
        let foreignUpdate = AppUpdateManifest(schemaVersion: 1, version: "3.1", build: 5, minimumSystemVersion: "13.0", releaseNotes: "test",
                                             archiveURL: URL(string: "https://github.com/other/repo/releases/download/v3.1/MacDownUp.zip"),
                                             sha256: String(repeating: "0", count: 64), fileSize: 100)
        do {
            try foreignUpdate.validate(source: URL(string: WebConfiguration.updateURL)!)
            throw VerificationError(message: "Принято обновление из чужого репозитория")
        } catch is DownloadFailure { print("PASS: Обновление приложения из другого репозитория отклонено") }
        print("VERIFIED")
    }

    @MainActor static func waitForDownload(_ manager: InstallerDownloadManager) async throws {
        let deadline = Date().addingTimeInterval(5)
        while manager.isBusy {
            guard Date() < deadline else { manager.cancel(); throw VerificationError(message: "Загрузка не завершилась за время теста") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
