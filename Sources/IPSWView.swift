import AppKit
import SwiftUI

struct IPSWView: View {
    @ObservedObject var catalog: IPSWCatalog
    @ObservedObject var downloads: InstallerDownloadManager
    var release: SystemRelease? = nil
    @State private var selectedModelID: String?
    @State private var modelQuery = ""
    @State private var signedOnly = true
    @State private var versionQuery = ""

    private var device: MacDevice? { catalog.devices.first { $0.id == selectedModelID } }
    private var models: [MacDevice] {
        catalog.devices.filter { modelQuery.isEmpty || "\($0.name) \($0.id)".localizedCaseInsensitiveContains(modelQuery) }
    }
    private var firmwares: [IPSWFirmware] {
        catalog.firmwares.filter {
            (release == nil || $0.generationID == release!.id) && (!signedOnly || $0.signed)
                && (versionQuery.isEmpty || "\($0.version) \($0.buildid)".localizedCaseInsensitiveContains(versionQuery))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(release == nil ? "IPSW для вашего Mac." : "IPSW · \(release!.displayName)")
                        .font(.system(size: release == nil ? 30 : 18, weight: .semibold)).tracking(-0.5)
                    Spacer()
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                        .help("Обновить модели и прошивки").disabled(catalog.loadingDevices || catalog.loadingFirmwares)
                }
                Text("Выберите модель и версию macOS. Файл восстановления загружается напрямую с серверов Apple.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label("Apple silicon", systemImage: "cpu")
                    Link("Как восстановить Mac ↗", destination: URL(string: "https://support.apple.com/108900")!)
                    Spacer()
                    Link("Каталог IPSW.me ↗", destination: IPSWAPI.reference)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                if downloads.status != nil { DownloadStatusBanner(manager: downloads) }
            }.padding(28)
            Divider()
            HStack(spacing: 0) {
                modelList.frame(width: 245)
                Divider()
                firmwareList.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            Text("IPSW — образ для восстановления Mac с Apple silicon. Для Intel Mac выберите установщик в библиотеке macOS.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(18)
        }.background(AppStyle.background)
            .task {
                if catalog.devices.isEmpty { await reload() }
                else if selectedModelID == nil { selectInitialDevice() }
            }
            .task(id: selectedModelID) { await catalog.loadFirmwares(for: selectedModelID ?? "") }
    }

    private var modelList: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Поиск модели или Mac ID", text: $modelQuery).textFieldStyle(.roundedBorder).padding(14)
                .accessibilityLabel("Поиск модели Mac для IPSW")
            if catalog.loadingDevices {
                ProgressView("Загружаем модели…").font(.system(size: 11)).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = catalog.devicesError {
                message("Модели недоступны", error, retry: { Task { await reload() } })
            } else if models.isEmpty {
                message("Модель не найдена", "Попробуйте название или идентификатор, например MacBookAir10,1.")
            } else {
                List(selection: $selectedModelID) {
                    ForEach(models) { model in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.name).font(.system(size: 11, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                            Text(model.id + (model.id == HostMac.identifier ? " · Этот Mac" : ""))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }.padding(.vertical, 5).tag(model.id)
                    }
                }.listStyle(.sidebar)
            }
            Text("\(models.count) моделей").font(.system(size: 10)).foregroundStyle(.secondary).padding(14)
        }
    }

    private var firmwareList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let device {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(device.name).font(.system(size: 17, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        Text(device.id).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    TextField("Версия macOS или сборка", text: $versionQuery).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Поиск версии IPSW")
                    Toggle("Только подписанные Apple", isOn: $signedOnly).toggleStyle(.switch).controlSize(.small)
                        .font(.system(size: 11))
                }.padding(22)
                Divider()
                if catalog.loadingFirmwares {
                    ProgressView("Получаем прошивки…").font(.system(size: 11)).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = catalog.firmwareError {
                    message("Прошивки недоступны", error, retry: { Task { await catalog.loadFirmwares(for: device.id) } })
                } else if firmwares.isEmpty {
                    message("Нет подходящих прошивок", versionQuery.isEmpty ? "Для этой модели нет \(release?.displayName ?? "macOS") с выбранным статусом подписи. Попробуйте другую модель или покажите все версии." : "Измените номер версии или сборки.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(firmwares) { firmware in
                                firmwareRow(firmware, device: device)
                                Divider().padding(.horizontal, 22)
                            }
                        }
                    }
                }
            } else {
                message("Выберите свой Mac", "Модели с Apple silicon находятся в списке слева.")
            }
        }
    }

    private func firmwareRow(_ firmware: IPSWFirmware, device: MacDevice) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("macOS \(firmware.version)").font(.system(size: 14, weight: .semibold))
                Text("\(firmware.buildid) · \(firmware.sizeLabel)").font(.system(size: 11)).foregroundStyle(.secondary)
                Label(firmware.signed ? "Подписана Apple" : "Подпись отозвана", systemImage: firmware.signed ? "checkmark.seal" : "minus.circle")
                    .font(.system(size: 10)).foregroundStyle(firmware.signed ? Color.green : .secondary)
            }
            Spacer(minLength: 8)
            Button { downloads.startIPSW(device: device, firmware: firmware) } label: {
                Label("Скачать", systemImage: "arrow.down").font(.system(size: 11, weight: .medium))
            }.buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(downloads.isBusy || !firmware.signed || (try? firmware.validateDownload()) == nil)
                .help(firmware.signed ? "Скачать IPSW для \(device.name)" : "Apple больше не подписывает эту версию")
        }.padding(.horizontal, 22).padding(.vertical, 18)
            .contextMenu {
                if let url = firmware.downloadURL, InstallerLinks.isApple(url) {
                    Button("Копировать ссылку Apple") { copyLink(url) }
                }
                Button("Копировать номер сборки") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(firmware.buildid, forType: .string)
                }
            }
    }

    private func message(_ title: String, _ subtitle: String, retry: (() -> Void)? = nil) -> some View {
        VStack(spacing: 12) {
            Image(systemName: retry == nil ? "laptopcomputer" : "wifi.exclamationmark").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 15, weight: .medium))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let retry { Button("Повторить", action: retry).controlSize(.small) }
        }.padding(25).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() async {
        let previous = selectedModelID
        await catalog.loadDevices()
        selectInitialDevice()
        if previous == selectedModelID, let selectedModelID { await catalog.loadFirmwares(for: selectedModelID) }
    }
    private func selectInitialDevice() {
        if let selectedModelID, catalog.devices.contains(where: { $0.id == selectedModelID }) { return }
        selectedModelID = catalog.devices.first(where: { $0.id == HostMac.identifier })?.id ?? catalog.devices.first?.id
    }
}
