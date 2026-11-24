import Combine
import Darwin
import Foundation

struct MacDevice: Codable, Identifiable, Hashable {
    let name: String
    let identifier: String
    var id: String { identifier }
    var isMac: Bool { identifier.hasPrefix("Mac") || identifier.hasPrefix("iMac") }
    var family: String {
        for family in ["MacBook Pro", "MacBook Air", "MacBook Neo", "MacBook", "Mac Studio", "Mac mini", "Mac Pro", "iMac"] {
            if name.localizedCaseInsensitiveContains(family) { return family }
        }
        return "Другие Mac"
    }
}

struct IPSWFirmware: Codable, Identifiable, Hashable {
    let version: String
    let buildid: String
    let url: String
    let filesize: Int64
    let signed: Bool
    let sha1sum: String?
    let sha256sum: String?
    let releasedate: String?
    var id: String { buildid + "-" + url }
    var downloadURL: URL? { URL(string: url) }
    var sizeLabel: String { ByteCountFormatter.string(fromByteCount: filesize, countStyle: .file) }
    var generationID: String {
        let pieces = version.split(separator: ".")
        return pieces.first == "10" ? pieces.prefix(2).joined(separator: ".") : String(pieces.first ?? "")
    }

    func validateDownload() throws -> URL {
        guard signed else { throw DownloadFailure.message("Apple больше не подписывает эту прошивку. Восстановление недоступно.") }
        guard let link = downloadURL, InstallerLinks.isApple(link), link.pathExtension.lowercased() == "ipsw" else {
            throw DownloadFailure.message("IPSW должен загружаться по HTTPS с серверов Apple.")
        }
        let digest = sha256sum?.isEmpty == false ? sha256sum : sha1sum
        let length = sha256sum?.isEmpty == false ? 64 : 40
        guard filesize > 0, let digest, digest.count == length, digest.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw DownloadFailure.message("У прошивки нет корректного размера или контрольной суммы.")
        }
        return link
    }
}

struct IPSWDeviceResponse: Codable {
    let identifier: String
    let firmwares: [IPSWFirmware]
}

enum IPSWAPI {
    static let reference = URL(string: "https://ipsw.me/product/Mac")!
    static func devices(session: URLSession = .shared) async throws -> [MacDevice] {
        let data = try await request(URL(string: "https://api.ipsw.me/v4/devices")!, session: session)
        let devices = try JSONDecoder().decode([MacDevice].self, from: data)
        var seen = Set<String>()
        return devices.filter { $0.isMac && seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func firmwares(for identifier: String, session: URLSession = .shared) async throws -> [IPSWFirmware] {
        guard !identifier.isEmpty, identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ",") }) else {
            throw DownloadFailure.message("Некорректный идентификатор Mac.")
        }
        let url = URL(string: "https://api.ipsw.me/v4/device/\(identifier)?type=ipsw")!
        let data = try await request(url, session: session)
        let device = try JSONDecoder().decode(IPSWDeviceResponse.self, from: data)
        guard device.identifier == identifier else { throw DownloadFailure.message("Источник вернул прошивки для другой модели Mac.") }
        var seen = Set<String>()
        return device.firmwares.filter { seen.insert($0.id).inserted }.sorted {
            if $0.version != $1.version { return $0.version.compare($1.version, options: .numeric) == .orderedDescending }
            return ($0.releasedate ?? "") > ($1.releasedate ?? "")
        }
    }

    private static func request(_ url: URL, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MacDownUp/3.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw DownloadFailure.message("Каталог IPSW недоступен. Попробуйте обновить список.")
        }
        return data
    }
}

@MainActor
final class IPSWCatalog: ObservableObject {
    @Published private(set) var devices: [MacDevice] = []
    @Published private(set) var firmwares: [IPSWFirmware] = []
    @Published private(set) var loadingDevices = false
    @Published private(set) var loadingFirmwares = false
    @Published private(set) var devicesError: String?
    @Published private(set) var firmwareError: String?
    private var firmwareRequestID = UUID()

    func loadDevices() async {
        guard !loadingDevices else { return }
        loadingDevices = true
        devicesError = nil
        defer { loadingDevices = false }
        do {
            devices = try await IPSWAPI.devices()
            if devices.isEmpty { devicesError = "В источнике пока нет моделей Mac." }
        } catch {
            if !Task.isCancelled { devicesError = "Не удалось загрузить модели Mac. Проверьте соединение и повторите.\n" + error.localizedDescription }
        }
    }

    func loadFirmwares(for identifier: String) async {
        let requestID = UUID()
        firmwareRequestID = requestID
        firmwares = []
        firmwareError = nil
        loadingFirmwares = !identifier.isEmpty
        guard !identifier.isEmpty else { return }
        do {
            let values = try await IPSWAPI.firmwares(for: identifier)
            guard firmwareRequestID == requestID else { return }
            firmwares = values
        } catch {
            guard firmwareRequestID == requestID else { return }
            if !Task.isCancelled { firmwareError = "Не удалось получить прошивки.\n" + error.localizedDescription }
        }
        if firmwareRequestID == requestID { loadingFirmwares = false }
    }
}

enum HostMac {
    static var identifier: String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &value, &size, nil, 0) == 0 else { return "" }
        return String(cString: value)
    }
}
