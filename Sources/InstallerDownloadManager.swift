import AppKit
import Combine
import CryptoKit
import Foundation

struct ArchiveMetadata: Decodable {
    struct File: Decodable {
        let name: String
        let size: String?
        let sha1: String?
    }
    let files: [File]

    func verifiedFiles(for package: ArchivePackage) throws -> [(File, Int64)] {
        guard !package.files.isEmpty else { throw DownloadFailure.message("В наборе нет файлов.") }
        return try package.files.map { path in
            guard let file = files.first(where: { $0.name == path }),
                  let digest = file.sha1, digest.count == 40,
                  digest.allSatisfy({ $0.isHexDigit }),
                  let size = file.size.flatMap(Int64.init), size > 0 else {
                throw DownloadFailure.message("У архива нет размера или SHA‑1 для \(path). Выберите другой источник.")
            }
            return (file, size)
        }
    }
}

enum DownloadFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }; return nil
    }
}

// URLSession's temporary file exists only during didFinishDownloadingTo.
// Move it synchronously on a serial background delegate queue before returning.
final class DownloadTransport: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    struct Pending {
        let continuation: CheckedContinuation<URL, Error>
        let progress: @Sendable (Int64, Int64) -> Void
        var lastUpdate: TimeInterval = 0
    }
    private let lock = NSLock()
    private var pending: [String: Pending] = [:]
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var session: URLSession!
    private let allowGitHub: Bool

    init(configuration: URLSessionConfiguration = .default, allowGitHub: Bool = false) {
        self.allowGitHub = allowGitHub
        super.init()
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 12 * 60 * 60
        configuration.httpMaximumConnectionsPerHost = 2
        let queue = OperationQueue()
        queue.name = "MacDownUp.downloads"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    func download(_ url: URL, progress: @escaping @Sendable (Int64, Int64) -> Void) async throws -> URL {
        let id = UUID().uuidString
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                var request = URLRequest(url: url)
                request.setValue("MacDownUp/3.0", forHTTPHeaderField: "User-Agent")
                let task = session.downloadTask(with: request)
                task.taskDescription = id
                lock.lock()
                pending[id] = Pending(continuation: continuation, progress: progress)
                tasks[id] = task
                lock.unlock()
                task.resume()
                if Task.isCancelled { cancel(id) }
            }
        } onCancel: { self.cancel(id) }
    }

    private func cancel(_ id: String) {
        lock.lock()
        let task = tasks.removeValue(forKey: id)
        let item = pending.removeValue(forKey: id)
        lock.unlock()
        task?.cancel()
        item?.continuation.resume(throwing: CancellationError())
    }

    private func take(_ task: URLSessionTask) -> Pending? {
        guard let id = task.taskDescription else { return nil }
        lock.lock()
        defer { lock.unlock() }
        tasks.removeValue(forKey: id)
        return pending.removeValue(forKey: id)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        lock.lock()
        guard var item = pending[id] else { lock.unlock(); return }
        let now = Date.timeIntervalSinceReferenceDate
        guard now - item.lastUpdate >= 0.25 else { lock.unlock(); return }
        item.lastUpdate = now
        pending[id] = item
        lock.unlock()
        item.progress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let item = take(downloadTask) else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw DownloadFailure.message("Сервер вернул HTTP \((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0). Ссылка могла устареть.")
            }
            let mime = response.mimeType?.lowercased() ?? ""
            guard !mime.contains("text/html"), !mime.contains("application/json") else {
                throw DownloadFailure.message("Вместо установщика сервер вернул веб-страницу. Выберите другой источник.")
            }
            let staging = FileManager.default.temporaryDirectory.appendingPathComponent("MacDownUp-\(UUID().uuidString).partial")
            try FileManager.default.moveItem(at: location, to: staging)
            item.continuation.resume(returning: staging)
        } catch { item.continuation.resume(throwing: error) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let item = take(task) else { return }
        item.continuation.resume(throwing: error ?? DownloadFailure.message("Сервер не передал файл."))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // A download may redirect within its provider, never to an arbitrary mirror.
        let original = task.originalRequest?.url
        let next = request.url
        let allowed = original != nil && next != nil &&
            ((InstallerLinks.isApple(original!) && InstallerLinks.isApple(next!)) ||
             (InstallerLinks.isArchive(original!) && InstallerLinks.isArchive(next!)) ||
             (allowGitHub && WebConfiguration.isGitHubAsset(original!) && WebConfiguration.isGitHubAsset(next!)))
        completionHandler(allowed ? request : nil)
    }
}

