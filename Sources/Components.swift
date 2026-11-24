import AppKit
import CryptoKit
import SwiftUI

enum AppStyle {
    static let blue = Color.accentColor
    static let background = Color(nsColor: .windowBackgroundColor)
    static let developerURL = URL(string: "https://github.com/laberthouman")!
}

struct SystemWallpaper: View {
    let release: SystemRelease
    @State private var remoteImage: NSImage?
    private static var images: [String: NSImage] = [:]

    private var artwork: NSImage? {
        if let image = Self.images[release.id] { return image }
        guard let url = Bundle.main.url(forResource: release.id, withExtension: "jpg", subdirectory: "Wallpapers"),
              let image = NSImage(contentsOf: url) else { return nil }
        Self.images[release.id] = image
        return image
    }

    var body: some View {
        GeometryReader { geometry in
            if let artwork = remoteImage ?? artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            } else {
                LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }.accessibilityHidden(true)
            .task(id: release.remote?.wallpaperURL) { await loadRemoteWallpaper() }
    }

    private func loadRemoteWallpaper() async {
        remoteImage = nil
        guard let url = release.remote?.wallpaperURL else { return }
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let folder = WebConfiguration.cacheDirectory.appendingPathComponent("Wallpapers", isDirectory: true)
        let cached = folder.appendingPathComponent(key + ".jpg")
        if let image = NSImage(contentsOf: cached) { remoteImage = image; return }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
            guard !Task.isCancelled, let response = response as? HTTPURLResponse, response.statusCode == 200,
                  data.count <= 8 * 1024 * 1024, let image = NSImage(data: data) else { return }
            remoteImage = image
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: cached, options: .atomic)
        } catch { /* The bundled wallpaper remains visible when offline. */ }
    }
}

struct ReleaseWallpaperStrip: View {
    let release: SystemRelease
    let isFavorite: Bool
    let height: CGFloat
    let details: () -> Void
    let favorite: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: details) {
                ZStack(alignment: .bottomLeading) {
                    SystemWallpaper(release: release)
                    LinearGradient(colors: [.black.opacity(0.52), .black.opacity(0.10), .clear], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.clear, .black.opacity(0.28)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(release.family)  \(release.finalVersion)").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                        Text(release.marketingName).font(.system(size: 34, weight: .semibold)).tracking(-0.8)
                        Text(release.detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.88))
                        HStack(spacing: 6) {
                            Text("Совместимые Mac и загрузка")
                            Image(systemName: "arrow.right")
                        }.font(.system(size: 11, weight: .medium)).padding(.top, 7)
                    }.foregroundStyle(.white).shadow(color: .black.opacity(0.18), radius: 3, y: 1).padding(30)
                    Text(String(release.year)).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(30)
                    Color.white.opacity(hovering ? 0.035 : 0)
                }.frame(height: height).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Открыть \(release.displayName): совместимость и загрузка")
            Button(action: favorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart").font(.system(size: 15))
                    .foregroundStyle(.white).padding(10).background(.black.opacity(0.20), in: Circle())
            }.buttonStyle(.plain).padding(20)
                .help(isFavorite ? "Убрать из избранного" : "Добавить в избранное")
                .accessibilityLabel(isFavorite ? "Убрать \(release.marketingName) из избранного" : "Добавить \(release.marketingName) в избранное")
        }.onHover { hovering = $0 }
            .contextMenu {
                Button("Совместимые Mac и загрузка", action: details)
                Button(isFavorite ? "Убрать из избранного" : "Добавить в избранное", action: favorite)
            }
    }
}

struct DownloadStatusBanner: View {
    @ObservedObject var manager: InstallerDownloadManager

    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: manager.isBusy ? "arrow.down.circle.fill" : manager.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(manager.isError ? .orange : AppStyle.blue)
            VStack(alignment: .leading, spacing: 6) {
                Text(manager.releaseName).font(.system(size: 12, weight: .semibold))
                Text(manager.status ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3)
                if manager.isBusy {
                    if manager.isIndeterminate {
                        ProgressView().progressViewStyle(.linear)
                    } else {
                        ProgressView(value: manager.progress).progressViewStyle(.linear)
                    }
                    if !manager.transferDetail.isEmpty {
                        Text(manager.transferDetail).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            Spacer(minLength: 5)
            if let url = manager.resultURL {
                Button("Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .controlSize(.small)
            }
            if manager.isBusy {
                Button("Отменить") { manager.cancel() }.controlSize(.small)
            } else {
                Button { manager.dismissStatus() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .medium)) }
                    .buttonStyle(.plain).help("Скрыть уведомление")
            }
        }
        .padding(17)
        .background(.regularMaterial)
        .overlay(Rectangle().strokeBorder((manager.isError ? Color.orange : AppStyle.blue).opacity(0.18), lineWidth: 1))
    }
}

func copyLink(_ url: URL) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
}
