import Foundation

@main
struct ExportWebCatalog {
    static func main() throws {
        let document = WebCatalogDocument(schemaVersion: 1, revision: 1, updatedAt: "2026-11-25T00:00:00Z",
                                          releases: InstallerCatalog.releases.map(WebSystemRelease.init))
        _ = try document.merged()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let directory = URL(fileURLWithPath: "WebCatalog", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(document).write(to: directory.appendingPathComponent("catalog.json"))
        let manifest = AppUpdateManifest(schemaVersion: 1, version: "3.0", build: 4, minimumSystemVersion: "13.0",
                                         releaseNotes: "Интерфейс с системными обоями, совместимость, IPSW по моделям и автоматический веб-каталог.",
                                         archiveURL: nil, sha256: nil, fileSize: nil)
        try encoder.encode(manifest).write(to: directory.appendingPathComponent("app-update.json"))
        print("Exported catalog.json and app-update.json")
    }
}