@MainActor
final class InstallerDownloadManager: ObservableObject {
    @Published private(set) var status: String?
    @Published private(set) var releaseName = ""
    @Published private(set) var progress = 0.0
    @Published private(set) var isIndeterminate = true
    @Published private(set) var isBusy = false
    @Published private(set) var isError = false
    @Published private(set) var resultURL: URL?
    @Published private(set) var transferDetail = ""

    private let transport: DownloadTransport
    private let catalogSession: URLSession
    private let downloadsRoot: URL?
    private var operation: Task<Void, Never>?
    private var operationID = UUID()
    private var softwareProcess: Process?
    private var outputBuffer = ""
    private var lastBytes: Int64 = 0
    private var lastSample = Date()
    private var metadataCache: [String: (Date, ArchiveMetadata)] = [:]
    private static let percentExpression = try! NSRegularExpression(pattern: #"(\d{1,3}(?:\.\d+)?)\s*%"#)

    init(transport: DownloadTransport = DownloadTransport(), catalogSession: URLSession = .shared, downloadsRoot: URL? = nil) {
        self.transport = transport
        self.catalogSession = catalogSession
        self.downloadsRoot = downloadsRoot
    }

    func startIPSW(device: MacDevice, firmware: IPSWFirmware) {
        guard !isBusy else { return }
        guard device.isMac else { fail("Выберите модель Mac."); return }
        do { _ = try firmware.validateDownload() } catch { fail(error.localizedDescription); return }
        begin(name: "\(device.name) · macOS \(firmware.version) IPSW", message: "Проверка подписи Apple…")
        let id = operationID
        operation = Task { [weak self] in
            guard let self else { return }
            do {
                // Refresh signing status and model membership immediately before downloading.
                let available = try await IPSWAPI.firmwares(for: device.id, session: self.catalogSession)
                guard let current = available.first(where: { $0.id == firmware.id }) else {
                    throw DownloadFailure.message("Эта прошивка больше не доступна для выбранной модели. Обновите список.")
                }
                let url = try current.validateDownload()
                try Task.checkCancellation()
                guard self.operationID == id else { return }
                let base = self.downloadsRoot ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let folder = base.appendingPathComponent("MacDownUp/IPSW", isDirectory: true).appendingPathComponent(device.id, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try self.checkSpace(at: folder, bytes: current.filesize)
                self.status = "Загрузка IPSW с серверов Apple…"
                let staged = try await self.transfer(url, id: id, total: current.filesize)
                defer { try? FileManager.default.removeItem(at: staged) }
                try Task.checkCancellation()
                let size = try FileManager.default.attributesOfItem(atPath: staged.path)[.size] as? NSNumber
                guard size?.int64Value == current.filesize else { throw DownloadFailure.message("Размер IPSW не совпал. Файл не сохранён.") }
                self.isIndeterminate = true
                self.status = "Проверка контрольной суммы IPSW…"
                self.transferDetail = "Проверяем целостность прошивки"
                let useSHA256 = current.sha256sum?.isEmpty == false
                let digest = useSHA256 ? try await Self.sha256(of: staged) : try await Self.sha1(of: staged)
                let expected = useSHA256 ? current.sha256sum! : current.sha1sum!
                guard digest.caseInsensitiveCompare(expected) == .orderedSame else { throw DownloadFailure.message("Контрольная сумма IPSW не совпала. Файл не сохранён.") }
                try Task.checkCancellation()
                guard self.operationID == id else { return }
                let target = try self.save(staged, in: folder, filename: url.lastPathComponent)
                self.finish("IPSW загружен · контрольная сумма совпала", at: target)
            } catch { self.handle(error, id: id) }
        }
    }

    func start(release: SystemRelease, option: InstallerOption) {
        guard !isBusy else { return }
        if case .webPage(let link, _) = option.source {
            if let url = URL(string: link), url.scheme == "https" { NSWorkspace.shared.open(url) }
            return
        }
        if case .appStore(let link) = option.source {
            guard let url = URL(string: link), InstallerLinks.isApple(url) else { fail("Некорректная ссылка App Store."); return }
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.scheme = "macappstores"
            NSWorkspace.shared.open(components.url!)
            return
        }
        begin(release: release, message: "Подключение к источнику…")
        let id = operationID
        switch option.source {
        case .softwareUpdate(let version): fetchSystemInstaller(release: release, version: version, id: id)
        case .appleImage(let link):
            operation = Task { [weak self] in
                guard let self else { return }
                do {
                    guard let url = URL(string: link), InstallerLinks.isApple(url) else { throw DownloadFailure.message("Ссылка не принадлежит серверам Apple.") }
                    let folder = try self.downloadsDirectory(for: release)
                    try self.checkSpace(at: folder, bytes: 0)
                    let staged = try await self.transfer(url, id: id)
                    defer { try? FileManager.default.removeItem(at: staged) }
                    try Task.checkCancellation()
                    guard self.operationID == id else { return }
                    let target = try self.save(staged, in: folder, filename: url.lastPathComponent)
                    self.finish("Установщик загружен", at: target)
                } catch { self.handle(error, id: id) }
            }
        case .archive(let packages):
            guard let package = packages.first else { fail("В источнике нет образов."); return }
            operation = Task { [weak self] in
                guard let self else { return }
                do {
                    self.status = "Получение манифеста Internet Archive…"
                    let metadata = try await self.archiveMetadata(package.itemID)
                    try Task.checkCancellation()
                    let files = try metadata.verifiedFiles(for: package)
                    let total = files.reduce(Int64(0)) { $0 + $1.1 }
                    let folder = try self.downloadsDirectory(for: release).appendingPathComponent(package.id, isDirectory: true)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try self.checkSpace(at: folder, bytes: total)
                    var saved: [URL] = []
                    var completed: Int64 = 0
                    for (index, pair) in files.enumerated() {
                        try Task.checkCancellation()
                        self.status = "Диск \(index + 1) из \(files.count) · загрузка"
                        let staged = try await self.transfer(package.downloadURL(for: pair.0.name), id: id, completed: completed, total: total)
                        defer { try? FileManager.default.removeItem(at: staged) }
                        let size = try FileManager.default.attributesOfItem(atPath: staged.path)[.size] as? NSNumber
                        guard size?.int64Value == pair.1 else { throw DownloadFailure.message("Размер файла не совпал с манифестом. Образ не сохранён.") }
                        self.status = "Диск \(index + 1) из \(files.count) · проверка SHA‑1"
                        self.isIndeterminate = true
                        self.transferDetail = "Проверяем целостность образа"
                        let digest = try await Self.sha1(of: staged)
                        try Task.checkCancellation()
                        guard self.operationID == id else { return }
                        guard digest.caseInsensitiveCompare(pair.0.sha1!) == .orderedSame else { throw DownloadFailure.message("SHA‑1 не совпал. Образ не сохранён — выберите другой источник.") }
                        saved.append(try self.save(staged, in: folder, filename: URL(fileURLWithPath: pair.0.name).lastPathComponent))
                        completed += pair.1
                        self.progress = Double(completed) / Double(total)
                    }
                    if let first = saved.first {
                        self.finish(files.count == 1 ? "Образ загружен · SHA‑1 совпал" : "Все \(files.count) диска загружены · SHA‑1 совпал", at: files.count == 1 ? first : folder)
                    }
                } catch { self.handle(error, id: id) }
            }
        case .appStore, .webPage: break
        }
    }

    private func transfer(_ url: URL, id: UUID, completed: Int64 = 0, total: Int64 = 0) async throws -> URL {
        lastBytes = 0
        lastSample = Date()
        isIndeterminate = true
        let staged = try await transport.download(url) { [weak self] bytes, expected in
            Task { @MainActor [weak self] in
                guard let self, self.isBusy, self.operationID == id else { return }
                let fullSize = total > 0 ? total : expected
                self.isIndeterminate = fullSize <= 0
                if fullSize > 0 { self.progress = min(Double(completed + bytes) / Double(fullSize), 0.999) }
                let elapsed = Date().timeIntervalSince(self.lastSample)
                let speed = elapsed > 0 ? Int64(Double(max(0, bytes - self.lastBytes)) / elapsed) : 0
                self.lastSample = Date()
                self.lastBytes = bytes
                let received = ByteCountFormatter.string(fromByteCount: completed + bytes, countStyle: .file)
                let size = fullSize > 0 ? " из " + ByteCountFormatter.string(fromByteCount: fullSize, countStyle: .file) : ""
                let rate = speed > 0 ? " · " + ByteCountFormatter.string(fromByteCount: speed, countStyle: .file) + "/с" : ""
                self.transferDetail = received + size + rate
            }
        }
        if Task.isCancelled { try? FileManager.default.removeItem(at: staged); throw CancellationError() }
        return staged
    }

    func archiveMetadata(_ itemID: String) async throws -> ArchiveMetadata {
        if let cached = metadataCache[itemID], Date().timeIntervalSince(cached.0) < 3600 { return cached.1 }
        var request = URLRequest(url: URL(string: "https://archive.org/metadata/\(itemID)")!, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DownloadFailure.message("Манифест Internet Archive недоступен. Попробуйте позже.") }
        let metadata = try JSONDecoder().decode(ArchiveMetadata.self, from: data)
        metadataCache[itemID] = (Date(), metadata)
        return metadata
    }

    func cancel() {
        operationID = UUID() // Late callbacks can no longer alter the next download.
        operation?.cancel()
        operation = nil
        if let process = softwareProcess, process.isRunning { process.terminate() }
        softwareProcess = nil
        isBusy = false
        isError = false
        status = "Загрузка отменена"
        transferDetail = ""
        resultURL = nil
        progress = 0
    }

    func dismissStatus() {
        guard !isBusy else { return }
        status = nil
        resultURL = nil
        transferDetail = ""
    }

    private func begin(release: SystemRelease, message: String) {
        begin(name: release.displayName, message: message)
    }

    private func begin(name: String, message: String) {
        operationID = UUID()
        releaseName = name
        status = message
        resultURL = nil
        isError = false
        isBusy = true
        isIndeterminate = true
        progress = 0
        transferDetail = ""
    }

    private func finish(_ message: String, at url: URL) {
        isBusy = false
        isError = false
        status = message
        resultURL = url
        progress = 1
        transferDetail = ""
        operation = nil
    }

    private func fail(_ message: String) {
        isBusy = false
        isError = true
        status = message
        resultURL = nil
        transferDetail = ""
        operation = nil
    }

    private func handle(_ error: Error, id: UUID) {
        guard operationID == id else { return }
        if error is CancellationError || (error as? URLError)?.code == .cancelled { cancel(); return }
        fail(error.localizedDescription)
    }

    private func downloadsDirectory(for release: SystemRelease) throws -> URL {
        let base = downloadsRoot ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("MacDownUp", isDirectory: true).appendingPathComponent(release.displayName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func checkSpace(at folder: URL, bytes: Int64) throws {
        let values = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        // Some macOS environments report zero for the purgeable-capacity estimate.
        // Fall back to actual free bytes rather than rejecting every download.
        let important = values.volumeAvailableCapacityForImportantUsage ?? 0
        let ordinary = Int64(values.volumeAvailableCapacity ?? 0)
        let free = (try? FileManager.default.attributesOfFileSystem(forPath: folder.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let available = max(important, ordinary, free)
        if available < max(bytes, 512 * 1024 * 1024) {
            throw DownloadFailure.message("Недостаточно свободного места для установщика.")
        }
    }

    private func save(_ staged: URL, in folder: URL, filename: String) throws -> URL {
        let initial = folder.appendingPathComponent(filename)
        var destination = initial
        var index = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\(initial.deletingPathExtension().lastPathComponent) (\(index)).\(initial.pathExtension)")
            index += 1
        }
        try FileManager.default.moveItem(at: staged, to: destination)
        return destination
    }

    nonisolated static func sha1(of url: URL) async throws -> String {
        let worker = Task.detached(priority: .utility) {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var hash = Insecure.SHA1()
            while true {
                try Task.checkCancellation()
                guard let data = try file.read(upToCount: 4 * 1024 * 1024), !data.isEmpty else { break }
                hash.update(data: data)
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    nonisolated static func sha256(of url: URL) async throws -> String {
        let worker = Task.detached(priority: .utility) {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var hash = SHA256()
            while true {
                try Task.checkCancellation()
                guard let data = try file.read(upToCount: 4 * 1024 * 1024), !data.isEmpty else { break }
                hash.update(data: data)
            }
            return hash.finalize().map { String(format: "%02x", $0) }.joined()
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private func fetchSystemInstaller(release: SystemRelease, version: String, id: UUID) {
        status = "Запрос полного установщика у Apple…"
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
        process.arguments = ["--fetch-full-installer", "--full-installer-version", version]
        process.standardOutput = pipe
        process.standardError = pipe
        softwareProcess = process
        outputBuffer = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                guard let self, self.operationID == id, self.isBusy else { return }
                self.outputBuffer = String((self.outputBuffer + text).suffix(8000))
                if let match = Self.percentExpression.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
                   let range = Range(match.range(at: 1), in: text), let value = Double(text[range]) {
                    self.isIndeterminate = false
                    self.progress = min(max(value / 100, 0), 1)
                    self.transferDetail = "\(Int(value))% · Apple Software Update"
                }
            }
        }
        process.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            Task { @MainActor [weak self] in
                guard let self, self.operationID == id, self.isBusy else { return }
                self.softwareProcess = nil
                if finished.terminationStatus == 0 {
                    let installer = URL(fileURLWithPath: "/Applications/Install macOS \(release.marketingName).app")
                    self.finish("Установщик готов в папке «Программы»", at: FileManager.default.fileExists(atPath: installer.path) ? installer : URL(fileURLWithPath: "/Applications"))
                } else {
                    self.fail("Apple не выдала этот установщик для вашего Mac. Выберите «Прямая загрузка Apple» в источниках.\n" + self.outputBuffer.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        do { try process.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            softwareProcess = nil
            handle(error, id: id)
        }
    }
}
