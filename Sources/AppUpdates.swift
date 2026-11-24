import AppKit
import Combine
import Foundation

struct AppUpdateManifest: Codable {
    let schemaVersion: Int
    let version: String
    let build: Int
    let minimumSystemVersion: String
    let releaseNotes: String
    let archiveURL: URL?
    let sha256: String?
    let fileSize: Int64?

    func isNewer(than version: String, build: Int) -> Bool {
        let comparison = self.version.compare(version, options: .numeric)
        return comparison == .orderedDescending || (comparison == .orderedSame && self.build > build)
    }
    func validate(source: URL) throws {
        guard schemaVersion == 1, WebConfiguration.isVersion(version), build > 0,
              WebConfiguration.isVersion(minimumSystemVersion) else { throw DownloadFailure.message("Некорректный файл обновления приложения.") }
        if let archiveURL {
            let parts = source.pathComponents
            guard parts.count >= 5, archiveURL.host == "github.com", WebConfiguration.isHTTPS(archiveURL),
                  archiveURL.path.hasPrefix("/\(parts[1])/\(parts[2])/releases/download/"), archiveURL.pathExtension == "zip",
                  let sha256, sha256.count == 64, sha256.allSatisfy({ $0.isASCII && $0.isHexDigit }),
                  let fileSize, fileSize > 0, fileSize < 1024 * 1024 * 1024 else {
                throw DownloadFailure.message("Обновление должно быть ZIP-файлом из Releases того же репозитория с размером и SHA-256.")
            }
        }
    }
}

@MainActor
final class AppUpdateManager: ObservableObject {
    @Published private(set) var manifest: AppUpdateManifest?
    @Published private(set) var status = "Проверка обновлений MacDownUp"
    @Published private(set) var checking = false
    @Published private(set) var downloading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var preparedApp: URL?
    private var operation: Task<Void, Never>?
    private var operationID = UUID()
    private let transport = DownloadTransport(allowGitHub: true)
    private var checkedSource = ""
    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.0" }
    var currentBuild: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4") ?? 4 }

    func check(source: String) async {
        guard !checking, !downloading else { return }
        checking = true
        if source != checkedSource { manifest = nil; preparedApp = nil }
        defer { checking = false }
        do {
            let url = try WebConfiguration.githubRawURL(source)
            let data = try await WebConfiguration.fetch(url)
            let value = try JSONDecoder().decode(AppUpdateManifest.self, from: data)
            try value.validate(source: url)
            if value.isNewer(than: currentVersion, build: currentBuild) {
                let os = ProcessInfo.processInfo.operatingSystemVersion
                let installedOS = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
                guard installedOS.compare(value.minimumSystemVersion, options: .numeric) != .orderedAscending else {
                    throw DownloadFailure.message("Новая версия требует macOS \(value.minimumSystemVersion).")
                }
                guard value.archiveURL != nil else { throw DownloadFailure.message("Новая версия объявлена, но ZIP-файл ещё не опубликован.") }
                if manifest?.version != value.version || manifest?.build != value.build || manifest?.sha256 != value.sha256 { preparedApp = nil }
                manifest = value; status = preparedApp == nil ? "Доступен MacDownUp \(value.version)" : "Обновление проверено и готово к установке"
            } else { manifest = nil; preparedApp = nil; status = "Установлена актуальная версия \(currentVersion)" }
            checkedSource = source
        } catch { status = error.localizedDescription }
    }

    func download() {
        guard let manifest, let url = manifest.archiveURL, !downloading else { return }
        operationID = UUID(); let id = operationID
        downloading = true; progress = 0; preparedApp = nil; status = "Загрузка MacDownUp \(manifest.version)…"
        operation = Task {
            do {
                let staged = try await transport.download(url) { [weak self] bytes, total in
                    Task { @MainActor [weak self] in
                        guard let self, self.operationID == id, self.downloading else { return }
                        if total > 0 { self.progress = Double(bytes) / Double(total) }
                    }
                }
                defer { try? FileManager.default.removeItem(at: staged) }
                try Task.checkCancellation()
                let size = try FileManager.default.attributesOfItem(atPath: staged.path)[.size] as? NSNumber
                guard size?.int64Value == manifest.fileSize else { throw DownloadFailure.message("Размер обновления не совпал.") }
                let hash = try await InstallerDownloadManager.sha256(of: staged)
                guard hash.caseInsensitiveCompare(manifest.sha256!) == .orderedSame else { throw DownloadFailure.message("SHA-256 обновления не совпал.") }
                try Task.checkCancellation()
                let folder = WebConfiguration.cacheDirectory.appendingPathComponent("Updates/\(UUID())", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let app = try await Task.detached(priority: .utility) {
                    try Self.unpack(staged, to: folder, manifest: manifest)
                }.value
                try Task.checkCancellation()
                guard operationID == id else { return }
                preparedApp = app; progress = 1; downloading = false; status = "Обновление проверено и готово к установке"
            } catch {
                guard operationID == id else { return }
                downloading = false; status = error is CancellationError ? "Загрузка обновления отменена" : error.localizedDescription
            }
        }
    }

    func cancel() { operationID = UUID(); operation?.cancel(); operation = nil; downloading = false; status = "Загрузка обновления отменена" }

    func installAndRestart() {
        guard let preparedApp else { return }
        let destination = Bundle.main.bundleURL
        let backup = destination.deletingLastPathComponent().appendingPathComponent("MacDownUp-previous-\(UUID()).app")
        do {
            guard destination.pathExtension == "app", FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
                NSWorkspace.shared.activateFileViewerSelecting([preparedApp])
                throw DownloadFailure.message("Для замены приложения в этой папке нужны права. Готовая сборка открыта в Finder.")
            }
            try FileManager.default.moveItem(at: destination, to: backup)
            do { try FileManager.default.moveItem(at: preparedApp, to: destination) }
            catch { try? FileManager.default.moveItem(at: backup, to: destination); throw error }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
                DispatchQueue.main.async {
                    if let error { self.status = "Обновление установлено. Откройте приложение вручную: " + error.localizedDescription }
                    else { NSApplication.shared.terminate(nil) }
                }
            }
        } catch { status = error.localizedDescription }
    }

    nonisolated static func unpack(_ archive: URL, to folder: URL, manifest: AppUpdateManifest) throws -> URL {
        let names = try run("/usr/bin/zipinfo", ["-1", archive.path]).split(separator: "\n")
        guard !names.isEmpty, names.allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") }) else {
            throw DownloadFailure.message("Некорректная структура ZIP-обновления.")
        }
        _ = try run("/usr/bin/ditto", ["-x", "-k", archive.path, folder.path])
        let app = folder.appendingPathComponent("MacDownUp.app", isDirectory: true)
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == "com.laberthouman.macdownup",
              bundle.infoDictionary?["CFBundleShortVersionString"] as? String == manifest.version,
              Int(bundle.infoDictionary?["CFBundleVersion"] as? String ?? "") == manifest.build,
              let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw DownloadFailure.message("В архиве нет ожидаемой сборки MacDownUp.")
        }
        _ = try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        return app
    }
    nonisolated private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw DownloadFailure.message("Не удалось проверить архив обновления.") }
        return String(decoding: data, as: UTF8.self)
    }
}
